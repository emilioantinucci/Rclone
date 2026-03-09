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
                try await authService.requestDeviceCode()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        authService.cancelDeviceCodeFlow()
    }

    func copyCode() {
        if let code = authService.userCode {
            UIPasteboard.general.string = code
        }
    }

    func openVerificationURL() {
        if let urlString = authService.verificationURL,
           let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}
