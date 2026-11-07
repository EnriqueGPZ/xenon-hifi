import AVFAudio
import Foundation
import Testing
@testable import CDPlayerKit

struct EqualizerTests {
    @Test func neutralIsFlat() {
        for frequency in [20.0, 100, 1000, 10_000, 20_000] {
            #expect(Equalizer.response(.neutral, at: frequency) == 0)
        }
        #expect(EQPreset.neutral.matches(.neutral))
    }

    @Test func eachBandLiftsItsOwnFrequency() {
        for (index, band) in Equalizer.bands.enumerated() {
            var settings = EQSettings.neutral
            settings.gains[index] = 6
            #expect(abs(Equalizer.response(settings, at: band.frequency) - 6) < 0.01, "\(band.label)")
            // Two octaves away it barely does anything.
            let far = index < 5 ? band.frequency * 4 : band.frequency / 4
            // The top band is wider below its centre (the cookbook keeps
            // its width right near 22 kHz that way): 0.66 dB at 4 kHz.
            #expect(Equalizer.response(settings, at: far) < (index == 9 ? 0.7 : 0.3), "\(band.label)")
        }
    }

    @Test func levelMovesTheWholeCurveAndOffIsFlat() {
        var settings = EQSettings.neutral
        settings.gains[5] = 6
        settings.preamp = -6
        #expect(abs(Equalizer.response(settings, at: 1000)) < 0.01)
        #expect(abs(Equalizer.response(settings, at: 63) + 6) < 0.05)
        settings.enabled = false
        #expect(Equalizer.response(settings, at: 1000) == 0)
        #expect(settings.values.allSatisfy { $0 == 0 })
    }

    @Test func controlsStayInRangeOnHalfDecibels() {
        #expect(Equalizer.clampGain(3.3) == 3.5)
        #expect(Equalizer.clampGain(40) == 12)
        #expect(Equalizer.clampGain(-40) == -12)
        #expect(Equalizer.clampPreamp(2) == 0)
        #expect(Equalizer.clampPreamp(-30) == -12)
        #expect(Equalizer.label(2.5) == "+2.5")
        #expect(Equalizer.label(-12) == "-12")
        #expect(Equalizer.label(0) == "0")
    }

    @Test func storedSettingsComeBackAndBadOnesAreRepaired() throws {
        let preset = EQPreset(name: "GRAVES", gains: [6, 4, 2, 0, 0, 0, 0, 0, 0, 0], preamp: -6)
        let data = try JSONEncoder().encode([preset])
        #expect(try JSONDecoder().decode([EQPreset].self, from: data) == [preset])
        let broken = EQSettings(gains: [30, 1.2], preamp: 5, enabled: true).cleaned
        #expect(broken.gains.count == Equalizer.bands.count)
        #expect(broken.gains[0] == 12 && broken.gains[1] == 1 && broken.preamp == 0)
    }

    @Test func rampReachesTheTargetInSmallSteps() {
        var ramp = EQRamp(values: [0, 0])
        #expect(ramp.bypass)
        ramp.aim(at: [6, -6])
        var seen: [[Double]] = []
        var bypassed: [Bool] = []
        while ramp.isMoving { seen.append(ramp.advance()); bypassed.append(ramp.bypass) }
        // First a step held flat with the filters running, then six steps.
        #expect(seen.first == [0, 0] && bypassed.first == false)
        #expect(seen.count == EQRamp.steps + 1)
        #expect(seen.last == [6, -6])
        #expect(abs(seen[1][0] - 1) < 1e-9)
        // Back to flat: it steps out only after half a second flat.
        ramp.aim(at: [0, 0])
        bypassed = []
        while ramp.isMoving { _ = ramp.advance(); bypassed.append(ramp.bypass) }
        #expect(ramp.current == [0, 0])
        #expect(bypassed.count == EQRamp.steps + EQRamp.settle - 1)
        #expect(bypassed.dropLast().allSatisfy { !$0 } && bypassed.last == true)
    }

