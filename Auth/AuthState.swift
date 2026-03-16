import Foundation
import Security

// MARK: - Keychain
private enum KC {
    static func save(_ v: String, key: String) {
        let data = v.data(using: .utf8)!
        let q: [CFString: Any] = [
            kSecClass:               kSecClassGenericPassword,
            kSecAttrAccount:         key,
            kSecAttrAccessible:      kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData:           data
        ]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }
    static func load(_ key: String) -> String? {
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: key,
                                  kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess,
              let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete(_ key: String) {
        SecItemDelete([kSecClass: kSecClassGenericPassword,
                       kSecAttrAccount: key] as CFDictionary)
    }
}

// MARK: - Auth State
@MainActor
final class AuthState: ObservableObject {
    @Published var isAuthenticated  = false
    @Published var serverURL        = ""
    @Published var allowsInsecureHTTP = false
    @Published var currentUser: SwingUser?

    // Probe result — drives what the pairing UI shows
    @Published var probeResult: ProbeResult? = nil
    @Published var isProbing    = false
    @Published var probeError: String? = nil

    private let serverKey  = "swing_server_url"
    private let accessKey  = "swing_access_token"
    private let refreshKey = "swing_refresh_token"
    private let insecureKey = "swing_allows_insecure"

    init() { restoreSession() }

    // MARK: - Probe
    // Step 1 of pairing: hit /auth/users to discover what auth is needed.
    // This also configures the URLSession so subsequent calls work.
    func probe(rawURL: String) async {
        isProbing = true; probeError = nil; probeResult = nil

        guard let normalized = ConnectionConfig.normalizeAndValidate(rawURL) else {
            probeError = "Enter a valid URL — e.g. https://music.example.com"
            isProbing = false; return
        }

        // Configure the session first so probe uses the right session
        let cfg = ConnectionConfig(rawURL: normalized, accessToken: nil,
                                   refreshToken: nil, allowsInsecureHTTP: allowsInsecureHTTP)
        await SwingAPIClient.shared.configure(with: cfg)

        do {
            let response = try await SwingAPIClient.shared.getAllUsers(rawURL: normalized)
            probeResult = ProbeResult(serverURL: normalized, response: response)
        } catch {
            probeError = friendlyError(error)
        }
        isProbing = false
    }

    // MARK: - Login with password
    func loginWithPassword(username: String, password: String) async -> String? {
        guard let probe = probeResult else { return "Probe the server first" }
        do {
            let result = try await SwingAPIClient.shared.loginWithPassword(
                baseURL: probe.serverURL, username: username, password: password)
            await finalize(url: probe.serverURL, result: result)
            return nil
        } catch {
            return friendlyError(error)
        }
    }

    // MARK: - Login as guest
    // Used when settings.enableGuest is true and usersOnLogin is false
    func loginAsGuest() async -> String? {
        guard let probe = probeResult else { return "Probe the server first" }
        // Guest login: just configure with no token — server allows open access
        let cfg = ConnectionConfig(rawURL: probe.serverURL, accessToken: nil,
                                   refreshToken: nil, allowsInsecureHTTP: allowsInsecureHTTP)
        await SwingAPIClient.shared.configure(with: cfg)
        serverURL = probe.serverURL
        UserDefaults.standard.set(probe.serverURL, forKey: serverKey)
        isAuthenticated = true
        return nil
    }

    // MARK: - QR login
    // The Swing Music QR code encodes a URL like:
    //   http://192.168.1.x:1970/auth/pair?code=XXXXXX
    // We call that URL directly (GET) and get back a LogInResult.
    func loginWithQR(scannedURL: String) async -> String? {
        // Parse the scanned URL to extract the base server URL
        guard let url = URL(string: scannedURL),
              let host = url.host else {
            return "Invalid QR code"
        }
        let scheme = url.scheme ?? "http"
        let port   = url.port.map { ":\($0)" } ?? ""
        let baseURL = "\(scheme)://\(host)\(port)"

        // Configure session for this server before making the request
        let cfg = ConnectionConfig(rawURL: baseURL, accessToken: nil,
                                   refreshToken: nil, allowsInsecureHTTP: true) // QR is usually LAN
        await SwingAPIClient.shared.configure(with: cfg)

        do {
            let result = try await SwingAPIClient.shared.loginWithQRURL(scannedURL: scannedURL)
            await finalize(url: baseURL, result: result)
            return nil
        } catch {
            return friendlyError(error)
        }
    }

