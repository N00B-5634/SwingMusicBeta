import SwiftUI
import Combine

// MARK: - App Entry Point
@main
struct SwingMusicApp: App {
    @StateObject private var authState   = AuthState()
    @StateObject private var playerState = PlayerState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authState)
                .environmentObject(playerState)
                .swingMusicTheme()
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: AuthState
    var body: some View {
        Group {
            if auth.isAuthenticated { MainTabView() }
            else { ServerPairingView() }
        }
        .animation(.easeInOut(duration: 0.3), value: auth.isAuthenticated)
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject var player: PlayerState
    @State private var tab: Tab = .home
    @State private var showPlayer = false

    enum Tab { case home, folders, albums, artists, search, settings }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                HomeView()
                    .tabItem { Label("Home",     systemImage: "house.fill") }
                    .tag(Tab.home)
                FolderView()
                    .tabItem { Label("Folders",  systemImage: "folder.fill") }
                    .tag(Tab.folders)
                AllAlbumsView()
                    .tabItem { Label("Albums",   systemImage: "square.stack.fill") }
                    .tag(Tab.albums)
                AllArtistsView()
                    .tabItem { Label("Artists",  systemImage: "person.2.fill") }
                    .tag(Tab.artists)
                SearchView()
                    .tabItem { Label("Search",   systemImage: "magnifyingglass") }
                    .tag(Tab.search)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(Tab.settings)
            }
            if player.nowPlayingTrack != nil {
                VStack(spacing: 0) {
                    MiniPlayerView(onTap: { showPlayer = true })
                        .background(.regularMaterial)
                    Spacer().frame(height: 49)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showPlayer) { NowPlayingView() }
        .animation(.spring(duration: 0.3), value: player.nowPlayingTrack != nil)
    }
}

// MARK: - Home
struct HomeView: View {
    var body: some View {
        NavigationStack {
            Text("Recently played — coming soon")
                .foregroundStyle(.secondary)
                .navigationTitle("Home")
        }
    }
}

// MARK: - Folder View
struct FolderView: View {
    @EnvironmentObject var player: PlayerState
    @State private var breadcrumbs: [Folder] = []
    @State private var currentFolders: [Folder] = []
    @State private var currentTracks: [Track]  = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var bottomSheetTrack: Track?
    @State private var loadedPath: String = "__unloaded__"

