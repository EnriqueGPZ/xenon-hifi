import CDPlayerKit
import Foundation

/// The tube preamp unit: its VÁLVULAS switch, the CALIDEZ knob, the glow of
/// its four tubes, and the CROSSFEED switch and selector. The sound lives in
/// CDPlayerKit/Tube.swift and CDPlayerKit/Crossfeed.swift.
@Observable
final class TubeModel {
    private(set) var settings: TubeSettings {
        didSet {
            send(settings)
            save()
        }
    }
    /// CROSSFEED, for headphones. Saved on its own, apart from the tubes.
    private(set) var crossfeed: CrossfeedSettings {
        didSet {
            sendCrossfeed(crossfeed)
            saveCrossfeed()
        }
    }
    /// How bright each pair of tubes is, 0...1: left channel, right channel.
    private(set) var glow: [Double] = [0, 0]

    private let send: (TubeSettings) -> Void
    private let sendCrossfeed: (CrossfeedSettings) -> Void
    private let loudness: () -> [Float]?
    private var timer: Timer?
    private var watchers = 0
    /// When the filaments started to warm up (the unit opened).
    private var lit: Date?
    /// Snapshots: a fixed glow, as if a song played.
    private var demo: [Double]?
    private static let settingsKey = "tube.settings"
    private static let crossfeedKey = "crossfeed.settings"

    init(send: @escaping (TubeSettings) -> Void, sendCrossfeed: @escaping (CrossfeedSettings) -> Void,
         loudness: @escaping () -> [Float]?) {
        self.send = send
        self.sendCrossfeed = sendCrossfeed
        self.loudness = loudness
        // Tests and snapshots start off and never touch what the listener saved.
        if !Store.isOverridden, let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(TubeSettings.self, from: data) {
            settings = saved
        } else {
            settings = .off
        }
        if !Store.isOverridden, let data = UserDefaults.standard.data(forKey: Self.crossfeedKey),
           let saved = try? JSONDecoder().decode(CrossfeedSettings.self, from: data) {
            crossfeed = saved
        } else {
            crossfeed = .off
        }
        send(settings)
        sendCrossfeed(crossfeed)
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

    func toggleCrossfeed() {
        crossfeed.enabled.toggle()
    }

    func setCrossfeedLevel(_ level: CrossfeedLevel) {
        crossfeed.level = level
    }

    /// SUAVE → MEDIO → FUERTE → SUAVE.
    func nextCrossfeedLevel() {
        crossfeed.level = CrossfeedLevel(index: (crossfeed.level.index + 1) % CrossfeedLevel.allCases.count)
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
        crossfeed.enabled = true
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

    private func saveCrossfeed() {
        guard !Store.isOverridden, let data = try? JSONEncoder().encode(crossfeed) else { return }
        UserDefaults.standard.set(data, forKey: Self.crossfeedKey)
    }
}
