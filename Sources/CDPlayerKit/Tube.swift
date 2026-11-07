import Accelerate
import Foundation

/// The tube preamp's sound: one hi-fi triode stage (the kind of ECC88 or
/// 12AU7 stage in a valve preamp), in software.
///
/// A triode amplifies a little more one way than the other, so it bends the
/// wave unevenly. That adds mostly even harmonics (the 2nd, an octave up),
/// which the ear hears as warmth and body rather than as distortion.
///
/// The curve is a biased tanh, `tanh(u + b) - tanh(b)`, the classic model
/// of a triode near its working point, scaled so quiet sound keeps exactly
/// its level (gain 1): the loudness stays the same and only the colour
/// changes. Written as `tanh(u) / (1 + t·tanh(u))` with `t = tanh(b)`, the
/// same curve without subtracting two close numbers. With `t = 0.5` the
/// 2nd harmonic leads by far; the 3rd stays some 30 dB under it.
///
/// WARMTH (0...1) sets the drive. At 1, a sine at -6 dBFS gets about 4 %
/// of 2nd harmonic (-28 dB); at 0.5, half that; quiet passages much less,
/// as in a real stage.
///
/// The curve runs at four times the CD's rate (twice at 88.2/96 kHz, as is
/// above), so the new harmonics of high notes do not fold back as false
/// tones. Only the part the curve adds goes through a 2 Hz filter that
/// removes the steady offset the uneven bend makes; the music itself is not
/// filtered there.
///
/// Off, the sound passes untouched, bit for bit. Switching on or off fades
/// over 30 ms between the two, so it never clicks. (The warm sound comes
/// about 1.5 ms later, through the oversampling filters; during the fade
/// the two overlap, which the ear does not notice in 30 ms.)
public final class TubeStage: @unchecked Sendable {
    /// `tanh(bias)`: how uneven the bend is.
    public static let asymmetry: Float = 0.5
    /// The drive at WARMTH 1.
    public static let maxDrive: Float = 0.33
    /// Taps of each phase of the oversampling filters.
    public static let tapsPerPhase = 64
    /// Sound is processed in pieces of this many frames.
    public static let block = 256
    public static let fadeSeconds: Double = 0.03
    public static let offsetFilterHz: Double = 2

    /// How many times the rate the curve runs at: 4 up to 48 kHz, 2 up to
    /// 96 kHz, 1 above.
    public static func factor(for rate: Double) -> Int {
        rate <= 50_000 ? 4 : rate <= 100_000 ? 2 : 1
    }

    /// The curve on one sample: `drive` 0 leaves it as it is.
    @inline(__always)
    public static func shape(_ x: Float, drive: Float) -> Float {
        guard drive > 1e-5 else { return x }
        let q = tanhf(drive * x)
        return q / (drive * (1 + asymmetry * q))
    }

    public let sampleRate: Double
    public let factor: Int
    /// The delay of the oversampling filters, in frames at `sampleRate`.
    public let latency: Int

    private let channels = 2
    private let taps: Int
    private let upPhases: [[Float]]
    private let downTaps: [Float]
    private let offsetCoefficient: Float
    private let fadeStep: Float

