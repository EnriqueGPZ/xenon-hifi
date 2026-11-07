import CDPlayerKit
import Foundation

/// The two needles of the VU display, left and right channel. They follow
/// how loud the sound that just played was, with the weight of a real
/// analog meter (CDPlayerKit/VUMeter.swift). Positions run from 0 (left
/// stop) to 1 (right stop).
@Observable
final class VUMeters {
    private(set) var left: Double = 0
    private(set) var right: Double = 0

    /// One step: `loudness` is the RMS of each channel, nil for silence (or,
    /// in tests, made-up music when `demo` is on).
    func update(loudness: [Float]?, time: TimeInterval, playing: Bool, demo: Bool) {
        var targets: (Double, Double) = (0, 0)
        if playing {
            if let loudness, let first = loudness.first {
                let second = loudness.count > 1 ? loudness[1] : first
                targets = (VUMeter.place(vu: VUMeter.vu(rms: Double(first))),
                           VUMeter.place(vu: VUMeter.vu(rms: Double(second))))
            } else if demo {
                targets = (0.62 + 0.12 * sin(time * 2.3), 0.58 + 0.14 * sin(time * 2.9 + 1))
            }
        }
        let step = 1 / SpectrumMeter.rate
        let nextLeft = VUMeter.swing(from: left, toward: targets.0, seconds: step)
        let nextRight = VUMeter.swing(from: right, toward: targets.1, seconds: step)
        // Settle on the stop instead of creeping toward it forever.
        left = nextLeft < 0.001 ? 0 : nextLeft
        right = nextRight < 0.001 ? 0 : nextRight
    }

    func reset() {
        left = 0
        right = 0
    }
}
