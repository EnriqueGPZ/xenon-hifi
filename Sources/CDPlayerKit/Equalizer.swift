import Accelerate
import AVFAudio
import Foundation

/// The rules of the graphic equalizer: ten bands an octave apart, each a
/// minimum-phase peaking filter (a biquad) one octave wide, and a level
/// control for headroom. The sound itself runs through Apple's
/// AVAudioUnitEQ: measured against the Audio EQ Cookbook's peaking filter
/// with bandwidth in octaves (`peaking`), it gives the same curve (±0.01 dB),
/// and with every band at 0 dB its output is bit-identical to its input.
/// The two end bands can also be shelves (graves and agudos, like an
/// amplifier's tone controls): Apple's shelves are the Cookbook's with the
/// standard slope (S = 1), measured within 0.03 dB.
public enum Equalizer {
    public struct Band: Sendable, Equatable {
        public let frequency: Double
        /// As printed under the fader.
        public let label: String
    }

    /// The ISO octave centres.
    public static let bands: [Band] = [
        Band(frequency: 31.5, label: "31"), Band(frequency: 63, label: "63"),
        Band(frequency: 125, label: "125"), Band(frequency: 250, label: "250"),
        Band(frequency: 500, label: "500"), Band(frequency: 1000, label: "1K"),
        Band(frequency: 2000, label: "2K"), Band(frequency: 4000, label: "4K"),
        Band(frequency: 8000, label: "8K"), Band(frequency: 16000, label: "16K"),
    ]
    /// The bands that can be shelves, and the shelf's middle (half its
    /// gain there, nearly all of it at the band's own frequency).
    public static let lowShelfBand = 0
    public static let highShelfBand = 9
    public static let lowShelfFrequency: Double = 63
    public static let highShelfFrequency: Double = 8000

    /// Each band's width, in octaves.
    public static let bandwidth: Double = 1
    /// How far a band can go up or down, and one click of the keys, in dB.
    public static let maxGain: Double = 12
    public static let step: Double = 0.5
    /// The level control: only down, so it can make room for boosted bands.
    public static let minPreamp: Double = -12

    public static func clampGain(_ gain: Double) -> Double {
        min(maxGain, max(-maxGain, (gain / step).rounded() * step))
    }

    public static func clampPreamp(_ level: Double) -> Double {
        min(0, max(minPreamp, (level / step).rounded() * step))
    }

    /// "+2.5", "-12", "0".
    public static func label(_ gain: Double) -> String {
        let rounded = (gain / step).rounded() * step
        if rounded == 0 { return "0" }
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return rounded > 0 ? "+" + text : text
    }

    /// The Audio EQ Cookbook's peaking filter, with the bandwidth in octaves
    /// (the form that keeps the width right near the top of the band).
    /// Normalised: b0, b1, b2, a1, a2.
    public static func peaking(frequency: Double, gain: Double, bandwidth: Double = bandwidth,
                               sampleRate: Double) -> [Double] {
        let a = pow(10, gain / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) * sinh(log(2) / 2 * bandwidth * w0 / sin(w0))
        let a0 = 1 + alpha / a
        return [(1 + alpha * a) / a0, -2 * cos(w0) / a0, (1 - alpha * a) / a0,
                -2 * cos(w0) / a0, (1 - alpha / a) / a0]
    }