    // Per channel, kept between calls.
    private var upWork: [[Float]]
    private var downWork: [[Float]]
    private var oversampled: [Float]
    private var dry: [Float]
    private var offsetIn: [Float]
    private var offsetOut: [Float]
    private var drive: Float = 0
    /// 0 off ... 1 on: the fade between the untouched and the warm sound.
    private var mix: Float = 0

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        let factor = Self.factor(for: sampleRate)
        self.factor = factor
        let p = Self.tapsPerPhase
        let taps = factor * p
        if factor > 1 {
            self.taps = taps
            let filter = Self.lowpass(taps: taps, factor: factor)
            // Each phase reversed, so a plain dot product applies it.
            upPhases = (0..<factor).map { phase in
                (0..<p).map { j in filter[phase + factor * (p - 1 - j)] * Float(factor) }
            }
            downTaps = filter.reversed()
            // Up and down filters each delay (taps - 1) / 2 fast samples.
            latency = Int((Double(taps - 1) / Double(factor)).rounded())
        } else {
            self.taps = 1
            upPhases = []
            downTaps = []
            latency = 0
        }
        offsetCoefficient = Float(exp(-2 * Double.pi * Self.offsetFilterHz / (sampleRate * Double(factor))))
        fadeStep = Float(1 / (Self.fadeSeconds * sampleRate))
        upWork = Array(repeating: [Float](repeating: 0, count: p - 1 + Self.block), count: 2)
        downWork = Array(repeating: [Float](repeating: 0, count: max(0, self.taps - 1) + Self.block * factor), count: 2)
        oversampled = [Float](repeating: 0, count: Self.block * factor)
        dry = [Float](repeating: 0, count: Self.block)
        offsetIn = [0, 0]
        offsetOut = [0, 0]
    }

    /// Whether the sound is touched at all now (on, or still fading out).
    public var isActive: Bool { mix > 0 }

    /// Processes stereo sound in place. `on` and `warmth` are the knob and
    /// switch now; changes glide, so they can come from any moment.
    /// Allocates nothing: safe on the sound thread.
    public func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
                        frames: Int, on: Bool, warmth: Float) {
        let target: Float = on ? 1 : 0
        // Fully off and staying off: not a single sample is touched.
        if mix == 0 && target == 0 { return }
        if mix == 0 { clearHistory() }
        let aimDrive = Self.maxDrive * min(1, max(0, warmth))
        var done = 0
        while done < frames {
            let count = min(Self.block, frames - done)
            // The drive glides to its new value over the piece.
            let startDrive = drive
            drive += (aimDrive - drive) * min(1, Float(count) / Float(sampleRate * 0.05))
            let startMix = mix
            let endMix = target > mix ? min(target, mix + fadeStep * Float(count))
                                      : max(target, mix - fadeStep * Float(count))
            mix = endMix
            processBlock(channel: 0, left + done, count: count, drives: (startDrive, drive), mixes: (startMix, endMix))
            processBlock(channel: 1, right + done, count: count, drives: (startDrive, drive), mixes: (startMix, endMix))
            done += count
        }
    }

    // MARK: - Private

    private func processBlock(channel: Int, _ samples: UnsafeMutablePointer<Float>, count: Int,
                              drives: (Float, Float), mixes: (Float, Float)) {
        let fullyOn = mixes.0 == 1 && mixes.1 == 1
        // Keep the untouched sound for the fades.
        if !fullyOn {
            dry.withUnsafeMutableBufferPointer { $0.baseAddress!.update(from: samples, count: count) }
        }
        let length = count * factor
        oversampled.withUnsafeMutableBufferPointer { fast in
            let fast = fast.baseAddress!
            upsample(channel: channel, samples, count: count, into: fast)
            // The curve, keeping only what it adds, with its offset removed.
            var inPrevious = offsetIn[channel]
            var outPrevious = offsetOut[channel]
            let r = offsetCoefficient
            let driveStep = (drives.1 - drives.0) / Float(length)
            var d = drives.0
            for i in 0..<length {
                let x = fast[i]
                let added = Self.shape(x, drive: d) - x
                let filtered = added - inPrevious + r * outPrevious
                inPrevious = added
                outPrevious = filtered
                fast[i] = x + filtered
                d += driveStep
            }
            offsetIn[channel] = inPrevious
            offsetOut[channel] = outPrevious
            downsample(channel: channel, fast, count: count, into: samples)
        }
        guard !fullyOn else { return }
        dry.withUnsafeBufferPointer { dry in
            let step = (mixes.1 - mixes.0) / Float(count)
            var g = mixes.0
            for i in 0..<count {
                g += step
                samples[i] = dry[i] + g * (samples[i] - dry[i])
            }
        }
    }

    private func upsample(channel: Int, _ input: UnsafeMutablePointer<Float>, count: Int,
                          into output: UnsafeMutablePointer<Float>) {
        guard factor > 1 else {
            output.update(from: input, count: count)
            return
        }
        let p = Self.tapsPerPhase
        upWork[channel].withUnsafeMutableBufferPointer { work in
            let work = work.baseAddress!
            (work + p - 1).update(from: input, count: count)
            for k in 0..<factor {
                upPhases[k].withUnsafeBufferPointer { phase in
                    for n in 0..<count {
                        var sum: Float = 0
                        vDSP_dotpr(work + n, 1, phase.baseAddress!, 1, &sum, vDSP_Length(p))
                        output[n * factor + k] = sum
                    }
                }
            }
            work.update(from: work + count, count: p - 1)
        }
    }

    private func downsample(channel: Int, _ input: UnsafeMutablePointer<Float>, count: Int,
                            into output: UnsafeMutablePointer<Float>) {
        guard factor > 1 else {
            output.update(from: input, count: count)
            return
        }
        let history = taps - 1
        downWork[channel].withUnsafeMutableBufferPointer { work in
            let work = work.baseAddress!
            (work + history).update(from: input, count: count * factor)
            downTaps.withUnsafeBufferPointer { filter in
                for n in 0..<count {
                    var sum: Float = 0
                    vDSP_dotpr(work + n * factor, 1, filter.baseAddress!, 1, &sum, vDSP_Length(taps))
                    output[n] = sum
                }
            }
            work.update(from: work + count * factor, count: history)
        }
    }

    /// After a long silence of the stage: no old sound left in the filters.
    private func clearHistory() {
        for channel in 0..<channels {
            for i in upWork[channel].indices { upWork[channel][i] = 0 }
            for i in downWork[channel].indices { downWork[channel][i] = 0 }
            offsetIn[channel] = 0
            offsetOut[channel] = 0
        }
        drive = 0
    }

    /// A windowed-sinc lowpass at the original rate's Nyquist (Kaiser window,
    /// about 90 dB down), for a signal `factor` times faster. Flat to 20 kHz
    /// at 44.1 kHz; it stops what would fold back below 20 kHz.
    static func lowpass(taps: Int, factor: Int) -> [Float] {
        let beta = 8.96
        let cutoff = 0.5 / Double(factor)
        let middle = Double(taps - 1) / 2
        var filter = (0..<taps).map { n -> Double in
            let x = Double(n) - middle
            let sinc = x == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * x) / (.pi * x)
            let ratio = x / middle
            let window = besselI0(beta * (1 - ratio * ratio).squareRoot()) / besselI0(beta)
            return sinc * window
        }
        let sum = filter.reduce(0, +)
        filter = filter.map { $0 / sum }
        return filter.map(Float.init)
    }

    private static func besselI0(_ x: Double) -> Double {
        var sum = 1.0, term = 1.0
        for k in 1..<40 {
            term *= (x / (2 * Double(k))) * (x / (2 * Double(k)))
            sum += term
            if term < 1e-12 * sum { break }
        }
        return sum
    }
}

