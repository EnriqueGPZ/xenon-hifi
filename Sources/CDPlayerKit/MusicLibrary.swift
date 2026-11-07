import Foundation

/// One song file in the music library, with what its tags and its sound say.
public struct LibraryTrack: Codable, Hashable, Sendable {
    public var path: String
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var year: String?
    public var duration: TimeInterval
    /// "FLAC", "MP3", "ALAC", "AAC", "WAV", "AIFF".
    public var format: String
    public var sampleRate: Double
    /// Bits per sample of lossless files; nil for MP3 and AAC.
    public var bits: Int?
    /// kbit/s, for MP3 and AAC.
    public var bitRate: Int?
    /// When the file last changed: a changed file is read again.
    public var modified: Date

    public var url: URL { URL(fileURLWithPath: path) }

    public init(path: String, title: String, artist: String, album: String, albumArtist: String? = nil,
                trackNumber: Int? = nil, discNumber: Int? = nil, year: String? = nil, duration: TimeInterval,
                format: String, sampleRate: Double, bits: Int? = nil, bitRate: Int? = nil, modified: Date) {
        self.path = path
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.year = year
        self.duration = duration
        self.format = format
        self.sampleRate = sampleRate
        self.bits = bits
        self.bitRate = bitRate
        self.modified = modified
    }

    /// "FLAC · 24 BIT · 96 KHZ", "MP3 · 44.1 KHZ · 320 KBPS".
    public var quality: String {
        let khz = sampleRate / 1000
        let rate = khz == khz.rounded() ? String(Int(khz)) : String(format: "%.1f", khz)
        var parts = [format]
        if let bits { parts.append("\(bits) BIT") }
        parts.append("\(rate) KHZ")
        if let bitRate { parts.append("\(bitRate) KBPS") }
        return parts.joined(separator: " · ")
    }
}

/// An album: the songs that share an album name and album artist.
public struct LibraryAlbum: Hashable, Sendable, Identifiable {
    /// The album name with its album artist or, without one, its folder:
    /// a compilation whose songs each name a different artist stays one album.
    public var id: String
    public var title: String
    public var artist: String
    public var year: String?
    /// In play order: disc, then track number, then file name.
    public var tracks: [LibraryTrack]

    /// The ★ Favoritas list, made from the marked songs of every album.
    public var isFavorites: Bool { id == MusicLibrary.favoritesID }

    /// Loose songs of one folder ("Varios"), not a record: no track numbers.
    public var isLooseSongs: Bool { id.hasPrefix(MusicLibrary.looseKey) || isFavorites }

    public init(title: String, artist: String, year: String?, tracks: [LibraryTrack], id: String? = nil) {
        self.id = id ?? artist.lowercased() + "\u{1}" + title.lowercased()
        self.title = title
        self.artist = artist
        self.year = year
        self.tracks = tracks
    }
}

/// A folder right inside the music folder, with every song below it.
public struct LibraryFolder: Hashable, Sendable, Identifiable {
    public var id: String { path }
    public var path: String
    public var name: String
    /// Album by album, in folder order.
    public var tracks: [LibraryTrack]

    public init(path: String, name: String, tracks: [LibraryTrack]) {
        self.path = path
        self.name = name
        self.tracks = tracks
    }
}

public enum MusicLibrary {
    public static let variousArtists = "VARIOS ARTISTAS"
    static let looseKey = "mix\u{1}"
    public static let favoritesID = "\u{1}favorites"
    public static let favoritesTitle = "★ Favoritas"

