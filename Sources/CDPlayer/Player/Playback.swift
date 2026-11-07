import Accelerate
import AVFoundation
import CDPlayerKit

/// Plays one track at a time, like a CD player with anti-skip memory: a
/// reader in the background takes the CD a couple of seconds at a time and
/// keeps about twelve seconds of sound ready, so a slow drive never starves
/// the sound. The next track is queued right behind the current one, so
/// there is no gap between tracks. Without a file (the demo disc in tests
/// and snapshots) it runs a silent clock, so the rest of the app behaves the
/// same either way.
///
/// The sound runs: reader → player node (balance) → tubes → equalizer →
/// mixer (volume) → the Mac's output (the DAC). The bars, the meters and the
/// clip lights listen right after the equalizer, so they show what you hear.
///
/// The same player plays the CD and the music files, each with its own
/// copy. The chain runs at the track's own sample rate, and before it
/// sounds the DAC is set to that rate (OutputDevice), so a 96 kHz file
/// reaches the DAC at 96 kHz and the CD at 44.1, with nothing converted.
final class Playback {
    var onFinish: (() -> Void)?
    /// The disc stopped giving sound for the track that plays (after retries).
    var onReadError: (() -> Void)?
    /// The sound card would not start.
    var onSoundError: (() -> Void)?
    var volume: Float = 0.7 {
        didSet { engine.mainMixerNode.outputVolume = volume; updateOutputGains() }
    }
    /// -1 all left, 0 centre, 1 all right (CDPlayerKit/Balance.swift).
    var balance: Float = 0 {
        didSet { node.pan = balance; updateOutputGains() }
    }
    /// The equalizer's setting. Changes glide over a tenth of a second
    /// (CDPlayerKit/Equalizer.swift, EQRamp), so they never click.
    var equalizer: EQSettings = .neutral {
        didSet {
            guard equalizer != oldValue else { return }
            driver.aim(at: equalizer)
            startRamp()
        }
    }

    /// The tube preamp's switch and knob (CDPlayerKit/Tube.swift). Off, the
    /// sound passes through it untouched; switching fades, so it never clicks.
    var tube: TubeSettings = .off {
        didSet { tubeUnit?.set(tube) }
    }

    /// The sample rate the chain runs at now.
    var sampleRate: Double { format.sampleRate }

