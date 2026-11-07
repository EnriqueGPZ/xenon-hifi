import Foundation
import Testing
@testable import CDPlayerKit

struct MusicLibraryTests {
    private func track(_ title: String, album: String = "Love", artist: String = "Diana", albumArtist: String? = nil,
                       number: Int? = nil, disc: Int? = nil, path: String? = nil) -> LibraryTrack {
        LibraryTrack(path: path ?? "/m/\(album)/\(title).flac", title: title, artist: artist, album: album,
                     albumArtist: albumArtist, trackNumber: number, discNumber: disc, duration: 100,
                     format: "FLAC", sampleRate: 96_000, bits: 24, modified: .distantPast)
    }

    @Test func tagsFromEveryFormat() {
        let flac = SongTags([("vorb/TITLE", "Tema"), ("vorb/ARTIST", "Diana"), ("vorb/ALBUM", "Love"),
                             ("vorb/TRACKNUMBER", "2/12"), ("vorb/DATE", "2001-05-01"), ("vorb/DISCNUMBER", "1")])
        #expect(flac.title == "Tema" && flac.artist == "Diana" && flac.album == "Love")
        #expect(flac.trackNumber == 2 && flac.discNumber == 1 && flac.year == "2001")
        let mp3 = SongTags([("id3/TIT2", "Uno"), ("id3/TPE1", "Art"), ("id3/TPE2", "Varios"),
                            ("id3/TRCK", "04"), ("id3/TYER", "1999")])
        #expect(mp3.title == "Uno" && mp3.albumArtist == "Varios" && mp3.trackNumber == 4 && mp3.year == "1999")
        let m4a = SongTags([("itsk/%A9nam", "Dos"), ("itsk/%A9ART", "Art"), ("itsk/%A9alb", "Alb")])
        #expect(m4a.title == "Dos" && m4a.artist == "Art" && m4a.album == "Alb")
        let blank = SongTags([("vorb/TITLE", "  ")])
        #expect(blank.title == nil)
    }

    @Test func qualityLine() {
        #expect(track("a").quality == "FLAC · 24 BIT · 96 KHZ")
        let mp3 = LibraryTrack(path: "/a.mp3", title: "a", artist: "", album: "", duration: 1, format: "MP3",
                               sampleRate: 44_100, bitRate: 320, modified: .distantPast)
        #expect(mp3.quality == "MP3 · 44.1 KHZ · 320 KBPS")
    }

    @Test func albumsGroupAndSortTheirSongs() {
        let albums = MusicLibrary.albums([
            track("b", number: 2), track("a", number: 1), track("c2", number: 1, disc: 2),
            track("x", album: "Zeta", artist: "Abba"),
            track("v1", album: "Mix", artist: "One", albumArtist: "Varios"),
            track("v2", album: "Mix", artist: "Two", albumArtist: "Varios"),
        ])
        #expect(albums.map(\.title) == ["Zeta", "Love", "Mix"])
        #expect(albums[1].tracks.map(\.title) == ["a", "b", "c2"])
        #expect(albums[2].tracks.count == 2)
    }

    @Test func aCompilationWithoutAlbumArtistStaysOneAlbum() {
        let albums = MusicLibrary.albums([track("a", album: "Jazz 1959", artist: "Miles", path: "/m/jazz/01.flac"),
                                          track("b", album: "Jazz 1959", artist: "Coltrane", path: "/m/jazz/02.flac"),
                                          track("c", album: "Jazz 1959", artist: "Miles", path: "/m/otro/01.flac")])
        let jazz = albums.first { $0.tracks.count == 2 }
        #expect(albums.count == 2)
        #expect(jazz?.artist == MusicLibrary.variousArtists)
    }

    @Test func discsInTheirOwnFoldersStayOneAlbum() {
        let albums = MusicLibrary.albums([
            track("a", album: "Live", disc: 1, path: "/m/Live/CD1/01.flac"),
            track("b", album: "Live", disc: 2, path: "/m/Live/Disc 2/01.flac"),
        ])
        #expect(albums.count == 1)
        #expect(albums[0].tracks.map(\.title) == ["a", "b"])
        #expect(MusicLibrary.albumFolder(of: URL(fileURLWithPath: "/m/CDs Favoritos/01.flac")).path == "/m/CDs Favoritos")
        #expect(MusicLibrary.albumFolder(of: URL(fileURLWithPath: "/m/A/Disco 1975/01.flac")).path == "/m/A/Disco 1975")
        #expect(MusicLibrary.albumFolder(of: URL(fileURLWithPath: "/m/A/cd01/01.flac")).path == "/m/A")
    }

    @Test func untaggedSongsKeepFileOrder() {
        let albums = MusicLibrary.albums([track("b", path: "/m/02 b.mp3"), track("a", path: "/m/10 a.mp3"),
                                          track("c", path: "/m/1 c.mp3")])
        #expect(albums[0].tracks.map(\.title) == ["c", "b", "a"])
    }