/// The tube preamp's switch and knob, as saved.
public struct TubeSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// 0...1.
    public var warmth: Double

    public init(enabled: Bool = false, warmth: Double = Self.defaultWarmth) {
        self.enabled = enabled
        self.warmth = warmth
    }

    public static let defaultWarmth = 0.5
    public static let off = TubeSettings()
    /// One click of the knob or the arrow keys.
    public static let step = 0.05

    public static func clampWarmth(_ value: Double) -> Double {
        min(1, max(0, (value / step).rounded() * step))
    }
}

/// How the tubes glow: a dim filament once warm, and with VÁLVULAS on, a
/// warmer light that follows the sound of each channel.
public enum TubeGlow {
    /// Seconds the filaments take to warm up when the unit opens.
    public static let warmUp: TimeInterval = 4
    /// The filament alone (0...1 of full glow).
    public static let idle = 0.35

    /// How far the warm-up has gone, eased like a heating filament.
    public static func warmth(after seconds: TimeInterval) -> Double {
        let x = min(1, max(0, seconds / warmUp))
        return x * x * (3 - 2 * x)
    }

    /// The glow, 0...1, for a channel's loudness (RMS 0...1).
    public static func level(rms: Double, warm: Double, on: Bool) -> Double {
        guard on else { return idle * warm }
        // About -40 dBFS just stirs it; -10 dBFS is full.
        let db = 20 * log10(max(rms, 1e-6))
        let sound = min(1, max(0, (db + 40) / 30))
        return warm * (idle + (1 - idle) * sound)
    }

    /// Follows the target quickly up and slowly down, like heat.
    public static func follow(shown: Double, target: Double, seconds: TimeInterval) -> Double {
        let time = target > shown ? 0.06 : 0.35
        return shown + (target - shown) * (1 - exp(-seconds / time))
    }
}