    @Test func shelvesLiftEverythingBeyondTheirEnd() {
        var settings = EQSettings.neutral
        settings.gains[0] = 6
        settings.gains[9] = 6
        settings.lowShelf = true
        settings.highShelf = true
        // All the way down and all the way up, unlike a bell.
        #expect(Equalizer.response(settings, at: 20) > 5.9)
        #expect(Equalizer.response(settings, at: 20_000) > 5.9)
        #expect(abs(Equalizer.response(settings, at: 63) - 3) < 0.05)
        #expect(abs(Equalizer.response(settings, at: 8000) - 3) < 0.05)
        #expect(abs(Equalizer.response(settings, at: 1000)) < 0.05)
        settings.lowShelf = false
        settings.highShelf = false
        #expect(Equalizer.response(settings, at: 20_000) < 5)
    }

    @Test func settingsSavedBeforeShelvesStillLoad() throws {
        let old = Data(#"{"gains":[1,0,0,0,0,0,0,0,0,0],"preamp":-1,"enabled":true}"#.utf8)
        let settings = try JSONDecoder().decode(EQSettings.self, from: old)
        #expect(settings.gains[0] == 1 && !settings.lowShelf && !settings.highShelf)
        let oldPreset = Data(#"[{"name":"A","gains":[0,0,0,0,0,0,0,0,0,0],"preamp":0}]"#.utf8)
        #expect(try JSONDecoder().decode([EQPreset].self, from: oldPreset).first?.lowShelf == false)
        let shelved = EQPreset(name: "B", gains: settings.gains, preamp: -1, lowShelf: true)
        #expect(!shelved.matches(settings))
    }

    @Test func changingShapeGoesThroughZero() {
        var settings = EQSettings.neutral
        settings.gains[0] = 6
        var driver = EQDriver(settings: settings)
        settings.lowShelf = true
        driver.aim(at: settings)
        var steps: [EQDriver.Step] = []
        while driver.isMoving { steps.append(driver.advance()) }
        let switched = steps.firstIndex { $0.lowShelf }!
        // The band is at 0 dB when it changes shape, and ends back at 6 dB.
        #expect(steps[switched].values[0] == 0)
        #expect(steps[..<switched].allSatisfy { !$0.lowShelf })
        #expect(steps.last?.values[0] == 6 && steps.last?.lowShelf == true)
    }

    @Test func peakMeterMarksFullScale() {
        #expect(PeakMeter.isOver(1))
        #expect(!PeakMeter.isOver(0.999))
        #expect(PeakMeter.place(1) == 1)
        #expect(PeakMeter.place(0) == 0)
        #expect(abs(PeakMeter.place(0.5) - (1 - 6.0206 / 36)) < 0.001)
        // Rises at once, falls slowly.
        #expect(PeakMeter.follow(shown: 0, peak: 1, seconds: 0.03) == 1)
        #expect(PeakMeter.follow(shown: 1, peak: 0, seconds: 0.5) > 0.6)
    }

    /// One block of one channel through the over counter.
    private func overs(_ block: [Float], gain: Float = 1, inRun: Bool = false) -> (runs: Int, endsInRun: Bool) {
        block.withUnsafeBufferPointer { PeakMeter.overs(in: $0, gain: gain, inRun: inRun) }
    }

    @Test func oversCountRunsNotSamples() {
        // A run inside one block counts once, however many samples it has.
        #expect(overs([0.2, 1.0, 1.1, -1.3, 0.3]).runs == 1)
        // Two separate runs in one block count twice.
        #expect(overs([1.0, 0.5, -1.0]).runs == 2)
        // Nothing below full scale is an over, not even 0.999.
        #expect(overs([0.999, -0.999, 0.5]) == (0, false))
        // The gain comes first: 0.6 with +6 dB (x2) is over, 0.4 is not.
        #expect(overs([0.6], gain: 2).runs == 1)
        #expect(overs([0.4], gain: 2) == (0, false))
    }

    @Test func aRunAcrossBlocksIsOneOver() {
        let first = overs([0.2, 1.5])
        #expect(first == (1, true))
        // The next block starts inside the same run: nothing new is counted.
        let second = overs([1.2, 1.0, 0.3], inRun: first.endsInRun)
        #expect(second == (0, false))
        // A run that starts a new block above full scale and then falls is still
        // the run that was already counted.
        let fresh = overs([0.2, 1.5])
        #expect(fresh == (1, true))
        #expect(overs([1.1, 0.2], inRun: fresh.endsInRun) == (0, false))
        // An empty block keeps the run as it was.
        #expect(overs([], inRun: true) == (0, true))
    }

    @Test func separateRunsAcrossBlocksCountSeparately() {
        let first = overs([1.0, 0.1])
        let second = overs([0.2, 1.0], inRun: first.endsInRun)
        #expect(first.runs + second.runs == 2)
        #expect(second.endsInRun)
    }

    @Test func channelsKeepTheirOwnRuns() {
        // Left is over at the end of its block, right is not: each one's state is its own.
        let left = overs([0.2, 1.2])
        let right = overs([0.2, 0.3])
        #expect(left == (1, true))
        #expect(right == (0, false))
        // The next block only continues left's run.
        #expect(overs([1.1], inRun: left.endsInRun) == (0, true))
        #expect(overs([1.1], inRun: right.endsInRun) == (1, true))
    }
}

/// The sound itself: Apple's equalizer node set up the way the app sets it
/// up, fed test tones offline, and measured.
struct EqualizerSoundTests {
    static let block: AVAudioFrameCount = 512

    /// Renders `input` (left, right) through the equalizer. `each` runs
    /// before every block of 512 frames, to move the controls mid-sound.
    func render(_ input: [[Float]], sampleRate: Double = 44_100,
                each: ((AVAudioUnitEQ, Int) -> Void)? = nil) throws -> [[Float]] {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: Equalizer.bands.count)
        Equalizer.prepare(eq)
        engine.attach(player)
        engine.attach(eq)
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: Self.block)
        try engine.start()
        let frames = input[0].count
        let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        source.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<2 { for i in 0..<frames { source.floatChannelData![channel][i] = input[channel][i] } }
        player.scheduleBuffer(source)
        player.play()
        let out = try #require(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: Self.block))
        var result: [[Float]] = [[], []]
        var done = 0
        while done < frames {
            each?(eq, done)
            _ = try engine.renderOffline(AVAudioFrameCount(min(Int(Self.block), frames - done)), to: out)
            for channel in 0..<2 {
                result[channel] += UnsafeBufferPointer(start: out.floatChannelData![channel], count: Int(out.frameLength))
            }
            done += Int(out.frameLength)
        }
        engine.stop()
        return result
    }