    @Test func findsMusicFilesOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let album = root.appendingPathComponent("Artista/Album")
        try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["01.flac", "02.MP3", "cover.jpg", ".hidden.flac", "notes.txt"] {
            try Data().write(to: album.appendingPathComponent(name))
        }
        let found = MusicLibrary.musicFiles(in: root).map(\.lastPathComponent)
        #expect(found == ["01.flac", "02.MP3"])
    }

    @Test func flacPictureGivesTheImage() {
        func u32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        let mime = Array("image/jpeg".utf8), image: [UInt8] = [0xFF, 0xD8, 1, 2, 3]
        let block = u32(3) + u32(mime.count) + mime + u32(0) + u32(300) + u32(300) + u32(24) + u32(0)
            + u32(image.count) + image
        #expect(FLACPicture.imageData(Data(block)) == Data(image))
        #expect(FLACPicture.imageData(Data([1, 2, 3])) == nil)
    }

    @Test func aFolderOfLooseSongsIsOneAlbum() {
        let albums = MusicLibrary.albums([
            track("Toro", album: "Toro", artist: "El Columpio", path: "/m/Varios/El Columpio - Toro.flac"),
            track("Atomic", album: "Atomic", artist: "Blondie", path: "/m/Varios/Blondie - Atomic.flac"),
            track("Sunday", album: "Parallel Lines", artist: "Blondie", path: "/m/Varios/Blondie - Sunday.flac"),
            track("Starman", album: "Ziggy", artist: "Bowie", path: "/m/Varios/Bowie - Starman.flac"),
            track("a", album: "Love", number: 1, path: "/m/Diana/Love/01.flac"),
            track("b", album: "Love", number: 2, path: "/m/Diana/Love/02.flac"),
            track("c", album: "Love", number: 3, path: "/m/Diana/Love/03.flac"),
        ])
        #expect(albums.count == 2)
        let varios = albums.first { $0.title == "Varios" }
        #expect(varios?.artist == MusicLibrary.variousArtists)
        #expect(varios?.tracks.map(\.title) == ["Atomic", "Sunday", "Starman", "Toro"])
    }

    @Test func aLoneSongInARecordsFolderJoinsTheRecord() {
        let songs = (1...4).map { track("h\($0)", album: "Grandes Éxitos", artist: "A\($0)", number: $0,
                                         path: "/m/Hits/0\($0).flac") }
            + [track("Islands", album: "Two Sides", artist: "Oldfield", path: "/m/Hits/Islands.flac")]
        let albums = MusicLibrary.albums(songs)
        #expect(albums.count == 1)
        #expect(albums[0].title == "Grandes Éxitos" && albums[0].tracks.count == 5)
    }

    @Test func aRecordWithTwoDiscNamesStaysTwoAlbums() {
        let songs = (1...6).map { track("s\($0)", album: $0 <= 3 ? "Hits CD1" : "Hits CD2", number: $0,
                                         path: "/m/Hits/\($0).flac") }
        #expect(MusicLibrary.albums(songs).count == 2)
    }

    @Test func foldersHoldEverySongBelowThem() {
        let albums = MusicLibrary.albums([
            track("p1", album: "Late Lights", artist: "Mira", number: 1, path: "/m/Mira/Late Lights/01.flac"),
            track("m1", album: "Music", artist: "Mira", number: 1, path: "/m/Mira/Music/01.flac"),
            track("m2", album: "Music", artist: "Mira", number: 2, path: "/m/Mira/Music/02.flac"),
            track("u1", album: "Joshua Tree", artist: "U2", path: "/m/U2/01.flac"),
            track("loose", album: "Single", artist: "X", path: "/m/loose.flac"),
        ])
        let folders = MusicLibrary.folders(albums, root: URL(fileURLWithPath: "/m"))
        #expect(folders.map(\.name) == ["m", "Mira", "U2"])
        #expect(folders[1].tracks.map(\.title) == ["p1", "m1", "m2"])
    }

    @Test func favoritesGatherMarkedSongsFromEveryAlbum() {
        let albums = MusicLibrary.albums([
            track("a", album: "Love", artist: "Diana", number: 1, path: "/Volumes/X/Diana/Love/01.flac"),
            track("b", album: "Love", artist: "Diana", number: 2, path: "/Volumes/X/Diana/Love/02.flac"),
            track("z", album: "Zeta", artist: "Abba", path: "/Volumes/X/Abba/Zeta/01.flac"),
        ])
        let root = URL(fileURLWithPath: "/Volumes/X")
        #expect(MusicLibrary.key(of: albums[1].tracks[1], in: root) == "Diana/Love/02.flac")
        let favorites = MusicLibrary.favorites(albums, marked: ["Diana/Love/02.flac", "Abba/Zeta/01.flac"], root: root)
        #expect(favorites?.tracks.map(\.title) == ["z", "b"])
        #expect(favorites?.isFavorites == true && favorites?.title == "★ Favoritas")
        #expect(MusicLibrary.favorites(albums, marked: [], root: root) == nil)
        // The same folder on a disk with another name keeps its favourites.
        #expect(MusicLibrary.key(of: albums[1].tracks[1], in: URL(fileURLWithPath: "/Volumes/X/")) == "Diana/Love/02.flac")
    }
}