    /// A song's name inside the music folder ("Mira/Music/01.flac"):
    /// favourites keep it, so they survive the folder moving or its disk
    /// changing name.
    public static func key(of track: LibraryTrack, in root: URL) -> String {
        let base = root.standardizedFileURL.path
        let path = track.url.standardizedFileURL.path
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    /// The marked songs of the whole library, album by album; nil when none.
    public static func favorites(_ albums: [LibraryAlbum], marked: Set<String>, root: URL) -> LibraryAlbum? {
        let tracks = albums.flatMap(\.tracks).filter { marked.contains(key(of: $0, in: root)) }
        guard !tracks.isEmpty else { return nil }
        return LibraryAlbum(title: favoritesTitle, artist: tracks.count == 1 ? "1 canción" : "\(tracks.count) canciones",
                            year: nil, tracks: tracks, id: favoritesID)
    }

    /// Every music file under `root`, hidden files and folders left out.
    public static func musicFiles(in root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker
        where FileTrackReader.extensions.contains(url.pathExtension.lowercased()) {
            found.append(url)
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// The songs grouped into albums, albums by artist then title.
    /// A folder of loose songs from many different albums ("Varios") is one
    /// album named after the folder, its songs in file order. A lone song in
    /// a record's folder that names another album joins that record.
    public static func albums(_ tracks: [LibraryTrack]) -> [LibraryAlbum] {
        struct Placed { var track: LibraryTrack; var key: String; var title: String; var stray = false }
        var placed = tracks.map { track in
            let folder = albumFolder(of: track.url)
            let owner = track.albumArtist?.lowercased() ?? folder.path
            return Placed(track: track, key: owner + "\u{1}" + track.album.lowercased(), title: track.album)
        }
        let byFolder = Dictionary(grouping: placed.indices) { albumFolder(of: placed[$0].track.url).path }
        for (folder, members) in byFolder where members.count >= 3 {
            let counts = Dictionary(members.map { (placed[$0].key, 1) }, uniquingKeysWith: +)
            if counts.count * 2 > members.count {
                for i in members {
                    placed[i].key = looseKey + folder
                    placed[i].title = URL(fileURLWithPath: folder).lastPathComponent
                }
            } else if let main = counts.max(by: { $0.value < $1.value }), main.value >= 3 {
                for i in members where counts[placed[i].key] == 1 {
                    placed[i].key = main.key
                    placed[i].stray = true
                }
            }
        }
        var groups: [String: LibraryAlbum] = [:]
        // The record's own songs first: they give the album its name.
        for item in placed.filter({ !$0.stray }) + placed.filter(\.stray) {
            var album = groups[item.key] ?? LibraryAlbum(title: item.title,
                                                         artist: item.track.albumArtist ?? item.track.artist,
                                                         year: item.track.year, tracks: [], id: item.key)
            album.tracks.append(item.track)
            if album.year == nil { album.year = item.track.year }
            groups[item.key] = album
        }
        return groups.values.map { album in
            var album = album
            let isMix = album.isLooseSongs
            album.tracks.sort(by: isMix ? fileOrder : playOrder)
            if isMix { album.year = nil }
            // No album artist and songs by several: a compilation.
            if isMix || album.tracks.first?.albumArtist == nil, Set(album.tracks.map(\.artist)).count > 1 {
                album.artist = variousArtists
            }
            return album
        }
        .sorted {
            let artists = $0.artist.localizedStandardCompare($1.artist)
            if artists != .orderedSame { return artists == .orderedAscending }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    /// The folders right inside the music folder, each with every song below
    /// it: its albums in folder order, each album in play order. Songs lying
    /// loose in the music folder itself make a row named after it.
    public static func folders(_ albums: [LibraryAlbum], root: URL) -> [LibraryFolder] {
        let base = root.standardizedFileURL.pathComponents
        var groups: [String: [LibraryAlbum]] = [:]
        for album in albums {
            var parts: [String: [LibraryTrack]] = [:]
            for track in album.tracks {
                let components = track.url.standardizedFileURL.pathComponents
                let top = components.count > base.count + 1 && Array(components.prefix(base.count)) == base
                    ? NSString.path(withComponents: Array(components.prefix(base.count + 1)))
                    : root.standardizedFileURL.path
                parts[top, default: []].append(track)
            }
            for (top, tracks) in parts {
                groups[top, default: []].append(LibraryAlbum(title: album.title, artist: album.artist,
                                                             year: album.year, tracks: tracks, id: album.id))
            }
        }
        return groups.map { path, albums in
            let ordered = albums.sorted { fileOrder($0.tracks[0], $1.tracks[0]) }
            return LibraryFolder(path: path, name: URL(fileURLWithPath: path).lastPathComponent,
                                 tracks: ordered.flatMap(\.tracks))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The folder an album lives in. Discs kept in their own subfolders
    /// ("CD1", "Disc 2") belong to the folder above.
    static func albumFolder(of file: URL) -> URL {
        let folder = file.deletingLastPathComponent()
        let name = folder.lastPathComponent.lowercased()
        // One or two digits: "Disco 1975" is an album, not disc 1975.
        let isDisc = ["cd", "disc", "disk", "disco"].contains { prefix in
            guard name.hasPrefix(prefix) else { return false }
            let number = name.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return (1...2).contains(number.count) && number.allSatisfy(\.isNumber)
        }
        return isDisc ? folder.deletingLastPathComponent() : folder
    }

    static func fileOrder(_ a: LibraryTrack, _ b: LibraryTrack) -> Bool {
        a.path.localizedStandardCompare(b.path) == .orderedAscending
    }

    static func playOrder(_ a: LibraryTrack, _ b: LibraryTrack) -> Bool {
        if (a.discNumber ?? 1) != (b.discNumber ?? 1) { return (a.discNumber ?? 1) < (b.discNumber ?? 1) }
        if let x = a.trackNumber, let y = b.trackNumber, x != y { return x < y }
        return a.path.localizedStandardCompare(b.path) == .orderedAscending
    }
}

/// What a file's tags say, from the tag names of FLAC (Vorbis comments),
/// MP3 (ID3) and M4A (iTunes), as AVFoundation reports them ("vorb/TITLE",
/// "id3/TIT2", "itsk/%A9nam", "common/title").
public struct SongTags: Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var year: String?

    public init() {}

    public init(_ pairs: [(identifier: String, value: String)]) {
        for (identifier, raw) in pairs {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            // iTunes keys start with © written as "%A9" (a Latin-1 byte, not UTF-8).
            let key = (identifier.split(separator: "/", maxSplits: 1).last.map(String.init) ?? identifier)
                .replacingOccurrences(of: "%A9", with: "©", options: .caseInsensitive).uppercased()
            switch key {
            case "TITLE", "TIT2", "©NAM", "TT2": title = title ?? value
            case "ARTIST", "TPE1", "©ART", "TP1": artist = artist ?? value
            case "ALBUM", "TALB", "©ALB", "TAL": album = album ?? value
            case "ALBUMARTIST", "ALBUM ARTIST", "TPE2", "AART", "TP2": albumArtist = albumArtist ?? value
            case "TRACKNUMBER", "TRCK", "TRKN", "TRK": trackNumber = trackNumber ?? Self.number(value)
            case "DISCNUMBER", "TPOS", "DISK", "TPA": discNumber = discNumber ?? Self.number(value)
            case "DATE", "YEAR", "TDRC", "TYER", "©DAY", "TYE":
                if year == nil, value.count >= 4 { year = String(value.prefix(4)) }
            default: break
            }
        }
    }

    /// "2", "02", "2/12" → 2.
    static func number(_ text: String) -> Int? {
        Int(text.split(separator: "/").first?.trimmingCharacters(in: .whitespaces) ?? "")
    }
}

/// The picture inside a FLAC file (a METADATA_BLOCK_PICTURE): the image bytes.
public enum FLACPicture {
    public static func imageData(_ block: Data) -> Data? {
        let bytes = [UInt8](block)
        var at = 0
        func u32() -> Int? {
            guard at + 4 <= bytes.count else { return nil }
            defer { at += 4 }
            return Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3])
        }
        guard u32() != nil, let mime = u32() else { return nil }
        at += mime
        guard let description = u32() else { return nil }
        at += description + 16
        guard let length = u32(), length > 0, at + length <= bytes.count else { return nil }
        return Data(bytes[at..<at + length])
    }
}
