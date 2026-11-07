import CDPlayerKit
import Foundation

/// The graphic equalizer unit: its ten faders, the level knob, on/off, the
/// saved settings, and the peak meters with their OVER lights. The rules
/// and the sound tests live in CDPlayerKit/Equalizer.swift.
@Observable
final class EqualizerModel {
    /// What the faders, the knob and the switch are set to.
    private(set) var settings: EQSettings {
        didSet {
            send(settings)
            save()
        }
    }
    /// The settings the listener saved, by name. NEUTRO is always there, first.
    private(set) var presets: [EQPreset]
    /// A short message on the unit's display ("1K +2.5 DB", "GUARDADO").
    private(set) var flash: String?
    /// The peak meters, 0 (bottom of the scale) to 1 (full scale), left and right.
    private(set) var meters: [Double] = [0, 0]
    /// Times each channel went over full scale on this song.
    private(set) var overs: [Int] = [0, 0]
    /// Each OVER light is lit until this moment.
    private(set) var overUntil: [Date] = [.distantPast, .distantPast]

    /// The preset these settings match, or nil when they were changed by hand.
    var presetName: String? {
        presets.first { $0.matches(settings) }?.name
    }

    private let send: (EQSettings) -> Void
    private let peaks: () -> (peaks: [Float], overs: [Int])?
    private let resetPeaks: () -> Void
    private var meterTimer: Timer?
    private var flashTask: Task<Void, Never>?
    private var watchers = 0
    private static let settingsKey = "eq.settings"
    private static let presetsKey = "eq.presets"

    init(send: @escaping (EQSettings) -> Void,
         peaks: @escaping () -> (peaks: [Float], overs: [Int])?,
         resetPeaks: @escaping () -> Void) {
        self.send = send
        self.peaks = peaks
        self.resetPeaks = resetPeaks
        // Tests and snapshots start neutral and never touch what the listener saved.
        let defaults = UserDefaults.standard
        if !Store.isOverridden, let data = defaults.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(EQSettings.self, from: data) {
            settings = saved.cleaned
        } else {
            settings = .neutral
        }
        var stored: [EQPreset] = []
        if !Store.isOverridden, let data = defaults.data(forKey: Self.presetsKey),
           let saved = try? JSONDecoder().decode([EQPreset].self, from: data) {
            stored = saved.filter { $0.name != EQPreset.neutralName }
        }
        presets = [.neutral] + stored
        send(settings)
    }

    // MARK: - Controls

    func setGain(_ gain: Double, band: Int) {
        guard settings.gains.indices.contains(band) else { return }
        settings.gains[band] = Equalizer.clampGain(gain)
        show("\(Equalizer.bands[band].label) HZ \(Equalizer.label(settings.gains[band])) DB")
    }

    func nudgeGain(band: Int, by steps: Int) {
        guard settings.gains.indices.contains(band) else { return }
        setGain(settings.gains[band] + Double(steps) * Equalizer.step, band: band)
    }

    func setPreamp(_ level: Double) {
        settings.preamp = Equalizer.clampPreamp(level)
        show("NIVEL \(Equalizer.label(settings.preamp)) DB")
    }

    func nudgePreamp(by steps: Int) {
        setPreamp(settings.preamp + Double(steps) * Equalizer.step)
    }

    func toggle() {
        settings.enabled.toggle()
        show(settings.enabled ? "ECUALIZADOR ON" : "ECUALIZADOR OFF")
    }

    /// Turns an end band (31 or 16K) between bell and shelf.
    func toggleShelf(band: Int) {
        switch band {
        case Equalizer.lowShelfBand: settings.lowShelf.toggle()
        case Equalizer.highShelfBand: settings.highShelf.toggle()
        default: return
        }
        let shelf = band == Equalizer.lowShelfBand ? settings.lowShelf : settings.highShelf
        let name = band == Equalizer.lowShelfBand ? "GRAVES" : "AGUDOS"
        show("\(name) \(shelf ? "ESTANTE" : "CAMPANA")")
    }

