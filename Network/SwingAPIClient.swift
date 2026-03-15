import Foundation
import Security

// MARK: - Connection Config
struct ConnectionConfig: Codable, Equatable {
    var rawURL: String
    var accessToken: String?
    var refreshToken: String?
    var allowsInsecureHTTP: Bool = false

    var baseURL: URL? {
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

// MARK: - TLS delegate — TLS 1.3, standard cert validation
// Rejects self-signed certs by default (performDefaultHandling).
// Cloudflare Tunnel, nginx, Caddy all present valid certs automatically.
final class SwingTLSDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.performDefaultHandling, URLCredential(trust: trust))
    }
}

// MARK: - API Client (actor — thread-safe)
actor SwingAPIClient {
    static let shared = SwingAPIClient()
    private var config: ConnectionConfig?
    private var session: URLSession = .shared
    private let tlsDelegate = SwingTLSDelegate()

    func configure(with config: ConnectionConfig) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 15
        cfg.timeoutIntervalForResource = 3600  // long audio streams
        // TLS 1.3 minimum — works with any modern reverse proxy
        // Cloudflare Tunnel: TLS 1.3 by default
        // nginx:  ssl_protocols TLSv1.3; in server block
        // Caddy:  TLS 1.3 by default
        cfg.tlsMinimumSupportedProtocolVersion = .TLSv13
        cfg.httpAdditionalHeaders = [
            "Accept": "application/json",
            "X-Client": "SwingMusic-iOS/1.0"
        ]
        cfg.httpMaximumConnectionsPerHost = 6
        self.session = URLSession(
            configuration: cfg,
            delegate: tlsDelegate,
            delegateQueue: nil
        )
    }

    // MARK: Generic typed request
    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil
    ) async throws -> T {
        guard let config, let base = config.baseURL else { throw APIError.notConfigured }
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
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

    // MARK: Stream URL — AVPlayer can't set headers, so token goes in query param
    // Swing Music server accepts ?token= as fallback (same as Android)
    func streamURL(trackHash: String) -> URL? {
        guard let base = config?.baseURL else { return nil }
        var comps = URLComponents(url: base.appendingPathComponent("api/stream/\(trackHash)"), resolvingAgainstBaseURL: false)
        if let token = config?.accessToken {
            comps?.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        return comps?.url
    }

    func imageURL(path: String) -> URL? {
        config?.baseURL?.appendingPathComponent(path)
    }

    func currentConfig() -> ConnectionConfig? { config }
    func updateTokens(access: String, refresh: String, maxAge: Int64) {
        config?.accessToken  = access
        config?.refreshToken = refresh
    }
}

// MARK: - All API endpoints (mirrors NetworkApiService.kt exactly)
extension SwingAPIClient {

    // Auth
    func loginWithQR(url: String, code: String) async throws -> LogInResult {
        guard var comps = URLComponents(string: url.hasSuffix("/") ? url + "auth/pair" : url + "/auth/pair")
        else { throw APIError.invalidURL }
        comps.queryItems = [URLQueryItem(name: "code", value: code)]
        guard let finalURL = comps.url else { throw APIError.invalidURL }
        let (data, resp) = try await session.data(from: finalURL)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(LogInResult.self, from: data)
    }

    func loginWithPassword(baseURL: String, username: String, password: String) async throws -> LogInResult {
        let endpoint = baseURL.hasSuffix("/") ? baseURL + "auth/login" : baseURL + "/auth/login"
        guard let url = URL(string: endpoint) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try JSONEncoder().encode(LoginRequest(username: username, password: password))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw APIError.incorrectPassword }
            if http.statusCode == 404 { throw APIError.userNotFound }
        }
        return try JSONDecoder().decode(LogInResult.self, from: data)
    }

    func refreshTokens() async throws -> LogInResult {
        try await request(path: "auth/refresh", method: "POST")
    }

    func getAllUsers(baseURL: String) async throws -> AllUsersResponse {
        let endpoint = baseURL.hasSuffix("/") ? baseURL + "auth/users" : baseURL + "/auth/users"
        guard let url = URL(string: endpoint) else { throw APIError.invalidURL }
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(AllUsersResponse.self, from: data)
    }

    // Folders
    func getFoldersAndTracks(folder: String, start: Int, limit: Int, tracksOnly: Bool = false) async throws -> FoldersAndTracks {
        try await request(path: "folder", method: "POST",
            body: FoldersAndTracksRequest(folder: folder, tracksOnly: tracksOnly, limit: limit, start: start))
    }

    func getRootDirectories() async throws -> RootDirs {
        try await request(path: "folder/root-dirs")
    }

    // Albums
    func getAllAlbums(start: Int, limit: Int = 20, sortBy: SortBy = .title, sortOrder: SortOrder = .ascending) async throws -> AllAlbums {
        try await request(path: "albums", queryItems: [
            .init(name: "start",   value: "\(start)"),
            .init(name: "limit",   value: "\(limit)"),
            .init(name: "sortby",  value: sortBy.rawValue),
            .init(name: "reverse", value: "\(sortOrder.rawValue)")
        ])
    }

    func getAlbumWithInfo(albumHash: String) async throws -> AlbumWithInfo {
        try await request(path: "albums/\(albumHash)", method: "POST",
            body: AlbumHashRequest(albumhash: albumHash))
    }

    func getAlbumTracks(albumHash: String) async throws -> [Track] {
        try await request(path: "albums/\(albumHash)/tracks")
    }

    // Artists
    func getAllArtists(start: Int, limit: Int = 20, sortBy: SortBy = .name, sortOrder: SortOrder = .ascending) async throws -> AllArtists {
        try await request(path: "artists", queryItems: [
            .init(name: "start",   value: "\(start)"),
            .init(name: "limit",   value: "\(limit)"),
            .init(name: "sortby",  value: sortBy.rawValue),
            .init(name: "reverse", value: "\(sortOrder.rawValue)")
        ])
    }

    func getArtistInfo(artistHash: String) async throws -> ArtistInfo {
        try await request(path: "artists/\(artistHash)", queryItems: [
            .init(name: "tracklimit", value: "-1"),
            .init(name: "all",        value: "true")
        ])
    }

    func getSimilarArtists(artistHash: String) async throws -> [Artist] {
        try await request(path: "artists/\(artistHash)/similar")
    }

    func getArtistTracks(artistHash: String) async throws -> [Track] {
        try await request(path: "artists/\(artistHash)/tracks")
    }

    // Search
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

    // Favorites
    func addFavorite(hash: String, type: String) async throws {
        let _: EmptyBody = try await request(path: "favorites/add", method: "POST",
            body: ToggleFavoriteRequest(hash: hash, type: type))
    }

    func removeFavorite(hash: String, type: String) async throws {
        let _: EmptyBody = try await request(path: "favorites/remove", method: "POST",
            body: ToggleFavoriteRequest(hash: hash, type: type))
    }

    // Play logging (mirrors logLastPlayedTrackToServer)
    func logTrack(trackHash: String, duration: Int, source: String) async throws {
        let ts = Int64(Date().timeIntervalSince1970)
        let _: EmptyBody = try await request(path: "logger/track/log", method: "POST",
            body: LogTrackRequest(duration: duration, source: source, timestamp: ts, trackHash: trackHash))
    }
}