    func tone(_ frequency: Double, seconds: Double = 0.5, sampleRate: Double = 44_100, level: Float = 0.25) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { level * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    func noise(_ count: Int) -> [Float] {
        var seed: UInt64 = 0x1234_5678
        return (0..<count).map { _ in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Int64(bitPattern: seed >> 11) % 1000) / 3000
        }
    }

    /// Level of the second half (the filter has settled), against the input, in dB.
    func gain(_ out: [Float], _ input: [Float]) -> Double {
        func rms(_ x: ArraySlice<Float>) -> Double { (x.reduce(0) { $0 + Double($1 * $1) } / Double(x.count)).squareRoot() }
        let half = input.count / 2
        return 20 * log10(rms(out[half...]) / rms(input[half...]))
    }

    /// The largest jump between two samples in a row: a click shows up as a
    /// jump bigger than the tone itself ever makes.
    func worstStep(_ x: [Float]) -> Float {
        zip(x.dropFirst(), x).map { abs($0 - $1) }.max() ?? 0
    }

    /// The largest bend (second difference): a click is a sudden bend far
    /// sharper than any low tone makes.
    func worstBend(_ x: [Float]) -> Float {
        (2..<x.count).map { abs(x[$0] - 2 * x[$0 - 1] + x[$0 - 2]) }.max() ?? 0
    }

