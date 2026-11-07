import Foundation

/// Formats a duration the way the matrix display shows it: mm:ss. Logic
/// lives here so it can be tested without the app.
public enum TrackTime {
    public static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