    /// The Audio EQ Cookbook's shelf with slope S = 1 (as Apple's node does
    /// it), all below `frequency` (low) or all above it (high). Normalised.
    public static func shelf(high: Bool, frequency: Double, gain: Double, sampleRate: Double) -> [Double] {
        let a = pow(10, gain / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let c = cos(w0)
        let k = 2 * a.squareRoot() * sin(w0) / 2 * 2.squareRoot()
        let sign: Double = high ? -1 : 1
        let b0 = a * ((a + 1) - sign * (a - 1) * c + k)
        let b1 = sign * 2 * a * ((a - 1) - sign * (a + 1) * c)
        let b2 = a * ((a + 1) - sign * (a - 1) * c - k)
        let a0 = (a + 1) + sign * (a - 1) * c + k
        let a1 = -sign * 2 * ((a - 1) + sign * (a + 1) * c)
        let a2 = (a + 1) + sign * (a - 1) * c - k
        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }

    /// The filter one band makes with `gain` in these settings.
    public static func coefficients(band index: Int, gain: Double, in settings: EQSettings,
                                    sampleRate: Double) -> [Double] {
        if index == lowShelfBand && settings.lowShelf {
            return shelf(high: false, frequency: lowShelfFrequency, gain: gain, sampleRate: sampleRate)
        }
        if index == highShelfBand && settings.highShelf {
            return shelf(high: true, frequency: highShelfFrequency, gain: gain, sampleRate: sampleRate)
        }
        return peaking(frequency: bands[index].frequency, gain: gain, sampleRate: sampleRate)
    }

    /// How much one biquad lifts or cuts `frequency`, in dB.
    public static func response(of coefficients: [Double], at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        func magnitude(_ c0: Double, _ c1: Double, _ c2: Double) -> Double {
            let re = c0 + c1 * cos(w) + c2 * cos(2 * w)
            let im = -c1 * sin(w) - c2 * sin(2 * w)
            return (re * re + im * im).squareRoot()
        }
        let c = coefficients
        return 20 * log10(magnitude(c[0], c[1], c[2]) / magnitude(1, c[3], c[4]))
    }

    /// The whole equalizer's curve at `frequency`, in dB: every band plus the level.
    public static func response(_ settings: EQSettings, at frequency: Double, sampleRate: Double = 44_100) -> Double {
        guard settings.enabled else { return 0 }
        var total = settings.preamp
        for (index, gain) in settings.gains.enumerated() where gain != 0 {
            total += response(of: coefficients(band: index, gain: gain, in: settings, sampleRate: sampleRate),
                              at: frequency, sampleRate: sampleRate)
        }
        return total
    }

    /// Sets up Apple's equalizer node with the ten bands, flat.
    public static func prepare(_ unit: AVAudioUnitEQ) {
        for (band, node) in zip(bands, unit.bands) {
            node.filterType = .parametric
            node.frequency = Float(band.frequency)
            node.bandwidth = Float(bandwidth)
            node.gain = 0
            node.bypass = false
        }
        unit.globalGain = 0
        unit.bypass = true
    }

    /// Makes the end bands shelves or bells. Change it only with those bands
    /// at 0 dB: both shapes are then a plain pass-through and the filter
    /// carries on without a jump (EQDriver does this).
    public static func shape(_ unit: AVAudioUnitEQ, lowShelf: Bool, highShelf: Bool) {
        let low = unit.bands[lowShelfBand], high = unit.bands[highShelfBand]
        low.filterType = lowShelf ? .lowShelf : .parametric
        low.frequency = Float(lowShelf ? lowShelfFrequency : bands[lowShelfBand].frequency)
        high.filterType = highShelf ? .highShelf : .parametric
        high.frequency = Float(highShelf ? highShelfFrequency : bands[highShelfBand].frequency)
    }

    /// Puts one step of sound settings into the node: `values` holds the ten
    /// band gains and then the level, in dB. With `bypass` the whole node
    /// steps out of the way: ten flat filters still change the last bits of
    /// the sound (by -256 dB, measured), and stepped out the sound passes
    /// bit for bit. Only step out, or back in, with every value at 0 dB: a
    /// filter that comes back mid-sound starts empty and clicks (measured).
    public static func apply(_ values: [Double], to unit: AVAudioUnitEQ, bypass: Bool? = nil) {
        for (node, gain) in zip(unit.bands, values) { node.gain = Float(gain) }
        unit.globalGain = Float(values.last ?? 0)
        unit.bypass = bypass ?? values.allSatisfy { $0 == 0 }
    }
}

/// What the equalizer is set to.
public struct EQSettings: Codable, Equatable, Sendable {
    public var gains: [Double]
    public var preamp: Double
    public var enabled: Bool
    /// The end bands as shelves instead of bells.
    public var lowShelf = false
    public var highShelf = false

    public init(gains: [Double], preamp: Double, enabled: Bool, lowShelf: Bool = false, highShelf: Bool = false) {
        self.gains = gains
        self.preamp = preamp
        self.enabled = enabled
        self.lowShelf = lowShelf
        self.highShelf = highShelf
    }

    /// Settings saved before the shelves existed read as bells.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gains = try c.decode([Double].self, forKey: .gains)
        preamp = try c.decode(Double.self, forKey: .preamp)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        lowShelf = try c.decodeIfPresent(Bool.self, forKey: .lowShelf) ?? false
        highShelf = try c.decodeIfPresent(Bool.self, forKey: .highShelf) ?? false
    }

