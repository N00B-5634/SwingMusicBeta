import Foundation
import AVFoundation
import MediaPlayer
import Combine

// MARK: - Lyrics state  (mirrors LyricsState.kt sealed class)
enum LyricsState {
    case idle, loading, notFound
    case success(synced: [LyricLine]?, plain: String?)
    case error(String)
}

// MARK: - Player State  (mirrors MediaControllerViewModel + PlayerUiState)
@MainActor
final class PlayerState: ObservableObject {

    // Published state  (mirrors PlayerUiState.kt fields)
    @Published var nowPlayingTrack: Track?
    @Published var queue: [Track] = []
    @Published var playingIndex: Int = 0
    @Published var playbackState: PlaybackState = .paused
    @Published var seekPosition: Float = 0
    @Published var currentTimeStr = "00:00"
    @Published var durationStr    = "00:00"
    @Published var isBuffering    = false
    @Published var repeatMode: RepeatMode = .all
    @Published var shuffleMode: ShuffleMode = .off
    @Published var showLyrics    = false
    @Published var lyricsState: LyricsState = .idle
    @Published var queueSource: QueueSource = .unknown

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObserver: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var currentDuration: Double = 0
    private var shuffledOrder: [Int] = []

    init() { setupAudioSession(); setupRemoteControls() }

    // MARK: Public API  (mirrors PlayerUiEvent.kt + QueueEvent.kt)

    func recreateQueue(tracks: [Track], startIndex: Int, source: QueueSource, isPartial: Bool = false) {
        queue = tracks
        queueSource = source
        playingIndex = startIndex
        if shuffleMode == .on { buildShuffle(startAt: startIndex) }
        load(at: startIndex)
    }

    func togglePlayPause() {
        guard player != nil else { return }
        if playbackState == .playing { pause() } else { resume() }
    }

    func next() { let i = nextIdx(); playingIndex = i; load(at: i) }

    func previous() {
        guard let p = player else { return }
        if p.currentTime().seconds > 3 { seek(to: 0); return }
        let i = prevIdx(); playingIndex = i; load(at: i)
    }

    func seek(to fraction: Float) {
        guard currentDuration > 0 else { return }
        let t = CMTime(seconds: Double(fraction) * currentDuration, preferredTimescale: 600)
        player?.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        seekPosition = fraction
    }

    func seekToQueueItem(index: Int) { playingIndex = index; load(at: index) }
    func toggleRepeat()  { repeatMode  = repeatMode.next }
    func toggleShuffle() {
        shuffleMode = shuffleMode == .on ? .off : .on
        if shuffleMode == .on { buildShuffle(startAt: playingIndex) }
    }

    func playNext(track: Track)   { queue.insert(track, at: min(playingIndex + 1, queue.count)) }
    func addToQueue(track: Track) { queue.append(track) }

    func toggleFavorite(trackHash: String, isFavorite: Bool) {
        // Optimistic update
        if let i = queue.firstIndex(where: { $0.trackHash == trackHash }) {
            queue[i].isFavorite = !isFavorite
        }
        if nowPlayingTrack?.trackHash == trackHash {
            nowPlayingTrack?.isFavorite = !isFavorite
        }
        Task {
            do {
                if isFavorite {
                    try await SwingAPIClient.shared.removeFavorite(hash: trackHash, type: "track")
                } else {
                    try await SwingAPIClient.shared.addFavorite(hash: trackHash, type: "track")
                }
            } catch {
                // Revert on failure
                if let i = self.queue.firstIndex(where: { $0.trackHash == trackHash }) {
                    self.queue[i].isFavorite = isFavorite
                }
                if self.nowPlayingTrack?.trackHash == trackHash {
                    self.nowPlayingTrack?.isFavorite = isFavorite
                }
            }
        }
    }

    func resumeFromError() { load(at: playingIndex) }

    func fetchLyrics(for track: Track) {
        lyricsState = .loading
        Task {
            do {
                let (synced, plain) = try await LyricsClient.shared.getLyrics(
                    title: track.title,
                    artist: track.trackArtists.first?.name ?? "",
                    album: track.album,
                    duration: track.duration
                )
                if synced == nil && plain == nil {
                    lyricsState = .notFound
                } else {
                    lyricsState = .success(synced: synced, plain: plain)
                }
            } catch {
                lyricsState = .error(error.localizedDescription)
            }
        }
    }

    // MARK: Private

