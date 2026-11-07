import AVFAudio
import Foundation
import Testing
@testable import CDPlayerKit

struct FileTrackReaderTests {
    /// Writes a file of the given kind with a known ramp of 24-bit values,
    /// so a lossless read must give them back exactly.
    private func makeFile(ext: String, formatID: AudioFormatID, rate: Double, channels: AVAudioChannelCount,
                          bits: Int, frames: Int) throws -> (URL, [[Float]]) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        var settings: [String: Any] = [AVFormatIDKey: formatID, AVSampleRateKey: rate,
                                       AVNumberOfChannelsKey: channels]
        if formatID == kAudioFormatLinearPCM {
            settings[AVLinearPCMBitDepthKey] = bits
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = false
        } else {
            settings[AVEncoderBitDepthHintKey] = bits
        }
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = file.processingFormat
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        let scale = Float(1 << (bits - 1))
        var written: [[Float]] = []
        for channel in 0..<Int(channels) {
            let values = (0..<frames).map { frame in
                Float((frame * 37 + channel * 1000) % Int(scale) - Int(scale) / 2) / scale
            }
            for (index, value) in values.enumerated() { buffer.floatChannelData![channel][index] = value }
            written.append(values)
        }
        try file.write(from: buffer)
        return (url, written)
    }

    private func readAll(_ reader: FileTrackReader, chunk: AVAudioFrameCount) throws -> [[Float]] {
        var out: [[Float]] = [[], []]
        while let buffer = try reader.read(frames: chunk) {
            #expect(buffer.format.channelCount == 2)
            #expect(buffer.format.sampleRate == reader.sampleRate)
            for channel in 0..<2 {
                out[channel] += Array(UnsafeBufferPointer(start: buffer.floatChannelData![channel],
                                                         count: Int(buffer.frameLength)))
            }
        }
        return out
    }

    @Test func flac24Bit96kHzComesBackExactAtItsOwnRate() throws {
        let (url, written) = try makeFile(ext: "flac", formatID: kAudioFormatFLAC, rate: 96_000, channels: 2,
                                          bits: 24, frames: 50_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = try FileTrackReader(url: url)
        #expect(reader.sampleRate == 96_000)
        #expect(reader.frames == 50_000)
        let read = try readAll(reader, chunk: 8_192)
        #expect(read[0] == written[0])
        #expect(read[1] == written[1])
        #expect(reader.atEnd)
    }

    @Test func monoComesOutOnBothChannels() throws {
        let (url, written) = try makeFile(ext: "wav", formatID: kAudioFormatLinearPCM, rate: 48_000, channels: 1,
                                          bits: 16, frames: 3_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = try FileTrackReader(url: url)
        let read = try readAll(reader, chunk: 1_000)
        #expect(read[0] == written[0])
        #expect(read[1] == written[0])
    }

    @Test func seekReadsFromThere() throws {
        let (url, written) = try makeFile(ext: "flac", formatID: kAudioFormatFLAC, rate: 44_100, channels: 2,
                                          bits: 16, frames: 20_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = try FileTrackReader(url: url)
        reader.seek(toFrame: 12_345)
        let read = try readAll(reader, chunk: 4_096)
        #expect(read[0] == Array(written[0][12_345...]))
        reader.seek(toFrame: 99_999)
        #expect(reader.atEnd)
        #expect(try reader.read(frames: 100) == nil)
    }

    @Test func surroundIsRefused() throws {
        let (url, _) = try makeFile(ext: "wav", formatID: kAudioFormatLinearPCM, rate: 48_000, channels: 6,
                                    bits: 16, frames: 100)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: FileTrackReader.ReadError.unsupported) { try FileTrackReader(url: url) }
    }
}
