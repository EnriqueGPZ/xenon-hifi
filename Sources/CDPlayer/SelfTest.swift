import AppKit
import AVFoundation
import SwiftData
import CDPlayerKit

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/CDPlayer-self.store ~/Applications/CDPlayer.app/Contents/MacOS/CDPlayer --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            let context = model.container.mainContext
            let disc = Disc(discID: "selftest-0001", title: "Disco de prueba", artist: "Prueba")
            context.insert(disc)
            for number in 1...3 {
                context.insert(Track(number: number, title: "Pista \(number)", duration: 30, disc: disc))
            }
            try? context.save()
            model.loadDisc(disc)

            check("the disc loads its tracks in order", model.tracks.map(\.number) == [1, 2, 3])

            model.play()
            check("play starts playback", model.playbackState == .playing)
            try? await Task.sleep(for: .seconds(1.2))
            check("the clock runs while playing", model.elapsed >= 1, "elapsed \(model.elapsed)")
            model.pause()
            check("pause holds the position", model.playbackState == .paused && model.elapsed >= 1)
            model.stop()
            check("stop resets the elapsed time", model.elapsed == 0 && model.playbackState == .stopped)

            model.fastForward()
            check("fast-forward jumps 8 seconds", model.elapsed == 8)
            model.rewind()
            check("rewind jumps back 8 seconds", model.elapsed == 0)

            model.next()
            check("next moves to the next track", model.currentTrackIndex == 1)
            model.previous()
            check("previous moves back to the first track", model.currentTrackIndex == 0)

            model.toggleFavoriteCurrent()
            check("starring a track marks it favorite", model.currentTrack?.isFavorite == true)
            model.loadDisc(disc)
            check("a favorite survives reloading the disc", model.tracks.first?.isFavorite == true)

            model.next()
            model.next()
            check("next on the last track without repeat stays on the disc", model.disc != nil)
            model.toggleRepeat()
            while model.currentTrackIndex != 2 { model.next() }
            model.next()
            check("repeat wraps from the last track to the first", model.currentTrackIndex == 0)
            model.toggleRepeat()

            model.toggleFavoritesOnly()
            model.next()
            check("favorites-only stays on the favorite tracks", model.currentTrack?.isFavorite == true)
            model.toggleFavoritesOnly()

            let mode = model.displayMode
            for _ in DisplayMode.allCases { model.cycleDisplay() }
            check("display cycles through every mode and back", model.displayMode == mode)

            model.displayMode = .spectrum
            if model.playbackState != .playing { model.playPause() }
            try? await Task.sleep(for: .seconds(0.5))
            check("the spectrum bars move while playing", (model.spectrum.levels.max() ?? 0) > 0.1)
            model.stop()
            try? await Task.sleep(for: .seconds(1.5))
            check("the spectrum bars fall to zero when stopped", (model.spectrum.levels.max() ?? 1) == 0)
            model.displayMode = .elapsed

            model.displayMode = .vu
            if model.playbackState != .playing { model.playPause() }
            try? await Task.sleep(for: .seconds(0.5))
            check("the VU needles swing up while playing", model.vuMeters.left > 0.3 && model.vuMeters.right > 0.3)
            model.stop()
            try? await Task.sleep(for: .seconds(1.5))
            check("the VU needles fall back to rest when stopped", model.vuMeters.left == 0 && model.vuMeters.right == 0)
            model.displayMode = .elapsed

            model.nudgeBalance(by: -0.2)
            check("balance turns left and shows it", model.balance == -0.2 && model.flash == "BALANCE L 20")
            model.nudgeBalance(by: 0.18)
            check("balance clicks into the centre", model.balance == 0 && model.flash == "BALANCE CENTRO")
            model.nudgeBalance(by: 5)
            check("balance stops all right", model.balance == 1)
            model.centerBalance()
            check("centre balance puts it back", model.balance == 0)

            model.nudgeVolume(by: 2)
            check("volume stops at 100%", model.volume == 1)

            let tube = model.tube!
            check("the tubes start off, at half warmth", !tube.settings.enabled && tube.settings.warmth == 0.5)
            tube.toggle()
            check("VÁLVULAS turns them on", tube.settings.enabled)
            tube.nudgeWarmth(by: 100)
            check("warmth stops at 100%", tube.warmthPercent == 100)
            tube.setWarmth(0.42)
            check("warmth moves in steps of 5%", tube.warmthPercent == 40)
            tube.resetWarmth()
            check("double-click puts warmth back at half", tube.warmthPercent == 50)
            tube.toggle()
            check("off again keeps the warmth", !tube.settings.enabled && tube.warmthPercent == 50)

            let off = TubeAudioUnit.check(on: false)
            check("the tube link loads into the sound chain", off != nil)
            check("tubes off give the sound back untouched", (off?.difference ?? 1) < 1e-6)
            let on = TubeAudioUnit.check(on: true)
            check("tubes on add a 2nd harmonic of about -28 dB", (on?.second ?? -200) > -32 && (on?.second ?? 0) < -24)

            check("crossfeed starts off at MEDIO", tube.crossfeed == .off && tube.crossfeed.level == .medium)
            tube.toggleCrossfeed()
            tube.nextCrossfeedLevel()
            check("C switches crossfeed on and ⇧C moves to the next level", tube.crossfeed.enabled && tube.crossfeed.level == .strong)
            tube.nextCrossfeedLevel()
            check("after FUERTE comes SUAVE", tube.crossfeed.level == .soft)
            tube.setCrossfeedLevel(.medium)
            tube.toggleCrossfeed()
            check("crossfeed off again keeps its level", !tube.crossfeed.enabled && tube.crossfeed.level == .medium)
            let crossOff = TubeAudioUnit.check(on: false, crossfeed: false, leftOnly: true)
            check("crossfeed off leaves a left-only sound on the left alone, untouched",
                  (crossOff?.difference ?? 1) < 1e-6 && (crossOff?.right ?? 0) < -100)
            let centre = TubeAudioUnit.check(on: false, crossfeed: true)
            check("crossfeed on leaves the centre untouched", (centre?.difference ?? 1) < 1e-6)
            let crossOn = TubeAudioUnit.check(on: false, crossfeed: true, leftOnly: true)
            check("crossfeed on brings a left-only sound softly to the right ear",
                  (crossOn?.right ?? -200) > -20 && (crossOn?.right ?? 0) < -6)

            let eq = model.equalizer!
            check("the equalizer starts neutral and on", eq.settings == .neutral && eq.presetName == "NEUTRO")
            eq.setGain(3.3, band: 5)
            check("a fader moves in half decibels and shows it", eq.settings.gains[5] == 3.5 && eq.flash == "1K HZ +3.5 DB")
            check("a moved fader is no longer neutral", eq.presetName == nil)
            eq.nudgeGain(band: 0, by: 100)
            check("a fader stops at +12 dB", eq.settings.gains[0] == 12)
            eq.setPreamp(-4)
            check("the level goes down to make room", eq.settings.preamp == -4)
            eq.nudgePreamp(by: 50)
            check("the level never goes above 0 dB", eq.settings.preamp == 0)
            eq.toggle()
            check("off keeps the faders for comparing", !eq.settings.enabled && eq.settings.gains[5] == 3.5)
            eq.toggle()
            eq.save(as: " graves ")
            check("a setting saves under its name", eq.presets.map(\.name) == ["NEUTRO", "GRAVES"] && eq.presetName == "GRAVES")
            eq.save(as: "neutro")
            check("NEUTRO cannot be overwritten", eq.presets.first == .neutral)
            eq.stepPreset(by: 1)
            check("next setting goes round to NEUTRO", eq.presetName == "NEUTRO" && eq.settings.gains.allSatisfy { $0 == 0 })
            eq.stepPreset(by: -1)
            check("previous setting brings GRAVES back", eq.presetName == "GRAVES" && eq.settings.gains[0] == 12)
            check("only saved settings can be deleted", eq.deletablePreset?.name == "GRAVES")
            eq.delete(eq.deletablePreset!)
            check("deleting removes it and keeps the sound", eq.presets == [.neutral] && eq.settings.gains[0] == 12)
            eq.toggleShelf(band: 0)
            check("the bass fader turns into a shelf", eq.settings.lowShelf && eq.flash == "GRAVES ESTANTE")
            eq.toggleShelf(band: 9)
            eq.save(as: "TONO")
            eq.toggleShelf(band: 9)
            check("a shelf can go back to a bell", !eq.settings.highShelf && eq.presetName == nil)
            eq.toggleShelf(band: 5)
            check("middle faders have no shelf", !eq.isShelf(band: 5))
            eq.stepPreset(by: 1)
            eq.stepPreset(by: -1)
            check("a saved setting keeps its shelves", eq.presetName == "TONO" && eq.settings.lowShelf && eq.settings.highShelf)
            eq.delete(eq.deletablePreset!)
            eq.flatten()
            check("neutral puts every fader at 0 and the ends back to bells",
                  eq.settings.gains.allSatisfy { $0 == 0 } && eq.settings.preamp == 0 && !eq.settings.lowShelf && !eq.settings.highShelf)

            model.eject()
            check("eject clears the loaded disc", model.disc == nil && model.tracks.isEmpty)
            model.play()
            check("play with no disc does nothing", model.playbackState == .stopped)

            check("time formats as mm:ss", TrackTime.format(65) == "01:05")

            WindowLevel.apply(floating: true)
            try? await Task.sleep(for: .seconds(0.2))
            let player = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
            check("always on top lifts the player window", player?.level == .floating)
            WindowLevel.apply(floating: false)
            try? await Task.sleep(for: .seconds(0.2))
            check("always on top off puts it back", player?.level == .normal)

            await fileChecks(model)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    /// The file player: reading a music folder, the files' quality, the
    /// lists, and one unit sounding at a time. Nothing is played aloud.
    private static func fileChecks(_ model: AppModel) async {
        let root = URL(fileURLWithPath: "/tmp/CDPlayer-selftest-music")
        let album = root.appendingPathComponent("Artista/Album de prueba")
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ name: String, format: AudioFormatID, rate: Double, bits: Int) {
            var settings: [String: Any] = [AVFormatIDKey: format, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2]
            if format == kAudioFormatLinearPCM {
                settings[AVLinearPCMBitDepthKey] = bits
                settings[AVLinearPCMIsFloatKey] = false
            } else {
                settings[AVEncoderBitDepthHintKey] = bits
            }
            guard let file = try? AVAudioFile(forWriting: album.appendingPathComponent(name), settings: settings),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_800) else { return }
            buffer.frameLength = 4_800
            try? file.write(from: buffer)
        }
        write("01 Uno.flac", format: kAudioFormatFLAC, rate: 96_000, bits: 24)
        write("02 Dos.wav", format: kAudioFormatLinearPCM, rate: 44_100, bits: 16)

        let flac = await FileInfo.track(at: album.appendingPathComponent("01 Uno.flac"))
        check("a FLAC file shows its own quality", flac?.quality == "FLAC · 24 BIT · 96 KHZ", flac?.quality ?? "nil")
        let wav = await FileInfo.track(at: album.appendingPathComponent("02 Dos.wav"))
        check("a WAV file shows its own quality", wav?.quality == "WAV · 16 BIT · 44.1 KHZ", wav?.quality ?? "nil")
        check("an untagged file takes its names from the file and folder",
              flac?.title == "01 Uno" && flac?.album == "Album de prueba")

        let files = model.filePlayer
        files.use(folder: root)
        for _ in 0..<50 where files.scanning != nil || files.albums.isEmpty {
            try? await Task.sleep(for: .seconds(0.1))
        }
        check("the music folder is read into albums",
              files.albums.count == 1 && files.albums.first?.tracks.map(\.title) == ["01 Uno", "02 Dos"],
              "\(files.albums.map(\.title))")
        files.toggleList()
        check("LISTA shows the albums", files.screen == .albums && files.rows == ["Album de prueba"])
        check("⏯ on the album list starts the highlighted album from its first song",
              files.highlightedPick?.start == 0 && files.highlightedPick?.tracks.count == 2)
        files.choose()
        files.moveHighlight(by: 1)
        check("an album opens its songs and the knob moves down them",
              files.albumForList != nil && files.highlight == 1)
        check("⏯ on a song list starts the highlighted song",
              files.highlightedPick?.start == 1 && files.highlightedPick?.tracks.count == 2)
        files.toggleList()
        check("LISTA goes from the songs to the folders, each with every song below it",
              files.screen == .folders && files.folders.count == 1 && files.folders.first?.tracks.count == 2,
              "\(files.folders.map(\.name))")
        files.toggleList()
        check("LISTA goes from the folders to the song screen", files.screen == .nowPlaying)
        files.toggleList()
        files.toggleList()
        check("LISTA goes from the albums to the highlighted album's songs",
              files.albumForList != nil && files.highlight == 0)
        files.toggleList()
        files.toggleList()

        // Only one unit sounds: the file player starting pauses the CD.
        let disc = Disc(discID: "selftest-files", title: "Disco", artist: "Prueba")
        model.container.mainContext.insert(disc)
        model.container.mainContext.insert(Track(number: 1, title: "Pista", duration: 30, disc: disc))
        model.loadDisc(disc)
        // In memory only (register), so the listener's own setting stays as it is.
        UserDefaults.standard.register(defaults: [ExclusiveOutput.settingKey: true])
        model.play()
        check("tests never take the DAC for themselves, even with the switch on",
              ExclusiveOutput.shared.heldDevice == nil && !OutputDevice.isHeld(OutputDevice.device))
        files.onStart?()
        check("the file player starting pauses the CD",
              model.playbackState == .paused && model.activeSource == .files)
        model.play()
        check("the CD starting makes it the unit the keys follow", model.activeSource == .cd)
        model.stop()
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