    @Test func neutralLeavesTheSoundUntouched() throws {
        let input = [noise(22_050), Array(noise(22_050).reversed())]
        let out = try render(input) { eq, frame in if frame == 0 { Equalizer.apply(EQSettings.neutral.values, to: eq) } }
        #expect(out[0] == input[0])
        #expect(out[1] == input[1])
    }

    @Test(arguments: [0, 3, 5, 7, 9])
    func eachBandWorksWhereItShould(index: Int) throws {
        let band = Equalizer.bands[index]
        let near = tone(band.frequency)
        let far = tone(index < 5 ? band.frequency * 4 : band.frequency / 4)
        let set: (AVAudioUnitEQ, Int) -> Void = { eq, frame in
            if frame == 0 { var values = EQSettings.neutral.values; values[index] = 6; Equalizer.apply(values, to: eq) }
        }
        let nearOut = try render([near, near], each: set)
        let farOut = try render([far, far], each: set)
        #expect(abs(gain(nearOut[0], near) - 6) < 0.1, "\(band.label) at its centre")
        #expect(gain(farOut[0], far) < (index == 9 ? 0.7 : 0.3), "\(band.label) two octaves away")
    }

    @Test func bothChannelsAreProcessedAndKeptApart() throws {
        let low = tone(63), high = tone(8000), silence = [Float](repeating: 0, count: low.count)
        let out = try render([low, high]) { eq, frame in if frame == 0 { var v = EQSettings.neutral.values; v[1] = 6; Equalizer.apply(v, to: eq) } }
        #expect(abs(gain(out[0], low) - 6) < 0.1)
        #expect(abs(gain(out[1], high)) < 0.1)
        let leftOnly = try render([low, silence]) { eq, frame in if frame == 0 { var v = EQSettings.neutral.values; v[1] = 12; Equalizer.apply(v, to: eq) } }
        #expect(leftOnly[1].allSatisfy { $0 == 0 })
    }

    @Test func movingTheControlsDoesNotClick() throws {
        // A low tone, the hardest case: the band swings 0 → +12 → -12 → 0 dB.
        let input = tone(63, seconds: 2, level: 0.2)
        var ramp = EQRamp(values: EQSettings.neutral.values)
        let targets = [6000: 12.0, 30000: -12.0, 60000: 0.0]
        let out = try render([input, input]) { eq, frame in
            if let target = targets.first(where: { abs($0.key - frame) < Int(Self.block) / 2 })?.value {
                var values = EQSettings.neutral.values
                values[1] = target
                ramp.aim(at: values)
            }
            Equalizer.apply(ramp.advance(), to: eq, bypass: ramp.bypass)
        }
        let turn = Float(2 * Double.pi * 63 / 44_100)
        let loudest = Float(0.2 * pow(10, 12.0 / 20)) * turn
        #expect(worstStep(out[0]) <= loudest * 1.05)
        #expect(worstBend(out[0]) <= loudest * turn * 1.05)
    }

    @Test func switchingOnAndOffDoesNotClick() throws {
        let input = tone(1000, seconds: 1, level: 0.2)
        var settings = EQSettings.neutral
        settings.gains[5] = 6
        var ramp = EQRamp(values: settings.values)
        let out = try render([input, input]) { eq, frame in
            if frame == 11_264 { settings.enabled = false; ramp.aim(at: settings.values) }
            if frame == 33_280 { settings.enabled = true; ramp.aim(at: settings.values) }
            Equalizer.apply(ramp.advance(), to: eq, bypass: ramp.bypass)
        }
        let turn = Float(2 * Double.pi * 1000 / 44_100)
        let loudest = Float(0.2 * pow(10, 6.0 / 20)) * turn
        #expect(worstStep(out[0]) <= loudest * 1.05)
        #expect(worstBend(out[0]) <= loudest * turn * 1.05)
        // Off long enough, the node stepped out and the tone passes bit for bit.
        #expect(out[0][31_000..<33_000] == input[31_000..<33_000])
    }

