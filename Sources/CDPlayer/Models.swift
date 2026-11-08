import Foundation
import SwiftData
import CDPlayerKit

/// A physical CD, known by its MusicBrainz disc ID (computed from the
/// table of contents), so favorites and the looked-up titles survive taking
/// the CD out and putting it back in.
@Model
final class Disc {
    @Attribute(.unique) var discID: String
    var title: String
    var artist: String
    var year: String = ""
    /// True once MusicBrainz answered (with titles, or "not found"), so the
    /// same disc is never looked up twice.
    var lookedUp: Bool = false
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \Track.disc) var tracks: [Track] = []

    init(discID: String, title: String, artist: String) {
        self.discID = discID
        self.title = title
        self.artist = artist
    }
}

@Model
final class Track {
    var number: Int
    var title: String
    /// The track's own artist on a compilation; empty when it is the album artist.
    var artist: String = ""
    var duration: TimeInterval
    var isFavorite: Bool = false
    var disc: Disc?

    init(number: Int, title: String, duration: TimeInterval, disc: Disc? = nil) {
        self.number = number
        self.title = title
        self.duration = duration
        self.disc = disc
    }
}

enum PlaybackState {
    case stopped, playing, paused
}

/// What the display shows: the track's time elapsed or remaining, the
/// spectrum bars, or two analog VU meters, the last two across the whole
/// display. The disc's total time is always on the bottom line, so it is
/// not a mode of its own.
enum DisplayMode: String, CaseIterable {
    case elapsed, remaining, spectrum, vu

    /// Modes that hide the text and draw the sound instead.
    var showsSound: Bool { self == .spectrum || self == .vu }
}

/// The whole player: the disc in the drive, the transport, and the modes.
/// One disc at a time, like a real CD player.
@Observable
final class AppModel {
    let container: ModelContainer
    let drive = CDDrive()

    private(set) var disc: Disc?
    private(set) var tracks: [Track] = []
    private(set) var currentTrackIndex = 0
    private(set) var playbackState: PlaybackState = .stopped
    private(set) var elapsed: TimeInterval = 0
    private(set) var isShuffle = false
    private(set) var isRepeat = false
    private(set) var favoritesOnly = false
    private(set) var isLookingUp = false
    var displayMode: DisplayMode = .elapsed {
        didSet { updateSpectrumTimer() }
    }
    /// The bars for the spectrum display mode.
    let spectrum = SpectrumMeter()
    /// The needles for the VU display mode.
    let vuMeters = VUMeters()
    /// The graphic equalizer unit (its own window).
    private(set) var equalizer: EqualizerModel!
    /// The tube preamp unit (its own window).
    private(set) var tube: TubeModel!
    /// The music file player unit (its own window). Only one unit sounds at
    /// a time: starting one pauses the other.
    let filePlayer = FilePlayerModel()
    /// The unit that played last: the media keys and Control Center follow it.
    private(set) var activeSource: Source = .cd

    enum Source { case cd, files }
    /// A short message that takes over the display's second line for a moment
    /// ("VOLUMEN 70", "SIN FAVORITAS").
    private(set) var flash: String?

    var volume: Double {
        didSet {
            playback.volume = Float(volume)
            filePlayer.playback.volume = Float(volume)
            if !Store.isOverridden { UserDefaults.standard.set(volume, forKey: "volume") }
        }
    }

    /// -1 all left, 0 centre, 1 all right.
    var balance: Double {
        didSet {
            playback.balance = Float(balance)
            filePlayer.playback.balance = Float(balance)
            if !Store.isOverridden { UserDefaults.standard.set(balance, forKey: "balance") }
        }
    }

    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    private let playback = Playback()
    private let nowPlaying = NowPlaying()
    /// Track number → the file macOS gives that track on the mounted CD.
    private var files: [Int: URL] = [:]
    /// Indices into `tracks`, in play order: shuffled or not, favorites-only or not.
    private var playOrder: [Int] = []
    private var loadedNumber: Int?
    private var ticker: Timer?
    private var spectrumTimer: Timer?
    private var flashTask: Task<Void, Never>?