    private var currentPath: String { breadcrumbs.last?.path ?? "" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !breadcrumbs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            PathIndicatorItem(
                                folder: Folder(name: "Home", path: "", trackCount: 0, folderCount: 0, isSym: false),
                                isRootPath: true,
                                isCurrentPath: breadcrumbs.isEmpty
                            ) { _ in breadcrumbs = [] }
                            ForEach(Array(breadcrumbs.enumerated()), id: \.element.path) { i, f in
                                Text("/").font(SwingType.labelSmall).foregroundStyle(.tertiary)
                                PathIndicatorItem(folder: f, isCurrentPath: i == breadcrumbs.count - 1) { _ in
                                    breadcrumbs = Array(breadcrumbs.prefix(i + 1))
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(height: 44)
                    Divider()
                }

                if isLoading {
                    Spacer(); ProgressView(); Spacer()
                } else if let e = error {
                    Spacer()
                    VStack(spacing: 12) {
                        Text(e).foregroundStyle(.secondary)
                        Button("Retry") { Task { await loadContent() } }
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(currentFolders) { folder in
                            FolderRow(folder: folder) { f in breadcrumbs.append(f) }
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                        }
                        ForEach(Array(currentTracks.enumerated()), id: \.element.trackHash) { i, track in
                            TrackRow(
                                track: track,
                                baseURL: SwingAPIClient.shared.imageURLSync(path: ""),
                                isPlaying: player.nowPlayingTrack?.trackHash == track.trackHash,
                                playbackState: player.playbackState,
                                onTap: {
                                    player.recreateQueue(
                                        tracks: currentTracks, startIndex: i,
                                        source: .folder(name: breadcrumbs.last?.name ?? "Folders",
                                                        path: currentPath))
                                },
                                onMoreTap: { bottomSheetTrack = track }
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Folders")
            .task { await loadContent() }
            // Watch the actual path string so back-navigation to same depth also fires
            .onChange(of: currentPath) { _ in Task { await loadContent() } }
            .sheet(item: $bottomSheetTrack) { track in
                TrackBottomSheet(
                    track: track,
                    baseURL: SwingAPIClient.shared.imageURLSync(path: ""),
                    isFavorite: track.isFavorite,
                    onDismiss: { bottomSheetTrack = nil },
                    onPlayNext:   { player.playNext(track: $0) },
                    onAddToQueue: { player.addToQueue(track: $0) },
                    onGoToAlbum:  { _ in },
                    onGoToArtist: { _ in }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func loadContent() async {
        isLoading = true; error = nil
        let path = currentPath
        do {
            let result = try await SwingAPIClient.shared.getFoldersAndTracks(
                folder: path, start: 0, limit: 500)
            currentFolders = result.folders
            currentTracks  = result.tracks
            loadedPath = path
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }
}

// MARK: - All Albums
struct AllAlbumsView: View {
    @EnvironmentObject var player: PlayerState
    @State private var albums: [Album] = []
    @State private var total = 0
    @State private var isLoading = false
    // iOS 16: use Bool + separate selection instead of navigationDestination(item:)
    @State private var selectedAlbum: Album? = nil
    @State private var showAlbumDetail = false
    @State private var sortBy: SortBy = .title
    @State private var sortOrder: SortOrder = .ascending
    private let pageSize = 40
    let cols = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([SortBy.title, .albumArtists, .date, .playCount], id: \.rawValue) { s in
                            SortByChip(sortBy: s, isSelected: sortBy == s, sortOrder: sortOrder) { tapped in
                                if sortBy == tapped { sortOrder = sortOrder == .ascending ? .descending : .ascending }
                                else { sortBy = tapped; sortOrder = .ascending }
                                albums = []; Task { await load() }
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }

                if isLoading && albums.isEmpty {
                    ProgressView().padding(40)
                } else {
                    LazyVGrid(columns: cols, spacing: 0) {
                        ForEach(albums) { album in
                            AlbumCard(
                                album: album,
                                baseURL: SwingAPIClient.shared.imageURLSync(path: ""),
                                onTap: { _ in selectedAlbum = album; showAlbumDetail = true }
                            )
                            .onAppear {
                                if album.id == albums.last?.id && albums.count < total {
                                    Task { await load() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .navigationTitle("Albums (\(total))")
            .task { if albums.isEmpty { await load() } }
            // iOS 16-compatible: isPresented instead of item
            .navigationDestination(isPresented: $showAlbumDetail) {
                if let album = selectedAlbum { AlbumDetailView(album: album) }
            }
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        do {
            let result = try await SwingAPIClient.shared.getAllAlbums(
                start: albums.count, limit: pageSize, sortBy: sortBy, sortOrder: sortOrder)
            albums.append(contentsOf: result.items)
            total = result.total
        } catch {}
        isLoading = false
    }
}

// MARK: - Album Detail
struct AlbumDetailView: View {
    let album: Album
    @EnvironmentObject var player: PlayerState
    @State private var detail: AlbumWithInfo?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding(40)
            } else if let d = detail {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 16) {
                        SwingAsyncImage(
                            url: SwingAPIClient.shared.imageURLSync(path: "img/thumbnail/medium/\(album.image)"),
                            size: 120
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(d.albumInfo.title).font(SwingType.headlineSmall).lineLimit(2)
                            Text(d.albumInfo.albumArtists.map(\.name).joined(separator: ", "))
                                .font(SwingType.bodyMedium).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text(String(d.albumInfo.date > 0 ?
                                    Calendar.current.component(.year, from: Date(timeIntervalSince1970: TimeInterval(d.albumInfo.date))) : 0))
                                Text("·")
                                Text("\(d.albumInfo.trackCount) tracks")
                                Text("·")
                                Text(d.albumInfo.formattedDuration)
                            }
                            .font(SwingType.bodySmall).foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)

                    Button {
                        player.recreateQueue(tracks: d.tracks, startIndex: 0,
                            source: .album(name: d.albumInfo.title, hash: d.albumInfo.albumHash))
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(SwingType.titleSmall)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.swingPrimary).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal, 16).padding(.bottom, 8)

                    Divider()

                    ForEach(Array(d.tracks.enumerated()), id: \.element.trackHash) { i, track in
                        TrackRow(
                            track: track,
                            baseURL: SwingAPIClient.shared.imageURLSync(path: ""),
                            isPlaying: player.nowPlayingTrack?.trackHash == track.trackHash,
                            playbackState: player.playbackState,
                            onTap: {
                                player.recreateQueue(tracks: d.tracks, startIndex: i,
                                    source: .album(name: d.albumInfo.title, hash: d.albumInfo.albumHash))
                            }
                        )
                        Divider().padding(.leading, 72)
                    }

                    if !d.copyright.isEmpty {
                        Text(d.copyright).font(SwingType.labelSmall).foregroundStyle(.tertiary).padding(16)
                    }
                }
            }
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { detail = try await SwingAPIClient.shared.getAlbumWithInfo(albumHash: album.albumHash) }
            catch {}
            isLoading = false
        }
    }
}

// MARK: - All Artists
struct AllArtistsView: View {
    @State private var artists: [Artist] = []
    @State private var total = 0
    @State private var isLoading = false
    @State private var selectedArtist: Artist? = nil
    @State private var showArtistDetail = false
    private let pageSize = 40
    let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading && artists.isEmpty {
                    ProgressView().padding(40)
                } else {
                    LazyVGrid(columns: cols, spacing: 0) {
                        ForEach(artists) { artist in
                            ArtistCell(
                                artist: artist,
                                baseURL: SwingAPIClient.shared.imageURLSync(path: ""),
                                size: 100,
                                onTap: { _ in selectedArtist = artist; showArtistDetail = true }
                            )
                            .onAppear {
                                if artist.id == artists.last?.id && artists.count < total {
                                    Task { await load() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .navigationTitle("Artists (\(total))")
            .task { if artists.isEmpty { await load() } }
            .navigationDestination(isPresented: $showArtistDetail) {
                if let artist = selectedArtist { ArtistInfoView(artist: artist) }
            }
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        do {
            let result = try await SwingAPIClient.shared.getAllArtists(start: artists.count, limit: pageSize)
            artists.append(contentsOf: result.items)
            total = result.total
        } catch {}
        isLoading = false
    }
}

// MARK: - Artist Info
struct ArtistInfoView: View {
    let artist: Artist
    @EnvironmentObject var player: PlayerState
    @State private var info: ArtistInfo?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding(40)
            } else if let info {
                VStack(alignment: .leading, spacing: 0) {
                    SwingAsyncImage(
                        url: SwingAPIClient.shared.imageURLSync(path: "img/artist/\(artist.image)"),
                        size: 200, isCircle: true
                    )
                    .frame(maxWidth: .infinity).padding(16)

                    Text(info.artist.name).font(SwingType.headlineLarge).padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        Text("\(info.artist.albumCount) albums")
                        Text("·")
                        Text("\(info.artist.trackCount) tracks")
                    }
                    .font(SwingType.bodySmall).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.top, 4)

                    if !info.tracks.isEmpty {
                        SectionHeader(title: "Top tracks")
                        ForEach(Array(info.tracks.prefix(5).enumerated()), id: \.element.trackHash) { i, track in
                            TrackRow(
                                track: track,
                                baseURL: SwingAPIClient.shared.imageURLSync(path: ""),
                                isPlaying: player.nowPlayingTrack?.trackHash == track.trackHash,
                                playbackState: player.playbackState,
                                onTap: {
                                    player.recreateQueue(tracks: info.tracks, startIndex: i,
                                        source: .artist(name: artist.name, hash: artist.artistHash))
                                }
                            )
                        }
                    }

                    let groups: [(String, [Album])] = [
                        ("Albums",        info.albumsAndAppearances.albums),
                        ("Singles & EPs", info.albumsAndAppearances.singlesAndEps),
                        ("Appearances",   info.albumsAndAppearances.appearances),
                        ("Compilations",  info.albumsAndAppearances.compilations)
                    ].filter { !$1.isEmpty }

                    ForEach(groups, id: \.0) { group in
                        SectionHeader(title: group.0)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(group.1) { album in
                                    AlbumCard(
                                        album: album,
                                        baseURL: SwingAPIClient.shared.imageURLSync(path: ""),
                                        screen: .artist,
                                        albumArtistHash: artist.artistHash
                                    )
                                    .frame(width: 160)
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { info = try await SwingAPIClient.shared.getArtistInfo(artistHash: artist.artistHash) }
            catch {}
            isLoading = false
        }
    }
}

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(SwingType.titleMedium)
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 4)
    }
}

// MARK: - Search
struct SearchView: View {
    @EnvironmentObject var player: PlayerState
    @State private var query = ""
    @State private var topResults: TopSearchResults?
    @State private var isLoading = false
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    Text("Search for tracks, albums, or artists")
                        .foregroundStyle(.secondary).font(SwingType.bodyMedium)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let results = topResults {
                    searchResults(results)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Tracks, albums, artists…")
            // iOS 16-compatible single-arg onChange
            .onChange(of: query) { q in
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled, !q.isEmpty else { return }
                    await search(q)
                }
            }
        }
    }

    private func search(_ q: String) async {
        isLoading = true
        do { topResults = try await SwingAPIClient.shared.getTopSearchResults(query: q, limit: 5) }
        catch {}
        isLoading = false
    }

    @ViewBuilder
    private func searchResults(_ r: TopSearchResults) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let top = r.topResultItem {
                    TopSearchResultCard(
                        item: top,
                        baseURL: SwingAPIClient.shared.imageURLSync(path: ""),
                        onPlayTap: { type, hash in
                            if type == "track" {
                                player.recreateQueue(tracks: r.tracks, startIndex: 0, source: .search(query: query))
                            }
                        }
                    )
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }

                if !r.tracks.isEmpty {
                    SectionHeader(title: "Tracks")
                    ForEach(Array(r.tracks.enumerated()), id: \.element.trackHash) { i, track in
                        TrackRow(
                            track: track,
                            baseURL: SwingAPIClient.shared.imageURLSync(path: ""),
                            isPlaying: player.nowPlayingTrack?.trackHash == track.trackHash,
                            playbackState: player.playbackState,
                            onTap: {
                                player.recreateQueue(tracks: r.tracks, startIndex: i,
                                    source: .search(query: query))
                            }
                        )
                    }
                }

                if !r.albums.isEmpty {
                    SectionHeader(title: "Albums")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top) {
                            ForEach(r.albums) { album in
                                AlbumCard(album: album, baseURL: SwingAPIClient.shared.imageURLSync(path: ""))
                                    .frame(width: 140)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }

                if !r.artists.isEmpty {
                    SectionHeader(title: "Artists")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(r.artists) { artist in
                                ArtistCell(artist: artist,
                                    baseURL: SwingAPIClient.shared.imageURLSync(path: ""), size: 80)
                                    .frame(width: 100)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
        }
    }
}

// MARK: - Settings
struct SettingsView: View {
    @EnvironmentObject var auth: AuthState
    @State private var showATSWarning = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if auth.allowsInsecureHTTP {
                        InsecureBanner { showATSWarning = true }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    LabeledContent("Server", value: auth.serverURL).font(SwingType.bodySmall)
                    Button("Re-pair / change server") { Task { await auth.unpair() } }
                    Button("Disconnect", role: .destructive) { Task { await auth.unpair() } }
                } header: { Text("Server") }

                Section {
                    Toggle("Allow insecure HTTP", isOn: Binding(
                        get: { auth.allowsInsecureHTTP },
                        set: { v in if v { showATSWarning = true } else { auth.enableInsecureHTTP(false) } }
                    ))
                    if auth.allowsInsecureHTTP {
                        Text("HTTP active — data travels unencrypted.")
                            .font(SwingType.bodySmall).foregroundStyle(.orange)
                    }
                } header: { Text("Advanced") }

                Section {
                    LabeledContent("Version", value: "1.0.0-beta")
                    LabeledContent("TLS minimum", value: "1.3")
                } header: { Text("About") }
            }
            .navigationTitle("Settings")
        }
        .sheet(isPresented: $showATSWarning) {
            ATSWarningSheet(
                onConfirm: { auth.enableInsecureHTTP(true);  showATSWarning = false },
                onCancel:  { auth.enableInsecureHTTP(false); showATSWarning = false }
            )
        }
    }
}

// MARK: - Server Pairing
// Flow:
//   1. Enter URL → probe BASE_URL/auth/users
//   2a. usersOnLogin=true → show user picker + password
//   2b. enableGuest=true, usersOnLogin=false → auto guest login
//   2c. Single user → pre-fill username, show password only
//   QR → scan → GET BASE_URL/auth/pair?code=XXX
struct ServerPairingView: View {
    @EnvironmentObject var auth: AuthState
    @State private var serverURL  = ""
    @State private var username   = ""
    @State private var password   = ""
    @State private var showPass   = false
    @State private var loginError: String?
    @State private var isLoggingIn = false
    @State private var showATS    = false
    @State private var showQR     = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    logoHeader
                    if let probe = auth.probeResult {
                        probedView(probe: probe)
                    } else {
                        urlEntryView
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showATS) {
            ATSWarningSheet(
                onConfirm: {
                    auth.enableInsecureHTTP(true)
                    showATS = false
                    Task { await auth.probe(rawURL: serverURL) }
                },
                onCancel: {
                    serverURL = serverURL
                        .replacingOccurrences(of: "http://", with: "https://",
                                              options: .caseInsensitive)
                    showATS = false
                }
            )
        }
        .sheet(isPresented: $showQR) {
            QRScanSheet { scanned in
                showQR = false
                Task {
                    isLoggingIn = true; loginError = nil
                    loginError = await auth.loginWithQR(scannedURL: scanned)
                    isLoggingIn = false
                }
            }
        }
    }

    // MARK: Logo
    private var logoHeader: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.swingPrimary.opacity(0.12)).frame(width: 80, height: 80)
                if UIImage(named: "SwingLogo") != nil {
                    Image("SwingLogo").resizable().scaledToFit().frame(width: 52, height: 52)
                } else {
                    Image(systemName: "music.note.house.fill")
                        .font(.system(size: 36)).foregroundStyle(Color.swingPrimary)
                }
            }
            Text("Swing Music").font(SwingType.headlineMedium)
            Text("Connect to your server").font(SwingType.bodyMedium).foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    // MARK: Step 1 — URL entry + QR button
    private var urlEntryView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Server URL").font(SwingType.labelMedium).foregroundStyle(.secondary)
                    Spacer()
                    if serverURL.lowercased().hasPrefix("http://") &&
                       !serverURL.lowercased().hasPrefix("https://") { InsecureBadge() }
                }
                TextField("https://music.example.com", text: $serverURL)
                    .textFieldStyle(.roundedBorder).keyboardType(.URL)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                Text("Cloudflare Tunnel, local IP, or any HTTPS reverse proxy")
                    .font(SwingType.labelSmall).foregroundStyle(.tertiary)
            }

            if let e = auth.probeError {
                Text(e).font(SwingType.labelSmall).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button { Task { await submitURL() } } label: {
                Group {
                    if auth.isProbing {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("Connecting…")
                        }
                    } else {
                        Text("Connect")
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.swingPrimary).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12)).font(SwingType.titleMedium)
            }
            .disabled(auth.isProbing || serverURL.trimmingCharacters(in: .whitespaces).isEmpty)