    private let engine = AVAudioEngine()
    private let open: @Sendable (URL) throws -> any SoundSource
    private var format: AVAudioFormat
    private let node = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: Equalizer.bands.count)
    private let tubeNode: AVAudioUnitEffect = {
        _ = TubeAudioUnit.register
        return AVAudioUnitEffect(audioComponentDescription: TubeAudioUnit.description)
    }()
    private var tubeUnit: TubeAudioUnit? { tubeNode.auAudioUnit as? TubeAudioUnit }
    private var driver = EQDriver(settings: .neutral)
    private var shapes = (low: false, high: false)
    private var rampTimer: Timer?
    private let feeder: Feeder
    private let listener = SoundListener()
    private var generation = 0
    /// The track that sounds now, and the one queued right behind it.
    private var current: Feeder.Segment?
    private var upcoming: Feeder.Segment?
    /// The track that took over without a gap, until the app asks for it.
    private var handedOver: URL?
    /// The current track played to its end with nothing behind it.
    private var currentEnded = false
    /// The disc failed in the middle: the next play reads again from heldTime.
    private var needsRestart = false
    private var isPlaying = false
    private var heldTime: TimeInterval = 0
    private var silentLength: TimeInterval = 0
    private var silentPosition: TimeInterval = 0
    private var silentStarted: Date?

    /// `open` gives the sound of a track: the CD's reader or a file's.
    init(open: @escaping @Sendable (URL) throws -> any SoundSource = Playback.openCDTrack) {
        self.open = open
        format = Feeder.format(rate: 44_100)
        engine.attach(node)
        engine.attach(tubeNode)
        engine.attach(eq)
        Equalizer.prepare(eq)
        engine.mainMixerNode.outputVolume = volume
        feeder = Feeder(node: node, format: format, open: open)
        connectChain()
        listener.attach(to: eq, format: format)
        updateOutputGains()
        feeder.onSegmentEnd = { [weak self] segment, generation in
            Task { @MainActor in self?.segmentEnded(segment, generation: generation) }
        }
        feeder.onReadError = { [weak self] segment, generation, time in
            Task { @MainActor in self?.readFailed(segment, generation: generation, at: time) }
        }
        // Headphones or the DAC unplugged and back: pick the sound up again.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeAfterDeviceChange() }
        }
    }

    /// A track of the CD: 16-bit stereo at 44.1 kHz, as macOS gives it.
    nonisolated static func openCDTrack(_ url: URL) throws -> any SoundSource {
        let reader = try CDTrackReader(url: url)
        guard reader.header.sampleRate == 44_100, reader.header.channels == 2
        else { throw CDTrackReader.ReadError.unsupported }
        return reader
    }

    var currentTime: TimeInterval {
        guard let current else {
            let running = silentStarted.map { Date.now.timeIntervalSince($0) } ?? 0
            return min(silentLength, silentPosition + running)
        }
        guard isPlaying, !currentEnded, let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime),
              let start = feeder.nodeStart(of: current) else { return heldTime }
        let frames = max(0, playerTime.sampleTime - start)
        let time = Double(current.startFrame + frames) / format.sampleRate
        return min(time, current.duration)
    }

    /// The latest sound that played, mixed to mono, for the bars. Nil when
    /// nothing plays.
    func recentSamples() -> [Float]? {
        guard isPlaying, current != nil else { return nil }
        return listener.latest()
    }

    /// How loud each channel (left, right) was in that same moment, as RMS
    /// from 0 to 1, for the VU meters. Nil when nothing plays.
    func recentLoudness() -> [Float]? {
        guard isPlaying, current != nil else { return nil }
        // The meters show what comes out, so they follow the balance too.
        let gains = Balance.gains(Double(balance))
        return listener.loudness().enumerated().map { channel, level in
            level * Float(channel == 0 ? gains.left : gains.right)
        }
    }

    /// The loudest sample of each channel since the last call, as it reaches
    /// the DAC (after balance and volume), and how many times each channel
    /// went over full scale since `resetOvers`. Nil when nothing plays.
    func recentPeaks() -> (peaks: [Float], overs: [Int])? {
        guard isPlaying, current != nil else { return nil }
        return listener.takePeaks()
    }

    func resetOvers() {
        listener.resetOvers()
    }

    func load(_ url: URL?, length: TimeInterval) throws {
        // The next track already took over without a gap: keep it going.
        if let url, url == handedOver, current?.url == url {
            handedOver = nil
            return
        }
        reset()
        if let url {
            let reader = try open(url)
            // Another sample rate: the chain changes to it (the DAC follows on play).
            if reader.sampleRate != format.sampleRate { change(to: reader.sampleRate) }
            let segment = Feeder.Segment(url: url, reader: reader, startFrame: 0)
            current = segment
            feeder.feed(segment, generation: generation)
        } else {
            silentLength = length
        }
    }

    /// Queues the next track right behind the current one. A different track
    /// than the one queued (shuffle or favorites changed) starts the reading
    /// again from here, with the new one behind. Nil drops the queued track.
    /// `opened` is the next track already open (music files): one at
    /// another sample rate is not queued, since the chain and the DAC must
    /// change rate between the two; it starts on its own after a short gap.
    func preload(_ url: URL?, opened: (any SoundSource)? = nil) {
        guard current != nil, !currentEnded else { return }
        var url = url
        if let opened, opened.sampleRate != format.sampleRate { url = nil }
        if let upcoming {
            guard upcoming.url != url else { return }
            restart(at: currentTime, playing: isPlaying)
        }
        guard let url, let current, url != current.url else { return }
        let segment = Feeder.Segment(url: url, reader: opened, startFrame: 0)
        upcoming = segment
        feeder.feed(segment, generation: generation)
    }

    /// Returns false when the sound card would not start.
    func play() -> Bool {
        guard current != nil else {
            if silentStarted == nil { silentStarted = .now }
            return true
        }
        if needsRestart { restart(at: heldTime, playing: false) }
        if currentEnded { seek(to: 0) }
        // The DAC at the track's rate, so nothing on the way converts it.
        if matchesDAC, OutputDevice.sampleRate != format.sampleRate {
            engine.stop()
            OutputDevice.setSampleRate(format.sampleRate)
        }
        if !engine.isRunning {
            do { try engine.start() } catch { return false }
        }
        feeder.play(true)
        isPlaying = true
        return true
    }

    func pause() {
        guard current != nil else {
            silentPosition = currentTime
            silentStarted = nil
            return
        }
        heldTime = currentTime
        feeder.play(false)
        node.pause()
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        guard current != nil else {
            silentPosition = min(max(0, time), silentLength)
            if silentStarted != nil { silentStarted = .now }
            return
        }
        // Already there (the next track that just took over starts at 0).
        if !currentEnded, !needsRestart, abs(time - currentTime) < 0.5 { return }
        restart(at: time, playing: isPlaying)
    }

    /// Closes the files, so the disc can be ejected.
    func unload() {
        reset()
        engine.stop()
        feeder.waitUntilIdle()
    }

    /// The silent clock has no reader: the app's clock asks it each tick.
    func checkSilentEnd() {
        guard current == nil, silentLength > 0, silentStarted != nil, currentTime >= silentLength else { return }
        silentPosition = silentLength
        silentStarted = nil
        onFinish?()
    }

    // MARK: - Private

    private func reset() {
        restartFeeding()
        current = nil
        isPlaying = false
        heldTime = 0
        silentLength = 0
        silentPosition = 0
        silentStarted = nil
    }

    /// Stops the sound and the reader, and forgets what was queued.
    private func restartFeeding() {
        generation = feeder.restart()
        node.stop()
        upcoming = nil
        handedOver = nil
        currentEnded = false
        needsRestart = false
        isPlaying = false
    }

    /// Reads the current track again from `time`, and plays on when `playing`.
    private func restart(at time: TimeInterval, playing: Bool) {
        guard let current else { return }
        restartFeeding()
        let frame = Int64(min(max(0, time), current.duration) * format.sampleRate)
        let segment = Feeder.Segment(url: current.url, reader: current.reader, startFrame: frame)
        self.current = segment
        heldTime = Double(frame) / format.sampleRate
        feeder.feed(segment, generation: generation)
        if playing {
            feeder.play(true)
            isPlaying = true
        }
    }

    /// The disc failed for the track that plays. The sound read before the
    /// failure has played out by now, and `time` is where the bad read starts:
    /// the place is kept, so the next play reads on from it.
    /// A next track that cannot be read is not special: it takes over without
    /// a gap like any other, and its marker plays right after the current
    /// track's last sound. Its marker's report comes after the handover (both
    /// are queued in that order), so the error shows at 0:00 of that track.
    private func readFailed(_ segment: Feeder.Segment, generation: Int, at time: TimeInterval) {
        guard generation == self.generation, segment === current else { return }
        let wasPlaying = isPlaying
        restartFeeding()
        heldTime = time
        needsRestart = true
        if wasPlaying { onReadError?() }
    }

    private func segmentEnded(_ segment: Feeder.Segment, generation: Int) {
        guard generation == self.generation, segment === current else { return }
        if let upcoming {
            // The next track is already sounding: it becomes the current one.
            current = upcoming
            self.upcoming = nil
            handedOver = upcoming.url
        } else {
            heldTime = segment.duration
            currentEnded = true
        }
        onFinish?()
    }

    /// Tests and snapshots never touch the DAC the listener uses.
    private var matchesDAC: Bool { !Store.isOverridden }

    /// Runs the chain at another sample rate. Nothing plays (load reset it).
    private func change(to rate: Double) {
        engine.stop()
        format = Feeder.format(rate: rate)
        listener.detach(from: eq)
        connectChain()
        listener.attach(to: eq, format: format)
        feeder.use(format)
    }

    private func connectChain() {
        engine.connect(node, to: tubeNode, format: format)
        engine.connect(tubeNode, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
    }

    private func updateOutputGains() {
        let gains = Balance.gains(Double(balance))
        listener.setOutputGains([Float(gains.left) * volume, Float(gains.right) * volume])
    }

    /// Moves the equalizer one small step at a time until it reaches the setting.
    private func startRamp() {
        guard rampTimer == nil else { return }
        let timer = Timer(timeInterval: EQRamp.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepRamp() }
        }
        RunLoop.main.add(timer, forMode: .common)
        rampTimer = timer
        stepRamp()
    }

    private func stepRamp() {
        let step = driver.advance()
        // The shape only when it changes: the driver changes it at 0 dB.
        if step.lowShelf != shapes.low || step.highShelf != shapes.high {
            shapes = (step.lowShelf, step.highShelf)
            Equalizer.shape(eq, lowShelf: step.lowShelf, highShelf: step.highShelf)
        }
        Equalizer.apply(step.values, to: eq, bypass: step.bypass)
        if !driver.isMoving {
            rampTimer?.invalidate()
            rampTimer = nil
        }
    }

    /// macOS restarted the sound card: the DAC changed rate (a song of higher
    /// quality, or the other unit), or it was unplugged and back. The engine
    /// stops and the player node drops the sound it had queued, so the music
    /// is read again from where it was; the node alone would sit silent.
    private func resumeAfterDeviceChange() {
        guard current != nil else { return }
        guard isPlaying else {
            // Paused: the next play reads again from the paused second.
            needsRestart = true
            return
        }
        let time = currentTime
        // Back to this music's own rate.
        if matchesDAC, OutputDevice.sampleRate != format.sampleRate {
            engine.stop()
            OutputDevice.setSampleRate(format.sampleRate)
        }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            heldTime = time
            isPlaying = false
            onSoundError?()
            return
        }
        // Through the feeder: the node starts once the first sound is queued.
        restart(at: time, playing: true)
    }
}

