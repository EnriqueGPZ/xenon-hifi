import Accelerate
import Foundation

/// Splits a short slice of sound into frequency bands, low on the left and
/// high on the right, like the bar graph on a hi-fi display. Each band's
/// level runs from 0 (silence) to 1 (very loud).
public final class SpectrumBands {
    public let size: Int
    public let bandCount: Int
    /// The frequency range each band covers, in Hz, spaced evenly in octaves.
    public let edges: [Double]

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private let sampleRate: Double
    /// Levels in decibels map to 0...1 across this range.
    /// Calibrated on real CDs (Sade, Phil Collins): music sits between them.
    private let floorDB: Float = -66
    private let ceilingDB: Float = -16
    /// Music has less energy up high; each band to the right gets a little
    /// lift so the treble bars move too, as on a real analyzer.
    private let tiltPerBand: Float = 0.9

    public init(size: Int = 2048, bands: Int = 24, sampleRate: Double = 44_100,
                lowest: Double = 40, highest: Double = 16_000) {
        self.size = size
        self.bandCount = bands
        self.sampleRate = sampleRate
        log2n = vDSP_Length(log2(Double(size)).rounded())
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        edges = (0...bands).map { lowest * pow(highest / lowest, Double($0) / Double(bands)) }
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// The band levels for `samples` (mono, -1...1). Fewer samples than
    /// `size` are padded with silence.
    public func levels(_ samples: [Float]) -> [Float] {
        var input = [Float](repeating: 0, count: size)
        for index in 0..<min(size, samples.count) { input[index] = samples[index] * window[index] }

        let half = size / 2
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                input.withUnsafeBufferPointer { inputPointer in
                    inputPointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }
        // zrip doubles the result; a full-scale sine through the window then
        // lands near 0 dB.
        let scale = 1 / Float(size * size)
        let binWidth = sampleRate / Double(size)

        return (0..<bandCount).map { band in
            var first = Int((edges[band] / binWidth).rounded(.down))
            var last = Int((edges[band + 1] / binWidth).rounded(.down))
            first = max(1, min(first, half - 1))
            last = max(first, min(last, half - 1))
            var energy: Float = 0
            for bin in first...last { energy += power[bin] * scale }
            let decibels = 10 * log10(max(energy, 1e-12)) + tiltPerBand * Float(band)
            return min(1, max(0, (decibels - floorDB) / (ceilingDB - floorDB)))
        }
    }
}