    private func load(at index: Int) {
        guard !queue.isEmpty, index < queue.count else { return }
        let track = queue[index]
        nowPlayingTrack = track
        isBuffering = true
        playbackState = .buffering
        teardown()

        guard let url = SwingAPIClient.shared.streamURLSync(trackHash: track.trackHash, filepath: track.filepath) else {
            playbackState = .error; isBuffering = false; return
        }

        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        playerItem = item
        player = AVPlayer(playerItem: item)
        player?.automaticallyWaitsToMinimizeStalling = true

        observeStatus()
        observeTime()
        observeEnd()
        player?.play()
        updateNowPlaying(track)

        if showLyrics { fetchLyrics(for: track) } else { lyricsState = .idle }
        Task { try? await SwingAPIClient.shared.logTrack(
            trackHash: track.trackHash, duration: 30, source: queueSource.displayName) }
    }

    private func resume() { player?.play(); playbackState = .playing; updateRate(1) }
    private func pause()  { player?.pause(); playbackState = .paused;  updateRate(0) }

    private func teardown() {
        if let o = timeObserver { player?.removeTimeObserver(o); timeObserver = nil }
        if let o = endObserver  { NotificationCenter.default.removeObserver(o); endObserver = nil }
        statusObserver?.cancel(); statusObserver = nil
        player?.pause(); player = nil; playerItem = nil
        seekPosition = 0; currentTimeStr = "00:00"; durationStr = "00:00"; currentDuration = 0
    }

    private func observeStatus() {
        statusObserver = playerItem?.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.isBuffering = false
                    self.playbackState = .playing
                    self.currentDuration = self.playerItem?.duration.seconds ?? 0
                    self.durationStr = self.fmt(self.currentDuration)
                case .failed:
                    self.isBuffering = false
                    self.playbackState = .error
                default: break
                }
            }
    }

    private func observeTime() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self else { return }
            Task { @MainActor in
                guard self.currentDuration > 0 else { return }
                self.seekPosition = Float(t.seconds / self.currentDuration)
                self.currentTimeStr = self.fmt(t.seconds)
            }
        }
    }

    private func observeEnd() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.handleEnd() }
        }
    }

    private func handleEnd() {
        switch repeatMode {
        case .one:  seek(to: 0); resume()
        case .all:  next()
        case .none: if playingIndex < queue.count - 1 { next() } else { pause(); seek(to: 0) }
        }
    }

    private func nextIdx() -> Int {
        if shuffleMode == .on { return nextShuffle() }
        switch repeatMode {
        case .one:  return playingIndex
        case .all:  return (playingIndex + 1) % queue.count
        case .none: return min(playingIndex + 1, queue.count - 1)
        }
    }

    private func prevIdx() -> Int {
        if shuffleMode == .on { return prevShuffle() }
        return max(playingIndex - 1, 0)
    }

    private func buildShuffle(startAt idx: Int) {
        let all = Array(0..<queue.count).filter { $0 != idx }
        shuffledOrder = [idx] + all.shuffled()
    }
    private func nextShuffle() -> Int {
        guard let pos = shuffledOrder.firstIndex(of: playingIndex) else { return 0 }
        return shuffledOrder[(pos + 1) % shuffledOrder.count]
    }
    private func prevShuffle() -> Int {
        guard let pos = shuffledOrder.firstIndex(of: playingIndex) else { return 0 }
        return shuffledOrder[(pos - 1 + shuffledOrder.count) % shuffledOrder.count]
    }

    private func fmt(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "00:00" }
        let h = Int(s)/3600; let m = (Int(s)%3600)/60; let sec = Int(s)%60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    // MARK: Audio session
    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: Lock screen / Control Center  (mirrors MediaSession + MPRemoteCommandCenter)
    private func updateNowPlaying(_ track: Track) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:             track.title,
            MPMediaItemPropertyArtist:            track.artistNames,
            MPMediaItemPropertyAlbumTitle:        track.album,
            MPMediaItemPropertyPlaybackDuration:  currentDuration,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
        Task {
            if let base = await SwingAPIClient.shared.currentConfig()?.baseURL {
                let imgURL = base.appendingPathComponent("img/thumbnail/medium/\(track.image)")
                if let data = try? Data(contentsOf: imgURL), let img = UIImage(data: data) {
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                    await MainActor.run { MPNowPlayingInfoCenter.default().nowPlayingInfo = info }
                    return
                }
            }
            await MainActor.run { MPNowPlayingInfoCenter.default().nowPlayingInfo = info }
        }
    }

    private func updateRate(_ rate: Float) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime().seconds ?? 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteControls() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget  { [weak self] _ in self?.resume();    return .success }
        cc.pauseCommand.addTarget { [weak self] _ in self?.pause();     return .success }
        cc.nextTrackCommand.addTarget     { [weak self] _ in self?.next();     return .success }
        cc.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent,
                  let d = self?.currentDuration, d > 0 else { return .commandFailed }
            self?.seek(to: Float(e.positionTime / d))
            return .success
        }
    }
}
