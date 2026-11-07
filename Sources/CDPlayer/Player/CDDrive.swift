import AppKit
import CDPlayerKit

/// An audio CD as macOS mounts it (cddafs): a folder with one AIFF file per
/// track and a hidden `.TOC.plist` with the table of contents.
struct MountedCD {
    let volume: URL
    let name: String
    let toc: DiscTOC
    /// Track number → the file macOS gives that track.
    let files: [Int: URL]
    /// Track number → the title macOS put in the file name, when it knows one.
    let fileTitles: [Int: String]

    static func read(volume: URL) -> MountedCD? {
        guard let data = try? Data(contentsOf: volume.appending(path: ".TOC.plist")),
              let toc = DiscTOC(plist: data) else { return nil }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: volume.path)) ?? []
        var files: [Int: URL] = [:]
        var titles: [Int: String] = [:]
        for name in names {
            guard let parsed = TrackFileName.parse(name) else { continue }
            files[parsed.number] = volume.appending(path: name)
            if let title = parsed.title { titles[parsed.number] = title }
        }
        guard !files.isEmpty else { return nil }
        return MountedCD(volume: volume, name: volume.lastPathComponent, toc: toc, files: files, fileTitles: titles)
    }
}

/// Watches the Mac for audio CDs coming and going, and ejects them.
final class CDDrive {
    var onChange: ((MountedCD?) -> Void)?
    private(set) var current: MountedCD?
    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            MainActor.assumeIsolated { self?.mounted(url) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] note in
            let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            MainActor.assumeIsolated { self?.unmounted(url) }
        })
        scan()
    }

    /// Looks through the mounted volumes for an audio CD.
    func scan() {
        // No .skipHiddenVolumes: macOS counts a disc whose name starts with a
        // dot ("...But Seriously") as hidden. Only volumes with a CD table
        // of contents pass MountedCD.read anyway.
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                            options: []) ?? []
        set(volumes.lazy.compactMap(MountedCD.read).first)
    }

    /// Ejects the CD; with no CD, opens the drive's tray.
    func eject() {
        let volume = current?.volume
        Task.detached {
            if let volume, (try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)) != nil { return }
            let drutil = Process()
            drutil.executableURL = URL(fileURLWithPath: "/usr/bin/drutil")
            drutil.arguments = volume == nil ? ["tray", "eject"] : ["eject"]
            try? drutil.run()
            drutil.waitUntilExit()
        }
    }

    private func mounted(_ url: URL?) {
        guard let url, current == nil else { return }
        if let cd = MountedCD.read(volume: url) {
            set(cd)
        } else {
            // The table of contents can show up a moment after the mount.
            Task {
                try? await Task.sleep(for: .seconds(1))
                if current == nil, let cd = MountedCD.read(volume: url) { set(cd) }
            }
        }
    }

    private func unmounted(_ url: URL?) {
        guard let url, let current, url.standardizedFileURL == current.volume.standardizedFileURL else { return }
        set(nil)
    }

    private func set(_ cd: MountedCD?) {
        current = cd
        onChange?(cd)
    }
}