private struct EmptyBody: Codable {}

// MARK: - Lyrics client (lrclib.net — always HTTPS, external)
actor LyricsClient {
    static let shared = LyricsClient()
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.tlsMinimumSupportedProtocolVersion = .TLSv13
        return URLSession(configuration: cfg)
    }()

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
            let min = Int64(g(1))!; let sec = Int64(g(2))!
            let centStr = g(3); let cent = Int64(centStr)!
            let ms = centStr.count == 2 ? cent * 10 : cent
            return LyricLine(timeMs: min*60_000 + sec*1_000 + ms, text: g(4).trimmingCharacters(in: .whitespaces))
        }.sorted { $0.timeMs < $1.timeMs }
    }
}

private struct LyricsResponse: Codable {
    let syncedLyrics: String?; let plainLyrics: String?
}

// MARK: - Errors
enum APIError: LocalizedError {
    case notConfigured, invalidURL, unauthorized, notFound
    case incorrectPassword, userNotFound, httpError(Int)
    var errorDescription: String? {
        switch self {
        case .notConfigured:     return "No server configured. Please pair with a server."
        case .invalidURL:        return "Invalid URL."
        case .unauthorized:      return "Session expired. Please log in again."
        case .notFound:          return "Resource not found."
        case .incorrectPassword: return "Incorrect password."
        case .userNotFound:      return "User not found."
        case .httpError(let c):  return "Server error \(c)."
        }
    }
}