            HStack {
                Divider()
                Text("or").font(SwingType.labelSmall).foregroundStyle(.tertiary).padding(.horizontal, 8)
                Divider()
            }
            .frame(height: 20)

            Button { showQR = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder").font(.system(size: 22))
                        .foregroundStyle(Color.swingPrimary).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan QR code").font(SwingType.labelMedium)
                        Text("Settings › Pair device in the Swing Music web app")
                            .font(SwingType.labelSmall).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color.secondary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.swingPrimary.opacity(0.3)))
            }
            .buttonStyle(.plain)

            if isLoggingIn { ProgressView("Authenticating…") }
            if let e = loginError {
                Text(e).font(SwingType.labelSmall).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            tips
        }
    }

    // MARK: Step 2 — Probed: show login based on server settings
    @ViewBuilder
    private func probedView(probe: ProbeResult) -> some View {
        VStack(spacing: 16) {
            // Server confirmed banner
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.swingPrimary)
                Text(probe.serverURL).font(SwingType.labelSmall).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Change") {
                    auth.probeResult = nil
                    auth.probeError  = nil
                    loginError = nil
                }
                .font(SwingType.labelSmall).foregroundStyle(Color.swingPrimary)
            }
            .padding(10).background(Color.swingPrimary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if let e = loginError {
                Text(e).font(SwingType.labelSmall).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if !probe.usersOnLogin && probe.guestAllowed {
                // Guest access — no credentials needed
                guestView
            } else {
                credentialView(probe: probe)
            }
        }
    }

    // Guest login
    private var guestView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.fill.checkmark")
                .font(.system(size: 40)).foregroundStyle(Color.swingPrimary)
            Text("Guest access enabled").font(SwingType.titleMedium)
            Text("This server allows open access without a password.")
                .font(SwingType.bodySmall).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    isLoggingIn = true; loginError = nil
                    loginError = await auth.loginAsGuest()
                    isLoggingIn = false
                }
            } label: {
                Group {
                    if isLoggingIn { ProgressView().tint(.white) }
                    else { Text("Enter as guest") }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.swingPrimary).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12)).font(SwingType.titleMedium)
            }
            .disabled(isLoggingIn)
        }
    }

    // Username + password login (with optional user picker)
    @ViewBuilder
    private func credentialView(probe: ProbeResult) -> some View {
        VStack(spacing: 14) {
            // User picker when server returns multiple users
            if probe.hasMultipleUsers {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select account").font(SwingType.labelMedium).foregroundStyle(.secondary)
                    ForEach(probe.users) { user in
                        Button { username = user.username } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(username == user.username
                                        ? Color.swingPrimary : Color.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(user.username).font(SwingType.labelMedium)
                                    if !user.firstname.isEmpty {
                                        let full = "\(user.firstname) \(user.lastname)"
                                            .trimmingCharacters(in: .whitespaces)
                                        Text(full).font(SwingType.labelSmall).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if username == user.username {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.swingPrimary)
                                }
                            }
                            .padding(10)
                            .background(username == user.username
                                ? Color.swingPrimary.opacity(0.08) : Color.secondary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .onAppear { if username.isEmpty, let first = probe.users.first {
                            username = first.username
                        }}
                    }
                }
            } else {
                // Single user or unknown — show username field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Username").font(SwingType.labelMedium).foregroundStyle(.secondary)
                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .onAppear { if let u = probe.users.first, username.isEmpty {
                            username = u.username
                        }}
                }
            }

            // Password
            VStack(alignment: .leading, spacing: 6) {
                Text("Password").font(SwingType.labelMedium).foregroundStyle(.secondary)
                HStack {
                    Group {
                        if showPass { TextField("Password", text: $password) }
                        else { SecureField("Password", text: $password) }
                    }
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button { showPass.toggle() } label: {
                        Image(systemName: showPass ? "eye.slash" : "eye").foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                Task {
                    isLoggingIn = true; loginError = nil
                    loginError = await auth.loginWithPassword(username: username, password: password)
                    isLoggingIn = false
                }
            } label: {
                Group {
                    if isLoggingIn { ProgressView().tint(.white) }
                    else { Text("Log in") }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.swingPrimary).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12)).font(SwingType.titleMedium)
            }
            .disabled(isLoggingIn || username.isEmpty)
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick setup").font(SwingType.labelMedium).foregroundStyle(.secondary)
            TipRow(icon: "cloud.fill",       color: .orange, title: "Cloudflare Tunnel",
                   detail: "Free HTTPS, no port forwarding")
            TipRow(icon: "lock.shield.fill", color: .blue,   title: "Local network",
                   detail: "192.168.x.x:1970 works automatically")
            TipRow(icon: "network",          color: .teal,   title: "Any reverse proxy",
                   detail: "nginx · Caddy · Traefik · all supported")
        }
        .padding(14).background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func submitURL() async {
        var raw = serverURL.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        raw = ConnectionConfig.normalize(raw)
        serverURL = raw
        if raw.lowercased().hasPrefix("http://") &&
           !raw.lowercased().hasPrefix("https://") &&
           !auth.allowsInsecureHTTP {
            showATS = true; return
        }
        await auth.probe(rawURL: raw)
    }
}


