import Foundation

/// Album, artist, year, and track titles for one disc, from MusicBrainz.
public struct DiscMetadata: Equatable, Sendable {
    public struct TrackInfo: Equatable, Sendable {
        public let title: String
        /// Set only when it differs from the album artist (compilations).
        public let artist: String?
    }

    public let album: String
    public let artist: String
    public let year: String
    public let tracks: [Int: TrackInfo]

    /// The lookup address for a disc ID (MusicBrainz web service, JSON).
    public static func lookupURL(discID: String) -> URL? {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/discid/\(discID)")
        components?.queryItems = [
            // discids: without it MusicBrainz leaves out each medium's discs, so
            // a multi-disc set (the disc is on one medium) is never found.
            URLQueryItem(name: "inc", value: "recordings artist-credits discids"),
            URLQueryItem(name: "fmt", value: "json"),
        ]
        return components?.url
    }

    /// Picks the first release that holds this exact disc and reads its
    /// medium. Returns nil when MusicBrainz does not know the disc.
    public static func parse(_ data: Data, discID: String) -> DiscMetadata? {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return nil }
        for release in reply.releases ?? [] {
            guard let medium = release.media.first(where: { $0.discs?.contains { $0.id == discID } == true })
                ?? (release.media.count == 1 ? release.media.first : nil) else { continue }
            let albumArtist = Credit.joined(release.artistCredit)
            var tracks: [Int: TrackInfo] = [:]
            for track in medium.tracks ?? [] {
                let artist = Credit.joined(track.artistCredit)
                tracks[track.position] = TrackInfo(title: track.title,
                                                   artist: artist.isEmpty || artist == albumArtist ? nil : artist)
            }
            guard !tracks.isEmpty else { continue }
            return DiscMetadata(album: release.title, artist: albumArtist,
                                year: String((release.date ?? "").prefix(4)), tracks: tracks)
        }
        return nil
    }

    private struct Reply: Decodable {
        let releases: [Release]?
    }

    private struct Release: Decodable {
        let title: String
        let date: String?
        let artistCredit: [Credit]?
        let media: [Medium]

        enum CodingKeys: String, CodingKey {
            case title, date, media
            case artistCredit = "artist-credit"
        }
    }

    private struct Medium: Decodable {
        let discs: [DiscRef]?
        let tracks: [Track]?
    }

    private struct DiscRef: Decodable {
        let id: String
    }

    private struct Track: Decodable {
        let position: Int
        let title: String
        let artistCredit: [Credit]?

        enum CodingKeys: String, CodingKey {
            case position, title
            case artistCredit = "artist-credit"
        }
    }

    private struct Credit: Decodable {
        let name: String
        let joinphrase: String?

        static func joined(_ credits: [Credit]?) -> String {
            (credits ?? []).map { $0.name + ($0.joinphrase ?? "") }.joined()
                .trimmingCharacters(in: .whitespaces)
        }
    }
}
