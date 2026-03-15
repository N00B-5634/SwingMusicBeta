import Foundation
import Security

// MARK: - Connection Config
struct ConnectionConfig: Codable, Equatable {
    var rawURL: String
    var accessToken: String?
    var refreshToken: String?
    var allowsInsecureHTTP: Bool = false

    // API base URL — all request() calls append paths to this.
    // e.g. rawURL=https://host → baseURL=https://host/api/
    var baseURL: URL? {
        let s = rawURL.hasSuffix("/") ? rawURL : rawURL + "/"
        return URL(string: s + "api/")
    }

    // Server root — for auth endpoints (/auth/...) and images (/img/...)
    // which live outside /api/.
    var rootURL: URL? {
        let s = rawURL.hasSuffix("/") ? rawURL : rawURL + "/"
        return URL(string: s)
    }

    var isHTTPS: Bool { rawURL.lowercased().hasPrefix("https://") }

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        return s
    }

    static func validate(_ raw: String) -> Bool {
        guard let url = URL(string: raw),
              let scheme = url.scheme,
              ["http","https"].contains(scheme),
              url.host != nil else { return false }
        return true
    }
}

// MARK: - TLS delegate
// Uses default handling — accepts any cert iOS trusts.
// This covers: Cloudflare Tunnel, Let's Encrypt, nginx, Caddy.
// For local HTTP servers (192.168.x.x) we skip TLS enforcement entirely.
final class SwingTLSDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod
                == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.performDefaultHandling, URLCredential(trust: trust))
    }
}

// MARK: - API Client
actor SwingAPIClient {
    static let shared = SwingAPIClient()
    static var cachedToken: String? = nil

    private var config: ConnectionConfig?
    private var session: URLSession = .shared
    private let tlsDelegate = SwingTLSDelegate()

    // MARK: Configure session
    func configure(with config: ConnectionConfig) {
        self.config = config
        SwingAPIClient.cachedToken = config.accessToken
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 20
        cfg.timeoutIntervalForResource = 3600
        cfg.httpAdditionalHeaders = [
            "Accept":   "application/json",
            "X-Client": "SwingMusic-iOS/1.0"
        ]
        cfg.httpMaximumConnectionsPerHost = 6
        // Do NOT enforce TLS 1.3 minimum — breaks local HTTP servers and
        // setups with older TLS. System default (TLS 1.2+) is fine for LAN.
        self.session = URLSession(
            configuration: cfg,
            delegate: tlsDelegate,
            delegateQueue: nil
        )
    }

    // MARK: Probe session — used before configure() to reach /api/auth/users
    // Uses URLSession.shared with no custom config so it works on any server
    private func probeRequest(url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw APIError.httpError(http.statusCode)
        }
        return data
    }

    // MARK: Generic typed request (requires configure() first)
    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil
    ) async throws -> T {
        guard let config, let base = config.baseURL else {
            throw APIError.notConfigured
        }
        var comps = URLComponents(
            url: base.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        comps?.queryItems = queryItems
        guard let url = comps?.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        if let token = config.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try JSONEncoder().encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 401: throw APIError.unauthorized
            case 404: throw APIError.notFound
            default:  throw APIError.httpError(http.statusCode)
            }
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: URL helpers
    func streamURL(trackHash: String) -> URL? {
        guard let base = config?.baseURL else { return nil }
        var comps = URLComponents(
            url: base.appendingPathComponent("stream/\(trackHash)"),
            resolvingAgainstBaseURL: false
        )
        if let token = config?.accessToken {
            comps?.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        return comps?.url
    }

    func imageURL(path: String) -> URL? {
        config?.rootURL?.appendingPathComponent(path)
    }

    nonisolated func imageURLSync(path: String) -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: "swing_server_url") else { return nil }
        let base = raw.hasSuffix("/") ? raw : raw + "/"
        return URL(string: base)?.appendingPathComponent(path)
    }

    nonisolated func streamURLSync(trackHash: String) -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: "swing_server_url") else { return nil }
        let base = raw.hasSuffix("/") ? raw : raw + "/"
        guard let baseURL = URL(string: base + "api/") else { return nil }
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("stream/\(trackHash)"),
            resolvingAgainstBaseURL: false
        )
        if let token = SwingAPIClient.cachedToken {
            comps?.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        return comps?.url
    }

    func currentConfig() -> ConnectionConfig? { config }

    func updateTokens(access: String, refresh: String, maxAge: Int64) {
        config?.accessToken  = access
        config?.refreshToken = refresh
        SwingAPIClient.cachedToken = access
    }

    func reset() {
        config = nil
        SwingAPIClient.cachedToken = nil
        session = .shared
    }
}