private struct TipRow: View {
    let icon: String; let color: Color; let title: String; let detail: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13))
                .foregroundStyle(color).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(SwingType.labelMedium)
                Text(detail).font(SwingType.labelSmall).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Real QR scanner using AVCaptureSession + Vision
import AVFoundation
import Vision

struct QRScanSheet: View {
    let onResult: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var manualCode = ""
    @State private var showManual = false
    @State private var cameraAllowed: Bool? = nil  // nil=checking, true=ok, false=denied

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if cameraAllowed == true {
                    QRCameraView(onScan: { code in
                        dismiss()
                        onResult(code)
                    })
                    .ignoresSafeArea(edges: .bottom)
                } else if cameraAllowed == false {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.slash").font(.system(size: 48))
                            .foregroundStyle(.secondary).padding(.top, 60)
                        Text("Camera access denied")
                            .font(SwingType.titleMedium)
                        Text("Go to Settings → Swing Music → Camera to allow access.")
                            .font(SwingType.bodySmall).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent).tint(Color.swingPrimary)
                    }
                } else {
                    ProgressView("Requesting camera…").padding(60)
                }

                // Manual fallback always visible at the bottom
                VStack(spacing: 10) {
                    Button(showManual ? "Hide manual entry" : "Enter code manually") {
                        showManual.toggle()
                    }
                    .font(SwingType.labelSmall).foregroundStyle(.secondary)

                    if showManual {
                        HStack {
                            TextField("http://192.168.1.x:1970 ABCDEF", text: $manualCode)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(SwingType.bodySmall)
                            Button("Pair") {
                                let code = manualCode.trimmingCharacters(in: .whitespaces)
                                guard !code.isEmpty else { return }
                                dismiss()
                                onResult(code)
                            }
                            .disabled(manualCode.isEmpty)
                            .buttonStyle(.borderedProminent)
                            .tint(Color.swingPrimary)
                        }
                        .padding(.horizontal)
                        Text("Format: URL followed by a space and the code shown in the web client")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                    }
                }
                .padding(.vertical, 16)
                .background(.regularMaterial)
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await checkCamera() }
    }

    private func checkCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAllowed = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraAllowed = granted
        default:
            cameraAllowed = false
        }
    }
}

