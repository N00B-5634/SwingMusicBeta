import SwiftUI

// MARK: - Shared image helper
// Replaces Coil AsyncImage + image path logic used in every component
struct SwingAsyncImage: View {
    let url: URL?
    let size: CGFloat
    var isCircle: Bool = false

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().aspectRatio(contentMode: .fill)
            default:
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary.opacity(0.3))
                            .font(.system(size: size * 0.3))
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(isCircle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.15)))
    }
}

// MARK: - TrackRow  (TrackItem.kt)
struct TrackRow: View {
    let track: Track
    let baseURL: URL?
    var isPlaying: Bool = false
    var playbackState: PlaybackState = .paused
    var onTap: () -> Void = {}
    var onMoreTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            // Album art / playing indicator overlay
            ZStack {
                SwingAsyncImage(
                    url: baseURL?.appendingPathComponent("img/thumbnail/small/\(track.image)"),
                    size: 48
                )
                if isPlaying {
                    Rectangle()
                        .fill(playbackState == .error
                              ? Color.red.opacity(0.75)
                              : Color(.systemBackground).opacity(0.75))
                        .frame(width: 48, height: 48)
                    PlayingIndicator(state: playbackState)
                        .frame(width: 48, height: 48)
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Title + artists
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(SwingType.bodyLarge)
                    .foregroundStyle(isPlaying ? Color.swingPrimary : Color.primary)
                    .lineLimit(1)
                Text(track.artistNames)
                    .font(SwingType.bodySmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 12)

            Spacer()

            // Duration
            Text(track.durationFormatted)
                .font(SwingType.labelSmall)
                .foregroundStyle(.tertiary)
                .padding(.trailing, 4)

            // More vert
            Button(action: onMoreTap) {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.leading, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - AlbumCard  (AlbumItem.kt)
struct AlbumCard: View {
    let album: Album
    let baseURL: URL?
    var screen: SwingScreen = .allAlbums
    var albumArtistHash: String = ""
    var showDate: Bool = true
    var onTap: (String) -> Void = { _ in }

    @Environment(\.colorScheme) var colorScheme

    var otherArtists: String? {
        album.albumArtists
            .filter { $0.artistHash != albumArtistHash }
            .map(\.name)
            .joined(separator: ", ")
            .nonEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Art
            SwingAsyncImage(
                url: baseURL?.appendingPathComponent("img/thumbnail/medium/\(album.image)"),
                size: .infinity
            )
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // HelpText (e.g. "2020") — only on non-ARTIST screens
            if !album.helpText.isEmpty && screen != .artist {
                Text(album.helpText)
                    .font(SwingType.bodySmall)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 10)
            }

            // Title
            Text(album.title)
                .font(SwingType.bodyLarge)
                .fontWeight(.bold)
                .lineLimit(1)
                .padding(.top, 6)

            // Subtitle
            if screen != .artist {
                if let first = album.albumArtists.first {
                    Text(first.name)
                        .font(SwingType.bodySmall)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 3)
                }
            } else {
                HStack(spacing: 0) {
                    if showDate {
                        Text(album.yearString)
                            .font(SwingType.bodySmall)
                            .foregroundStyle(.secondary.opacity(0.75))
                    }
                    if let other = otherArtists {
                        if showDate {
                            Circle()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 4, height: 4)
                                .padding(.horizontal, 8)
                        }
                        Text(other)
                            .font(SwingType.bodySmall)
                            .foregroundStyle(.secondary.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .padding(.top, 6)
            }

            // Version badges  (mirrors LazyRow of version chips)
            if !album.versions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(album.versions, id: \.self) { version in
                            Text(version.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.versionText(darkMode: colorScheme == .dark))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 4)
                                .background(Color.versionBg(darkMode: colorScheme == .dark))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { onTap(album.albumHash) }
    }
}

// MARK: - ArtistCell  (ArtistItem.kt)
struct ArtistCell: View {
    let artist: Artist
    let baseURL: URL?
    var size: CGFloat = 120
    var onTap: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            SwingAsyncImage(
                url: baseURL?.appendingPathComponent("img/artist/medium/\(artist.image)"),
                size: size,
                isCircle: true
            )
            .onTapGesture { onTap(artist.artistHash) }

            Spacer().frame(height: 8)

            Text(artist.name)
                .font(SwingType.bodyLarge)
                .fontWeight(.bold)
                .lineLimit(1)

            if !artist.helpText.isEmpty {
                Text(artist.displayHelpText)
                    .font(SwingType.bodySmall)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 3)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .padding(.horizontal, 8)
    }
}

// MARK: - FolderRow  (FolderItem.kt)
struct FolderRow: View {
    let folder: Folder
    var onTap: (Folder) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            // Folder icon box
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: "folder.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(folder.name)
                    .font(SwingType.bodyLarge)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    if folder.folderCount > 0 {
                        Text(folder.folderCountText)
                            .font(SwingType.bodySmall)
                            .foregroundStyle(.secondary.opacity(0.84))
                    }
                    if folder.folderCount > 0 && folder.trackCount > 0 {
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 3, height: 3)
                            .padding(.horizontal, 8)
                    }
                    if folder.trackCount > 0 {
                        Text(folder.trackCountText)
                            .font(SwingType.bodySmall)
                            .foregroundStyle(.secondary.opacity(0.84))
                    } else if folder.folderCount == 0 {
                        Text("This folder is empty")
                            .font(SwingType.bodySmall)
                            .foregroundStyle(.secondary.opacity(0.84))
                    }
                }
            }

