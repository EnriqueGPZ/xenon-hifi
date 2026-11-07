import AppKit
import CDPlayerKit
import CryptoKit
import Foundation

/// The music file player unit: the music folder the listener chose (usually on
/// a disk he plugs in), its albums, and the album that plays. It has its own
/// Playback, so it plays at each file's own quality; the app makes sure only
/// one unit sounds at a time.
@Observable
final class FilePlayerModel {
    /// What the colour screen shows.
    enum Screen: Equatable {
        case nowPlaying
        case albums
        case tracks(albumID: String)
        case folders
    }

    // MARK: Library

    /// The folder the music comes from; nil until chosen.
    private(set) var folder: URL? { didSet { refreshFolders() } }
    private(set) var albums: [LibraryAlbum] = [] { didSet { refreshFolders() } }
    /// The songs marked FAVORITA, by their name inside the music folder.
    private(set) var favorites: Set<String> = FavoritesFile.load() { didSet { refreshFolders() } }
    /// ★ Favoritas, while some song is marked.
    private(set) var favoritesAlbum: LibraryAlbum?
    /// The ÁLBUMES list: ★ Favoritas first, then the library.
    var listAlbums: [LibraryAlbum] { (favoritesAlbum.map { [$0] } ?? []) + albums }
    /// The folders right inside the music folder, for the CARPETAS list.
    private(set) var folders: [LibraryFolder] = []
    private(set) var trackCount = 0
    /// Songs read so far and songs found, while the folder is being read.
    private(set) var scanning: (done: Int, total: Int)?
    /// The folder's disk is not plugged in.
    var folderMissing: Bool { folder.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false }

    // MARK: Playing

    private(set) var queue: [LibraryTrack] = []
    private(set) var index = 0
    private(set) var state: PlaybackState = .stopped
    private(set) var elapsed: TimeInterval = 0
    private(set) var cover: NSImage?
    var current: LibraryTrack? { queue.indices.contains(index) ? queue[index] : nil }
    var isPlaying: Bool { state == .playing }

    // MARK: Screen

    private(set) var screen: Screen = .nowPlaying
    /// The highlighted row in a list.
    private(set) var highlight = 0
    /// A short message on the screen ("DISCO NO CONECTADO").
    private(set) var flash: String?

    /// Called when this unit starts to sound, so the CD can pause.
    var onStart: (() -> Void)?
    /// Called when what plays changes, for Control Center and the media keys.
    var onChange: (() -> Void)?

    let playback = Playback(open: { try FileTrackReader(url: $0) })
    private var ticker: Timer?
    private var flashTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var loadedPath: String?
    /// The song whose next one is already queued (opened once, not every tick).
    private var preloadedFor: String?
    private static let folderKey = "files.folder"
    private static let resumeKey = "files.resume"
    private var lastResumeSave = Date.distantPast

    /// Where the music was: the songs in line, the one playing, its second.
    private struct Resume: Codable {
        var paths: [String]
        var index: Int
        var elapsed: TimeInterval
    }

    private func saveResume() {
        guard !Store.isOverridden else { return }
        lastResumeSave = .now
        guard current != nil else { UserDefaults.standard.removeObject(forKey: Self.resumeKey); return }
        let resume = Resume(paths: queue.map(\.path), index: index, elapsed: elapsed)
        UserDefaults.standard.set(try? JSONEncoder().encode(resume), forKey: Self.resumeKey)
    }

