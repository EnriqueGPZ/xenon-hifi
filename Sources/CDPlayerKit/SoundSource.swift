import AVFAudio
import Foundation

/// Where the player takes the sound of one track from, a big chunk at a
/// time: a CD track (CDTrackReader) or a music file (FileTrackReader).
/// Every read gives stereo, 32-bit float, at the source's own sample rate.
///
/// Not thread-safe: use one source from one thread at a time.
public protocol SoundSource: AnyObject, Sendable {
    /// The next frame a read gives.
    var position: Int64 { get }
    /// No more sound: the real end of the track.
    var atEnd: Bool { get }
    var duration: TimeInterval { get }
    var sampleRate: Double { get }
    func seek(toFrame frame: Int64)
    /// Up to `frames` frames from `position`. Nil at the end; throws when
    /// the disk does not give the sound.
    func read(frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer?
}