// MARK: - All Swing Music API endpoints
// Base: /api/  (e.g. https://host/api/auth/users)
// Images: /img/ (e.g. https://host/img/thumbnail/small/hash.webp)
extension SwingAPIClient {

    // ── Auth ─────────────────────────────────────────────────────────────────
    //
    // Endpoints (no /api/ prefix — request() adds it via baseURL):
    //   GET  /auth/users              — probe: returns users + settings
    //   POST /auth/login              — username + password → LogInResult
    //   GET  /auth/pair?code=CODE     — QR code → LogInResult
    //   POST /auth/logout             — invalidate session
    //   POST /auth/token/refresh      — refresh token → LogInResult
    //
    // Note: probe calls happen BEFORE configure(), so they use a fresh
    // URLSession built from the raw URL rather than the stored session.

    // GET BASE_URL/auth/users
    // Called before configure() — uses a fresh session for the given URL.
    func getAllUsers(rawURL: String) async throws -> AllUsersResponse {
        let base = rawURL.hasSuffix("/") ? rawURL : rawURL + "/"
        guard let url = URL(string: base + "auth/users") else {
            throw APIError.invalidURL
        }
        let data = try await probeRequest(url: url)
        do {
            return try JSONDecoder().decode(AllUsersResponse.self, from: data)
        } catch {
            // Surface the raw response in debug to help diagnose mismatched paths
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "(binary)"
            throw APIError.decodingError("auth/users decode failed. Response: \(preview)")
        }
    }

