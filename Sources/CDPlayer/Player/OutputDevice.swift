import CoreAudio
import Foundation

/// The Mac's sound output (the DAC): its sample rate, read and set through
/// Core Audio. Setting it to the music's own rate means nothing between the
/// file and the DAC converts the sound ("bit-perfect" when the equalizer is
/// neutral and the volume at full).
enum OutputDevice {
    /// The rate the DAC runs at now; 0 when there is no output.
    static var sampleRate: Double {
        guard let device else { return 0 }
        var address = address(kAudioDevicePropertyNominalSampleRate)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr else { return 0 }
        return rate
    }

    /// The rates the DAC can run at.
    static var supportedRates: [Double] {
        guard let device else { return [] }
        var address = address(kAudioDevicePropertyAvailableNominalSampleRates)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return [] }
        var ranges = [AudioValueRange](repeating: AudioValueRange(),
                                       count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &ranges) == noErr else { return [] }
        return ranges.map(\.mMinimum)
    }

    /// Asks the DAC for `rate` and waits (at most a second) until it runs at
    /// it. A rate the DAC cannot do is left alone: macOS converts then.
    /// Returns whether the DAC now runs at `rate`.
    @discardableResult
    static func setSampleRate(_ rate: Double) -> Bool {
        guard let device, supportedRates.contains(rate) else { return false }
        if sampleRate == rate { return true }
        var address = address(kAudioDevicePropertyNominalSampleRate)
        var wanted: Float64 = rate
        let status = AudioObjectSetPropertyData(device, &address, 0, nil,
                                                UInt32(MemoryLayout<Float64>.size), &wanted)
        guard status == noErr else { return false }
        // The change takes a moment; the sound must not start before it.
        let deadline = Date.now.addingTimeInterval(1)
        while sampleRate != rate, Date.now < deadline { Thread.sleep(forTimeInterval: 0.01) }
        return sampleRate == rate
    }

    private static var device: AudioDeviceID? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size,
                                         &device) == noErr, device != 0 else { return nil }
        return device
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
