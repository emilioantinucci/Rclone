import Foundation
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var errorMessage: String?
    @Published var isSigningIn = false

    let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    func signIn() {
        isSigningIn = true
        errorMessage = nil

        Task {
            do {
                try await authService.signIn()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }

    func signOut() {
        authService.signOut()
    }
}
