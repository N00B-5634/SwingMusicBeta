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
    // Track previous breadcrumb count to detect changes on iOS 16
    @State private var breadcrumbCount = 0

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
            // iOS 16-compatible onChange: single-arg form
            .onChange(of: breadcrumbs.count) { _ in Task { await loadContent() } }
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
        do {
            let result = try await SwingAPIClient.shared.getFoldersAndTracks(
                folder: currentPath, start: 0, limit: 500)
            currentFolders = result.folders
            currentTracks  = result.tracks
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
struct ServerPairingView: View {
    @EnvironmentObject var auth: AuthState
    @State private var serverURL = ""
    @State private var username  = ""
    @State private var password  = ""
    @State private var showPass  = false
    @State private var isLoading = false
    @State private var error: String?
    @State private var showATS   = false
    @State private var showQR    = false
    @State private var mode: Mode = .qr

    enum Mode { case qr, password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle().fill(Color.swingPrimary.opacity(0.12)).frame(width: 80, height: 80)
                            Image(systemName: "music.note.house.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.swingPrimary) // explicit Color. prefix
                        }
                        Text("Swing Music").font(SwingType.headlineMedium)
                        Text("Connect to your server").font(SwingType.bodyMedium).foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

                    Picker("Mode", selection: $mode) {
                        Text("QR Code").tag(Mode.qr)
                        Text("Username").tag(Mode.password)
                    }
                    .pickerStyle(.segmented).padding(.horizontal)

                    if mode == .qr { qrSection } else { passwordSection }
                    tips
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showATS) {
            ATSWarningSheet(
                onConfirm: { auth.enableInsecureHTTP(true); showATS = false; Task { await doLogin() } },
                onCancel:  { serverURL = serverURL.replacingOccurrences(of: "http://", with: "https://",
                              options: .caseInsensitive); showATS = false }
            )
        }
        .sheet(isPresented: $showQR) {
            QRScanSheet { code in showQR = false; handleQR(code) }
        }
    }

    private var qrSection: some View {
        VStack(spacing: 12) {
            Button { showQR = true } label: {
                VStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.swingPrimary)       // explicit Color. prefix
                    Text("Scan QR code").font(SwingType.titleMedium)
                    Text("Settings > Pair device in the web client")
                        .font(SwingType.bodySmall).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(24)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.swingPrimary.opacity(0.3)))  // explicit Color. prefix
            }
            .buttonStyle(.plain)
            if isLoading { ProgressView("Authenticating…") }
            if let e = error { Text(e).font(SwingType.labelSmall).foregroundStyle(.red).multilineTextAlignment(.center) }
        }
    }

    private var passwordSection: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Server URL").font(SwingType.labelMedium).foregroundStyle(.secondary)
                    Spacer()
                    if serverURL.lowercased().hasPrefix("http://") && !serverURL.lowercased().hasPrefix("https://") {
                        InsecureBadge()
                    }
                }
                TextField("https://music.example.com", text: $serverURL)
                    .textFieldStyle(.roundedBorder).keyboardType(.URL)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                Text("Works with any HTTPS endpoint — Cloudflare Tunnel, nginx, Caddy, Traefik, direct IP")
                    .font(SwingType.labelSmall).foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Username").font(SwingType.labelMedium).foregroundStyle(.secondary)
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Password").font(SwingType.labelMedium).foregroundStyle(.secondary)
                HStack {
                    Group {
                        if showPass { TextField("Password", text: $password) }
                        else { SecureField("Password", text: $password) }
                    }
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button { showPass.toggle() } label: {
                        Image(systemName: showPass ? "eye.slash" : "eye").foregroundStyle(.secondary)
                    }
                }
            }
            if let e = error { Text(e).font(SwingType.labelSmall).foregroundStyle(.red).multilineTextAlignment(.center) }
            Button { Task { await attemptLogin() } } label: {
                Group {
                    if isLoading { ProgressView().tint(.white) } else { Text("Connect") }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.swingPrimary).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12)).font(SwingType.titleMedium)
            }
            .disabled(isLoading || serverURL.isEmpty || username.isEmpty)
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick setup").font(SwingType.labelMedium).foregroundStyle(.secondary)
            TipRow(icon: "cloud.fill",       color: .orange, title: "Cloudflare Tunnel", detail: "Free HTTPS, no port forwarding")
            TipRow(icon: "lock.shield.fill", color: .blue,   title: "Local network",     detail: "192.168.x.x:1970 works automatically")
            TipRow(icon: "network",          color: .teal,   title: "Any reverse proxy", detail: "nginx · Caddy · Traefik · all supported")
        }
        .padding(14).background(Color.secondary.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func attemptLogin() async {
        guard let normalized = AuthState.normalizeAndValidate(serverURL) else {
            error = "Enter a valid URL (e.g. https://music.example.com)"; return
        }
        serverURL = normalized
        if normalized.lowercased().hasPrefix("http://") && !auth.allowsInsecureHTTP {
            showATS = true; return
        }
        await doLogin()
    }

    private func doLogin() async {
        isLoading = true; error = nil
        do {
            let r = try await SwingAPIClient.shared.loginWithPassword(
                baseURL: serverURL, username: username, password: password)
            await auth.pair(rawURL: serverURL, accessToken: r.accessToken,
                            refreshToken: r.refreshToken, maxAge: r.maxAge)
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    private func handleQR(_ encoded: String) {
        guard let (url, code) = auth.parseQRCode(encoded) else {
            error = "Invalid QR code"; return
        }
        isLoading = true; error = nil
        Task {
            do {
                let r = try await SwingAPIClient.shared.loginWithQR(url: url, code: code)
                await auth.pair(rawURL: url, accessToken: r.accessToken,
                                refreshToken: r.refreshToken, maxAge: r.maxAge)
            } catch { self.error = error.localizedDescription }
            isLoading = false
        }
    }
}

private struct TipRow: View {
    let icon: String; let color: Color; let title: String; let detail: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(color).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(SwingType.labelMedium)
                Text(detail).font(SwingType.labelSmall).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - QR scan stub
struct QRScanSheet: View {
    let onResult: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var manual = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Point camera at the Swing Music QR code")
                    .font(SwingType.bodyMedium).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.top, 20)
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.1)).frame(width: 260, height: 260)
                    .overlay(
                        Image(systemName: "qrcode.viewfinder").font(.system(size: 64))
                            .foregroundStyle(Color.swingPrimary.opacity(0.4))  // explicit Color. prefix
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.swingPrimary, lineWidth: 2)    // explicit Color. prefix
                    )
                VStack(spacing: 8) {
                    Text("Or enter QR data manually").font(SwingType.labelSmall).foregroundStyle(.secondary)
                    HStack {
                        TextField("http://host:1970 CODE", text: $manual)
                            .textFieldStyle(.roundedBorder).font(SwingType.bodySmall)
                        Button("Pair") { onResult(manual) }.disabled(manual.isEmpty)
                            .buttonStyle(.borderedProminent).tint(Color.swingPrimary)
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
    }
}
