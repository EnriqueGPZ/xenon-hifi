import AudioToolbox
import AVFoundation
import CDPlayerKit
import Synchronization

/// The tube preamp as a link of the sound chain: the tube stage
/// (CDPlayerKit/Tube.swift), then the crossfeed (CDPlayerKit/Crossfeed.swift).
/// An Audio Unit that lives inside the app, so AVAudioEngine can put it
/// between the player and the equalizer. The crossfeed treats both channels
/// alike in nothing but their difference, and the equalizer treats both
/// alike, so crossfeed before the equalizer sounds the same as after it.
///
/// The switches, the knob and the selector reach the sound thread through
/// atomics: the sound thread never waits for the app.
nonisolated final class TubeAudioUnit: AUAudioUnit, @unchecked Sendable {
    static let description = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: fourCharCode("tube"),
        componentManufacturer: fourCharCode("Xenn"),
        componentFlags: 0,
        componentFlagsMask: 0)

    /// Registers the unit with the system, once, before the first one is made.
    static let register: Void = {
        AUAudioUnit.registerSubclass(TubeAudioUnit.self, as: description, name: "XENON: Válvulas", version: 1)
    }()

    private static func fourCharCode(_ text: String) -> FourCharCode {
        text.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }

    private let enabled = Atomic<Bool>(false)
    private let warmthBits = Atomic<UInt32>(Float(TubeSettings.defaultWarmth).bitPattern)
    private let crossfeedOn = Atomic<Bool>(false)
    private let crossfeedLevel = Atomic<Int>(CrossfeedLevel.medium.index)
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var inputs: AUAudioUnitBusArray!
    private var outputs: AUAudioUnitBusArray!
    /// Made in allocateRenderResources, for the rate the chain runs at.
    private var stage: TubeStage?
    private var crossfeed: Crossfeed?
    private var inputBuffer: AVAudioPCMBuffer?

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = 4096
    }

    override var inputBusses: AUAudioUnitBusArray { inputs }
    override var outputBusses: AUAudioUnitBusArray { outputs }
    override var canProcessInPlace: Bool { true }

    func set(_ settings: TubeSettings) {
        enabled.store(settings.enabled, ordering: .relaxed)
        warmthBits.store(Float(settings.warmth).bitPattern, ordering: .relaxed)
    }

    func set(_ settings: CrossfeedSettings) {
        crossfeedOn.store(settings.enabled, ordering: .relaxed)
        crossfeedLevel.store(settings.level.index, ordering: .relaxed)
    }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let format = inputBus.format
        guard format.channelCount == 2, outputBus.format.channelCount == 2 else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        stage = TubeStage(sampleRate: format.sampleRate)
        crossfeed = Crossfeed(sampleRate: format.sampleRate)
        inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFramesToRender)
    }

    override func deallocateRenderResources() {
        stage = nil
        crossfeed = nil
        inputBuffer = nil
        super.deallocateRenderResources()
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        return { [unowned self] _, timestamp, frameCount, _, outputData, _, pullInputBlock in
            guard let pullInputBlock, let stage, let crossfeed, let inputBuffer else { return kAudioUnitErr_NoConnection }
            guard frameCount <= inputBuffer.frameCapacity else { return kAudioUnitErr_TooManyFramesToProcess }
            // Pull the sound from the player into our own buffer.
            let input = inputBuffer.mutableAudioBufferList
            let inputList = UnsafeMutableAudioBufferListPointer(input)
            for index in 0..<inputList.count {
                inputList[index].mDataByteSize = frameCount * UInt32(MemoryLayout<Float>.size)
            }
            var flags = AudioUnitRenderActionFlags()
            let status = pullInputBlock(&flags, timestamp, frameCount, 0, input)
            guard status == noErr else { return status }
            // Out in place: the output points at our buffer unless it has its own.
            let outputList = UnsafeMutableAudioBufferListPointer(outputData)
            for index in 0..<min(outputList.count, inputList.count) {
                if outputList[index].mData == nil {
                    outputList[index].mData = inputList[index].mData
                } else if outputList[index].mData != inputList[index].mData {
                    outputList[index].mData!.copyMemory(from: inputList[index].mData!,
                                                        byteCount: Int(inputList[index].mDataByteSize))
                }
                outputList[index].mDataByteSize = inputList[index].mDataByteSize
            }
            guard outputList.count >= 2,
                  let left = outputList[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = outputList[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            stage.process(left: left, right: right, frames: Int(frameCount),
                          on: self.enabled.load(ordering: .relaxed),
                          warmth: Float(bitPattern: self.warmthBits.load(ordering: .relaxed)))
            crossfeed.process(left: left, right: right, frames: Int(frameCount),
                              on: self.crossfeedOn.load(ordering: .relaxed),
                              level: CrossfeedLevel(index: self.crossfeedLevel.load(ordering: .relaxed)))
            return noErr
        }
    }
}

extension TubeAudioUnit {
    /// The self-test: a second of a 1 kHz tone through the real chain link,
    /// rendered offline (nothing reaches the DAC). Off must give the tone
    /// back as it went in; tubes on must add a 2nd harmonic. With
    /// `leftOnly`, the tone plays on the left alone, so crossfeed shows as
    /// sound on the right. Returns the biggest change on either channel, the
    /// 2nd harmonic on the left, and the right channel's tone against the
    /// left input, both in dB. Nil if the unit would not load.
    static func check(on: Bool, crossfeed: Bool = false, leftOnly: Bool = false)
        -> (difference: Float, second: Double, right: Double)? {
        _ = register
        let rate = 44_100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let frames = AVAudioFrameCount(rate)
        guard let tone = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        tone.frameLength = frames
        for channel in 0..<2 {
            for n in 0..<Int(frames) {
                let silent = leftOnly && channel == 1
                tone.floatChannelData![channel][n] = silent ? 0 : 0.5 * Float(sin(2 * Double.pi * 1000 * Double(n) / rate))
            }
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let node = AVAudioUnitEffect(audioComponentDescription: description)
        guard let unit = node.auAudioUnit as? TubeAudioUnit else { return nil }
        unit.set(TubeSettings(enabled: on, warmth: 1))
        unit.set(CrossfeedSettings(enabled: crossfeed, level: .medium))
        engine.attach(player)
        engine.attach(node)
        engine.connect(player, to: node, format: format)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
            try engine.start()
        } catch { return nil }
        player.scheduleBuffer(tone)
        player.play()
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        var rendered: [[Float]] = [[], []]
        while rendered[0].count < Int(frames) {
            let count = min(engine.manualRenderingMaximumFrameCount, frames - AVAudioFrameCount(rendered[0].count))
            guard (try? engine.renderOffline(count, to: out)) == .success else { return nil }
            for channel in 0..<2 {
                rendered[channel] += UnsafeBufferPointer(start: out.floatChannelData![channel], count: Int(out.frameLength))
            }
        }
        engine.stop()
        var difference: Float = 0
        for channel in 0..<2 {
            let input = UnsafeBufferPointer(start: tone.floatChannelData![channel], count: Int(frames))
            difference = zip(rendered[channel], input).reduce(difference) { max($0, abs($1.0 - $1.1)) }
        }
        // A tone's level in the settled second half of a channel.
        func level(_ samples: [Float], _ hz: Double) -> Double {
            var re = 0.0, im = 0.0
            let start = samples.count / 2
            for n in start..<samples.count {
                let phase = 2 * Double.pi * hz * Double(n) / rate
                re += Double(samples[n]) * cos(phase)
                im += Double(samples[n]) * sin(phase)
            }
            return (re * re + im * im).squareRoot()
        }
        let reference = level(Array(UnsafeBufferPointer(start: tone.floatChannelData![0], count: Int(frames))), 1000)
        return (difference,
                20 * log10(max(level(rendered[0], 2000), 1e-12) / level(rendered[0], 1000)),
                20 * log10(max(level(rendered[1], 1000), 1e-12) / reference))
    }
}
