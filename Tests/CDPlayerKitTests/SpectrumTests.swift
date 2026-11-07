import Foundation
import Testing
@testable import CDPlayerKit

struct SpectrumTests {
    private func sine(_ hertz: Double, amplitude: Float, count: Int = 2048) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * hertz * Double($0) / 44_100)) }
    }

    @Test func silenceGivesEmptyBars() {
        let levels = SpectrumBands().levels([Float](repeating: 0, count: 2048))
        #expect(levels.count == 24)
        #expect(levels.allSatisfy { $0 == 0 })
    }

    @Test func aToneLightsItsOwnBand() {
        let spectrum = SpectrumBands()
        let levels = spectrum.levels(sine(1_000, amplitude: 0.5))
        let loudest = levels.indices.max { levels[$0] < levels[$1] }!
        #expect(spectrum.edges[loudest] <= 1_000 && 1_000 < spectrum.edges[loudest + 1])
        #expect(levels[loudest] > 0.7)
        #expect(levels[0] < 0.2 && levels[23] < 0.2)
    }

    @Test func lowAndHighTonesLandLeftAndRight() {
        let spectrum = SpectrumBands()
        let low = spectrum.levels(sine(80, amplitude: 0.5))
        let high = spectrum.levels(sine(8_000, amplitude: 0.5))
        let lowBand = low.indices.max { low[$0] < low[$1] }!
        let highBand = high.indices.max { high[$0] < high[$1] }!
        #expect(lowBand < 6)
        #expect(highBand > 18)
    }

    @Test func louderSoundsReachHigher() {
        let spectrum = SpectrumBands()
        let quiet = spectrum.levels(sine(1_000, amplitude: 0.05)).max()!
        let loud = spectrum.levels(sine(1_000, amplitude: 0.5)).max()!
        #expect(loud > quiet)
    }
}
