import Foundation
import Testing
@testable import CDPlayerKit

/// "The Best Of Sade", read from a real CD's .TOC.plist.
private let sadeStarts = [150, 16742, 37202, 56800, 81620, 102492, 131257, 149222,
                          168740, 185180, 202925, 236092, 252675, 271642, 288380, 316867]

private func sadePlist() -> Data {
    let tracks = sadeStarts.enumerated().map { index, start in
        ["Point": index + 1, "Start Block": start, "Data": false, "Session Number": 1] as [String: Any]
    }
    let root: [String: Any] = ["Sessions": [[
        "First Track": 1, "Last Track": 16, "Leadout Block": 337_375,
        "Session Number": 1, "Session Type": 0, "Track Array": tracks,
    ]]]
    return try! PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
}

@Test("Reads a real table of contents")
func readsTOC() throws {
    let toc = try #require(DiscTOC(plist: sadePlist()))
    #expect(toc.firstTrack == 1)
    #expect(toc.lastTrack == 16)
    #expect(toc.audioEntries.count == 16)
}

@Test("Computes the MusicBrainz disc ID")
func discID() throws {
    let toc = try #require(DiscTOC(plist: sadePlist()))
    #expect(toc.musicBrainzID == "OKHpuyKx9Fy7jvHkgynIA3faxgI-")
}

@Test("Track lengths come from the block offsets")
func durations() throws {
    let toc = try #require(DiscTOC(plist: sadePlist()))
    #expect(abs(toc.duration(ofTrack: 1) - 221.226) < 0.01)
    #expect(abs(toc.duration(ofTrack: 16) - Double(337_375 - 316_867) / 75) < 0.01)
    #expect(abs(toc.totalDuration - Double(337_375 - 150) / 75) < 0.01)
}

@Test("A data track ends the audio but counts in the disc ID")
func dataTrack() {
    let toc = DiscTOC(firstTrack: 1, lastTrack: 3, leadoutBlock: 90_000, entries: [
        .init(number: 1, startBlock: 150), .init(number: 2, startBlock: 20_000),
        .init(number: 3, startBlock: 60_000, isData: true),
    ])
    #expect(toc.audioEntries.map(\.number) == [1, 2])
    #expect(toc.musicBrainzID.count == 28)
}

@Test("Rejects a plist that is not a table of contents")
func rejectsGarbage() {
    #expect(DiscTOC(plist: Data("hola".utf8)) == nil)
}

@Test("Reads macOS track file names", arguments: [
    ("1 Your Love Is King.aiff", 1, "Your Love Is King" as String?),
    ("12 Like A Tattoo.aiff", 12, "Like A Tattoo"),
    ("3 Audio Track.aiff", 3, nil),
    ("7.aiff", 7, nil),
])
func fileNames(_ name: String, number: Int, title: String?) throws {
    let parsed = try #require(TrackFileName.parse(name))
    #expect(parsed.number == number)
    #expect(parsed.title == title)
}

@Test("Skips files that are not tracks")
func notTracks() {
    #expect(TrackFileName.parse(".TOC.plist") == nil)
    #expect(TrackFileName.parse("Notas.aiff") == nil)
}

private let reply = """
{"releases":[{"title":"The Best of Sade","date":"1994-10-31",
 "artist-credit":[{"name":"Sade","joinphrase":""}],
 "media":[{"discs":[{"id":"OKHpuyKx9Fy7jvHkgynIA3faxgI-"}],
  "tracks":[{"position":1,"title":"Your Love Is King","artist-credit":[{"name":"Sade"}]},
            {"position":2,"title":"Hang On to Your Love","artist-credit":[{"name":"Sade"}]},
            {"position":3,"title":"Duet","artist-credit":[{"name":"Sade","joinphrase":" & "},{"name":"Guest"}]}]}]}]}
"""

@Test("Reads album, artist, year, and titles from MusicBrainz")
func parsesMetadata() throws {
    let meta = try #require(DiscMetadata.parse(Data(reply.utf8), discID: "OKHpuyKx9Fy7jvHkgynIA3faxgI-"))
    #expect(meta.album == "The Best of Sade")
    #expect(meta.artist == "Sade")
    #expect(meta.year == "1994")
    #expect(meta.tracks[2]?.title == "Hang On to Your Love")
    #expect(meta.tracks[1]?.artist == nil)
    #expect(meta.tracks[3]?.artist == "Sade & Guest")
}

@Test("An unknown disc gives no metadata")
func unknownDisc() {
    #expect(DiscMetadata.parse(Data(#"{"error":"Not Found"}"#.utf8), discID: "x") == nil)
    #expect(DiscMetadata.parse(Data(#"{"releases":[]}"#.utf8), discID: "x") == nil)
}

@Test("The lookup address asks for recordings and artists as JSON")
func lookupURL() throws {
    let url = try #require(DiscMetadata.lookupURL(discID: "OKHpuyKx9Fy7jvHkgynIA3faxgI-"))
    #expect(url.absoluteString.hasPrefix("https://musicbrainz.org/ws/2/discid/OKHpuyKx9Fy7jvHkgynIA3faxgI-?"))
    #expect(url.absoluteString.contains("fmt=json"))
    // Each medium's discs come back only with discids (MusicBrainz WS/2 docs, discid lookup).
    #expect(url.absoluteString.contains("discids"))
}
