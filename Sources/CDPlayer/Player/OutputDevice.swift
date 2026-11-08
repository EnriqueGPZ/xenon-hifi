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

    /// Whether this app holds `device` for itself alone (Core Audio's hog mode).
    static func isHeld(_ device: AudioDeviceID?) -> Bool {
        guard let device else { return false }
        return hogOwner(device) == getpid()
    }

    /// Takes the Mac's chosen output for this app alone. Returns the device,
    /// or nil when it could not be taken (another app holds it). macOS then
    /// sends every other app's sound to another output (the Mac's speakers).
    static func hold() -> AudioDeviceID? {
        guard let device = systemDefault else { return nil }
        if hogOwner(device) == getpid() { return device }
        guard hogOwner(device) == -1 else { return nil }
        setHog(device, to: getpid())
        return hogOwner(device) == getpid() ? device : nil
    }

    /// Gives `device` back to the rest of the Mac, if this app holds it.
    static func release(_ device: AudioDeviceID) {
        guard hogOwner(device) == getpid() else { return }
        setHog(device, to: -1)
    }

    /// Where the sound goes: the DAC this app holds, else the Mac's chosen output.
    static var device: AudioDeviceID? { ExclusiveOutput.shared.heldDevice ?? systemDefault }

    private static func hogOwner(_ device: AudioDeviceID) -> pid_t {
        var address = address(kAudioDevicePropertyHogMode)
        var owner: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &owner) == noErr else { return -1 }
        return owner
    }

    private static func setHog(_ device: AudioDeviceID, to pid: pid_t) {
        var address = address(kAudioDevicePropertyHogMode)
        var value = pid
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<pid_t>.size), &value)
    }

    /// The output chosen in the Mac's sound settings. Held by this app, macOS
    /// shows another one here for the rest of the apps.
    private static var systemDefault: AudioDeviceID? {
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

/// "Usar el DAC en exclusiva" (Settings): while any player sounds, the app
/// holds the DAC for itself, so no other sound mixes in and no other app
/// changes its rate. Paused or stopped, the DAC goes back to the Mac.
/// macOS gives it back on its own if the app quits or crashes.
/// Holding it makes macOS move the Mac's default output elsewhere, so the
/// players pin their engine to the held DAC (Playback.routeOutput).
final class ExclusiveOutput {
    static let shared = ExclusiveOutput()
    static let settingKey = "exclusiveDAC"

    private var playing: Set<ObjectIdentifier> = []
    private(set) var heldDevice: AudioDeviceID?

    var isOn: Bool { UserDefaults.standard.bool(forKey: Self.settingKey) }

    /// True when a player is about to sound and the DAC still has to be taken.
    func needsHold() -> Bool {
        isOn && !OutputDevice.isHeld(heldDevice)
    }

    /// Takes the DAC (call with the engine stopped). False when another app holds it.
    @discardableResult
    func hold() -> Bool {
        // One held before but gone (unplugged): forget it first.
        if let heldDevice { OutputDevice.release(heldDevice); self.heldDevice = nil }
        heldDevice = OutputDevice.hold()
        return heldDevice != nil
    }

    func setPlaying(_ player: AnyObject, _ isPlaying: Bool) {
        if isPlaying { playing.insert(ObjectIdentifier(player)) } else { playing.remove(ObjectIdentifier(player)) }
        // A moment later: reading again from a point stops and starts the
        // player in one go, and the DAC must not go back in between.
        guard playing.isEmpty else { return }
        DispatchQueue.main.async { [self] in
            if playing.isEmpty { releaseHeld() }
        }
    }

    /// The switch in Settings changed: off gives the DAC back now; on takes
    /// it the next time Play is pressed.
    func settingChanged() {
        if !isOn { releaseHeld() }
    }

    func releaseHeld() {
        if let heldDevice { OutputDevice.release(heldDevice) }
        heldDevice = nil
    }
}
