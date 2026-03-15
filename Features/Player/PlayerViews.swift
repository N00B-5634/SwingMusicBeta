import SwiftUI

// MARK: - Mini Player  (MiniPlayer.kt)
struct MiniPlayerView: View {
    @EnvironmentObject var player: PlayerState
    @EnvironmentObject var auth: AuthState
    let onTap: () -> Void
    @State private var swipeOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Art with playing indicator overlay
                ZStack {
                    SwingAsyncImage(
                        url: SwingAPIClient.shared.imageURL(path: "img/thumbnail/small/\(player.nowPlayingTrack?.image ?? "")"),
                        size: 48
                    )
                    if player.playbackState != .paused {
                        Rectangle()
                            .fill(player.playbackState == .error
                                  ? Color.red.opacity(0.75)
                                  : Color(.systemBackground).opacity(0.75))
                            .frame(width: 48, height: 48)
                        PlayingIndicator(state: player.playbackState)
                            .frame(width: 28, height: 28)
                    }
                }
                .offset(x: swipeOffset / 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.nowPlayingTrack?.title ?? "")
                        .font(SwingType.titleSmall)
                        .lineLimit(1)
                        .opacity(swipeOffset != 0 ? 0.25 : 0.84)
                    Text(player.nowPlayingTrack?.artistNames ?? "")
                        .font(SwingType.bodySmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    if player.playbackState == .error { player.resumeFromError() }
                    else { player.togglePlayPause() }
                } label: {
                    if player.isBuffering {
                        ProgressView().frame(width: 40, height: 40)
                    } else {
                        Image(systemName: miniPlayIcon)
                            .font(.system(size: 22))
                            .frame(width: 40, height: 40)
                    }
                }
                .padding(.trailing, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { v in swipeOffset = v.translation.width }
                    .onEnded { v in
                        withAnimation(.spring(duration: 0.3)) { swipeOffset = 0 }
                        if v.translation.width > 50 { player.previous() }
                        else if v.translation.width < -50 { player.next() }
                    }
            )

            // Progress bar  (LinearProgressIndicator equivalent)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 3)
                    Rectangle()
                        .fill(Color.swingPrimary)
                        .frame(width: geo.size.width * CGFloat(player.seekPosition), height: 3)
                        .animation(.linear(duration: 0.5), value: player.seekPosition)
                }
            }
            .frame(height: 3)
        }
    }

    private var miniPlayIcon: String {
        switch player.playbackState {
        case .playing:  return "pause.fill"
        case .error:    return "arrow.clockwise"
        default:        return "play.fill"
        }
    }
}

// MARK: - Now Playing  (NowPlaying.kt)
struct NowPlayingView: View {
    @EnvironmentObject var player: PlayerState
    @Environment(\.dismiss) var dismiss
    @State private var showQueue = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Art
                    SwingAsyncImage(
                        url: SwingAPIClient.shared.imageURL(
                            path: "img/thumbnail/\(player.nowPlayingTrack?.image ?? "")"),
                        size: 280
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 20)
                    .padding(.horizontal, 40)

                    Spacer().frame(height: 24)

