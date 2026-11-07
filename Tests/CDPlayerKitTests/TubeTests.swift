import Foundation
import Testing
@testable import CDPlayerKit

/// The tube stage, measured: off is untouched, on keeps the level and adds
/// mostly the 2nd harmonic, high notes fold back nothing, switching never clicks.
struct TubeTests {
    let rate = 44_100.0

    /// Two seconds of a sine through the stage; returns the second one, settled.
    func run(frequency: Double, amplitude: Float, warmth: Float, on: Bool = true,
             rate: Double = 44_100) -> [Float] {
        let stage = TubeStage(sampleRate: rate)
        let total = Int(rate) * 2
        var left = (0..<total).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / rate)) }
        var right = left
        var at = 0
        // In pieces of the size the sound card asks for.
        while at < total {
            let count = min(512, total - at)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    stage.process(left: l.baseAddress! + at, right: r.baseAddress! + at,
                                  frames: count, on: on, warmth: warmth)
                }
            }
            at += count
        }
        return Array(left[Int(rate)...])
    }

    /// Amplitude of `frequency` in one second of sound (a whole number of
    /// cycles, so the bin is exact).
    func amplitude(_ samples: [Float], at frequency: Double, rate: Double = 44_100) -> Double {
        var re = 0.0, im = 0.0
        for (n, x) in samples.enumerated() {
            let phase = 2 * .pi * frequency * Double(n) / rate
            re += Double(x) * cos(phase)
            im += Double(x) * sin(phase)
        }
        return 2 * (re * re + im * im).squareRoot() / Double(samples.count)
    }

    func rms(_ samples: [Float]) -> Double {
        (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
    }

    func db(_ ratio: Double) -> Double { 20 * log10(ratio) }

    @Test func offLeavesEverySampleUntouched() {
        let stage = TubeStage(sampleRate: rate)
        let original = (0..<4096).map { _ in Float.random(in: -1...1) }
        var left = original, right = original
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                stage.process(left: l.baseAddress!, right: r.baseAddress!, frames: 4096, on: false, warmth: 1)
            }
        }
        #expect(left == original)
        #expect(right == original)
    }

    @Test func quietSoundKeepsItsLevel() {
        let out = run(frequency: 1000, amplitude: 0.01, warmth: 1)
        #expect(abs(db(amplitude(out, at: 1000) / 0.01)) < 0.05)
    }

    @Test func musicLevelStaysTheSame() {
        // About -15 dBFS, where music spends most of its time.
        let out = run(frequency: 440, amplitude: 0.25, warmth: 1)
        #expect(abs(db(rms(out) / (0.25 / 2.0.squareRoot()))) < 0.3)
    }

    @Test func addsMostlyTheSecondHarmonic() {
        let out = run(frequency: 1000, amplitude: 0.5, warmth: 1)
        let fundamental = amplitude(out, at: 1000)
        let second = db(amplitude(out, at: 2000) / fundamental)
        let third = db(amplitude(out, at: 3000) / fundamental)
        #expect(second > -32 && second < -24, "2nd harmonic \(second) dB")
        #expect(third < second - 20, "3rd harmonic \(third) dB")
    }

    @Test func halfWarmthIsGentler() {
        let full = run(frequency: 1000, amplitude: 0.5, warmth: 1)
        let half = run(frequency: 1000, amplitude: 0.5, warmth: 0.5)
        let fullSecond = amplitude(full, at: 2000)
        let halfSecond = amplitude(half, at: 2000)
        #expect(abs(db(halfSecond / fullSecond) + 6) < 1)
    }

    @Test func highNotesFoldNothingBack() {
        // 15 kHz: its 2nd harmonic (30 kHz) would fold back to 14.1 kHz
        // without oversampling.
        let out = run(frequency: 15_000, amplitude: 0.5, warmth: 1)
        let folded = db(amplitude(out, at: 14_100) / amplitude(out, at: 15_000))
        #expect(folded < -80, "folded back \(folded) dB")
    }

    @Test func highNotesKeepTheirLevel() {
        let out = run(frequency: 18_000, amplitude: 0.01, warmth: 1)
        #expect(abs(db(amplitude(out, at: 18_000) / 0.01)) < 0.1)
    }

    @Test func highRatesWorkToo() {
        for rate in [88_200.0, 192_000] {
            let out = run(frequency: 1000, amplitude: 0.5, warmth: 1, rate: rate)
            let fundamental = amplitude(out, at: 1000, rate: rate)
            #expect(abs(db(fundamental / 0.5)) < 0.5)
            let second = db(amplitude(out, at: 2000, rate: rate) / fundamental)
            #expect(second > -32 && second < -24)
        }
    }

    @Test func oversamplingByRate() {
        #expect(TubeStage.factor(for: 44_100) == 4)
        #expect(TubeStage.factor(for: 48_000) == 4)
        #expect(TubeStage.factor(for: 96_000) == 2)
        #expect(TubeStage.factor(for: 192_000) == 1)
    }

    @Test func switchingNeverClicks() {
        // A low, loud note; the switch flips every 0.2 s.
        let stage = TubeStage(sampleRate: rate)
        let total = Int(rate) * 2
        var left = (0..<total).map { 0.8 * Float(sin(2 * .pi * 100 * Double($0) / rate)) }
        var right = left
        var at = 0, on = false
        while at < total {
            if at % 8820 < 512 { on.toggle() }
            let count = min(512, total - at)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    stage.process(left: l.baseAddress! + at, right: r.baseAddress! + at,
                                  frames: count, on: on, warmth: 1)
                }
            }
            at += count
        }
        // A 100 Hz sine at 0.8 moves at most ~0.011 per sample; a click jumps.
        var biggest: Float = 0
        for n in 1..<total { biggest = max(biggest, abs(left[n] - left[n - 1])) }
        #expect(biggest < 0.03, "biggest jump \(biggest)")
    }

    @Test func warmthClicksInSteps() {
        #expect(TubeSettings.clampWarmth(0.52) == 0.5)
        #expect(TubeSettings.clampWarmth(1.4) == 1)
        #expect(TubeSettings.clampWarmth(-1) == 0)
    }

    @Test func glowFollowsSoundOnlyWhenOn() {
        #expect(TubeGlow.level(rms: 0.3, warm: 1, on: false) == TubeGlow.idle)
        #expect(TubeGlow.level(rms: 0, warm: 1, on: true) == TubeGlow.idle)
        #expect(TubeGlow.level(rms: 0.5, warm: 1, on: true) == 1)
        #expect(TubeGlow.level(rms: 0.5, warm: 0, on: true) == 0)
        #expect(TubeGlow.warmth(after: 0) == 0)
        #expect(TubeGlow.warmth(after: TubeGlow.warmUp) == 1)
    }
}
