import Testing
@testable import CDPlayerKit

@Test("Formats seconds as mm:ss", arguments: [
    (0.0, "00:00"),
    (5.0, "00:05"),
    (65.0, "01:05"),
    (3_661.0, "61:01"),
    (-4.0, "00:00"),
])
func formats(_ input: Double, expected: String) {
    #expect(TrackTime.format(input) == expected)
}