    init(container: ModelContainer) {
        self.container = container
        let saved = UserDefaults.standard.object(forKey: "volume") as? Double
        volume = Store.isOverridden ? 0.7 : (saved ?? 0.7)
        balance = Store.isOverridden ? 0 : Balance.clamp(UserDefaults.standard.double(forKey: "balance"))
        playback.volume = Float(volume)
        playback.balance = Float(balance)
        playback.onFinish = { [weak self] in self?.trackFinished() }
        playback.onReadError = { [weak self] in self?.readFailed() }
        playback.onSoundError = { [weak self] in self?.soundFailed() }
        let playback = playback
        let files = filePlayer
        files.playback.volume = Float(volume)
        files.playback.balance = Float(balance)
        // The equalizer works on whichever unit sounds; its meters watch that one.
        equalizer = EqualizerModel(send: { playback.equalizer = $0; files.playback.equalizer = $0 },
                                   peaks: { files.isPlaying ? files.playback.recentPeaks() : playback.recentPeaks() },
                                   resetPeaks: { playback.resetOvers(); files.playback.resetOvers() })
        // The tubes warm whichever unit sounds, and glow with it.
        tube = TubeModel(send: { playback.tube = $0; files.playback.tube = $0 },
                         sendCrossfeed: { playback.crossfeed = $0; files.playback.crossfeed = $0 },
                         loudness: { files.isPlaying ? files.playback.recentLoudness() : playback.recentLoudness() })
        files.onStart = { [weak self] in
            self?.pause()
            self?.activeSource = .files
        }
        files.onChange = { [weak self] in self?.filePlayerChanged() }
        nowPlaying.attach(to: self)
        if Store.isOverridden {
            // Tests and snapshots use the demo disc, never the real drive.
            loadLatestDisc()
        } else {
            drive.onChange = { [weak self] cd in self?.insert(cd) }
            drive.start()
        }
    }

    var currentTrack: Track? {
        tracks.indices.contains(currentTrackIndex) ? tracks[currentTrackIndex] : nil
    }

