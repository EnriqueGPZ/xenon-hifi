import CDPlayerKit
import Foundation

/// The tube preamp unit: its VÁLVULAS switch, the CALIDEZ knob, and the
/// glow of its four tubes. The sound lives in CDPlayerKit/Tube.swift.
@Observable
final class TubeModel {
    private(set) var settings: TubeSettings {
        didSet {
            send(settings)
            save()
        }
    }
    /// How bright each pair of tubes is, 0...1: left channel, right channel.
    private(set) var glow: [Double] = [0, 0]

    private let send: (TubeSettings) -> Void
    private let loudness: () -> [Float]?
    private var timer: Timer?
    private var watchers = 0
    /// When the filaments started to warm up (the unit opened).
    private var lit: Date?
    /// Snapshots: a fixed glow, as if a song played.
    private var demo: [Double]?
    private static let settingsKey = "tube.settings"

    init(send: @escaping (TubeSettings) -> Void, loudness: @escaping () -> [Float]?) {
        self.send = send
        self.loudness = loudness
        // Tests and snapshots start off and never touch what the listener saved.
        if !Store.isOverridden, let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(TubeSettings.self, from: data) {
            settings = saved
        } else {
            settings = .off
        }
        send(settings)
    }

    var warmthPercent: Int { Int((settings.warmth * 100).rounded()) }

    // MARK: - Controls

    func toggle() {
        settings.enabled.toggle()
    }

    func setWarmth(_ value: Double) {
        settings.warmth = TubeSettings.clampWarmth(value)
    }

    func nudgeWarmth(by steps: Int) {
        setWarmth(settings.warmth + Double(steps) * TubeSettings.step)
    }

    func resetWarmth() {
        setWarmth(TubeSettings.defaultWarmth)
    }

    // MARK: - Glow

    /// The tubes glow while the unit is on screen; they warm up each time it opens.
    func startWatching() {
        watchers += 1
        guard timer == nil else { return }
        lit = .now
        let timer = Timer(timeInterval: 1 / SpectrumMeter.rate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
        lit = nil
        glow = [0, 0]
    }

    /// Snapshots only: warm, on, and glowing as if a song played.
    func showDemo() {
        guard Store.isOverridden else { return }
        settings.enabled = true
        settings.warmth = 0.6
        demo = [0.82, 0.64]
        glow = demo!
    }

    private func tick() {
        if let demo {
            glow = demo
            return
        }
        let warm = TubeGlow.warmth(after: lit.map { Date.now.timeIntervalSince($0) } ?? 0)
        let levels = loudness()
        let step = 1 / SpectrumMeter.rate
        for channel in 0..<2 {
            let rms = levels.map { Double($0.count > channel ? $0[channel] : $0.first ?? 0) } ?? 0
            let target = TubeGlow.level(rms: rms, warm: warm, on: settings.enabled)
            glow[channel] = TubeGlow.follow(shown: glow[channel], target: target, seconds: step)
        }
    }

    // MARK: - Private

    private func save() {
        guard !Store.isOverridden, let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }
}