                    // Track info + favorite
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(player.nowPlayingTrack?.title ?? "")
                                .font(SwingType.titleLarge)
                                .lineLimit(2)
                            Text(player.nowPlayingTrack?.artistNames ?? "")
                                .font(SwingType.bodyMedium)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            if let t = player.nowPlayingTrack {
                                player.toggleFavorite(trackHash: t.trackHash, isFavorite: t.isFavorite)
                            }
                        } label: {
                            Image(systemName: player.nowPlayingTrack?.isFavorite == true ? "heart.fill" : "heart")
                                .font(.system(size: 22))
                                .foregroundStyle(player.nowPlayingTrack?.isFavorite == true ? .red : .secondary)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.horizontal, 32)

                    Spacer().frame(height: 20)

                    // Seek
                    VStack(spacing: 4) {
                        Slider(value: Binding(
                            get: { Double(player.seekPosition) },
                            set: { player.seek(to: Float($0)) }
                        ))
                        .tint(.swingPrimary)
                        .padding(.horizontal, 32)
                        HStack {
                            Text(player.currentTimeStr)
                            Spacer()
                            Text(player.durationStr)
                        }
                        .font(SwingType.labelSmall)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 34)
                    }

                    Spacer().frame(height: 20)

                    // Controls
                    HStack(spacing: 36) {
                        Button { player.toggleShuffle() } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 20))
                                .foregroundStyle(player.shuffleMode == .on ? Color.swingPrimary : Color.secondary)
                        }
                        Button { player.previous() } label: {
                            Image(systemName: "backward.fill").font(.system(size: 28))
                        }
                        Button {
                            if player.playbackState == .error { player.resumeFromError() }
                            else { player.togglePlayPause() }
                        } label: {
                            ZStack {
                                Circle().fill(Color.swingPrimary).frame(width: 68, height: 68)
                                if player.isBuffering {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: bigPlayIcon)
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        Button { player.next() } label: {
                            Image(systemName: "forward.fill").font(.system(size: 28))
                        }
                        Button { player.toggleRepeat() } label: {
                            Image(systemName: player.repeatMode.systemImage)
                                .font(.system(size: 20))
                                .foregroundStyle(player.repeatMode.isActive ? Color.swingPrimary : Color.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 32)

                    Spacer().frame(height: 20)

                    // Bottom bar — lyrics + source + queue
                    HStack {
                        Button {
                            player.showLyrics.toggle()
                            if player.showLyrics, let t = player.nowPlayingTrack {
                                player.fetchLyrics(for: t)
                            }
                        } label: {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 18))
                                .foregroundStyle(player.showLyrics ? Color.swingPrimary : Color.secondary)
                        }
                        Spacer()
                        Text(player.queueSource.displayName)
                            .font(SwingType.labelSmall).foregroundStyle(.secondary)
                        Spacer()
                        Button { showQueue = true } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 18)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 36)

                    // Lyrics
                    if player.showLyrics {
                        LyricsPanel()
                            .padding(.horizontal, 32)
                            .padding(.top, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Spacer().frame(height: 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Now playing").font(SwingType.labelMedium)
                        if !player.queueSource.displayName.isEmpty {
                            Text(player.queueSource.displayName)
                                .font(SwingType.labelSmall).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showQueue) { QueueView() }
        .animation(.spring(duration: 0.3), value: player.showLyrics)
    }

    private var bigPlayIcon: String {
        switch player.playbackState {
        case .playing: return "pause.fill"
        case .error:   return "arrow.clockwise"
        default:       return "play.fill"
        }
    }
}

// MARK: - Lyrics Panel
struct LyricsPanel: View {
    @EnvironmentObject var player: PlayerState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch player.lyricsState {
            case .idle: EmptyView()
            case .loading:
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            case .notFound:
                Text("No lyrics found")
                    .font(SwingType.bodySmall).foregroundStyle(.secondary).padding()
            case .success(let synced, let plain):
                if let lines = synced, !lines.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(lines) { line in
                            Text(line.text)
                                .font(SwingType.bodyMedium)
                                .foregroundStyle(isActiveLine(line) ? Color.primary : Color.secondary)
                                .fontWeight(isActiveLine(line) ? .semibold : .regular)
                        }
                    }
                } else if let plain {
                    Text(plain).font(SwingType.bodySmall).foregroundStyle(.secondary)
                }
            case .error(let msg):
                Text(msg).font(SwingType.bodySmall).foregroundStyle(.red).padding()
            }
        }
    }

    private func isActiveLine(_ line: LyricLine) -> Bool {
        guard player.playbackState == .playing,
              let dur = player.nowPlayingTrack.map({ Double($0.duration) }),
              dur > 0 else { return false }
        let ms = Int64(Double(player.seekPosition) * dur * 1000)
        return line.timeMs <= ms
    }
}

// MARK: - Queue View  (Queue.kt)
struct QueueView: View {
    @EnvironmentObject var player: PlayerState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.element.trackHash) { i, track in
                    HStack(spacing: 12) {
                        SwingAsyncImage(
                            url: SwingAPIClient.shared.imageURL(path: "img/thumbnail/small/\(track.image)"),
                            size: 44
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(SwingType.bodyMedium)
                                .foregroundStyle(i == player.playingIndex ? Color.swingPrimary : Color.primary)
                                .lineLimit(1)
                            Text(track.artistNames)
                                .font(SwingType.bodySmall).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if i == player.playingIndex {
                            PlayingIndicator(state: player.playbackState)
                                .frame(width: 24, height: 24)
                        } else {
                            Text(track.durationFormatted)
                                .font(SwingType.labelSmall).foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { player.seekToQueueItem(index: i); dismiss() }
                }
            }
            .listStyle(.plain)
            .navigationTitle(player.queueSource.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
        }
    }
}
