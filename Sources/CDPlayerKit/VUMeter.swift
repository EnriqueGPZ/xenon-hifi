import Foundation

/// The rules of an analog VU meter's needle: how loud sound maps onto the
/// printed scale, and how the needle swings, with the weight of a real
/// meter (it rises and falls in about a third of a second, never jumps).
public enum VUMeter {
    /// The printed scale, in VU.
    public static let scaleLow: Double = -20
    public static let scaleHigh: Double = 3
    /// Marks on the scale, and where the red part starts.
    public static let marks: [Double] = [-20, -10, -7, -5, -3, -2, -1, 0, 1, 2, 3]
    public static let redFrom: Double = 0
    /// The sound level (RMS, in dB below full scale) that reads 0 VU.
    /// Calibrated on real CDs so music swings around 0 without living in the red.
    public static let referenceDBFS: Double = -16
    /// How quickly the needle follows, in seconds: a real VU reaches 99 %
    /// of a step in 0.3 s.
    public static let rise: Double = 0.065
    public static let fall: Double = 0.09

    /// VU for an RMS amplitude (0...1).
    public static func vu(rms: Double) -> Double {
        guard rms > 0 else { return scaleLow - 10 }
        return 20 * log10(rms) - referenceDBFS
    }

    /// Where `vu` sits on the scale, 0 (left stop) to 1 (right stop).
    /// The scale is printed in voltage, like a real meter: the low end is
    /// squeezed and 0 VU sits about seven tenths of the way across.
    public static func place(vu: Double) -> Double {
        let low = pow(10, scaleLow / 20), high = pow(10, scaleHigh / 20)
        let volts = pow(10, min(max(vu, scaleLow - 10), scaleHigh + 1) / 20)
        return min(max((volts - low) / (high - low), 0), 1.04)
    }

    /// The needle one step later: `current` moving toward `target` (both
    /// scale positions) over `seconds`.
    public static func swing(from current: Double, toward target: Double, seconds: Double) -> Double {
        let time = target > current ? rise : fall
        let factor = 1 - exp(-seconds / time)
        return current + (target - current) * factor
    }
}
