import Foundation

/// Crossfeed, for listening on headphones.
///
/// With speakers, each ear hears both: the left speaker reaches the right ear
/// too, around the head, a fraction of a millisecond later, a little softer
/// and without its highs (the head shades them). On headphones each ear hears
/// only its own channel, so the music sits inside the head, and a sound mixed
/// to one side only (common on 1960s stereo records) sits glued to one ear.
///
/// This feeds each channel a little of the other, the way the head would:
///
///     left  = L + g · (low(R) − low(L))
///     right = R + g · (low(L) − low(R))
///
/// `low` is a gentle lowpass (6 dB per octave at 650–700 Hz). It takes the
/// highs out of what crosses, and its phase delays it by `1 / (2π · cutoff)`,
/// about 0.23 ms in the bass, close to the time sound takes around the head.
/// What crosses is the *difference* between the channels, so whatever is the
/// same on both (a voice in the centre) comes out exactly as it went in: no
/// louder, no fuller. Only the sides are drawn in: in the bass, a sound mixed
/// fully to one side reaches the other ear `feed` dB softer than its own.
///
/// The three levels are the classic settings: soft (Jan Meier, 650 Hz,
/// 9.5 dB), medium (Chu Moy, 700 Hz, 6 dB), strong (Bauer, 700 Hz, 4.5 dB).
///
/// Off, the sound passes untouched, bit for bit. Switching on or off, or
/// changing level, glides over 30 ms, so it never clicks.
public final class Crossfeed: @unchecked Sendable {
    public static let fadeSeconds: Double = 0.03

    public let sampleRate: Double
    private let fadeStep: Float
    private var lowLeft: Float = 0
    private var lowRight: Float = 0
    /// How much crosses now; glides to the level's gain, 0 when off.
    private var gain: Float = 0

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        // The strongest level is reached in `fadeSeconds`; smaller steps take as long or less.
        fadeStep = CrossfeedLevel.strong.gain / Float(Self.fadeSeconds * sampleRate)
    }

    /// Whether the sound is touched at all now (on, or still fading out).
    public var isActive: Bool { gain > 0 }

    /// How late what crosses arrives, in the bass, in seconds.
    public static func delay(for level: CrossfeedLevel) -> Double {
        1 / (2 * .pi * level.cutoff)
    }

    /// Processes stereo sound in place. `on` and `level` are the switch and
    /// the selector now; changes glide, so they can come from any moment.
    /// Allocates nothing: safe on the sound thread.
    public func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
                        frames: Int, on: Bool, level: CrossfeedLevel) {
        let target: Float = on ? level.gain : 0
        // Fully off and staying off: not a single sample is touched.
        if gain == 0 && target == 0 { return }
        if gain == 0 {
            lowLeft = 0
            lowRight = 0
        }
        let alpha = Float(1 - exp(-2 * Double.pi * level.cutoff / sampleRate))
        var g = gain
        var lowL = lowLeft
        var lowR = lowRight
        for i in 0..<frames {
            if g != target {
                g = g < target ? min(target, g + fadeStep) : max(target, g - fadeStep)
            }
            let l = left[i]
            let r = right[i]
            lowL += alpha * (l - lowL)
            lowR += alpha * (r - lowR)
            let cross = g * (lowR - lowL)
            left[i] = l + cross
            right[i] = r - cross
        }
        gain = g
        lowLeft = lowL
        lowRight = lowR
    }
}

/// The three positions of the selector.
public enum CrossfeedLevel: String, Codable, CaseIterable, Sendable {
    case soft, medium, strong

    /// Where the highs stop crossing, in Hz.
    public var cutoff: Double { self == .soft ? 650 : 700 }

    /// How much softer, in dB, a sound on one side reaches the other ear, in the bass.
    public var feed: Double {
        switch self {
        case .soft: 9.5
        case .medium: 6
        case .strong: 4.5
        }
    }

    /// The `g` of the formula: with `a = 10^(−feed/20)`, the far ear gets
    /// `g` and the near one `1 − g`, so their ratio is `a`.
    public var gain: Float {
        let a = pow(10, -feed / 20)
        return Float(a / (1 + a))
    }

    /// 0, 1, 2: for passing the level to the sound thread through an atomic
    /// without making an array there.
    public var index: Int {
        switch self {
        case .soft: 0
        case .medium: 1
        case .strong: 2
        }
    }

    public init(index: Int) {
        self = index <= 0 ? .soft : index == 1 ? .medium : .strong
    }

    /// As printed on the panel.
    public var label: String {
        switch self {
        case .soft: "SUAVE"
        case .medium: "MEDIO"
        case .strong: "FUERTE"
        }
    }
}

/// The CROSSFEED switch and selector, as saved.
public struct CrossfeedSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var level: CrossfeedLevel

    public init(enabled: Bool = false, level: CrossfeedLevel = .medium) {
        self.enabled = enabled
        self.level = level
    }

    public static let off = CrossfeedSettings()
}
