import Foundation
import Security

// MARK: - Connection Config
struct ConnectionConfig: Codable, Equatable {
    var rawURL: String
    var accessToken: String?
    var refreshToken: String?
    var allowsInsecureHTTP: Bool = false

    // API base URL — Swing Music routes live at the server root, not under /api/.
    // e.g. rawURL=https://host → baseURL=https://host/
    //   folder endpoint: https://host/folder
    //   albums endpoint: https://host/albums
    // Auth endpoints also live at root: https://host/auth/users
    var baseURL: URL? {
        let s = rawURL.hasSuffix("/") ? rawURL : rawURL + "/"
        return URL(string: s)
    }

    // Alias for image/stream URLs — same as baseURL for Swing Music
    var rootURL: URL? { baseURL }

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
// Accepts ALL TLS certificates — needed for:
//   - Self-signed certs on local servers
//   - Cloudflare Tunnel (trycloudflare.com, your-domain.com via CF)
//   - Any valid or invalid cert on a self-hosted server
//
// This is intentional for a self-hosted music server app. The user
// explicitly typed in the server URL, so they trust it.
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
            // Non-TLS challenge (e.g. Basic auth) — default handling
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // Accept the certificate unconditionally
        completionHandler(.useCredential, URLCredential(trust: trust))
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
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 3600
        // Do NOT set waitsForConnectivity — it causes silent .cancelled errors
        // on some iOS versions when the server takes > 1s to respond.

        // User-Agent must look like a browser to pass Cloudflare Tunnel's
        // browser integrity check. CF rejects generic URLSession UA strings
        // with a 403 challenge page, which the app then fails to decode as JSON.
        cfg.httpAdditionalHeaders = [
            "Accept":     "application/json",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
                        + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
                        + "SwingMusic-iOS/1.0",
            "X-Client":   "SwingMusic-iOS/1.0"
        ]
        cfg.httpMaximumConnectionsPerHost = 6