    // MARK: - Token refresh
    func refreshTokensIfNeeded() async {
        guard isAuthenticated else { return }
        do {
            let result = try await SwingAPIClient.shared.refreshTokens()
            KC.save(result.accessToken,  key: accessKey)
            KC.save(result.refreshToken, key: refreshKey)
            await SwingAPIClient.shared.updateTokens(
                access: result.accessToken, refresh: result.refreshToken, maxAge: result.maxAge)
        } catch {}
    }

    // MARK: - Unpair
    func unpair() async {
        KC.delete(accessKey); KC.delete(refreshKey)
        UserDefaults.standard.removeObject(forKey: serverKey)
        serverURL = ""; isAuthenticated = false
        currentUser = nil; probeResult = nil
        await SwingAPIClient.shared.reset()
    }

    func enableInsecureHTTP(_ on: Bool) {
        allowsInsecureHTTP = on
        UserDefaults.standard.set(on, forKey: insecureKey)
    }

    // MARK: - Internal
    private func finalize(url: String, result: LogInResult) async {
        KC.save(result.accessToken,  key: accessKey)
        KC.save(result.refreshToken, key: refreshKey)
        UserDefaults.standard.set(url, forKey: serverKey)
        serverURL = url
        let cfg = ConnectionConfig(rawURL: url, accessToken: result.accessToken,
                                   refreshToken: result.refreshToken,
                                   allowsInsecureHTTP: allowsInsecureHTTP)
        await SwingAPIClient.shared.configure(with: cfg)
        isAuthenticated = true
    }

    private func restoreSession() {
        guard let url    = UserDefaults.standard.string(forKey: serverKey),
              let access = KC.load(accessKey) else { return }
        let refresh = KC.load(refreshKey)
        serverURL = url
        allowsInsecureHTTP = UserDefaults.standard.bool(forKey: insecureKey)
        let cfg = ConnectionConfig(rawURL: url, accessToken: access,
                                   refreshToken: refresh,
                                   allowsInsecureHTTP: allowsInsecureHTTP)
        Task { await SwingAPIClient.shared.configure(with: cfg) }
        isAuthenticated = true
    }

    private func friendlyError(_ error: Error) -> String {
        if let api = error as? APIError { return api.errorDescription ?? error.localizedDescription }
        let msg = error.localizedDescription
        // URLSession cancelled = wrong URL, no server, or ATS blocking HTTP
        if msg.contains("cancelled") || msg.contains("Cancel") {
            return "Could not reach server — check the URL and that Swing Music is running"
        }
        if msg.contains("secure connection") || msg.contains("SSL") || msg.contains("TLS") {
            return "TLS error — try using https:// or enable HTTP in advanced settings"
        }
        return msg
    }
}

// MARK: - Probe result
struct ProbeResult {
    let serverURL: String
    let response: AllUsersResponse

    // True if the server requires selecting a user to log in
    var usersOnLogin: Bool { response.settings.usersOnLogin }
    // True if guest access is available (no login needed)
    var guestAllowed: Bool { response.settings.enableGuest }
    // True if there are multiple users to pick from
    var hasMultipleUsers: Bool { response.users.count > 1 }
    var users: [SwingUser] { response.users }
}

// MARK: - ConnectionConfig extension
extension ConnectionConfig {
    static func normalizeAndValidate(_ raw: String) -> String? {
        let n = normalize(raw)
        return validate(n) ? n : nil
    }
}
