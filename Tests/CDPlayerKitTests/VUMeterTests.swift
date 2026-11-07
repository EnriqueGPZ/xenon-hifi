import Foundation
import Testing
@testable import CDPlayerKit

struct VUMeterTests {
    @Test func scaleEndsAndZero() {
        #expect(VUMeter.place(vu: -20) == 0)
        #expect(abs(VUMeter.place(vu: 3) - 1) < 0.0001)
        // 0 VU sits about seven tenths across, as printed on real meters.
        let zero = VUMeter.place(vu: 0)
        #expect(zero > 0.65 && zero < 0.72)
        // Silence rests on the left stop.
        #expect(VUMeter.place(vu: VUMeter.vu(rms: 0)) == 0)
    }

    @Test func referenceLevelReadsZero() {
        let rms = pow(10, VUMeter.referenceDBFS / 20)
        #expect(abs(VUMeter.vu(rms: rms)) < 0.0001)
    }

    @Test func needleMovesSmoothlyNotAtOnce() {
        let step = VUMeter.swing(from: 0, toward: 1, seconds: 1.0 / 30)
        #expect(step > 0.2 && step < 0.6)
        var needle = 0.0
        for _ in 0..<9 { needle = VUMeter.swing(from: needle, toward: 1, seconds: 1.0 / 30) }
        #expect(needle > 0.95)
        // Falls a little slower than it rises.
        #expect(VUMeter.swing(from: 1, toward: 0, seconds: 1.0 / 30) > 1 - step)
    }
}