    func isShelf(band: Int) -> Bool {
        band == Equalizer.lowShelfBand ? settings.lowShelf : band == Equalizer.highShelfBand ? settings.highShelf : false
    }

    /// Every fader to 0 and the level to full: the sound as it comes from the CD.
    func flatten() {
        apply(.neutral)
    }

    // MARK: - Presets

    func apply(_ preset: EQPreset) {
        settings.gains = preset.gains
        settings.preamp = preset.preamp
        settings.lowShelf = preset.lowShelf
        settings.highShelf = preset.highShelf
        show(preset.name)
    }

    /// The next or previous saved setting, round the list.
    func stepPreset(by offset: Int) {
        let index = presets.firstIndex { $0.matches(settings) } ?? (offset > 0 ? -1 : 0)
        let next = (index + offset + presets.count) % presets.count
        apply(presets[next])
    }

    /// Saves the current faders and level under `name`, replacing one with the same name.
    func save(as rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !name.isEmpty else { return }
        guard name != EQPreset.neutralName else {
            show("NEUTRO NO SE CAMBIA")
            return
        }
        let preset = EQPreset(name: name, gains: settings.gains, preamp: settings.preamp,
                              lowShelf: settings.lowShelf, highShelf: settings.highShelf)
        if let at = presets.firstIndex(where: { $0.name == name }) {
            presets[at] = preset
        } else {
            presets.append(preset)
        }
        savePresets()
        show("GUARDADO \(name)")
    }

    /// The saved setting that matches the faders now, if it can be deleted.
    var deletablePreset: EQPreset? {
        presets.first { $0.matches(settings) && $0.name != EQPreset.neutralName }
    }

    func delete(_ preset: EQPreset) {
        guard preset.name != EQPreset.neutralName else { return }
        presets.removeAll { $0.name == preset.name }
        savePresets()
        show("BORRADO \(preset.name)")
    }

    // MARK: - Peak meters

    /// The meters run while the unit is on screen.
    func startWatching() {
        watchers += 1
        guard meterTimer == nil else { return }
        let timer = Timer(timeInterval: 1 / SpectrumMeter.rate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.meterTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    func stopWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        meterTimer?.invalidate()
        meterTimer = nil
        meters = [0, 0]
    }

    /// A new song: the OVER counts start again.
    func newSong() {
        resetPeaks()
        overs = [0, 0]
        overUntil = [.distantPast, .distantPast]
    }

    /// Snapshots only: the meters as if a loud song played, right one over.
    func showDemoPeaks() {
        guard Store.isOverridden else { return }
        demoHold = true
        meters = [0.78, 1]
        overs = [0, 3]
        overUntil = [.distantPast, .now.addingTimeInterval(60)]
    }

    private var demoHold = false

    private func meterTick() {
        guard !demoHold else { return }
        let reading = peaks()
        let step = 1 / SpectrumMeter.rate
        let now = Date.now
        for channel in 0..<2 {
            let peak = Double(reading?.peaks[channel] ?? 0)
            meters[channel] = PeakMeter.follow(shown: meters[channel], peak: peak, seconds: step)
            if meters[channel] < 0.001 { meters[channel] = 0 }
            let count = reading?.overs[channel] ?? overs[channel]
            if count > overs[channel] { overUntil[channel] = now.addingTimeInterval(PeakMeter.overHold) }
            overs[channel] = count
        }
    }

    // MARK: - Private

    private func show(_ text: String) {
        flash = text
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            if !Task.isCancelled { flash = nil }
        }
    }

    private func save() {
        guard !Store.isOverridden, let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }

    private func savePresets() {
        guard !Store.isOverridden,
              let data = try? JSONEncoder().encode(presets.filter { $0.name != EQPreset.neutralName }) else { return }
        UserDefaults.standard.set(data, forKey: Self.presetsKey)
    }
}