/// Reads the CD in the background and hands the sound to the player node.
/// Runs off the main thread: the drive can take a while to answer.
nonisolated final class Feeder: @unchecked Sendable {
    /// Stereo float at `rate`: what the sources give and the chain runs at.
    static func format(rate: Double) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
    }
    /// Half a second first, so play starts quickly; then two seconds a read.
    static let firstChunk: TimeInterval = 0.5
    static let chunk: TimeInterval = 2
    /// How much sound to keep ready ahead of what plays.
    static let ahead: TimeInterval = 12

    /// One stretch of a track to play, from `startFrame` to its end.
    final class Segment: @unchecked Sendable {
        let url: URL
        /// Opened in the background when nil (the next track).
        var reader: (any SoundSource)?
        let startFrame: Int64
        var duration: TimeInterval { reader?.duration ?? 0 }

        init(url: URL, reader: (any SoundSource)?, startFrame: Int64) {
            self.url = url
            self.reader = reader
            self.startFrame = startFrame
        }
    }

    /// Called (from the audio thread) when a segment's last sound has played.
    var onSegmentEnd: (@Sendable (Segment, Int) -> Void)?
    /// Called when a segment could not be read even after the retries, once
    /// the sound read before the failure has played out. The time is where the
    /// bad read starts, in the track.
    var onReadError: (@Sendable (Segment, Int, TimeInterval) -> Void)?

    static let readAttempts = 3
    /// Pause before a read is tried again (a scratch or a loose cable often passes).
    static let retryPause: TimeInterval = 0.2

    private let node: AVAudioPlayerNode
    private let open: @Sendable (URL) throws -> any SoundSource
    /// Changed only while nothing is queued (`use`).
    private var format: AVAudioFormat
    private let queue = DispatchQueue(label: "CDPlayer.reader", qos: .userInitiated)
    private let lock = NSLock()
    private let room = DispatchSemaphore(value: 0)
    private var generation = 0
    private var queuedFrames: Int64 = 0
    private var scheduledFrames: Int64 = 0
    private var starts: [ObjectIdentifier: Int64] = [:]
    /// Play was pressed before the first sound was read.
    private var playPending = false

    init(node: AVAudioPlayerNode, format: AVAudioFormat, open: @escaping @Sendable (URL) throws -> any SoundSource) {
        self.node = node
        self.format = format
        self.open = open
    }

    /// The format of what comes next. Call right after `restart`.
    func use(_ format: AVAudioFormat) {
        lock.lock()
        self.format = format
        lock.unlock()
    }

    /// Forgets everything queued. Call `node.stop()` right after.
    func restart() -> Int {
        lock.lock()
        generation += 1
        queuedFrames = 0
        scheduledFrames = 0
        starts = [:]
        playPending = false
        let current = generation
        lock.unlock()
        room.signal()
        return current
    }

    /// Where `segment` starts on the player node's clock, once queued.
    func nodeStart(of segment: Segment) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        return starts[ObjectIdentifier(segment)]
    }

    /// Starts the sound, or stops waiting to. The node starts only once it
    /// has sound queued, so its clock matches what plays.
    func play(_ wanted: Bool) {
        lock.lock()
        let ready = scheduledFrames > 0
        playPending = wanted && !ready
        lock.unlock()
        if wanted && ready { node.play() }
    }

    func waitUntilIdle() {
        let done = DispatchSemaphore(value: 0)
        queue.async { done.signal() }
        _ = done.wait(timeout: .now() + 3)
    }

    func feed(_ segment: Segment, generation: Int) {
        queue.async { [self] in
            run(segment, generation: generation)
        }
    }

    private func run(_ segment: Segment, generation: Int) {
        lock.lock()
        let format = self.format
        let current = self.generation == generation
        lock.unlock()
        guard current else { return }
        let rate = format.sampleRate
        let ahead = Int64(Self.ahead * rate)
        segment.reader?.seek(toFrame: segment.startFrame)
        var first = true
        while true {
            lock.lock()
            guard self.generation == generation else { lock.unlock(); return }
            let full = queuedFrames >= ahead
            if first { starts[ObjectIdentifier(segment)] = scheduledFrames }
            lock.unlock()
            if full {
                _ = room.wait(timeout: .now() + 0.25)
                continue
            }
            // One big read from the disc.
            let seconds = first ? Self.firstChunk : Self.chunk
            let chunk = readChunk(segment, frames: AVAudioFrameCount(seconds * rate))
            first = false
            let buffer: AVAudioPCMBuffer
            let last: Bool
            switch chunk {
            case .sound(let sound):
                buffer = sound
                last = segment.reader?.atEnd != false
            case .end:
                // A tiny silence marks the real end of the track.
                guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1) else { return }
                silence.frameLength = 1
                buffer = silence
                last = true
            case .failed:
                // Still failing after the retries: the track does not end here.
                queueFailure(segment, generation: generation, format: format)
                return
            }
            let frames = Int64(buffer.frameLength)

            lock.lock()
            guard self.generation == generation else { lock.unlock(); return }
            queuedFrames += frames
            scheduledFrames += frames
            node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [self] _ in
                played(frames, generation: generation, ended: last ? segment : nil)
            }
            let startNow = playPending
            playPending = false
            lock.unlock()
            if startNow { node.play() }
            if last { return }
        }
    }

    /// Queues a marker behind the sound already read. When the marker plays,
    /// the sound before the bad read has been heard, and the app is told where
    /// the bad read starts. The marker is one silent frame, and it only exists
    /// when a read failed.
    private func queueFailure(_ segment: Segment, generation: Int, format: AVAudioFormat) {
        guard let marker = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1) else { return }
        marker.frameLength = 1
        // The reader keeps its place at the start of the bad read.
        let position = segment.reader?.position ?? segment.startFrame
        let time = Double(position) / format.sampleRate
        lock.lock()
        guard self.generation == generation else { lock.unlock(); return }
        node.scheduleBuffer(marker, completionCallbackType: .dataPlayedBack) { [self] _ in
            onReadError?(segment, generation, time)
        }
        let startNow = playPending
        playPending = false
        lock.unlock()
        if startNow { node.play() }
    }

    /// One read from the disc, tried again when it fails (see DiscRead). It
    /// reads from where the last read stopped, so a retry loses nothing.
    private func readChunk(_ segment: Segment, frames: AVAudioFrameCount) -> ReadAttempt<AVAudioPCMBuffer> {
        DiscRead.chunk(attempts: Self.readAttempts, pause: { Thread.sleep(forTimeInterval: Self.retryPause) }) {
            if segment.reader == nil {
                segment.reader = try? open(segment.url)
                segment.reader?.seek(toFrame: segment.startFrame)
            }
            guard let reader = segment.reader else { return .failed }
            if let buffer = try? reader.read(frames: frames) { return .sound(buffer) }
            return reader.atEnd ? .end : .failed
        }
    }

    private func played(_ frames: Int64, generation: Int, ended segment: Segment?) {
        lock.lock()
        let current = self.generation == generation
        if current { queuedFrames -= frames }
        lock.unlock()
        room.signal()
        if current, let segment { onSegmentEnd?(segment, generation) }
    }

}

