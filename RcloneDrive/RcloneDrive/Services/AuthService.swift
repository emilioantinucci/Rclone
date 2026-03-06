import Foundation
import MSAL

@MainActor
final class AuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var userDisplayName: String?
    @Published var userEmail: String?

    private var msalApplication: MSALPublicClientApplication?
    private var currentAccount: MSALAccount?

    init() {
        setupMSAL()
    }

    private func setupMSAL() {
        guard let authorityURL = URL(string: Constants.authority) else { return }
        do {
            let authority = try MSALAADAuthority(url: authorityURL)
            let config = MSALPublicClientApplicationConfig(
                clientId: Constants.clientID,
                redirectUri: Constants.redirectURI,
                authority: authority
            )
            msalApplication = try MSALPublicClientApplication(configuration: config)
            loadCachedAccount()
        } catch {
            print("Failed to create MSAL application: \(error)")
        }
    }

    private func loadCachedAccount() {
        guard let app = msalApplication else { return }
        do {
            let accounts = try app.allAccounts()
            if let account = accounts.first {
                currentAccount = account
                isAuthenticated = true
                userDisplayName = account.username
                fetchUserProfile()
            }
        } catch {
            print("Failed to load cached account: \(error)")
        }
    }

    func signIn(from viewController: UIViewController? = nil) async throws {
        guard let app = msalApplication else {
            throw AuthError.notConfigured
        }

        let parameters = MSALInteractiveTokenParameters(
            scopes: Constants.scopes,
            webviewParameters: MSALWebviewParameters(authPresentationViewController: viewController ?? rootViewController)
        )

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MSALResult, Error>) in
            app.acquireToken(with: parameters) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: AuthError.unknown)
                }
            }
        }

        currentAccount = result.account
        isAuthenticated = true
        userDisplayName = result.account.username
        fetchUserProfile()
    }

    func signOut() {
        guard let app = msalApplication, let account = currentAccount else { return }
        do {
            try app.remove(account)
        } catch {
            print("Failed to remove account: \(error)")
        }
        currentAccount = nil
        isAuthenticated = false
        userDisplayName = nil
        userEmail = nil
    }

    func acquireTokenSilently() async throws -> String {
        guard let app = msalApplication, let account = currentAccount else {
            throw AuthError.notAuthenticated
        }

        let parameters = MSALSilentTokenParameters(scopes: Constants.scopes, account: account)

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MSALResult, Error>) in
            app.acquireTokenSilent(with: parameters) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: AuthError.unknown)
                }
            }
        }

        return result.accessToken
    }

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

    private var rootViewController: UIViewController {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else {
            fatalError("No root view controller found")
        }
        return rootVC
    }
}

enum AuthError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case unknown

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "MSAL is not configured. Check your Client ID."
        case .notAuthenticated: return "No authenticated account found. Please sign in."
        case .unknown: return "An unknown authentication error occurred."
        }
    }
}
