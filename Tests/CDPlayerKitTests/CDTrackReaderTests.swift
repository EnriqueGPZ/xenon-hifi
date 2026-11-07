import Foundation
import Testing
@testable import CDPlayerKit

struct CDTrackReaderTests {
    /// A small CD-style file: AIFF-C "sowt" (little-endian, as macOS gives
    /// CD tracks) or plain big-endian AIFF, 16-bit stereo at 44.1 kHz.
    private func makeFile(frames: [(Int16, Int16)], littleEndian: Bool) throws -> URL {
        func be16(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 0xFF)] }
        func be32(_ value: UInt32) -> [UInt8] { be16(UInt16(value >> 16)) + be16(UInt16(value & 0xFFFF)) }
        // 44100 as an 80-bit extended number.
        let rate: [UInt8] = [0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]
        var comm = be16(2) + be32(UInt32(frames.count)) + be16(16) + rate
        if littleEndian { comm += Array("sowt".utf8) + [0, 0] }
        var samples: [UInt8] = []
        for (left, right) in frames {
            for value in [left, right] {
                let bits = UInt16(bitPattern: value)
                samples += littleEndian ? [UInt8(bits & 0xFF), UInt8(bits >> 8)] : be16(bits)
            }
        }
        // Like the real files: the sound starts after a padding offset.
        let padding = [UInt8](repeating: 0, count: 12)
        let ssnd = be32(UInt32(padding.count)) + be32(0) + padding + samples
        var body = Array((littleEndian ? "AIFC" : "AIFF").utf8)
        body += Array("COMM".utf8) + be32(UInt32(comm.count)) + comm
        body += Array("SSND".utf8) + be32(UInt32(ssnd.count)) + ssnd
        let file = Array("FORM".utf8) + be32(UInt32(body.count)) + body
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).aiff")
        try Data(file).write(to: url)
        return url
    }

    @Test(arguments: [true, false])
    func readsSamplesInOrder(littleEndian: Bool) throws {
        let url = try makeFile(frames: [(0, 16_384), (-32_768, 1), (100, -100)], littleEndian: littleEndian)
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = try CDTrackReader(url: url)
        #expect(reader.header.channels == 2)
        #expect(reader.header.frames == 3)
        #expect(reader.header.sampleRate == 44_100)
        #expect(reader.header.littleEndian == littleEndian)

        let buffer = try #require(try reader.read(frames: 2))
        #expect(buffer.frameLength == 2)
        let left = buffer.floatChannelData![0], right = buffer.floatChannelData![1]
        #expect(left[0] == 0 && right[0] == 0.5)
        #expect(left[1] == -1 && right[1] == 1 / 32_768)

        let rest = try #require(try reader.read(frames: 100))
        #expect(rest.frameLength == 1)
        #expect(reader.atEnd)
        #expect(try reader.read(frames: 100) == nil)
    }

    @Test func aCutShortFileIsAnErrorNotTheEnd() throws {
        let url = try makeFile(frames: [(1, 1), (2, 2), (3, 3)], littleEndian: true)
        defer { try? FileManager.default.removeItem(at: url) }
        // Cut the last frame off, as a failing disc would.
        try Data(contentsOf: url).dropLast(4).write(to: url)
        let reader = try CDTrackReader(url: url)
        let rest = try #require(try reader.read(frames: 3))
        #expect(rest.frameLength == 2)
        #expect(try reader.read(frames: 1) == nil)
        // Nil without an end is a failure: the player tries again instead of ending the track.
        #expect(!reader.atEnd)
    }

    @Test func seeksToAFrame() throws {
        let url = try makeFile(frames: (0..<10).map { (Int16($0), 0) }, littleEndian: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = try CDTrackReader(url: url)
        reader.seek(toFrame: 7)
        let buffer = try #require(try reader.read(frames: 10))
        #expect(buffer.frameLength == 3)
        #expect(buffer.floatChannelData![0][0] * 32_768 == 7)
    }

    @Test func rejectsWhatIsNotAIFF() {
        #expect(throws: CDTrackReader.ReadError.notAIFF) { try CDTrackReader.parse(Data("RIFF....WAVE".utf8)) }
    }
}

/// The rule behind the player's retries, with a fake disc that fails a set number of times.
struct DiscReadTests {
    @Test func aFlakyReadRecoversWithinTheTries() {
        var calls = 0, pauses = 0
        let result = DiscRead.chunk(attempts: 3, pause: { pauses += 1 }) { () -> ReadAttempt<Int> in
            calls += 1
            return calls < 3 ? .failed : .sound(7)
        }
        guard case .sound(let value) = result else { return #expect(Bool(false), "expected sound") }
        #expect(value == 7)
        #expect(calls == 3)
        #expect(pauses == 2)
    }

    @Test func aDeadReadGivesUpAfterEveryTry() {
        var calls = 0, pauses = 0
        let result = DiscRead.chunk(attempts: 3, pause: { pauses += 1 }) { () -> ReadAttempt<Int> in
            calls += 1
            return .failed
        }
        guard case .failed = result else { return #expect(Bool(false), "expected failure") }
        #expect(calls == 3)
        #expect(pauses == 2)
    }

    @Test func aSingleTryDoesNotPause() {
        var pauses = 0
        let result = DiscRead.chunk(attempts: 1, pause: { pauses += 1 }) { () -> ReadAttempt<Int> in .failed }
        guard case .failed = result else { return #expect(Bool(false), "expected failure") }
        #expect(pauses == 0)
    }

    @Test func theRealEndIsNotRetried() {
        var calls = 0, pauses = 0
        let result = DiscRead.chunk(attempts: 3, pause: { pauses += 1 }) { () -> ReadAttempt<Int> in
            calls += 1
            return .end
        }
        guard case .end = result else { return #expect(Bool(false), "expected end") }
        #expect(calls == 1)
        #expect(pauses == 0)
    }
}
