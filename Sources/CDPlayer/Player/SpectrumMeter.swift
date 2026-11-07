import CDPlayerKit
import Foundation

/// The bars of the spectrum display. They split the sound that just played
/// (the player hands it over; nothing extra is read from the CD) into bands
/// and move: up at once, down smoothly, with a peak dot that waits and then
/// falls.
@Observable
final class SpectrumMeter {
    static let bandCount = 24

    private(set) var levels = [Float](repeating: 0, count: SpectrumMeter.bandCount)
    private(set) var peaks = [Float](repeating: 0, count: SpectrumMeter.bandCount)

    @ObservationIgnored private var bands = SpectrumBands(bands: SpectrumMeter.bandCount)
    @ObservationIgnored private var bandsRate: Double = 44_100
    @ObservationIgnored private var peakHold = [Int](repeating: 0, count: SpectrumMeter.bandCount)

    /// Bars per second. Only while the spectrum is on screen.
    static let rate: Double = 30
    private let fall: Float = 0.045
    private let peakFall: Float = 0.012
    private let peakWait = 18

    /// One step: `samples` is the sound that just played, nil for silence
    /// (or, in tests, made-up music when `demo` is on).
    func update(samples: [Float]?, time: TimeInterval, playing: Bool, demo: Bool, sampleRate: Double = 44_100) {
        // The bands sit at the same frequencies whatever the music's rate.
        if sampleRate != bandsRate {
            bands = SpectrumBands(bands: Self.bandCount, sampleRate: sampleRate)
            bandsRate = sampleRate
        }
        var target = [Float](repeating: 0, count: Self.bandCount)
        if playing {
            if let samples, !samples.isEmpty {
                target = bands.levels(samples)
            } else if demo {
                target = Self.demoLevels(at: time)
            }
        }
        step(toward: target)
    }

    func reset() {
        levels = .init(repeating: 0, count: Self.bandCount)
        peaks = levels
    }

    private func step(toward target: [Float]) {
        var nextLevels = levels
        var nextPeaks = peaks
        for band in 0..<Self.bandCount {
            nextLevels[band] = max(target[band], levels[band] - fall)
            if nextLevels[band] >= peaks[band] {
                nextPeaks[band] = nextLevels[band]
                peakHold[band] = peakWait
            } else if peakHold[band] > 0 {
                peakHold[band] -= 1
            } else {
                nextPeaks[band] = max(nextLevels[band], peaks[band] - peakFall)
            }
        }
        if nextLevels != levels { levels = nextLevels }
        if nextPeaks != peaks { peaks = nextPeaks }
    }

    /// Made-up music for the demo disc in tests: strong lows, a lively middle.
    private static func demoLevels(at time: TimeInterval) -> [Float] {
        (0..<bandCount).map { band in
            let position = Double(band) / Double(bandCount - 1)
            let shape = 0.85 - 0.5 * position
            let wobble = 0.18 * sin(time * 5.3 + Double(band) * 0.9) + 0.1 * sin(time * 9.1 + Double(band) * 2.3)
            return Float(min(1, max(0, shape + wobble)))
        }
    }
}