    /// Flat, at full level, switched on: it does not change the sound.
    public static let neutral = EQSettings(gains: Array(repeating: 0, count: Equalizer.bands.count),
                                           preamp: 0, enabled: true)

    /// The gains and the level as they reach the sound: all zero when off.
    public var values: [Double] {
        enabled ? gains + [preamp] : Array(repeating: 0, count: gains.count + 1)
    }

    /// Anything the stored copy got wrong (fewer bands, out of range) put right.
    public var cleaned: EQSettings {
        var gains = gains.map(Equalizer.clampGain)
        let count = Equalizer.bands.count
        gains = Array((gains + Array(repeating: 0, count: count)).prefix(count))
        return EQSettings(gains: gains, preamp: Equalizer.clampPreamp(preamp), enabled: enabled,
                          lowShelf: lowShelf, highShelf: highShelf)
    }
}

/// A saved setting, with its name.
public struct EQPreset: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var gains: [Double]
    public var preamp: Double
    public var lowShelf = false
    public var highShelf = false
    public var id: String { name }

    public init(name: String, gains: [Double], preamp: Double, lowShelf: Bool = false, highShelf: Bool = false) {
        self.name = name
        self.gains = gains
        self.preamp = preamp
        self.lowShelf = lowShelf
        self.highShelf = highShelf
    }

    /// Presets saved before the shelves existed read as bells.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        gains = try c.decode([Double].self, forKey: .gains)
        preamp = try c.decode(Double.self, forKey: .preamp)
        lowShelf = try c.decodeIfPresent(Bool.self, forKey: .lowShelf) ?? false
        highShelf = try c.decodeIfPresent(Bool.self, forKey: .highShelf) ?? false
    }

    /// The fixed preset that leaves the sound as it is.
    public static let neutralName = "NEUTRO"
    public static let neutral = EQPreset(name: neutralName, gains: EQSettings.neutral.gains, preamp: 0)

    public func matches(_ settings: EQSettings) -> Bool {
        gains == settings.gains && preamp == settings.preamp
            && lowShelf == settings.lowShelf && highShelf == settings.highShelf
    }
}

/// Moves the equalizer from one setting to another in a few small steps,
/// so a change never jumps in the middle of the sound (switching the whole
/// equalizer off at once makes an audible click: measured). It also says
/// when the node may step out of the way (`bypass`): only after half a
/// second with everything flat (a filter that just went flat still rings
/// with what it did before, measured as a jump at 63 Hz), and leaving the flat setting it first steps back
/// in while still flat, so the filters are already running when they start
/// to change the sound.
public struct EQRamp: Sendable {
    /// Steps per change, and the time between them: about a tenth of a second.
    public static let steps = 6
    public static let interval: Double = 1.0 / 60
    /// Steps to stay flat before stepping out: half a second.
    public static let settle = 30

    public private(set) var current: [Double]
    private var start: [Double]
    private var target: [Double]
    private var done = 0
    private var flatFor = 0

    public init(values: [Double]) {
        current = values
        start = values
        target = values
        done = Self.steps
        flatFor = Self.settle
    }

    /// It has reached what it was aimed at (it may still be settling flat).
    public var arrived: Bool { done >= Self.steps }

    public var isMoving: Bool { done < Self.steps || (Self.isFlat(current) && flatFor < Self.settle) }

    /// The node may step out: flat, and long enough for the filters to rest.
    public var bypass: Bool { Self.isFlat(current) && flatFor >= Self.settle }

    /// Heads for `values` from wherever it is now.
    public mutating func aim(at values: [Double]) {
        guard values != target else { return }
        start = current
        target = values
        // Leaving flat: one step held at flat with the filters running.
        done = Self.isFlat(current) && !Self.isFlat(values) ? -1 : 0
        flatFor = 0
    }

    /// One step closer; returns the values to apply (and then check `bypass`).
    public mutating func advance() -> [Double] {
        if done < Self.steps {
            done += 1
            if done > 0 {
                let share = Double(done) / Double(Self.steps)
                current = zip(start, target).map { from, to in done == Self.steps ? to : from + (to - from) * share }
            }
        }
        flatFor = Self.isFlat(current) && done >= Self.steps ? flatFor + 1 : 0
        return current
    }

    private static func isFlat(_ values: [Double]) -> Bool { values.allSatisfy { $0 == 0 } }
}