    /// On opening: the song it was at, paused at its second, ready for ⏯.
    /// Songs no longer in the library are left out of the line.
    private func restoreResume() {
        guard let data = UserDefaults.standard.data(forKey: Self.resumeKey),
              let resume = try? JSONDecoder().decode(Resume.self, from: data),
              resume.paths.indices.contains(resume.index) else { return }
        let known = Dictionary(albums.flatMap(\.tracks).map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        let tracks = resume.paths.compactMap { known[$0] }
        guard let at = tracks.firstIndex(where: { $0.path == resume.paths[resume.index] }) else { return }
        queue = tracks
        index = at
        elapsed = min(max(0, resume.elapsed), max(0, tracks[at].duration - 0.5))
        state = .paused
        loadCover(for: tracks[at])
    }

    init() {
        playback.onFinish = { [weak self] in self?.trackFinished() }
        playback.onReadError = { [weak self] in self?.failed("ERROR DE LECTURA") }
        playback.onSoundError = { [weak self] in self?.failed("ERROR DE SONIDO") }
        guard !Store.isOverridden else { return }
        if let path = UserDefaults.standard.string(forKey: Self.folderKey) {
            folder = URL(fileURLWithPath: path)
            albums = MusicLibrary.albums(LibraryCache.load(for: path))
            trackCount = albums.reduce(0) { $0 + $1.tracks.count }
            restoreResume()
            rescan()
        }
        // Quitting keeps the song and the second it was at.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveResume() }
        }
        // The music's disk plugged in: read its folder again. Other disks are left alone.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil,
                                                          queue: .main) { [weak self] note in
            let volume = (note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path
            MainActor.assumeIsolated {
                guard let self, let folder = self.folder?.path, let volume,
                      folder == volume || folder.hasPrefix(volume + "/") else { return }
                // The disk came back: files opened before it left are dead,
                // so the next play opens them again.
                if !self.isPlaying {
                    self.playback.unload()
                    self.loadedPath = nil
                }
                self.rescan()
            }
        }
    }

    // MARK: - Folder