/// Keeps the last moment of sound that played, for the spectrum bars and
/// the VU meters, and watches the peaks for the clip lights.
nonisolated final class SoundListener: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var rms: [Float] = []
    private let keep = 2048
    /// What balance and volume do to each channel after this point.
    private var outputGains: [Float] = [1, 1]
    private var peaks: [Float] = [0, 0]
    private var overs: [Int] = [0, 0]
    /// Whether each channel's last block ended above full scale: a run that
    /// goes on into the next block is still one over.
    private var overRun: [Bool] = [false, false]

    func attach(to node: AVAudioNode, format: AVAudioFormat) {
        node.installTap(onBus: 0, bufferSize: 2048, format: format) { [self] buffer, _ in
            store(buffer)
        }
    }

    func detach(from node: AVAudioNode) {
        node.removeTap(onBus: 0)
    }

    func latest() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func loudness() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return rms
    }

    func setOutputGains(_ gains: [Float]) {
        lock.lock()
        outputGains = gains
        lock.unlock()
    }

    /// The loudest sample per channel since the last call, and the over counts.
    func takePeaks() -> (peaks: [Float], overs: [Int]) {
        lock.lock()
        defer { lock.unlock() }
        let result = (peaks, overs)
        peaks = [0, 0]
        return result
    }

    func resetOvers() {
        lock.lock()
        overs = [0, 0]
        // A new song starts its count clean, even if the last one ended over.
        overRun = [false, false]
        lock.unlock()
    }

    private func store(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let start = max(0, frames - keep)
        var mono = [Float](repeating: 0, count: frames - start)
        for frame in start..<frames {
            var sum: Float = 0
            for channel in 0..<channelCount { sum += channels[channel][frame] }
            mono[frame - start] = sum / Float(channelCount)
        }
        let loudness = (0..<channelCount).map { channel in
            var sum: Float = 0
            for frame in start..<frames { sum += channels[channel][frame] * channels[channel][frame] }
            return (sum / Float(max(1, frames - start))).squareRoot()
        }
        // Every sample counts for the clip lights, not just the last moment.
        var loudest = [Float](repeating: 0, count: channelCount)
        for channel in 0..<channelCount {
            var peak: Float = 0
            vDSP_maxmgv(channels[channel], 1, &peak, vDSP_Length(frames))
            loudest[channel] = peak
        }
        lock.lock()
        samples = mono
        rms = loudness
        for channel in 0..<min(2, channelCount) {
            let peak = loudest[channel] * outputGains[channel]
            peaks[channel] = max(peaks[channel], peak)
            // An over is a run of samples at full scale, counted once (PeakMeter.overs).
            let block = UnsafeBufferPointer(start: UnsafePointer(channels[channel]), count: frames)
            let counted = PeakMeter.overs(in: block, gain: outputGains[channel], inRun: overRun[channel])
            overs[channel] += counted.runs
            overRun[channel] = counted.endsInRun
        }
        lock.unlock()
    }
}
