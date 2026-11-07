import MediaPlayer

/// The Mac's media keys and the "Now Playing" entry in Control Center.
final class NowPlaying {
    private weak var model: AppModel?

    func attach(to model: AppModel) {
        self.model = model
        guard !Store.isOverridden else { return }
        let center = MPRemoteCommandCenter.shared()
        // The keys work the unit that played last (AppModel.activeSource).
        center.playCommand.addTarget { [weak self] _ in
            self?.run { $0.activeSource == .files ? $0.filePlayer.play() : $0.play() } ?? .commandFailed
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.run { $0.activeSource == .files ? $0.filePlayer.pause() : $0.pause() } ?? .commandFailed
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.run { $0.activeSource == .files ? $0.filePlayer.playPause() : $0.playPause() } ?? .commandFailed
        }
        center.stopCommand.addTarget { [weak self] _ in
            self?.run { $0.activeSource == .files ? $0.filePlayer.stop() : $0.stop() } ?? .commandFailed
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.run { $0.activeSource == .files ? $0.filePlayer.next() : $0.next() } ?? .commandFailed
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.run { $0.activeSource == .files ? $0.filePlayer.previous() : $0.previous() } ?? .commandFailed
        }
    }

    private nonisolated func run(_ action: @escaping @MainActor (AppModel) -> Void) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor [weak self] in
            if let model = self?.model { action(model) }
        }
        return .success
    }

    func update(title: String?, artist: String, album: String?, duration: TimeInterval,
                elapsed: TimeInterval, state: PlaybackState) {
        guard !Store.isOverridden else { return }
        let center = MPNowPlayingInfoCenter.default()
        guard let title else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
        ]
        center.playbackState = switch state {
        case .playing: .playing
        case .paused: .paused
        case .stopped: .stopped
        }
    }
}