/// Drives the equalizer node through every change: the gains glide on the
/// ramp, and turning an end band between bell and shelf goes in three
/// moves, so it never clicks: that band glides to 0 dB, rests there half a
/// second (a filter that just went flat still rings with what it did, and
/// changing its shape then makes a kink: measured), changes shape (both
/// shapes are a plain pass-through at 0 dB), and glides to its gain.
public struct EQDriver: Sendable {
    public struct Step: Equatable, Sendable {
        public var values: [Double]
        public var bypass: Bool
        public var lowShelf: Bool
        public var highShelf: Bool
    }

    public private(set) var lowShelf: Bool
    public private(set) var highShelf: Bool
    private var ramp: EQRamp
    private var wanted: EQSettings
    private var restedFor = 0

    public init(settings: EQSettings) {
        wanted = settings
        lowShelf = settings.lowShelf
        highShelf = settings.highShelf
        ramp = EQRamp(values: settings.values)
    }

    public var isMoving: Bool { ramp.isMoving || reshaping }
    public var bypass: Bool { ramp.bypass }

    private var reshaping: Bool { lowShelf != wanted.lowShelf || highShelf != wanted.highShelf }

    public mutating func aim(at settings: EQSettings) {
        wanted = settings
        ramp.aim(at: reshaping ? quietened(settings.values) : settings.values)
    }

    public mutating func advance() -> Step {
        var values = ramp.advance()
        restedFor = reshaping && ramp.arrived && quietened(values) == values ? restedFor + 1 : 0
        if reshaping, restedFor > EQRamp.settle {
            restedFor = 0
            lowShelf = wanted.lowShelf
            highShelf = wanted.highShelf
            ramp.aim(at: wanted.values)
            values = ramp.current
        }
        return Step(values: values, bypass: ramp.bypass, lowShelf: lowShelf, highShelf: highShelf)
    }

    /// `values` with the end bands that change shape at 0 dB.
    private func quietened(_ values: [Double]) -> [Double] {
        var values = values
        if lowShelf != wanted.lowShelf { values[Equalizer.lowShelfBand] = 0 }
        if highShelf != wanted.highShelf { values[Equalizer.highShelfBand] = 0 }
        return values
    }
}

/// The peak meters that warn when the sound would be cut off at the DAC:
/// a sample at or above full scale (0 dBFS) cannot leave the Mac whole.
public enum PeakMeter {
    /// The meter's scale, in dB below full scale.
    public static let floor: Double = -36
    public static let marks: [Double] = [-36, -24, -12, -6, -3, 0]
    /// How long the OVER light stays on after a cut, in seconds.
    public static let overHold: Double = 2
    /// How fast the meter falls back, in dB a second (it rises at once).
    public static let fall: Double = 24

    public static func dBFS(_ peak: Double) -> Double {
        peak > 0 ? 20 * log10(peak) : floor - 1
    }

    public static func isOver(_ peak: Double) -> Bool { peak >= 1 }

    /// Where `peak` sits on the meter, 0 (bottom of the scale) to 1 (0 dBFS).
    public static func place(_ peak: Double) -> Double {
        min(1, max(0, (dBFS(peak) - floor) / -floor))
    }

    /// The bar one step later: up at once to a louder peak, down slowly.
    public static func follow(shown: Double, peak: Double, seconds: Double) -> Double {
        let target = place(peak)
        return max(target, shown - fall / -floor * seconds)
    }
}

extension PeakMeter {
    /// Counts the OVER lights' overs in one block of one channel. An over is a
    /// run of samples at or above full scale, after the output gain, and a run
    /// counts once however many blocks it crosses: `inRun` says whether the
    /// block before ended above full scale, and `endsInRun` tells the next one.
    /// It counts sample values, not the true peak between them: a true peak
    /// would light OVER on loud masters with the equalizer flat (decided).
    public static func overs(in samples: UnsafeBufferPointer<Float>, gain: Float,
                             inRun: Bool) -> (runs: Int, endsInRun: Bool) {
        guard let base = samples.baseAddress, !samples.isEmpty else { return (0, inRun) }
        var loudest: Float = 0
        vDSP_maxmgv(base, 1, &loudest, vDSP_Length(samples.count))
        // Nothing reaches full scale in this block, so any run has ended.
        guard isOver(Double(loudest * gain)) else { return (0, false) }
        var runs = 0
        var inside = inRun
        for sample in samples {
            let over = isOver(Double(abs(sample) * gain))
            if over && !inside { runs += 1 }
            inside = over
        }
        return (runs, inside)
    }
}
