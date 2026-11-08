import AppKit
import CDPlayerKit
import IOKit.pwr_mgt
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots ~/Applications/CDPlayer.app/Contents/MacOS/CDPlayer
/// writes player-light.png and player-dark.png for the main panel, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// help-<topic>-light.png and -dark.png for every help topic.
/// APP_SNAPSHOT_PAGES=player,help,settings limits which ones run.
/// Add APP_ACCENT=<id> to see the pages in another accent.
enum Snapshot {
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction, openWindow: OpenWindowAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real database.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            if only == nil || only?.contains("player") == true {
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/player-\(mode).png")
                }
            }
            if only == nil || only?.contains("spectrum") == true {
                // The bars need sound: the demo disc plays silently in test mode.
                model.displayMode = .spectrum
                model.playPause()
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(1.2))
                    capture(to: "\(dir)/spectrum-\(mode).png")
                }
                model.stop()
                model.displayMode = .elapsed
            }
            if only == nil || only?.contains("vu") == true {
                // The needles need sound: the demo disc plays silently in test mode.
                model.displayMode = .vu
                model.playPause()
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(1.2))
                    capture(to: "\(dir)/vu-\(mode).png")
                }
                model.stop()
                model.displayMode = .elapsed
            }
            if only == nil || only?.contains("eq") == true {
                // A setting with a shape, and the meters as if a loud song played.
                let eq = model.equalizer!
                for (band, gain) in [6.0, 4.5, 2, 0, -1.5, -2, 0, 2.5, 4, 3].enumerated() { eq.setGain(gain, band: band) }
                eq.setPreamp(-6)
                eq.toggleShelf(band: 0)
                eq.showDemoPeaks()
                openWindow(id: EqualizerView.windowID)
                try? await Task.sleep(for: .seconds(1.5))
                let unit = NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.hasPrefix(EqualizerView.windowID) == true }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    eq.showDemoPeaks()
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/eq-\(mode).png", window: unit)
                }
                unit?.close()
                eq.flatten()
            }
            if only == nil || only?.contains("tubes") == true {
                // On, warm, glowing as if a song played.
                let tube = model.tube!
                openWindow(id: TubeView.windowID)
                try? await Task.sleep(for: .seconds(1.5))
                tube.showDemo()
                let unit = NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.hasPrefix(TubeView.windowID) == true }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/tubes-\(mode).png", window: unit)
                }
                unit?.close()
            }
            if only == nil || only?.contains("files") == true {
                // A made-up cover (warm rings) and album, nothing read from disk.
                let cover = NSImage(size: NSSize(width: 288, height: 288), flipped: false) { rect in
                    NSColor(srgbRed: 0.10, green: 0.07, blue: 0.04, alpha: 1).setFill()
                    rect.fill()
                    for ring in stride(from: 15, through: 1, by: -1) {
                        let r = CGFloat(ring) * 22
                        let shade = ring % 2 == 0 ? 0.85 : 0.45
                        NSColor(srgbRed: shade, green: shade * 0.72, blue: shade * 0.30, alpha: 1).setFill()
                        NSBezierPath(ovalIn: NSRect(x: -60 - r / 2, y: -40 - r / 2, width: r * 2, height: r * 2)).fill()
                    }
                    return true
                }
                let songs = ["Let's Fall in Love", "I Remember You", "The Look of Love", "Cry Me a River",
                             "Besame Mucho", "Love Letters", "I Get Along Without You Very Well"]
                let album = LibraryAlbum(title: "The Look of Love", artist: "Diana Krall", year: "2001", tracks:
                    songs.enumerated().map { number, title in
                        LibraryTrack(path: "/demo/\(number).flac", title: title, artist: "Diana Krall",
                                     album: "The Look of Love", trackNumber: number + 1, year: "2001",
                                     duration: 283, format: "FLAC", sampleRate: 96_000, bits: 24,
                                     modified: .distantPast)
                    })
                let files = model.filePlayer
                openWindow(id: FilePlayerView.windowID)
                try? await Task.sleep(for: .seconds(1.5))
                let unit = NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.hasPrefix(FilePlayerView.windowID) == true }
                for (name, screen) in [("files", FilePlayerModel.Screen.nowPlaying),
                                       ("files-list", .tracks(albumID: album.id)), ("files-folders", .folders)] {
                    files.showDemo(album, cover: cover, screen: screen, highlight: 2)
                    for mode in ["light", "dark"] {
                        NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                        try? await Task.sleep(for: .seconds(0.8))
                        capture(to: "\(dir)/\(name)-\(mode).png", window: unit)
                    }
                }
                // The four units stacked, from the screen.
                openWindow(id: TubeView.windowID)
                openWindow(id: EqualizerView.windowID)
                try? await Task.sleep(for: .seconds(1.5))
                // The stack, checked by where the windows stand (no screen
                // picture: it would catch whatever else is on the listener's screen).
                if let player = playerWindow {
                    let frames = [player] + (player.childWindows ?? [])
                    print("SNAPSHOT stack " + frames.map { "\($0.identifier?.rawValue ?? "?") y=\(Int($0.frame.minY))-\(Int($0.frame.maxY)) x=\(Int($0.frame.midX))" }.joined(separator: " | "))
                }
                // The whole stack at work, for the README: the file player
                // with its demo song, the tubes glowing, the equalizer with a
                // curve, the CD player's VU needles moving. All made-up data.
                files.showDemo(album, cover: cover, screen: .nowPlaying, highlight: 2)
                model.tube.showDemo()
                let eq = model.equalizer!
                for (band, gain) in [3.0, 2, 1.5, -1, -1, 0.5, 1, 0.5, 2, 3].enumerated() { eq.setGain(gain, band: band) }
                eq.toggleShelf(band: 0)
                model.displayMode = .vu
                model.playPause()
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    eq.showDemoPeaks()
                    try? await Task.sleep(for: .seconds(1.2))
                    capture(to: "\(dir)/stack-\(mode).png")
                }
                model.stop()
                model.displayMode = .elapsed
                eq.flatten()
                NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.hasPrefix(EqualizerView.windowID) == true }?.close()
                NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.hasPrefix(TubeView.windowID) == true }?.close()
                unit?.close()
            }
            // The help guide: every topic, help-<topic>-light/dark.png.
            if only == nil || only?.contains("help") == true {
                openWindow(id: HelpView.windowID)
                try? await Task.sleep(for: .seconds(1.5))
                let help = NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.hasPrefix(HelpView.windowID) == true }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for topic in HelpTopic.all {
                        HelpNavigation.shared.topic = topic.id
                        try? await Task.sleep(for: .seconds(0.8))
                        capture(to: "\(dir)/help-\(topic.id)-\(mode).png", window: help)
                    }
                }
                HelpNavigation.shared.topic = HelpTopic.all.first?.id
                help?.close()
            }
            if only == nil || only?.contains("settings") == true {
                let main = playerWindow
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// The player's window. It has no title bar, so it never becomes "main":
    /// find it as the visible window that SwiftUI opened for the "main" scene.
    private static var playerWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && !$0.isSheet && $0.identifier?.rawValue.hasPrefix("main") == true }
            ?? NSApp.windows.first { $0.isVisible && !$0.isSheet }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    private static func capture(to path: String, window: NSWindow? = nil) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? playerWindow else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