    @Test(arguments: [44_100.0, 48_000, 96_000])
    func otherSampleRatesKeepTheBandsInPlace(sampleRate: Double) throws {
        let index = 7 // 4 kHz
        let input = tone(4000, sampleRate: sampleRate)
        let out = try render([input, input], sampleRate: sampleRate) { eq, frame in
            if frame == 0 { var v = EQSettings.neutral.values; v[index] = 6; Equalizer.apply(v, to: eq) }
        }
        #expect(abs(gain(out[0], input) - 6) < 0.1)
        let off = tone(1000, sampleRate: sampleRate)
        let offOut = try render([off, off], sampleRate: sampleRate) { eq, frame in
            if frame == 0 { var v = EQSettings.neutral.values; v[index] = 6; Equalizer.apply(v, to: eq) }
        }
        let expected = Equalizer.response(of: Equalizer.peaking(frequency: 4000, gain: 6, sampleRate: sampleRate),
                                          at: 1000, sampleRate: sampleRate)
        #expect(abs(gain(offOut[0], off) - expected) < 0.05)
    }

    @Test func shelvesMatchTheCookbook() throws {
        for (high, band, frequencies) in [(false, 0, [20.0, 40, 63, 125, 500]), (true, 9, [2000.0, 5000, 8000, 12_000, 19_000])] {
            let coefficients = Equalizer.shelf(high: high, frequency: high ? Equalizer.highShelfFrequency : Equalizer.lowShelfFrequency,
                                               gain: 6, sampleRate: 44_100)
            for frequency in frequencies {
                let input = tone(frequency, seconds: 1)
                let out = try render([input, input]) { eq, frame in
                    if frame == 0 {
                        Equalizer.shape(eq, lowShelf: !high, highShelf: high)
                        var v = EQSettings.neutral.values; v[band] = 6; Equalizer.apply(v, to: eq)
                    }
                }
                let expected = Equalizer.response(of: coefficients, at: frequency, sampleRate: 44_100)
                #expect(abs(gain(out[0], input) - expected) < 0.05, "\(high ? "agudos" : "graves") \(frequency) Hz")
            }
        }
    }

    @Test func changingShapeWhilePlayingDoesNotClick() throws {
        // A deep tone with the bass band up, turned bell → shelf → bell.
        let input = tone(40, seconds: 2, level: 0.2)
        var settings = EQSettings.neutral
        settings.gains[0] = 9
        settings.gains[9] = 9
        var driver = EQDriver(settings: settings)
        var shapes = (false, false)
        let out = try render([input, input]) { eq, frame in
            if frame == 0 { Equalizer.apply(settings.values, to: eq, bypass: false) }
            if frame == 20_480 { settings.lowShelf = true; settings.highShelf = true; driver.aim(at: settings) }
            if frame == 56_320 { settings.lowShelf = false; settings.highShelf = false; driver.aim(at: settings) }
            let step = driver.advance()
            if step.lowShelf != shapes.0 || step.highShelf != shapes.1 {
                shapes = (step.lowShelf, step.highShelf)
                Equalizer.shape(eq, lowShelf: step.lowShelf, highShelf: step.highShelf)
            }
            Equalizer.apply(step.values, to: eq, bypass: step.bypass)
        }
        let turn = Float(2 * Double.pi * 40 / 44_100)
        let loudest = Float(0.2 * pow(10, 9.0 / 20)) * turn
        #expect(worstStep(out[0]) <= loudest * 1.05)
        #expect(worstBend(out[0]) <= loudest * turn * 1.05)
    }

    @Test func matchesTheCookbookFilterAcrossTheBand() throws {
        let coefficients = Equalizer.peaking(frequency: 16_000, gain: 6, sampleRate: 44_100)
        for frequency in [8000.0, 12_000, 16_000, 19_000] {
            let input = tone(frequency)
            let out = try render([input, input]) { eq, frame in if frame == 0 { var v = EQSettings.neutral.values; v[9] = 6; Equalizer.apply(v, to: eq) } }
            let expected = Equalizer.response(of: coefficients, at: frequency, sampleRate: 44_100)
            #expect(abs(gain(out[0], input) - expected) < 0.05, "\(frequency) Hz")
        }
    }
}