            Spacer()

            // Reserved 48pt space — mirrors Android's reserved MoreVert space
            Color.clear.frame(width: 48, height: 48)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onTap(folder) }
    }
}

// MARK: - PathIndicatorItem  (PathIndicatorItem.kt)
struct PathIndicatorItem: View {
    let folder: Folder
    var isRootPath: Bool = false
    var isCurrentPath: Bool
    var onTap: (Folder) -> Void = { _ in }

    var body: some View {
        Button { onTap(folder) } label: {
            HStack(spacing: 4) {
                if isRootPath {
                    Image(systemName: "folder")
                        .font(.system(size: 16))
                        .foregroundStyle(isCurrentPath ? Color.primary : Color.secondary.opacity(0.3))
                }
                Text(folder.name.uppercased())
                    .font(SwingType.titleMedium)
                    .foregroundStyle(isCurrentPath ? Color.primary : Color.secondary.opacity(0.3))
                    .padding(.vertical, 2)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SoundSignalBars  (SoundSignalBars.kt)
struct SoundSignalBars: View {
    var animate: Bool
    @State private var heights: [CGFloat] = [0.15, 0.45, 0.75]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                SignalBar(height: heights[i], animate: animate)
            }
        }
        .padding(.horizontal, 2)
        .onAppear { if animate { startAnimation() } }
        .onChange(of: animate) { on in if on { startAnimation() } }
    }

    private func startAnimation() {
        guard animate else { return }
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { t in
            if !animate { t.invalidate(); return }
            withAnimation(.easeInOut(duration: 0.5)) {
                heights = (0..<3).map { _ in CGFloat.random(in: 0.1...1.0) }
            }
        }
    }
}

private struct SignalBar: View {
    let height: CGFloat
    let animate: Bool

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.primary)
                .frame(width: 6, height: geo.size.height * height)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: 6, height: 28)
        .animation(animate ? .easeInOut(duration: 0.5) : .none, value: height)
    }
}

// MARK: - PlayingIndicator  (PlayingTrackIndicator.kt)
struct PlayingIndicator: View {
    let state: PlaybackState

    var body: some View {
        Group {
            switch state {
            case .playing:
                SoundSignalBars(animate: true)
            case .paused:
                SoundSignalBars(animate: false)
            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.red)
            case .buffering:
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }
}

// MARK: - SortByChip  (SortByChip.kt)
struct SortByChip: View {
    let sortBy: SortBy
    var isSelected: Bool = false
    var sortOrder: SortOrder = .descending
    var onTap: (SortBy) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 4) {
            Text(sortBy.displayLabel)
                .font(SwingType.bodyMedium)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            if isSelected {
                Image(systemName: sortOrder == .ascending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isSelected ? Color.secondary.opacity(0.15) : Color.clear)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    isSelected ? Color.clear : Color.secondary.opacity(0.4),
                    lineWidth: 0.4
                )
        )
        .onTapGesture { onTap(sortBy) }
    }
}

// MARK: - TopSearchResultCard  (TopSearchResultItem.kt)
struct TopSearchResultCard: View {
    let item: TopResultItem
    let baseURL: URL?
    var isLoadingTracks: Bool = false
    var onTap: (String, String) -> Void = { _, _ in }
    var onPlayTap: (String, String) -> Void = { _, _ in }

