import CryptoKit
import Foundation

/// The table of contents of an audio CD, as macOS writes it in the hidden
/// `.TOC.plist` at the root of a mounted CD (cddafs). Block numbers there
/// already include the 150-frame lead-in, which is what MusicBrainz expects.
public struct DiscTOC: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let number: Int
        public let startBlock: Int
        public let isData: Bool

        public init(number: Int, startBlock: Int, isData: Bool = false) {
            self.number = number
            self.startBlock = startBlock
            self.isData = isData
        }
    }

    public static let framesPerSecond = 75.0

    public let firstTrack: Int
    public let lastTrack: Int
    public let leadoutBlock: Int
    public let entries: [Entry]

    public init(firstTrack: Int, lastTrack: Int, leadoutBlock: Int, entries: [Entry]) {
        self.firstTrack = firstTrack
        self.lastTrack = lastTrack
        self.leadoutBlock = leadoutBlock
        self.entries = entries.sorted { $0.number < $1.number }
    }

    /// Reads the first session of a `.TOC.plist`. Returns nil for anything
    /// that is not an audio CD's table of contents.
    public init?(plist data: Data) {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let session = (root["Sessions"] as? [[String: Any]])?.first,
              let first = session["First Track"] as? Int,
              let last = session["Last Track"] as? Int,
              let leadout = session["Leadout Block"] as? Int,
              let array = session["Track Array"] as? [[String: Any]] else { return nil }
        let entries = array.compactMap { item -> Entry? in
            guard let point = item["Point"] as? Int, let start = item["Start Block"] as? Int else { return nil }
            return Entry(number: point, startBlock: start, isData: item["Data"] as? Bool ?? false)
        }
        guard !entries.isEmpty, first <= last else { return nil }
        self.init(firstTrack: first, lastTrack: last, leadoutBlock: leadout, entries: entries)
    }

    /// The audio tracks only: an enhanced CD can end with a data track.
    public var audioEntries: [Entry] { entries.filter { !$0.isData } }

    /// Seconds from this track's start to the next one's (or the lead-out).
    public func duration(ofTrack number: Int) -> TimeInterval {
        guard let index = entries.firstIndex(where: { $0.number == number }) else { return 0 }
        let end = index + 1 < entries.count ? entries[index + 1].startBlock : leadoutBlock
        return Double(end - entries[index].startBlock) / Self.framesPerSecond
    }

    public var totalDuration: TimeInterval {
        audioEntries.reduce(0) { $0 + duration(ofTrack: $1.number) }
    }

    /// The MusicBrainz disc ID: SHA-1 of the first and last track, the
    /// lead-out, and 99 track offsets in upper-case hex, in base64 with
    /// `.`, `_` and `-` for `+`, `/` and `=`.
    public var musicBrainzID: String {
        var text = String(format: "%02X%02X%08X", firstTrack, lastTrack, leadoutBlock)
        let offsets = Dictionary(entries.map { ($0.number, $0.startBlock) }, uniquingKeysWith: { first, _ in first })
        for number in 1...99 {
            text += String(format: "%08X", offsets[number] ?? 0)
        }
        let digest = Insecure.SHA1.hash(data: Data(text.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: ".")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "-")
    }
}

/// macOS names each track file on a mounted CD "<number> <title>.aiff".
/// The title is "Audio Track" when macOS does not know it.
public enum TrackFileName {
    public static func parse(_ fileName: String) -> (number: Int, title: String?)? {
        guard fileName.lowercased().hasSuffix(".aiff") else { return nil }
        let stem = String(fileName.dropLast(5))
        let parts = stem.split(separator: " ", maxSplits: 1)
        guard let first = parts.first, let number = Int(first) else { return nil }
        let title = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        let unknown = title.isEmpty || title.caseInsensitiveCompare("Audio Track") == .orderedSame
        return (number, unknown ? nil : title)
    }
}
