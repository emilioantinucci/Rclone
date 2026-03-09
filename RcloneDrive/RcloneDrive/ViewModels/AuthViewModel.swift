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
        Task {
            do {
                try await authService.signIn()
            } catch let error as NSError where error.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" && error.code == 1 {
                // User cancelled — not an error
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
