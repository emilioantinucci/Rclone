import Foundation
import Security

/// Authentication service using OAuth2 Device Code Flow (same as rclone).
/// No MSAL dependency needed — talks directly to Microsoft's OAuth2 endpoints.
@MainActor
final class AuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var userDisplayName: String?
    @Published var userEmail: String?

    // Device code flow state
    @Published var deviceCode: String?
    @Published var userCode: String?
    @Published var verificationURL: String?
    @Published var isPolling = false

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    private var pollingTask: Task<Void, Never>?

    init() {
        loadTokensFromKeychain()
        if refreshToken != nil {
            isAuthenticated = true
            Task { await refreshAccessToken() }
        }
    }

    // MARK: - Device Code Flow

    /// Step 1: Request a device code from Microsoft
    func requestDeviceCode() async throws {
        let body = "client_id=\(Constants.clientID)&scope=\(Constants.scopeString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

        var request = URLRequest(url: URL(string: Constants.deviceCodeURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        guard let dc = json["device_code"] as? String,
              let uc = json["user_code"] as? String,
              let url = json["verification_uri"] as? String else {
            throw AuthError.deviceCodeFailed
        }

        deviceCode = dc
        userCode = uc
        verificationURL = url

        // Start polling for token
        startPolling(interval: json["interval"] as? Int ?? 5)
    }

    /// Step 2: Poll Microsoft for token (user is entering code in browser)
    private func startPolling(interval: Int) {
        isPolling = true
        pollingTask?.cancel()

        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                if Task.isCancelled { break }

                do {
                    let success = try await pollForToken()
                    if success {
                        isPolling = false
                        deviceCode = nil
                        userCode = nil
                        verificationURL = nil
                        isAuthenticated = true
                        fetchUserProfile()
                        return
                    }
                } catch AuthError.pollingExpired {
                    isPolling = false
                    deviceCode = nil
                    return
                } catch {
                    // authorization_pending — keep polling
                }
            }
        }
    }

    private func pollForToken() async throws -> Bool {
        guard let dc = deviceCode else { return false }

        let body = "grant_type=urn:ietf:params:oauth:grant-type:device_code&client_id=\(Constants.clientID)&device_code=\(dc)"

        var request = URLRequest(url: URL(string: Constants.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        if let error = json["error"] as? String {
            if error == "authorization_pending" {
                return false
            } else if error == "expired_token" || error == "authorization_declined" {
                throw AuthError.pollingExpired
            }
            return false
        }

        guard let at = json["access_token"] as? String,
              let rt = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            return false
        }

        accessToken = at
        refreshToken = rt
        tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
        saveTokensToKeychain()
        return true
    }

    // MARK: - Token Management

    func acquireTokenSilently() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date().addingTimeInterval(60) {
            return token
        }

        guard await refreshAccessToken() else {
            throw AuthError.notAuthenticated
        }

        guard let token = accessToken else {
            throw AuthError.notAuthenticated
        }
        return token
    }

    @discardableResult
    private func refreshAccessToken() async -> Bool {
        guard let rt = refreshToken else { return false }

        let body = "grant_type=refresh_token&client_id=\(Constants.clientID)&refresh_token=\(rt)&scope=\(Constants.scopeString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

        var request = URLRequest(url: URL(string: Constants.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            guard let at = json["access_token"] as? String,
                  let newRt = json["refresh_token"] as? String,
                  let expiresIn = json["expires_in"] as? Int else {
                return false
            }

            accessToken = at
            refreshToken = newRt
            tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
            saveTokensToKeychain()
            return true
        } catch {
            return false
        }
    }

    func signOut() {
        pollingTask?.cancel()
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        isAuthenticated = false
        userDisplayName = nil
        userEmail = nil
        deviceCode = nil
        userCode = nil
        deleteFromKeychain(key: Constants.keychainAccessToken)
        deleteFromKeychain(key: Constants.keychainRefreshToken)
        deleteFromKeychain(key: Constants.keychainTokenExpiry)
    }

    func cancelDeviceCodeFlow() {
        pollingTask?.cancel()
        isPolling = false
        deviceCode = nil
        userCode = nil
        verificationURL = nil
    }

    // MARK: - User Profile

    private func fetchUserProfile() {
        Task {
            do {
                let token = try await acquireTokenSilently()
                var request = URLRequest(url: URL(string: "\(Constants.graphBaseURL)/me")!)
                request.setAuthHeader(token)

                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    userDisplayName = json["displayName"] as? String
                    userEmail = json["mail"] as? String ?? json["userPrincipalName"] as? String
                }
            } catch {
                print("Failed to fetch user profile: \(error)")
            }
        }
    }

    // MARK: - Keychain Storage

    private func saveTokensToKeychain() {
        if let at = accessToken { saveToKeychain(key: Constants.keychainAccessToken, value: at) }
        if let rt = refreshToken { saveToKeychain(key: Constants.keychainRefreshToken, value: rt) }
        if let exp = tokenExpiry {
            saveToKeychain(key: Constants.keychainTokenExpiry, value: String(exp.timeIntervalSince1970))
        }
    }

    private func loadTokensFromKeychain() {
        accessToken = loadFromKeychain(key: Constants.keychainAccessToken)
        refreshToken = loadFromKeychain(key: Constants.keychainRefreshToken)
        if let expStr = loadFromKeychain(key: Constants.keychainTokenExpiry),
           let expInterval = Double(expStr) {
            tokenExpiry = Date(timeIntervalSince1970: expInterval)
        }
    }

    private func saveToKeychain(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum AuthError: LocalizedError {
    case notAuthenticated
    case deviceCodeFailed
    case pollingExpired
    case unknown

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated. Please sign in."
        case .deviceCodeFailed: return "Failed to get device code from Microsoft."
        case .pollingExpired: return "Sign-in timed out. Please try again."
        case .unknown: return "An unknown authentication error occurred."
        }
    }
}