    var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }

    var hasFavorites: Bool { tracks.contains(where: \.isFavorite) }

    /// The artist to show for the current track: its own on a compilation,
    /// otherwise the album's.
    var currentArtist: String {
        if let artist = currentTrack?.artist, !artist.isEmpty { return artist }
        return disc?.artist ?? ""
    }

    // MARK: - Discs

    /// The demo disc for tests and snapshots: whichever was stored last.
    func loadLatestDisc() {
        let descriptor = FetchDescriptor<Disc>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let latest = try? container.mainContext.fetch(descriptor).first {
            loadDisc(latest)
        } else {
            clearDisc()
        }
    }

    func loadDisc(_ disc: Disc) {
        stopPlayback(unload: true)
        // The title search of the disc before (if any) no longer shows here.
        isLookingUp = false
        self.disc = disc
        tracks = disc.tracks.sorted { $0.number < $1.number }
        currentTrackIndex = 0
        rebuildPlayOrder()
        publishNowPlaying()
    }

    /// A CD appeared in the drive (or left it, with nil).
    func insert(_ cd: MountedCD?) {
        guard let cd else {
            files = [:]
            clearDisc()
            return
        }
        let context = container.mainContext
        let id = cd.toc.musicBrainzID
        let found = try? context.fetch(FetchDescriptor<Disc>(predicate: #Predicate { $0.discID == id })).first
        let disc: Disc
        if let found {
            disc = found
        } else {
            disc = Disc(discID: id, title: cd.name, artist: "")
            context.insert(disc)
        }
        var existing = Dictionary(disc.tracks.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in cd.toc.audioEntries {
            let number = entry.number
            let track = existing[number] ?? {
                let track = Track(number: number, title: "Pista \(number)", duration: 0, disc: disc)
                context.insert(track)
                existing[number] = track
                return track
            }()
            track.duration = cd.toc.duration(ofTrack: number)
            if !disc.lookedUp, let title = cd.fileTitles[number] { track.title = title }
        }
        try? context.save()
        files = cd.files
        loadDisc(disc)
        if !disc.lookedUp, UserDefaults.standard.object(forKey: "lookUpTitles") as? Bool ?? true {
            Task { await lookUp(disc) }
        }
        if UserDefaults.standard.bool(forKey: "autoPlay") { play() }
    }

    private func clearDisc() {
        stopPlayback(unload: true)
        disc = nil
        tracks = []
        playOrder = []
        currentTrackIndex = 0
        isLookingUp = false
        publishNowPlaying()
    }

    /// Asks MusicBrainz for the album, artist, and titles, once per disc.
    /// Without internet the titles macOS gave the files stay, and the next
    /// insert tries again.
    private func lookUp(_ disc: Disc) async {
        guard let url = DiscMetadata.lookupURL(discID: disc.discID) else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("XENON-HiFi/1.0 (https://github.com/EnriqueGPZ/xenon-hifi)", forHTTPHeaderField: "User-Agent")
        isLookingUp = true
        defer { if self.disc === disc { isLookingUp = false } }
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            if self.disc === disc { show("SIN CONEXIÓN") }
            return
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if let meta = DiscMetadata.parse(data, discID: disc.discID) {
            disc.title = meta.album
            disc.artist = meta.artist
            disc.year = meta.year
            for track in disc.tracks {
                guard let info = meta.tracks[track.number] else { continue }
                track.title = info.title
                track.artist = info.artist ?? ""
            }
            disc.lookedUp = true
        } else if status == 404 {
            disc.lookedUp = true
            if self.disc === disc { show("DISCO NO ENCONTRADO") }
        }
        try? container.mainContext.save()
        if self.disc === disc { publishNowPlaying() }
    }

    // MARK: - Transport

    func playPause() {
        playbackState == .playing ? pause() : play()
    }

    func play() {
        guard disc != nil else { show("SIN DISCO"); return }
        guard !playOrder.isEmpty else { show("SIN FAVORITAS"); return }
        guard prepareCurrent() else {
            stopPlayback(unload: false)
            publishNowPlaying()
            return
        }
        filePlayer.pause()
        activeSource = .cd
        guard playback.play() else {
            soundFailed()
            return
        }
        playbackState = .playing
        startTicker()
        publishNowPlaying()
    }

    func pause() {
        guard playbackState == .playing else { return }
        playback.pause()
        elapsed = playback.currentTime
        playbackState = .paused
        stopTicker()
        publishNowPlaying()
    }

    func stop() {
        stopPlayback(unload: false)
        publishNowPlaying()
    }

    /// Ejects the disc; with no disc, opens the tray.
    func eject() {
        stopPlayback(unload: true)
        if Store.isOverridden {
            clearDisc()
        } else {
            drive.eject()
        }
    }

    func next() {
        advance(by: 1)
    }

    /// Early in a track, goes to the previous track; later, restarts the
    /// current one, like a real player's |<< button.
    func previous() {
        if elapsed > 3 {
            seek(to: 0)
        } else {
            advance(by: -1)
        }
    }

    func fastForward() {
        seek(to: elapsed + 8)
    }

    func rewind() {
        seek(to: elapsed - 8)
    }

    private func seek(to time: TimeInterval) {
        guard let track = currentTrack else { return }
        elapsed = min(max(0, time), max(0, track.duration - 0.5))
        if loadedNumber == track.number { playback.seek(to: elapsed) }
        publishNowPlaying()
    }

    private func advance(by step: Int) {
        guard !playOrder.isEmpty else { return }
        let position = playOrder.firstIndex(of: currentTrackIndex) ?? -1
        var next = position + step
        if next < 0 {
            next = isRepeat ? playOrder.count - 1 : 0
        }
        if next >= playOrder.count {
            guard isRepeat else {
                stopPlayback(unload: false)
                currentTrackIndex = playOrder[0]
                publishNowPlaying()
                return
            }
            next = 0
        }
        let wasPlaying = playbackState == .playing
        currentTrackIndex = playOrder[next]
        elapsed = 0
        if wasPlaying {
            play()
        } else {
            if playbackState == .paused { playbackState = .stopped }
            publishNowPlaying()
        }
    }

    private func trackFinished() {
        // Paused is included: the sound may already have moved on to the next
        // track, and the screen has to follow it.
        guard playbackState != .stopped else { return }
        advance(by: 1)
    }

    /// The disc stopped giving sound while a track played: stop here and say so.
    /// It stops where the bad read starts, and keeps that place: play reads on from there.
    private func readFailed() {
        guard playbackState == .playing else { return }
        stopTicker()
        playback.pause()
        playbackState = .stopped
        elapsed = playback.currentTime
        show("ERROR DE LECTURA")
        publishNowPlaying()
    }

    /// The sound card would not start: stop here and say so.
    private func soundFailed() {
        stopPlayback(unload: false)
        show("ERROR DE SONIDO")
        publishNowPlaying()
    }

    /// Opens the current track's audio if it is not open yet, at `elapsed`.
    private func prepareCurrent() -> Bool {
        guard let track = currentTrack else { return false }
        if loadedNumber == track.number { return true }
        do {
            try playback.load(files[track.number], length: track.duration)
            loadedNumber = track.number
            equalizer.newSong()
            playback.seek(to: elapsed)
            return true
        } catch {
            // Nothing is open now, so the old track must not count as loaded.
            loadedNumber = nil
            show("ERROR DE LECTURA")
            return false
        }
    }

    private func stopPlayback(unload: Bool) {
        stopTicker()
        if unload {
            playback.unload()
            loadedNumber = nil
        } else {
            playback.pause()
            playback.seek(to: 0)
        }
        playbackState = .stopped
        elapsed = 0
    }

    // MARK: - Modes

    func toggleShuffle() {
        isShuffle.toggle()
        rebuildPlayOrder()
    }

    func toggleRepeat() {
        isRepeat.toggle()
    }

    func toggleFavoritesOnly() {
        guard favoritesOnly || hasFavorites || disc == nil else {
            show("SIN FAVORITAS")
            return
        }
        favoritesOnly.toggle()
        rebuildPlayOrder()
        if favoritesOnly, let track = currentTrack, !track.isFavorite { advance(by: 1) }
    }

    func cycleDisplay() {
        let all = DisplayMode.allCases
        let index = all.firstIndex(of: displayMode) ?? 0
        displayMode = all[(index + 1) % all.count]
    }

    func toggleFavoriteCurrent() {
        guard let track = currentTrack else { return }
        track.isFavorite.toggle()
        try? container.mainContext.save()
        show(track.isFavorite ? "FAVORITA ★" : "YA NO ES FAVORITA")
        if favoritesOnly {
            rebuildPlayOrder()
            if playOrder.isEmpty { favoritesOnly = false; rebuildPlayOrder() }
        }
    }

    /// Turns the knob by a step, from the arrow keys.
    func nudgeVolume(by step: Double) {
        volume = min(1, max(0, volume + step))
        showVolume()
    }

    func nudgeBalance(by step: Double) {
        balance = Balance.clamp(balance + step)
        showBalance()
    }

    func centerBalance() {
        balance = 0
        showBalance()
    }

    func showBalance() {
        show("BALANCE \(Balance.label(balance))")
    }

    func showVolume() {
        show("VOLUMEN \(Int((volume * 100).rounded()))")
    }

    private func rebuildPlayOrder() {
        let before = nextIndex
        let pool = favoritesOnly ? tracks.indices.filter { tracks[$0].isFavorite } : Array(tracks.indices)
        playOrder = isShuffle ? pool.shuffled() : pool
        if isShuffle, let at = playOrder.firstIndex(of: currentTrackIndex) {
            // The playing track stays first, so shuffle never jumps away from it.
            playOrder.swapAt(0, at)
        }
        // A track already queued behind the current one may no longer be next.
        if nextIndex != before, playbackState == .playing { prepareUpcoming() }
    }

    /// The track that plays after the current one, or nil at the end of the disc.
    private var nextIndex: Int? {
        guard let position = playOrder.firstIndex(of: currentTrackIndex) else { return nil }
        if position + 1 < playOrder.count { return playOrder[position + 1] }
        return isRepeat ? playOrder.first : nil
    }

    // MARK: - Display messages

    private func show(_ text: String) {
        flash = text
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            if !Task.isCancelled { flash = nil }
        }
    }

    // MARK: - Spectrum

    /// The bars and needles run only while they are on screen.
    private func updateSpectrumTimer() {
        spectrum.reset()
        vuMeters.reset()
        if displayMode.showsSound {
            guard spectrumTimer == nil else { return }
            let timer = Timer(timeInterval: 1 / SpectrumMeter.rate, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.spectrumTick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            spectrumTimer = timer
        } else {
            spectrumTimer?.invalidate()
            spectrumTimer = nil
        }
    }

    private func spectrumTick() {
        // The bars and needles show what sounds: the CD or the file player.
        let files = filePlayer.isPlaying
        let source = files ? filePlayer.playback : playback
        let playing = files || playbackState == .playing
        let time = source.currentTime
        switch displayMode {
        case .spectrum:
            spectrum.update(samples: playing ? source.recentSamples() : nil, time: time,
                            playing: playing, demo: Store.isOverridden && !files, sampleRate: source.sampleRate)
        case .vu:
            vuMeters.update(loudness: playing ? source.recentLoudness() : nil, time: time,
                            playing: playing, demo: Store.isOverridden && !files)
        case .elapsed, .remaining:
            break
        }
    }

    // MARK: - Clock

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common keeps the clock running while a menu is open or the window moves.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard playbackState == .playing else { return }
        elapsed = playback.currentTime
        playback.checkSilentEnd()
        prepareUpcoming()
    }

    /// Ten seconds before a track ends, opens the next one so it starts
    /// without waiting for the drive.
    private func prepareUpcoming() {
        guard let track = currentTrack, track.duration - elapsed < 10 else { return }
        // Nil when there is no next track: a queued one is then dropped.
        let next = nextIndex.flatMap { files[tracks[$0].number] }
        playback.preload(next)
    }

    /// A new song on the file player restarts the OVER counts, like a new CD track.
    private var fileSongPath: String?

    private func filePlayerChanged() {
        // Only when the file player is the one sounding: browsing it while
        // the CD plays must not clear the CD's counts.
        if filePlayer.current?.path != fileSongPath, activeSource == .files {
            fileSongPath = filePlayer.current?.path
            equalizer.newSong()
        }
        if activeSource == .files { publishNowPlaying() }
    }

    private func publishNowPlaying() {
        if activeSource == .files {
            let track = filePlayer.current
            nowPlaying.update(title: track?.title, artist: track?.artist ?? "", album: track?.album,
                              duration: track?.duration ?? 0, elapsed: filePlayer.elapsed, state: filePlayer.state)
            return
        }
        nowPlaying.update(title: currentTrack?.title, artist: currentArtist, album: disc?.title,
                          duration: currentTrack?.duration ?? 0, elapsed: elapsed, state: playbackState)
    }
}
