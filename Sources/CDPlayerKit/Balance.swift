import Foundation

/// The rules of the balance knob: -1 is all left, 0 the centre, 1 all
/// right. Like an amplifier's balance, the centre leaves both sides at full
/// level and turning away fades only the other side (this matches how the
/// Mac's mixer applies it, measured).
public enum Balance {
    /// One click of the arrow keys or the menu.
    public static let step = 0.05
    /// Near the centre the knob clicks into place, as real ones do.
    public static let detent = 0.04

    public static func clamp(_ value: Double) -> Double {
        let clamped = min(1, max(-1, value))
        return abs(clamped) < detent ? 0 : clamped
    }

    /// How loud each side plays, 0...1.
    public static func gains(_ balance: Double) -> (left: Double, right: Double) {
        (min(1, 1 - balance), min(1, 1 + balance))
    }

    /// What the display shows: "CENTRO", or the side and how far, "L 20".
    public static func label(_ balance: Double) -> String {
        let amount = Int((abs(balance) * 100).rounded())
        guard amount > 0 else { return "CENTRO" }
        return "\(balance < 0 ? "L" : "R") \(amount)"
    }
}
