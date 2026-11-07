import AVFAudio
import Foundation

/// Reads a music file (FLAC, MP3, WAV, AIFF, ALAC…) with the Mac's own
/// decoders, at the file's own sample rate and without changing a sample:
/// a 24-bit 96 kHz FLAC comes out as 96 kHz, ready for the DAC as it is.
/// Mono files come out on both channels.
public final class FileTrackReader: SoundSource, @unchecked Sendable {
    public enum ReadError: Error, Equatable {
        /// More than two channels (surround files).
        case unsupported
    }

    /// The file types the player opens.
    public static let extensions: Set<String> = ["flac", "mp3", "m4a", "wav", "aif", "aiff", "aifc", "caf"]

    public let url: URL
    /// Stereo float at the file's rate: what every read gives.
    public let format: AVAudioFormat
    public private(set) var position: Int64 = 0
    /// Frames in the file. MP3 headers can overstate it: the real end found
    /// while reading takes its place.
    public private(set) var frames: Int64
    public var atEnd: Bool { position >= frames }
    public var duration: TimeInterval { Double(frames) / format.sampleRate }
    public var sampleRate: Double { format.sampleRate }

    private let file: AVAudioFile
    private let mono: Bool

    public init(url: URL) throws {
        self.url = url
        file = try AVAudioFile(forReading: url)
        let channels = file.processingFormat.channelCount
        guard channels == 1 || channels == 2,
              let format = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 2)
        else { throw ReadError.unsupported }
        self.format = format
        mono = channels == 1
        frames = file.length
    }

    public func seek(toFrame frame: Int64) {
        position = min(max(0, frame), frames)
    }

    public func read(frames wanted: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        let count = AVAudioFrameCount(min(Int64(wanted), frames - position))
        guard count > 0 else { return nil }
        // From where the last good read stopped, so a retry loses nothing.
        file.framePosition = position
        guard let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { return nil }
        do {
            try file.read(into: raw, frameCount: count)
        } catch let error as NSError where error.code == Self.endOfFile {
            raw.frameLength = 0
        }
        let got = raw.frameLength
        guard got > 0 else {
            // The file ends before its header said: that is its real end.
            frames = position
            return nil
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: got),
              let source = raw.floatChannelData, let target = buffer.floatChannelData else { return nil }
        buffer.frameLength = got
        let bytes = Int(got) * MemoryLayout<Float>.size
        memcpy(target[0], source[0], bytes)
        memcpy(target[1], source[mono ? 0 : 1], bytes)
        position += Int64(got)
        return buffer
    }

    /// Core Audio's "end of file" (eofErr).
    private static let endOfFile = -39
}