        // Use tlsDelegate to accept all TLS certs — needed for self-signed
        // certs on local servers and for Cloudflare Tunnel edge certificates.
        // Without this, connections to https://x.trycloudflare.com and
        // local HTTPS servers are rejected with "cancelled" or SSL errors.
        self.session = URLSession(
            configuration: cfg,
            delegate: tlsDelegate,
            delegateQueue: nil
        )
    }

    // MARK: Probe request — uses the current session (has browser UA for Cloudflare)
    // Falls back to a fresh session with browser UA if session is unconfigured.
    private func probeRequest(url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) SwingMusic-iOS/1.0",
            forHTTPHeaderField: "User-Agent"
        )

        // If session is already configured (e.g. re-probe after login), use it.
        // Otherwise build a one-shot session with browser UA for Cloudflare.
        let probeSession: URLSession
        if config != nil {
            probeSession = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 15
            cfg.httpAdditionalHeaders = [
                "Accept":     "application/json",
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
                            + "AppleWebKit/605.1.15 (KHTML, like Gecko) SwingMusic-iOS/1.0"
            ]
            probeSession = URLSession(
                configuration: cfg,
                delegate: tlsDelegate,
                delegateQueue: nil
            )
        }
        do {
            let (data, response) = try await probeSession.data(for: req)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                // 404 on /auth/users likely means wrong base URL
                if http.statusCode == 404 {
                    throw APIError.decodingError(
                        "Got 404 from \(url.absoluteString). " +
                        "Check your server URL — it should be just the host, " +
                        "e.g. https://music.example.com (not /auth/users or /api)"
                    )
                }
                throw APIError.httpError(http.statusCode)
            }
            return data
        } catch let urlError as URLError {
            let scheme = url.scheme ?? "unknown"
            switch urlError.code {
            case .cancelled:
                if scheme == "http" {
                    throw APIError.decodingError(
                        "HTTP blocked — iOS requires HTTPS by default. " +
                        "Enable 'Allow insecure HTTP' in Settings or use HTTPS."
                    )
                }
                throw APIError.decodingError(
                    "Cannot reach server at \(url.host ?? url.absoluteString). " +
                    "Is Swing Music running? Is the URL correct?"
                )
            case .cannotConnectToHost, .networkConnectionLost:
                throw APIError.decodingError(
                    "Cannot connect to \(url.host ?? "server"). " +
                    "Check the server is running and reachable from this device."
                )
            case .timedOut:
                throw APIError.decodingError(
                    "Server timed out. Check the URL and that Swing Music is running."
                )
            case .secureConnectionFailed, .serverCertificateUntrusted:
                throw APIError.decodingError(
                    "SSL error — use a trusted certificate (Cloudflare Tunnel is free) " +
                    "or connect over local HTTP."
                )
            default:
                throw APIError.decodingError(
                    "Connection error (\(urlError.code.rawValue)): \(urlError.localizedDescription)"
                )
            }
        }
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
            // Swing Music accepts both Bearer header and cookie-based auth
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            // Also send as cookie - server uses access_token_cookie
            req.setValue("access_token_cookie=\(token)", forHTTPHeaderField: "Cookie")
        }
        if let body {
            req.httpBody = try JSONEncoder().encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let urlError as URLError {
            switch urlError.code {
            case .cancelled:
                // "cancelled" almost always means ATS blocked the request (HTTP not allowed)
                // or the server is unreachable. Show the actual URL to help debug.
                let scheme = url.scheme ?? "unknown"
                if scheme == "http" {
                    throw APIError.decodingError(
                        "HTTP blocked by iOS security policy. " +
                        "Enable 'Allow insecure HTTP' in Settings, or use HTTPS."
                    )
                }
                throw APIError.decodingError(
                    "Request cancelled — server unreachable or connection refused. " +
                    "URL: \(url.absoluteString)"
                )
            case .notConnectedToInternet:
                throw APIError.decodingError("No internet connection.")
            case .timedOut:
                throw APIError.decodingError("Request timed out — server took too long to respond.")
            case .cannotConnectToHost:
                throw APIError.decodingError(
                    "Cannot connect to \(url.host ?? "server"). " +
                    "Check the server is running and the URL is correct."
                )
            case .secureConnectionFailed, .serverCertificateUntrusted:
                throw APIError.decodingError(
                    "TLS/SSL error — the server certificate is not trusted. " +
                    "Use a valid HTTPS certificate (Cloudflare Tunnel provides one free)."
                )
            default:
                throw APIError.decodingError(
                    "Network error (\(urlError.code.rawValue)): \(urlError.localizedDescription)"
                )
            }
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 401: throw APIError.unauthorized
            case 404: throw APIError.notFound
            case 403: throw APIError.decodingError(
                    "403 Forbidden — if using Cloudflare Tunnel, make sure " +
                    "'Browser Integrity Check' is disabled in the tunnel settings, " +
                    "or add an Access bypass rule for your IP."
                )
            case 405: throw APIError.decodingError(
                    "405 Method Not Allowed at \(url.absoluteString). " +
                    "Check the server URL is the Swing Music root (e.g. https://music.example.com) " +
                    "with no trailing path. If using Cloudflare, try disabling WAF rules."
                )
            default:  throw APIError.httpError(http.statusCode)
            }
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let preview = String(data: data.prefix(300), encoding: .utf8) ?? "(binary)"
            throw APIError.decodingError(
                "Decode failed for \(path). Server sent: \(preview)"
            )
        }
    }

    // MARK: URL helpers
    // GET /file/<trackhash>/legacy?filepath=<path>
    // The server needs filepath to find the file — we pass trackhash as filepath
    // fallback since we don't always have the full path client-side.
    func streamURL(trackHash: String, filepath: String = "") -> URL? {
        guard let base = config?.baseURL else { return nil }
        var comps = URLComponents(
            url: base.appendingPathComponent("file/\(trackHash)/legacy"),
            resolvingAgainstBaseURL: false
        )
        var items = [URLQueryItem(name: "filepath", value: filepath.isEmpty ? trackHash : filepath)]
        if let token = config?.accessToken {
            items.append(URLQueryItem(name: "token", value: token))
        }
        comps?.queryItems = items
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

    nonisolated func streamURLSync(trackHash: String, filepath: String = "") -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: "swing_server_url") else { return nil }
        let base = raw.hasSuffix("/") ? raw : raw + "/"
        guard let baseURL = URL(string: base) else { return nil }
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("file/\(trackHash)/legacy"),
            resolvingAgainstBaseURL: false
        )
        var items = [URLQueryItem(name: "filepath", value: filepath.isEmpty ? trackHash : filepath)]
        if let token = SwingAPIClient.cachedToken {
            items.append(URLQueryItem(name: "token", value: token))
        }
        comps?.queryItems = items
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
// Actual Swing Music route map (confirmed from Python source):
//
//   /auth/...         auth
//   /folder           POST  folders + tracks
//   /album            POST  album info + tracks  (NOT /albums)
//   /album/<h>/tracks GET   album tracks
//   /artist/<h>       GET   artist info
//   /getall/albums    GET   paginated album list  (NOT /albums)
//   /getall/artists   GET   paginated artist list (NOT /artists)
//   /search/top       GET   top search results   (NOT /search)
//   /search/          GET   itemtype search
//   /file/<h>/legacy  GET   audio stream         (NOT /stream)
//   /favorites        GET/POST
//   /playlists        GET/POST
//   /logger/track/log POST  scrobble
//   /nothome/recents/played GET recently played
//   /img/...          images
//   /notsettings      settings
//   /lyrics           POST  lyrics
//   /colors/album/<h> GET   album color