    // POST BASE_URL/auth/login  { username, password }
    // Session must be configured first (probe() does this).
    func loginWithPassword(baseURL: String, username: String, password: String) async throws -> LogInResult {
        let base = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        guard let url = URL(string: base + "auth/login") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody   = try JSONEncoder().encode(LoginRequest(username: username, password: password))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 401: throw APIError.incorrectPassword
            case 404: throw APIError.userNotFound
            default:  throw APIError.httpError(http.statusCode)
            }
        }
        return try JSONDecoder().decode(LogInResult.self, from: data)
    }

    // GET BASE_URL/auth/pair?code=CODE
    // scannedURL is the full URL from the QR code, e.g.:
    //   http://192.168.1.10:1970/auth/pair?code=XXXXXX
    // We call it directly — the server returns LogInResult.
    func loginWithQRURL(scannedURL: String) async throws -> LogInResult {
        guard let url = URL(string: scannedURL) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        // Use session (already configured for this server by AuthState.loginWithQR)
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw APIError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(LogInResult.self, from: data)
    }

    // POST BASE_URL/auth/token/refresh
    // Authorization: Bearer <refreshToken>
    func refreshTokens() async throws -> LogInResult {
        guard let cfg = config,
              let refresh = cfg.refreshToken,
              let base = cfg.rootURL,
              let url = URL(string: base.absoluteString + "auth/token/refresh")
        else { throw APIError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(refresh)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",   forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw APIError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(LogInResult.self, from: data)
    }

    // POST BASE_URL/auth/logout
    func logout() async throws {
        let _: EmptyBody = try await request(path: "auth/logout", method: "POST")
    }

    // ── Folders ──────────────────────────────────────────────────────────────

    // POST /api/folder
    func getFoldersAndTracks(folder: String, start: Int, limit: Int, tracksOnly: Bool = false) async throws -> FoldersAndTracks {
        try await request(path: "folder", method: "POST",
            body: FoldersAndTracksRequest(folder: folder, tracksOnly: tracksOnly, limit: limit, start: start))
    }

    // GET /api/folder/root-dirs
    func getRootDirectories() async throws -> RootDirs {
        try await request(path: "folder/root-dirs")
    }

    // ── Albums ───────────────────────────────────────────────────────────────

    // GET /api/albums
    func getAllAlbums(start: Int, limit: Int = 20, sortBy: SortBy = .title, sortOrder: SortOrder = .ascending) async throws -> AllAlbums {
        try await request(path: "albums", queryItems: [
            .init(name: "start",   value: "\(start)"),
            .init(name: "limit",   value: "\(limit)"),
            .init(name: "sortby",  value: sortBy.rawValue),
            .init(name: "reverse", value: sortOrder == .descending ? "1" : "0")
        ])
    }

    // POST /api/albums/:hash
    func getAlbumWithInfo(albumHash: String) async throws -> AlbumWithInfo {
        try await request(path: "albums/\(albumHash)", method: "POST",
            body: AlbumHashRequest(albumhash: albumHash))
    }

    // GET /api/albums/:hash/tracks
    func getAlbumTracks(albumHash: String) async throws -> [Track] {
        try await request(path: "albums/\(albumHash)/tracks")
    }

    // ── Artists ──────────────────────────────────────────────────────────────

    // GET /api/artists
    func getAllArtists(start: Int, limit: Int = 20, sortBy: SortBy = .name, sortOrder: SortOrder = .ascending) async throws -> AllArtists {
        try await request(path: "artists", queryItems: [
            .init(name: "start",   value: "\(start)"),
            .init(name: "limit",   value: "\(limit)"),
            .init(name: "sortby",  value: sortBy.rawValue),
            .init(name: "reverse", value: sortOrder == .descending ? "1" : "0")
        ])
    }

    // GET /api/artists/:hash
    func getArtistInfo(artistHash: String) async throws -> ArtistInfo {
        try await request(path: "artists/\(artistHash)", queryItems: [
            .init(name: "tracklimit", value: "-1"),
            .init(name: "all",        value: "true")
        ])
    }

    // GET /api/artists/:hash/similar
    func getSimilarArtists(artistHash: String) async throws -> [Artist] {
        try await request(path: "artists/\(artistHash)/similar")
    }

    // GET /api/artists/:hash/tracks
    func getArtistTracks(artistHash: String) async throws -> [Track] {
        try await request(path: "artists/\(artistHash)/tracks")
    }

    // ── Search ───────────────────────────────────────────────────────────────

    // GET /api/search?q=&limit=
    func getTopSearchResults(query: String, limit: Int = 5) async throws -> TopSearchResults {
        try await request(path: "search", queryItems: [
            .init(name: "q",     value: query),
            .init(name: "limit", value: "\(limit)")
        ])
    }

    func searchTracks(query: String, limit: Int = -1) async throws -> TracksSearchResult {
        try await request(path: "search", queryItems: [
            .init(name: "q",        value: query),
            .init(name: "limit",    value: "\(limit)"),
            .init(name: "itemtype", value: "tracks")
        ])
    }

    func searchAlbums(query: String, limit: Int = -1) async throws -> AlbumsSearchResult {
        try await request(path: "search", queryItems: [
            .init(name: "q",        value: query),
            .init(name: "limit",    value: "\(limit)"),
            .init(name: "itemtype", value: "albums")
        ])
    }

    func searchArtists(query: String, limit: Int = -1) async throws -> ArtistsSearchResult {
        try await request(path: "search", queryItems: [
            .init(name: "q",        value: query),
            .init(name: "limit",    value: "\(limit)"),
            .init(name: "itemtype", value: "artists")
        ])
    }

    // ── Favorites ────────────────────────────────────────────────────────────

    // POST /api/favorites/add
    func addFavorite(hash: String, type: String) async throws {
        let _: EmptyBody = try await request(path: "favorites/add", method: "POST",
            body: ToggleFavoriteRequest(hash: hash, type: type))
    }

    // POST /api/favorites/remove
    func removeFavorite(hash: String, type: String) async throws {
        let _: EmptyBody = try await request(path: "favorites/remove", method: "POST",
            body: ToggleFavoriteRequest(hash: hash, type: type))
    }

    // GET /api/favorites  — type: tracks | albums | artists
    func getFavorites(type: String = "tracks") async throws -> [Track] {
        try await request(path: "favorites", queryItems: [
            .init(name: "type", value: type)
        ])
    }

    // ── Playlists ────────────────────────────────────────────────────────────

    // GET /api/playlists
    func getPlaylists() async throws -> PlaylistsResponse {
        try await request(path: "playlists")
    }

    // GET /api/playlists/:id
    func getPlaylist(id: Int) async throws -> PlaylistWithTracks {
        try await request(path: "playlists/\(id)")
    }

    // POST /api/playlists/new
    func createPlaylist(name: String) async throws -> Playlist {
        try await request(path: "playlists/new", method: "POST",
            body: CreatePlaylistRequest(name: name))
    }

    // POST /api/playlists/:id/add
    func addToPlaylist(id: Int, trackHashes: [String]) async throws {
        let _: EmptyBody = try await request(path: "playlists/\(id)/add", method: "POST",
            body: PlaylistTracksRequest(trackhashes: trackHashes))
    }

    // ── Recently played / Queue ───────────────────────────────────────────────

    // GET /api/recents/tracks
    func getRecentlyPlayed() async throws -> RecentlyPlayedResponse {
        try await request(path: "recents")
    }

    // GET /api/queue
    func getSavedQueue() async throws -> QueueResponse {
        try await request(path: "queue")
    }

    // POST /api/queue/update
    func saveQueue(hashes: [String], currentIndex: Int) async throws {
        let _: EmptyBody = try await request(path: "queue/update", method: "POST",
            body: SaveQueueRequest(trackhashes: hashes, currentIndex: currentIndex))
    }

    // ── Track logger ──────────────────────────────────────────────────────────

    // POST /api/logger/track/log
    func logTrack(trackHash: String, duration: Int, source: String) async throws {
        let ts = Int64(Date().timeIntervalSince1970)
        let _: EmptyBody = try await request(path: "logger/track/log", method: "POST",
            body: LogTrackRequest(duration: duration, source: source, timestamp: ts, trackHash: trackHash))
    }
}