    /// Asks the listener for the music folder or disk, then reads it.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Usar esta música"
        panel.message = "Elige el disco o la carpeta donde está tu música"
        panel.directoryURL = folder ?? URL(fileURLWithPath: "/Volumes")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        use(folder: url)
    }

    func use(folder url: URL) {
        stop()
        // Nothing of the old folder stays: its songs, its queue, its cover.
        playback.unload()
        loadedPath = nil
        queue = []
        index = 0
        cover = nil
        screen = .nowPlaying
        highlight = 0
        folder = url
        albums = []
        trackCount = 0
        if !Store.isOverridden { UserDefaults.standard.set(url.path, forKey: Self.folderKey) }
        rescan()
    }

    /// Reads the folder again: new and changed files are read, the rest
    /// come from the saved library.
    func rescan() {
        guard let folder, !folderMissing else { return }
        scanTask?.cancel()
        let known = Dictionary(albums.flatMap(\.tracks).map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        scanTask = Task { [weak self] in
            // Listing the folder and checking every file's date touch the
            // disk: off the main thread, so a disk that spins up never
            // freezes the panel.
            let (files, kept, fresh) = await Task.detached {
                let files = MusicLibrary.musicFiles(in: folder)
                var kept: [LibraryTrack] = []
                var fresh: [URL] = []
                for url in files {
                    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    if let old = known[url.path], old.modified == modified { kept.append(old) } else { fresh.append(url) }
                }
                return (files, kept, fresh)
            }.value
            if Task.isCancelled { return }
            var tracks = kept
            self?.scanning = (tracks.count, files.count)
            // Four files at a time: fast on an SSD, gentle on a disk that spins.
            for batch in stride(from: 0, to: fresh.count, by: 4).map({ Array(fresh[$0..<min($0 + 4, fresh.count)]) }) {
                if Task.isCancelled { return }
                let read = await withTaskGroup(of: LibraryTrack?.self) { group in
                    for url in batch { group.addTask { await FileInfo.track(at: url) } }
                    var read: [LibraryTrack] = []
                    for await track in group { if let track { read.append(track) } }
                    return read
                }
                tracks += read
                self?.scanning = (tracks.count, files.count)
            }
            if Task.isCancelled { return }
            self?.finishScan(tracks, folder: folder)
        }
    }

    private func finishScan(_ tracks: [LibraryTrack], folder: URL) {
        scanning = nil
        albums = MusicLibrary.albums(tracks)
        trackCount = tracks.count
        // A disk pulled out mid-read leaves a short list: never saved over a good one.
        guard !folderMissing, !Store.isOverridden else { return }
        LibraryCache.save(tracks, for: folder.path)
    }

    // MARK: - Transport

    /// ⏯: on a list, what is highlighted starts from its beginning (a song,
    /// an album, a folder); what already plays pauses or goes on.
    func playPause() {
        if let pick = highlightedPick, !pick.tracks.isEmpty {
            let playing = current?.path
            let isCurrent = screen == .albums || screen == .folders
                ? pick.tracks.contains { $0.path == playing }
                : pick.tracks[pick.start].path == playing
            if !isCurrent {
                play(pick.tracks, from: pick.start)
                return
            }
        }
        isPlaying ? pause() : play()
    }

    /// The songs the highlighted row stands for, and the one to start on.
    var highlightedPick: (tracks: [LibraryTrack], start: Int)? {
        switch screen {
        case .nowPlaying: nil
        case .albums: listAlbums.indices.contains(highlight) ? (listAlbums[highlight].tracks, 0) : nil
        case .tracks:
            albumForList.flatMap { $0.tracks.indices.contains(highlight) ? ($0.tracks, highlight) : nil }
        case .folders: folders.indices.contains(highlight) ? (folders[highlight].tracks, 0) : nil
        }
    }

    func play() {
        if current == nil {
            // Nothing chosen yet: the highlighted album, or the first one.
            let highlighted = screen == .albums && listAlbums.indices.contains(highlight) ? listAlbums[highlight] : nil
            guard let album = albumForList ?? highlighted ?? albums.first else {
                show(folder == nil ? "PULSA MÚSICA" : "SIN CANCIONES")
                return
            }
            queue = album.tracks
            index = 0
        }
        guard prepareCurrent() else { return }
        onStart?()
        guard playback.play() else { failed("ERROR DE SONIDO"); return }
        state = .playing
        startTicker()
        saveResume()
        onChange?()
    }

    func pause() {
        guard isPlaying else { return }
        playback.pause()
        elapsed = playback.currentTime
        state = .paused
        stopTicker()
        saveResume()
        onChange?()
    }

    func stop() {
        stopTicker()
        // The files stay open (no disc to eject): stopping is pausing at 0:00.
        playback.pause()
        rewind()
        state = .stopped
        elapsed = 0
        saveResume()
        onChange?()
    }

    /// Back to 0:00. Going back drops the queued next song, so it is
    /// queued again near the end, for the gapless change.
    private func rewind() {
        playback.seek(to: 0)
        preloadedFor = nil
    }

    /// Seconds moved each repeat while |<< or >>| is held.
    static let scanStep: TimeInterval = 5

    /// Forward or back through the song, held to the song's length.
    func skip(by seconds: TimeInterval) {
        seek(to: elapsed + seconds)
    }

    func seek(to time: TimeInterval) {
        guard let track = current else { return }
        elapsed = min(max(0, time), max(0, track.duration - 0.5))
        if loadedPath == track.path {
            playback.seek(to: elapsed)
            // Going back drops the queued next song; it is queued again near the end.
            preloadedFor = nil
        }
        onChange?()
    }

    func next() {
        guard index + 1 < queue.count else { return }
        jump(to: index + 1)
    }

    /// Back to the start of the song, or to the previous one in its first seconds.
    func previous() {
        if elapsed > 3 || index == 0 {
            rewind()
            elapsed = 0
            onChange?()
        } else {
            jump(to: index - 1)
        }
    }

    /// Plays every song in `folder`, album by album.
    func play(_ folder: LibraryFolder) {
        play(folder.tracks)
    }

    /// Plays `album` from its song `start`.
    func play(_ album: LibraryAlbum, from start: Int = 0) {
        play(album.tracks, from: start)
    }

    private func play(_ tracks: [LibraryTrack], from start: Int = 0) {
        guard tracks.indices.contains(start) else { return }
        queue = tracks
        screen = .nowPlaying
        jump(to: start, forcePlay: true)
    }

    private func jump(to newIndex: Int, forcePlay: Bool = false) {
        let wasPlaying = isPlaying || forcePlay
        index = newIndex
        elapsed = 0
        loadedPath = nil
        if wasPlaying { play() } else { _ = prepareCurrent(); saveResume(); onChange?() }
    }

    private func prepareCurrent() -> Bool {
        guard let track = current else { return false }
        if loadedPath == track.path { return true }
        do {
            try playback.load(track.url, length: track.duration)
            loadedPath = track.path
            preloadedFor = nil
            if elapsed > 0 { playback.seek(to: elapsed) }
            loadCover(for: track)
            return true
        } catch {
            stop()
            show(folderMissing ? "DISCO NO CONECTADO" : "NO SE PUEDE ABRIR")
            return false
        }
    }

    private func trackFinished() {
        // The next song already took over without a gap, or starts now.
        if index + 1 < queue.count {
            index += 1
            elapsed = 0
            if isPlaying {
                if !prepareCurrent() { return }
                if !playback.play() { failed("ERROR DE SONIDO"); return }
            }
            onChange?()
        } else {
            stop()
            index = 0
            // The album is over: the screen shows its first song, with its cover.
            if let first = current { loadCover(for: first) }
        }
    }

    private func failed(_ message: String) {
        stopTicker()
        playback.pause()
        elapsed = playback.currentTime
        state = .stopped
        show(message)
        onChange?()
    }

    // MARK: - Lists and the knob

    /// LISTA goes round four screens: what plays, the albums, the songs of
    /// the highlighted album, the folders, and back to what plays.
    func toggleList() {
        switch screen {
        case .nowPlaying:
            screen = .albums
            // The record that plays, not ★ Favoritas.
            highlight = listAlbums.firstIndex { !$0.isFavorites && $0.tracks.contains { $0.path == current?.path } } ?? 0
        case .albums:
            guard listAlbums.indices.contains(highlight) else { screen = .nowPlaying; return }
            let album = listAlbums[highlight]
            screen = .tracks(albumID: album.id)
            highlight = album.tracks.firstIndex { $0.path == current?.path } ?? 0
        case .tracks:
            // The folder of the song playing, else of the album just listed.
            let path = current?.path ?? albumForList?.tracks.first?.path
            screen = .folders
            highlight = folders.firstIndex { $0.tracks.contains { $0.path == path } } ?? 0
        case .folders: screen = .nowPlaying
        }
    }

    /// The SELECCIÓN knob: one row up or down.
    func moveHighlight(by steps: Int) {
        // Turning the knob on the song screen opens the album list.
        if screen == .nowPlaying { toggleList(); return }
        let count = rows.count
        guard count > 0 else { return }
        highlight = min(max(0, highlight + steps), count - 1)
    }


    /// Enter on a row: an album opens its songs, a song plays.
    func choose(_ row: Int? = nil) {
        let row = row ?? highlight
        switch screen {
        case .nowPlaying: playPause()
        case .albums:
            guard listAlbums.indices.contains(row) else { return }
            screen = .tracks(albumID: listAlbums[row].id)
            highlight = 0
        case .tracks:
            guard let album = albumForList, album.tracks.indices.contains(row) else { return }
            play(album, from: row)
        case .folders:
            guard folders.indices.contains(row) else { return }
            play(folders[row])
        }
    }

    /// The album whose songs the screen lists.
    var albumForList: LibraryAlbum? {
        guard case .tracks(let id) = screen else { return nil }
        return listAlbums.first { $0.id == id }
    }

    /// The rows the knob moves over.
    var rows: [String] {
        switch screen {
        case .nowPlaying: []
        case .albums: listAlbums.map(\.title)
        case .tracks: albumForList?.tracks.map(\.title) ?? []
        case .folders: folders.map(\.name)
        }
    }

    // MARK: - Private

    private func refreshFolders() {
        folders = folder.map { MusicLibrary.folders(albums, root: $0) } ?? []
        favoritesAlbum = folder.flatMap { MusicLibrary.favorites(albums, marked: favorites, root: $0) }
    }

    // MARK: - Favourites

    func isFavorite(_ track: LibraryTrack?) -> Bool {
        guard let track, let folder else { return false }
        return favorites.contains(MusicLibrary.key(of: track, in: folder))
    }

    /// FAVORITA: marks the song that plays, or unmarks it.
    func toggleFavorite() {
        guard let track = current, let folder else { show("NADA SONANDO"); return }
        let key = MusicLibrary.key(of: track, in: folder)
        let marked = !favorites.contains(key)
        if marked { favorites.insert(key) } else { favorites.remove(key) }
        if !Store.isOverridden { FavoritesFile.save(favorites) }
        show(marked ? "FAVORITA ★" : "YA NO ES FAVORITA")
    }

    private func loadCover(for track: LibraryTrack) {
        Task { [weak self] in
            let image = await FileInfo.cover(for: track.url)
            guard self?.current?.path == track.path else { return }
            self?.cover = image
        }
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard isPlaying, let track = current else { return }
        elapsed = playback.currentTime
        if Date.now.timeIntervalSince(lastResumeSave) > 10 { saveResume() }
        // Ten seconds before the end, the next song is opened and queued, so
        // it follows without a gap (unless its sample rate differs).
        guard track.duration - elapsed < 10, preloadedFor != track.path else { return }
        preloadedFor = track.path
        if index + 1 < queue.count {
            let next = queue[index + 1]
            playback.preload(next.url, opened: try? FileTrackReader(url: next.url))
        } else {
            playback.preload(nil)
        }
    }

    func show(_ text: String) {
        flash = text
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { flash = nil }
        }
    }

    /// Snapshots only: a library and a song on screen, nothing read from disk.
    func showDemo(_ album: LibraryAlbum, cover: NSImage?, screen: Screen = .nowPlaying, highlight: Int = 0) {
        guard Store.isOverridden else { return }
        albums = [album, LibraryAlbum(title: "Live in Paris", artist: "Diana Krall", year: "2002", tracks: album.tracks),
                  LibraryAlbum(title: "Kind of Blue", artist: "Miles Davis", year: "1959", tracks: album.tracks)]
        trackCount = 1_240
        folder = URL(fileURLWithPath: "/Volumes/Music")
        favorites = [MusicLibrary.key(of: album.tracks[1], in: folder!)]
        queue = album.tracks
        index = 1
        elapsed = 83
        state = .paused
        self.cover = cover
        self.screen = screen
        self.highlight = highlight
    }
}

/// The library read last time, per folder, so opening the app does not read
/// every file again. Kept beside the app's database.
/// The marked songs, kept on the Mac (never in the music files).
enum FavoritesFile {
    static func load() -> Set<String> {
        guard !Store.isOverridden, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    static func save(_ favorites: Set<String>) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(favorites.sorted()).write(to: url, options: .atomic)
    }

    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "CDPlayer/file-favorites.json")
    }
}

enum LibraryCache {
    static func load(for folder: String) -> [LibraryTrack] {
        guard let data = try? Data(contentsOf: url(for: folder)) else { return [] }
        return (try? JSONDecoder().decode([LibraryTrack].self, from: data)) ?? []
    }

    static func save(_ tracks: [LibraryTrack], for folder: String) {
        let target = url(for: folder)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(tracks).write(to: target, options: .atomic)
        // Files named another way (an older version) are never read again.
        let folder = target.deletingLastPathComponent()
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        where name.count != 64 + ".json".count {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private static func url(for folder: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // One file per folder, named by a fingerprint of its whole path.
        let name = SHA256.hash(data: Data(folder.utf8)).map { String(format: "%02x", $0) }.joined()
        return support.appendingPathComponent("CDPlayer/Library/\(name).json")
    }
}