    private var imagePath: String {
        item.type == "artist"
            ? "img/artist/\(item.image)"
            : "img/thumbnail/\(item.image)"
    }
    private var bgImagePath: String {
        item.type == "artist"
            ? "img/artist/small/\(item.image)"
            : "img/thumbnail/small/\(item.image)"
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Background blur image
            AsyncImage(url: baseURL?.appendingPathComponent(bgImagePath)) { phase in
                if case .success(let img) = phase {
                    img.resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 18)
                        .saturation(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            .clipped()

            // Gradient overlay (mirrors Brush.horizontalGradient)
            LinearGradient(
                colors: [.clear, Color(.systemBackground).opacity(0.9), Color(.systemBackground)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 170)

            HStack(spacing: 0) {
                // Main image
                AsyncImage(url: baseURL?.appendingPathComponent(imagePath)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(Color.secondary.opacity(0.2))
                    }
                }
                .frame(width: 154, height: 154)
                .clipShape(item.type == "artist" ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
                .padding(8)
                .onTapGesture { onTap(item.type, item.hash) }

                // Right panel
                VStack(alignment: .trailing, spacing: 4) {
                    // Play button
                    Button { onPlayTap(item.type, item.hash) } label: {
                        ZStack {
                            Circle()
                                .fill(Color.swingPrimary)
                                .frame(width: 44, height: 44)
                            if isLoadingTracks {
                                ProgressView().tint(.white).scaleEffect(0.75)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.trailing, 12)

                    Spacer()

                    VStack(alignment: .leading, spacing: 4) {
                        // Type badge
                        Text(item.displayType)
                            .font(SwingType.labelSmall)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.15))
                            .clipShape(Capsule())

                        // Title
                        Text(item.displayTitle.isEmpty ? "Unknown" : item.displayTitle)
                            .font(SwingType.titleLarge)
                            .lineLimit(2)

                        // Artists
                        if item.type == "album" || item.type == "track" {
                            let artistStr = item.type == "album"
                                ? item.albumArtists.map(\.name).joined(separator: ", ")
                                : item.artists.map(\.name).joined(separator: ", ")
                            Text(artistStr)
                                .font(SwingType.labelSmall)
                                .foregroundStyle(.secondary.opacity(0.84))
                                .lineLimit(1)
                        }
                    }
                    .padding(.bottom, 24)
                    .padding(.leading, 4)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .contentShape(Rectangle())
        .onTapGesture { onTap(item.type, item.hash) }
    }
}

// MARK: - TrackBottomSheet  (CustomTrackBottomSheet.kt)
struct TrackBottomSheet: View {
    let track: Track
    let baseURL: URL?
    var isFavorite: Bool = false
    var currentArtistHash: String? = nil
    var onDismiss: () -> Void = {}
    var onToggleFavorite: (String, Bool) -> Void = { _, _ in }
    var onPlayNext: (Track) -> Void = { _ in }
    var onAddToQueue: (Track) -> Void = { _ in }
    var onGoToAlbum: (String) -> Void = { _ in }
    var onGoToArtist: (String) -> Void = { _ in }

    @State private var showArtistPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Track header
            HStack(spacing: 0) {
                HStack(spacing: 12) {
                    SwingAsyncImage(
                        url: baseURL?.appendingPathComponent("img/thumbnail/small/\(track.image)"),
                        size: 48
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).font(SwingType.bodyLarge).lineLimit(1)
                        Text(track.artistNames).font(SwingType.bodySmall).foregroundStyle(.secondary).lineLimit(1)
                        Text(track.durationFormatted + " · " + (track.bitrate > 0 ? "\(track.bitrate) kbps" : ""))
                            .font(SwingType.labelSmall).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Button { onToggleFavorite(track.trackHash, isFavorite) } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 20))
                        .foregroundStyle(isFavorite ? .red : .secondary)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Action rows
            SheetActionRow(icon: "text.line.first.and.arrowtriangle.forward", label: "Play next") {
                onPlayNext(track); onDismiss()
            }
            SheetActionRow(icon: "list.bullet", label: "Add to queue") {
                onAddToQueue(track); onDismiss()
            }
            SheetActionRow(icon: "square.stack.fill", label: "Go to album") {
                onGoToAlbum(track.albumHash); onDismiss()
            }
            SheetActionRow(icon: "person.fill", label: "Go to artist") {
                if track.trackArtists.count == 1 {
                    onGoToArtist(track.trackArtists[0].artistHash); onDismiss()
                } else {
                    showArtistPicker = true
                }
            }

            Spacer().frame(height: 48)
        }
        .sheet(isPresented: $showArtistPicker) {
            ArtistPickerSheet(
                artists: track.trackArtists,
                currentArtistHash: currentArtistHash,
                baseURL: baseURL,
                onPick: { hash in onGoToArtist(hash); onDismiss() }
            )
            .presentationDetents([.medium])
        }
    }
}

private struct SheetActionRow: View {
    let icon: String; let label: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 18)).frame(width: 24)
                Text(label).font(SwingType.bodyLarge)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ArtistPickerSheet: View {
    let artists: [TrackArtist]
    let currentArtistHash: String?
    let baseURL: URL?
    var onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose artist")
                .font(SwingType.titleLarge)
                .fontWeight(.bold)
                .padding(20)

            ForEach(artists, id: \.artistHash) { artist in
                let isCurrentArtist = artist.artistHash == currentArtistHash
                HStack(spacing: 12) {
                    AsyncImage(url: baseURL?.appendingPathComponent("img/artist/small/\(artist.artistHash).webp")) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else { Circle().fill(Color.secondary.opacity(0.2)) }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .saturation(isCurrentArtist ? 0 : 1)

                    Text(artist.name)
                        .font(SwingType.bodyLarge)
                        .foregroundStyle(isCurrentArtist ? Color.secondary.opacity(0.2) : Color.primary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture { if !isCurrentArtist { onPick(artist.artistHash) } }
            }
        }
    }
}

// MARK: - String helper
private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