private struct EmptyBody: Codable {}

// MARK: - Lyrics client (lrclib.net)
actor LyricsClient {
    static let shared = LyricsClient()
    private let session = URLSession.shared

    func getLyrics(title: String, artist: String, album: String, duration: Int) async throws -> (synced: [LyricLine]?, plain: String?) {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            .init(name: "track_name",  value: title),
            .init(name: "artist_name", value: artist),
            .init(name: "album_name",  value: album),
            .init(name: "duration",    value: "\(duration)")
        ]
        guard let url = comps.url else { return (nil, nil) }
        let (data, resp) = try await session.data(from: url)
        if let http = resp as? HTTPURLResponse, http.statusCode == 404 { return (nil, nil) }
        let dto = try JSONDecoder().decode(LyricsResponse.self, from: data)
        let synced = dto.syncedLyrics.flatMap { parseLRC($0) }
        return (synced, dto.plainLyrics)
    }

    private func parseLRC(_ lrc: String) -> [LyricLine] {
        let pattern = #"^\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return lrc.components(separatedBy: "\n").compactMap { line in
            let r = NSRange(line.startIndex..., in: line)
            guard let m = regex.firstMatch(in: line, range: r) else { return nil }
            func g(_ i: Int) -> String { String(line[Range(m.range(at: i), in: line)!]) }
            let mins = Int64(g(1))!; let secs = Int64(g(2))!
            let centStr = g(3); let cent = Int64(centStr)!
            let ms = centStr.count == 2 ? cent * 10 : cent
            return LyricLine(timeMs: mins*60_000 + secs*1_000 + ms,
                             text: g(4).trimmingCharacters(in: .whitespaces))
        }.sorted { $0.timeMs < $1.timeMs }
    }
}

private struct LyricsResponse: Codable {
    let syncedLyrics: String?
    let plainLyrics:  String?
}

// MARK: - Errors
enum APIError: LocalizedError {
    case notConfigured, invalidURL, unauthorized, notFound
    case incorrectPassword, userNotFound, httpError(Int)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:        return "No server configured — please pair first."
        case .invalidURL:           return "Invalid URL."
        case .unauthorized:         return "Session expired — please log in again."
        case .notFound:             return "Not found."
        case .incorrectPassword:    return "Incorrect password."
        case .userNotFound:         return "User not found."
        case .httpError(let c):     return "Server returned \(c)."
        case .decodingError(let m): return "Response error: \(m)"
        }
    }
}
