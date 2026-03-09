import Foundation
import AuthenticationServices
import Security
import CryptoKit

/// Authentication service using OAuth2 Authorization Code Flow with PKCE.
/// Uses ASWebAuthenticationSession for the browser-based sign-in.
@MainActor
final class AuthService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var isAuthenticated = false
    @Published var userDisplayName: String?
    @Published var userEmail: String?
    @Published var isSigningIn = false

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?

    // PKCE
    private var codeVerifier: String?

    override init() {
        super.init()
        loadTokensFromKeychain()
        if refreshToken != nil {
            isAuthenticated = true
            Task { await refreshAccessToken() }
        }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }

    // MARK: - Authorization Code Flow with PKCE

    func signIn() async throws {
        isSigningIn = true
        defer { isSigningIn = false }

        // Generate PKCE code verifier and challenge
        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        // Build authorization URL
        let redirectURI = Constants.redirectURI
        let scope = Constants.scopeString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let authURL = URL(string: "\(Constants.authority)/oauth2/v2.0/authorize?client_id=\(Constants.clientID)&response_type=code&redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&scope=\(scope)&code_challenge=\(challenge)&code_challenge_method=S256")!

        // Present browser for sign-in
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Constants.callbackScheme
            ) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: AuthError.unknown)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        // Extract authorization code from callback URL
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.noAuthCode
        }

        // Exchange code for tokens
        try await exchangeCodeForTokens(code: code, redirectURI: redirectURI)
        isAuthenticated = true
        fetchUserProfile()
    }

    private func exchangeCodeForTokens(code: String, redirectURI: String) async throws {
        guard let verifier = codeVerifier else { throw AuthError.unknown }

        let body = [
            "grant_type=authorization_code",
            "client_id=\(Constants.clientID)",
            "code=\(code)",
            "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
            "code_verifier=\(verifier)",
            "scope=\(Constants.scopeString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        ].joined(separator: "&")

        var request = URLRequest(url: URL(string: Constants.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        guard let at = json["access_token"] as? String,
              let rt = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorDesc = json["error_description"] as? String ?? json["error"] as? String ?? "Unknown error"
            throw AuthError.tokenExchangeFailed("HTTP \(httpStatus): \(errorDesc)")
        }

        accessToken = at
        refreshToken = rt
        tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
        codeVerifier = nil
        saveTokensToKeychain()
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        isAuthenticated = false
        userDisplayName = nil
        userEmail = nil
        deleteFromKeychain(key: Constants.keychainAccessToken)
        deleteFromKeychain(key: Constants.keychainRefreshToken)
        deleteFromKeychain(key: Constants.keychainTokenExpiry)
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
    case noAuthCode
    case tokenExchangeFailed(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated. Please sign in."
        case .noAuthCode: return "No authorization code received."
        case .tokenExchangeFailed(let detail): return "Token exchange failed: \(detail)"
        case .unknown: return "An unknown authentication error occurred."
        }
    }
}
