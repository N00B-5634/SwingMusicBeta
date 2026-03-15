import Foundation
import Security

// MARK: - Keychain
private enum KC {
    static func save(_ v: String, key: String) {
        let data = v.data(using: .utf8)!
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: key, kSecValueData: data]
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
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key] as CFDictionary)
    }
}

// MARK: - Auth State  (mirrors DataAuthRepository + AuthViewModel)
@MainActor
final class AuthState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var serverURL = ""
    @Published var allowsInsecureHTTP = false
    @Published var currentUser: SwingUser?

    private let configKey   = "swing_server_url"
    private let accessKey   = "swing_access_token"
    private let refreshKey  = "swing_refresh_token"
    private let insecureKey = "swing_allows_insecure"

    init() { restoreSession() }

    // MARK: Pair
    func pair(rawURL: String, accessToken: String, refreshToken: String, maxAge: Int64) async {
        let url = ConnectionConfig.normalize(rawURL)
        serverURL = url
        KC.save(accessToken,  key: accessKey)
        KC.save(refreshToken, key: refreshKey)
        UserDefaults.standard.set(url, forKey: configKey)
        let cfg = ConnectionConfig(rawURL: url, accessToken: accessToken, refreshToken: refreshToken,
                                   allowsInsecureHTTP: allowsInsecureHTTP)
        await SwingAPIClient.shared.configure(with: cfg)
        isAuthenticated = true
    }

    func enableInsecureHTTP(_ on: Bool) {
        allowsInsecureHTTP = on
        UserDefaults.standard.set(on, forKey: insecureKey)
    }

    func unpair() async {
        KC.delete(accessKey); KC.delete(refreshKey)
        UserDefaults.standard.removeObject(forKey: configKey)
        serverURL = ""; isAuthenticated = false; currentUser = nil
    }

    // MARK: QR parsing  (mirrors DataAuthRepository.processQrCodeData)
    // Format: "http://host:port CODE"  (space-separated, exactly 2 parts)
    func parseQRCode(_ encoded: String) -> (url: String, code: String)? {
        let parts = encoded.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    // MARK: Token refresh  (mirrors TokenRefreshWorker)
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

    // MARK: URL validation  (mirrors AuthUtils.normalizeUrl + validInputUrl)
    static func normalizeAndValidate(_ raw: String) -> String? {
        let normalized = ConnectionConfig.normalize(raw)
        return ConnectionConfig.validate(normalized) ? normalized : nil
    }

    // MARK: Restore
    private func restoreSession() {
        guard let url    = UserDefaults.standard.string(forKey: configKey),
              let access = KC.load(accessKey) else { return }
        let refresh = KC.load(refreshKey)
        serverURL = url
        allowsInsecureHTTP = UserDefaults.standard.bool(forKey: insecureKey)
        let cfg = ConnectionConfig(rawURL: url, accessToken: access, refreshToken: refresh,
                                   allowsInsecureHTTP: allowsInsecureHTTP)
        Task { await SwingAPIClient.shared.configure(with: cfg) }
        isAuthenticated = true
    }
}
