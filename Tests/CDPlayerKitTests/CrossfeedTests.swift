import Foundation
import Testing
@testable import CDPlayerKit

/// Crossfeed, measured: off is untouched, the centre is untouched, a sound on
/// one side reaches the other ear softer, later and without highs, and
/// switching never clicks.
struct CrossfeedTests {
    let rate = 44_100.0

    /// Runs `left`/`right` through the crossfeed in pieces of 512 frames.
    /// `onFrom` switches it on at that frame (0: on from the start).
    func run(_ left: [Float], _ right: [Float], on: Bool = true, level: CrossfeedLevel = .medium,
             onFrom: Int = 0, rate: Double = 44_100) -> (left: [Float], right: [Float]) {
        let crossfeed = Crossfeed(sampleRate: rate)
        var l = left, r = right
        var at = 0
        while at < l.count {
            let count = min(512, l.count - at)
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    crossfeed.process(left: lp.baseAddress! + at, right: rp.baseAddress! + at,
                                      frames: count, on: on && at >= onFrom, level: level)
                }
            }
            at += count
        }
        return (l, r)
    }

    func sine(_ frequency: Double, amplitude: Float = 0.5, seconds: Double = 2) -> [Float] {
        (0..<Int(rate * seconds)).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / rate)) }
    }

    /// Amplitude and phase of `frequency` in the last second (whole cycles).
    func measure(_ samples: [Float], at frequency: Double) -> (amplitude: Double, phase: Double) {
        let tail = samples.suffix(Int(rate))
        var re = 0.0, im = 0.0
        for (n, x) in tail.enumerated() {
            let phase = 2 * .pi * frequency * Double(n) / rate
            re += Double(x) * cos(phase)
            im += Double(x) * sin(phase)
        }
        let count = Double(tail.count)
        return (2 * (re * re + im * im).squareRoot() / count, atan2(re, im))
    }

    func db(_ x: Double) -> Double { 20 * log10(max(x, 1e-12)) }

    @Test func offLeavesEverySampleAsItWas() {
        var seed: UInt64 = 7
        func noise() -> Float {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Int64(bitPattern: seed >> 11) % 2000 - 1000) / 1000
        }
        let left = (0..<20_000).map { _ in noise() }
        let right = (0..<20_000).map { _ in noise() }
        let out = run(left, right, on: false)
        #expect(out.left == left)
        #expect(out.right == right)
    }

    @Test(arguments: CrossfeedLevel.allCases)
    func theCentreComesOutExactlyAsItWent(level: CrossfeedLevel) {
        // The same on both channels: a voice in the middle.
        let voice = zip(sine(220), sine(3_000, amplitude: 0.2)).map { $0 + $1 }
        let out = run(voice, voice, level: level)
        #expect(out.left == voice)
        #expect(out.right == voice)
    }

    @Test(arguments: CrossfeedLevel.allCases)
    func aBassOnOneSideReachesTheOtherEarFeedDecibelsSofter(level: CrossfeedLevel) {
        let bass = sine(50)
        let out = run(bass, [Float](repeating: 0, count: bass.count), level: level)
        let near = measure(out.left, at: 50).amplitude
        let far = measure(out.right, at: 50).amplitude
        #expect(abs((db(near) - db(far)) - level.feed) < 0.3)
    }

    @Test func highsBarelyCrossAndKeepTheirLevel() {
        let high = sine(10_000)
        let out = run(high, [Float](repeating: 0, count: high.count), level: .strong)
        let near = measure(out.left, at: 10_000).amplitude
        let far = measure(out.right, at: 10_000).amplitude
        #expect(abs(db(near) - db(0.5)) < 0.5)
        #expect(db(far) - db(near) < -20)
    }

    @Test func whatCrossesArrivesAboutAQuarterMillisecondLate() {
        let tone = sine(100)
        let out = run(tone, [Float](repeating: 0, count: tone.count))
        let input = measure(tone, at: 100).phase
        // With the right channel silent, the far ear gets g·low(L).
        let far = measure(out.right, at: 100).phase
        var lag = input - far
        if lag < 0 { lag += 2 * .pi }
        let seconds = lag / (2 * .pi * 100)
        #expect(abs(seconds - Crossfeed.delay(for: .medium)) < 0.00005)
        #expect(seconds > 0.0002 && seconds < 0.0003)
    }

    @Test func switchingOnWhilePlayingDoesNotClick() {
        let tone = sine(1_000, seconds: 1)
        let silent = [Float](repeating: 0, count: tone.count)
        let out = run(tone, silent, level: .strong, onFrom: 20_480)
        // The far ear rises gently from silence: no jump bigger than the
        // settled tone's own steps.
        let jumps = zip(out.right.dropFirst(), out.right).map { abs($0 - $1) }
        let settled = jumps.suffix(4_410).max() ?? 0
        #expect((jumps.max() ?? 0) <= settled * 1.05)
        #expect(out.right[..<20_480].allSatisfy { $0 == 0 })
    }

    @Test func worksAtHighRatesToo() {
        let rate = 192_000.0
        let bass = (0..<Int(rate)).map { 0.5 * Float(sin(2 * .pi * 50 * Double($0) / rate)) }
        let out = run(bass, [Float](repeating: 0, count: bass.count), level: .medium, rate: rate)
        let peakFar = out.right.suffix(Int(rate / 2)).map(abs).max() ?? 0
        let peakNear = out.left.suffix(Int(rate / 2)).map(abs).max() ?? 0
        #expect(abs(db(Double(peakNear)) - db(Double(peakFar)) - CrossfeedLevel.medium.feed) < 0.3)
    }

    @Test func settingsStartOffAtMedium() throws {
        #expect(CrossfeedSettings.off == CrossfeedSettings(enabled: false, level: .medium))
        let data = try JSONEncoder().encode(CrossfeedSettings(enabled: true, level: .soft))
        #expect(try JSONDecoder().decode(CrossfeedSettings.self, from: data) == CrossfeedSettings(enabled: true, level: .soft))
    }
}
