import AVFAudio
import Foundation

/// Reads the sound of one track from the .aiff file macOS shows for it on
/// an audio CD, in big chunks. USB drives deliver big reads fast but small
/// ones very slowly, so the player reads a couple of seconds at a time
/// ahead of what is playing, like a CD player's anti-skip memory.
///
/// Not thread-safe: use one reader from one thread at a time.
public final class CDTrackReader: SoundSource, @unchecked Sendable {
    public enum ReadError: Error, Equatable {
        case notAIFF
        case unsupported
    }

    /// What the file's header says.
    public struct Header: Equatable, Sendable {
        public var channels: Int
        public var frames: Int64
        public var bitsPerSample: Int
        public var sampleRate: Double
        public var littleEndian: Bool
        /// Where the first sample starts in the file, in bytes.
        public var dataOffset: UInt64
    }

    public let url: URL
    public let header: Header
    public private(set) var position: Int64 = 0
    public var atEnd: Bool { position >= header.frames }
    public var duration: TimeInterval { Double(header.frames) / header.sampleRate }
    public var sampleRate: Double { header.sampleRate }

    private let handle: FileHandle
    private let format: AVAudioFormat
    private var bytesPerFrame: Int { header.channels * 2 }

    public init(url: URL) throws {
        self.url = url
        handle = try FileHandle(forReadingFrom: url)
        let start = try handle.read(upToCount: 4096) ?? Data()
        header = try Self.parse(start)
        guard header.bitsPerSample == 16, header.channels > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: header.sampleRate,
                                         channels: AVAudioChannelCount(header.channels))
        else { throw ReadError.unsupported }
        self.format = format
    }

    public func seek(toFrame frame: Int64) {
        position = min(max(0, frame), header.frames)
    }

    /// Up to `frames` of sound from the current position, as float samples,
    /// in one read from the disc. Nil at the end of the track.
    public func read(frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        let wanted = min(Int64(frames), header.frames - position)
        guard wanted > 0 else { return nil }
        try handle.seek(toOffset: header.dataOffset + UInt64(position) * UInt64(bytesPerFrame))
        let data = try handle.read(upToCount: Int(wanted) * bytesPerFrame) ?? Data()
        let got = data.count / bytesPerFrame
        guard got > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(got)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(got)
        let channelCount = header.channels
        let little = header.littleEndian
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for frame in 0..<got {
                for channel in 0..<channelCount {
                    let index = (frame * channelCount + channel) * 2
                    let first = UInt16(raw[index]), second = UInt16(raw[index + 1])
                    let bits = little ? (second << 8 | first) : (first << 8 | second)
                    channels[channel][frame] = Float(Int16(bitPattern: bits)) / 32_768
                }
            }
        }
        position += Int64(got)
        return buffer
    }

    // MARK: - Header

    /// Reads an AIFF or AIFF-C header (big-endian, or little-endian "sowt"
    /// as macOS gives for CD tracks).
    public static func parse(_ data: Data) throws -> Header {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, String(bytes: bytes[0..<4], encoding: .ascii) == "FORM" else { throw ReadError.notAIFF }
        let form = String(bytes: bytes[8..<12], encoding: .ascii)
        guard form == "AIFF" || form == "AIFC" else { throw ReadError.notAIFF }

        var channels: Int?, frames: Int64 = 0, bits = 0, rate = 0.0, little = false
        var cursor = 12
        while cursor + 8 <= bytes.count {
            let id = String(bytes: bytes[cursor..<cursor + 4], encoding: .ascii) ?? ""
            let size = Int(uint32(bytes, cursor + 4))
            let body = cursor + 8
            switch id {
            case "COMM":
                guard body + 18 <= bytes.count else { throw ReadError.notAIFF }
                channels = Int(uint16(bytes, body))
                frames = Int64(uint32(bytes, body + 2))
                bits = Int(uint16(bytes, body + 6))
                rate = extended(bytes, body + 8)
                if form == "AIFC" {
                    guard body + 22 <= bytes.count else { throw ReadError.notAIFF }
                    let compression = String(bytes: bytes[body + 18..<body + 22], encoding: .ascii)
                    switch compression {
                    case "sowt": little = true
                    case "NONE", "twos": little = false
                    default: throw ReadError.unsupported
                    }
                }
            case "SSND":
                guard let channels, body + 8 <= bytes.count else { throw ReadError.notAIFF }
                let offset = UInt64(uint32(bytes, body))
                return Header(channels: channels, frames: frames, bitsPerSample: bits, sampleRate: rate,
                              littleEndian: little, dataOffset: UInt64(body + 8) + offset)
            default:
                break
            }
            cursor = body + size + (size & 1)
        }
        throw ReadError.notAIFF
    }

    private static func uint16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        UInt16(bytes[at]) << 8 | UInt16(bytes[at + 1])
    }

    private static func uint32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(uint16(bytes, at)) << 16 | UInt32(uint16(bytes, at + 2))
    }

    /// The 80-bit number AIFF uses for the sample rate.
    private static func extended(_ bytes: [UInt8], _ at: Int) -> Double {
        let exponent = Int(uint16(bytes, at) & 0x7FFF)
        var mantissa: UInt64 = 0
        for index in 0..<8 { mantissa = mantissa << 8 | UInt64(bytes[at + 2 + index]) }
        guard mantissa != 0 else { return 0 }
        return Double(mantissa) * pow(2, Double(exponent - 16_383 - 63))
    }
}

/// What one read of a track gave.
public enum ReadAttempt<Sound> {
    case sound(Sound)
    /// Nothing and no error: the real end of the track.
    case end
    /// The read failed (an error, or short of the end): the disc did not give the sound.
    case failed
}

/// Reads a chunk, trying again when a read fails (a scratch or a loose cable
/// often passes). Stops at the first sound or at the real end; `.failed` only
/// when every try failed.
public enum DiscRead {
    public static func chunk<Sound>(attempts: Int, pause: () -> Void,
                                    _ attempt: () -> ReadAttempt<Sound>) -> ReadAttempt<Sound> {
        for count in 1...max(1, attempts) {
            let result = attempt()
            guard case .failed = result else { return result }
            if count < attempts { pause() }
        }
        return .failed
    }
}