extension SwingAPIClient {

    // ── Auth ─────────────────────────────────────────────────────────────────

    func getAllUsers(rawURL: String) async throws -> AllUsersResponse {
        let base = rawURL.hasSuffix("/") ? rawURL : rawURL + "/"
        guard let url = URL(string: base + "auth/users") else { throw APIError.invalidURL }
        let data = try await probeRequest(url: url)
        let decoder = JSONDecoder()
        if let result = try? decoder.decode(AllUsersResponse.self, from: data) { return result }
        let raw = String(data: data.prefix(500), encoding: .utf8) ?? "(binary)"
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let usersArr = json["users"] as? [[String: Any]] {
                let usersData = try JSONSerialization.data(withJSONObject: usersArr)
                let users = (try? decoder.decode([SwingUser].self, from: usersData)) ?? []
                return AllUsersResponse(users: users,
                    settings: ProfileSettings(enableGuest: false, usersOnLogin: !users.isEmpty))
            }
            if let msg = json["error"] as? String { throw APIError.decodingError("Server: \(msg)") }
        }
        throw APIError.decodingError("Cannot read /auth/users. Raw: \(raw)")
    }

    func loginWithPassword(baseURL: String, username: String, password: String) async throws -> LogInResult {
        let base = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        guard let url = URL(string: base + "auth/login") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody   = try JSONEncoder().encode(LoginRequest(username: username, password: password))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 SwingMusic-iOS/1.0",
                     forHTTPHeaderField: "User-Agent")
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

    // GET BASE_URL/auth/pair?code=CODE  (full URL from QR code)
    func loginWithQRURL(scannedURL: String) async throws -> LogInResult {
        guard let url = URL(string: scannedURL) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 SwingMusic-iOS/1.0",
                     forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(LogInResult.self, from: data)
    }

    // POST /auth/refresh  — send refresh token as Bearer header
    func refreshTokens() async throws -> LogInResult {
        guard let cfg = config,
              let refresh = cfg.refreshToken,
              let base = cfg.rootURL,
              let url = URL(string: base.absoluteString + "auth/refresh")
        else { throw APIError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(refresh)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",   forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(LogInResult.self, from: data)
    }

    func logout() async throws {
        let _: EmptyBody = try await request(path: "auth/logout", method: "GET")
    }

    // ── Folders ───────────────────────────────────────────────────────────────
    // POST /folder

    func getFoldersAndTracks(folder: String, start: Int, limit: Int, tracksOnly: Bool = false) async throws -> FoldersAndTracks {
        try await request(path: "folder", method: "POST",
            body: FoldersAndTracksRequest(folder: folder, tracksOnly: tracksOnly, limit: limit, start: start))
    }

    // ── Albums ────────────────────────────────────────────────────────────────
    // POST /album  — returns album info + tracks
    // GET  /getall/albums — paginated list of all albums

    func getAlbumWithInfo(albumHash: String) async throws -> AlbumWithInfo {
        try await request(path: "album", method: "POST",
            body: AlbumHashRequest(albumhash: albumHash))
    }

    func getAlbumTracks(albumHash: String) async throws -> [Track] {
        try await request(path: "album/\(albumHash)/tracks")
    }

    func getAllAlbums(start: Int, limit: Int = 20, sortBy: SortBy = .title, sortOrder: SortOrder = .ascending) async throws -> AllAlbums {
        try await request(path: "getall/albums", queryItems: [
            .init(name: "start",   value: "\(start)"),
            .init(name: "limit",   value: "\(limit)"),
            .init(name: "sortby",  value: sortBy.rawValue),
            .init(name: "reverse", value: sortOrder == .descending ? "1" : "0")
        ])
    }

    // ── Artists ───────────────────────────────────────────────────────────────
    // GET /artist/<hash>         — single artist info
    // GET /getall/artists        — paginated list of all artists

    func getArtistInfo(artistHash: String) async throws -> ArtistInfo {
        try await request(path: "artist/\(artistHash)", queryItems: [
            .init(name: "tracklimit", value: "5"),
            .init(name: "albumlimit", value: "7")
        ])
    }

    func getSimilarArtists(artistHash: String) async throws -> [Artist] {
        try await request(path: "artist/\(artistHash)/similar")
    }

    func getArtistTracks(artistHash: String) async throws -> [Track] {
        try await request(path: "artist/\(artistHash)/tracks")
    }

    func getAllArtists(start: Int, limit: Int = 20, sortBy: SortBy = .name, sortOrder: SortOrder = .ascending) async throws -> AllArtists {
        try await request(path: "getall/artists", queryItems: [
            .init(name: "start",   value: "\(start)"),
            .init(name: "limit",   value: "\(limit)"),
            .init(name: "sortby",  value: sortBy.rawValue),
            .init(name: "reverse", value: sortOrder == .descending ? "1" : "0")
        ])
    }

    // ── Search ────────────────────────────────────────────────────────────────
    // GET /search/top?q=&limit=   — top results (tracks + albums + artists)
    // GET /search/?q=&itemtype=   — load more of a specific type

    func getTopSearchResults(query: String, limit: Int = 5) async throws -> TopSearchResults {
        try await request(path: "search/top", queryItems: [
            .init(name: "q",     value: query),
            .init(name: "limit", value: "\(limit)")
        ])
    }

    func searchTracks(query: String, limit: Int = 30) async throws -> TracksSearchResult {
        try await request(path: "search/", queryItems: [
            .init(name: "q",        value: query),
            .init(name: "limit",    value: "\(limit)"),
            .init(name: "itemtype", value: "tracks")
        ])
    }

    func searchAlbums(query: String, limit: Int = 30) async throws -> AlbumsSearchResult {
        try await request(path: "search/", queryItems: [
            .init(name: "q",        value: query),
            .init(name: "limit",    value: "\(limit)"),
            .init(name: "itemtype", value: "albums")
        ])
    }

    func searchArtists(query: String, limit: Int = 30) async throws -> ArtistsSearchResult {
        try await request(path: "search/", queryItems: [
            .init(name: "q",        value: query),
            .init(name: "limit",    value: "\(limit)"),
            .init(name: "itemtype", value: "artists")
        ])
    }

    // ── Favorites ─────────────────────────────────────────────────────────────
    // POST /favorites/add
    // POST /favorites/remove
    // GET  /favorites

    func addFavorite(hash: String, type: String) async throws {
        let _: EmptyBody = try await request(path: "favorites/add", method: "POST",
            body: ToggleFavoriteRequest(hash: hash, type: type))
    }

    func removeFavorite(hash: String, type: String) async throws {
        let _: EmptyBody = try await request(path: "favorites/remove", method: "POST",
            body: ToggleFavoriteRequest(hash: hash, type: type))
    }



    // ── Playlists ─────────────────────────────────────────────────────────────
    // GET  /playlists
    // GET  /playlists/<id>
    // POST /playlists/new

    func getPlaylists() async throws -> PlaylistsResponse {
        try await request(path: "playlists")
    }

    func getPlaylist(id: Int) async throws -> PlaylistWithTracks {
        try await request(path: "playlists/\(id)")
    }

    func createPlaylist(name: String) async throws -> Playlist {
        try await request(path: "playlists/new", method: "POST",
            body: CreatePlaylistRequest(name: name))
    }

    func addToPlaylist(id: Int, trackHashes: [String]) async throws {
        struct AddBody: Encodable {
            let itemtype = "tracks"
            let itemhash: String
        }
        let hashes = trackHashes.joined(separator: ",")
        let _: EmptyBody = try await request(path: "playlists/\(id)/add", method: "POST",
            body: AddBody(itemhash: hashes))
    }

    // ── Recently played ───────────────────────────────────────────────────────
    // GET /nothome/recents/played   — recently played items

    func getRecentlyPlayed() async throws -> RecentlyPlayedResponse {
        try await request(path: "nothome/recents/played")
    }

    func getRecentlyAdded() async throws -> RecentlyPlayedResponse {
        try await request(path: "nothome/recents/added")
    }



    // ── Track logger ──────────────────────────────────────────────────────────
    // POST /logger/track/log

    func logTrack(trackHash: String, duration: Int, source: String) async throws {
        let ts = Int64(Date().timeIntervalSince1970)
        let _: EmptyBody = try await request(path: "logger/track/log", method: "POST",
            body: LogTrackRequest(duration: duration, source: source, timestamp: ts, trackHash: trackHash))
    }

    // ── Colors ────────────────────────────────────────────────────────────────
    // GET /colors/album/<hash>

    func getAlbumColor(albumHash: String) async throws -> String {
        struct ColorResponse: Decodable { let color: String }
        let r: ColorResponse = try await request(path: "colors/album/\(albumHash)")
        return r.color
    }

    // ── Lyrics ────────────────────────────────────────────────────────────────
    // POST /lyrics


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
    // ── Favorites ─────────────────────────────────────────────────────────────

    func getFavorites() async throws -> FavoritesResponse {
        try await request(path: "favorites")
    }

    // ── Homepage ──────────────────────────────────────────────────────────────

    func getHomepage() async throws -> HomepageResponse {
        try await request(path: "nothome/")
    }

    // ── Lyrics ────────────────────────────────────────────────────────────────

    func getLyrics(trackHash: String, filepath: String) async throws -> LyricsServerResponse {
        struct LyricsBody: Encodable { let trackhash: String; let filepath: String }
        return try await request(path: "lyrics", method: "POST",
            body: LyricsBody(trackhash: trackHash, filepath: filepath))
    }

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
