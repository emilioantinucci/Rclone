import Foundation
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var errorMessage: String?

    let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    func startSignIn() {
        errorMessage = nil
        authService.startSignIn()
    }

    func handleCallback(url: URL) {
        Task {
            do {
                try await authService.handleAuthCallback(url: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        authService.cancelSignIn()
    }
}