// UIViewRepresentable wrapping AVCaptureSession with Vision QR detection
struct QRCameraView: UIViewRepresentable {
    let onScan: (String) -> Void

    func makeUIView(context: Context) -> QRCaptureUIView {
        let view = QRCaptureUIView()
        view.onScan = onScan
        return view
    }

    func updateUIView(_ uiView: QRCaptureUIView, context: Context) {}
}

final class QRCaptureUIView: UIView {
    var onScan: ((String) -> Void)?
    private var session    = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var scanned    = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input  = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "qr.scan"))
        if session.canAddOutput(output) { session.addOutput(output) }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        layer.addSublayer(preview)
        previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }

        // Finder overlay
        let finder = UIView()
        finder.layer.borderColor = UIColor(Color.swingPrimary).cgColor
        finder.layer.borderWidth = 2
        finder.layer.cornerRadius = 12
        finder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(finder)
        NSLayoutConstraint.activate([
            finder.centerXAnchor.constraint(equalTo: centerXAnchor),
            finder.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -30),
            finder.widthAnchor.constraint(equalToConstant: 240),
            finder.heightAnchor.constraint(equalToConstant: 240)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        session.stopRunning()
    }
}

extension QRCaptureUIView: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !scanned,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectBarcodesRequest { [weak self] req, _ in
            guard let self,
                  let results = req.results as? [VNBarcodeObservation],
                  let payload = results.first(where: { $0.symbology == .qr })?.payloadStringValue,
                  !payload.isEmpty else { return }
            self.scanned = true
            DispatchQueue.main.async { self.onScan?(payload) }
        }
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .right)
        try? handler.perform([request])
    }
}
