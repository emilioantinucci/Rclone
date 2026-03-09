import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App branding
            VStack(spacing: 16) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("RcloneDrive")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Your OneDrive, your way")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Sign-in button
            VStack(spacing: 16) {
                Button(action: { viewModel.startSignIn() }) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.badge.key.fill")
                        Text("Sign in with Microsoft")
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(viewModel.authService.isSigningIn)
                .padding(.horizontal, 32)

                if viewModel.authService.isSigningIn {
                    ProgressView("Signing in...")
                        .font(.caption)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }

            Spacer()
                .frame(height: 40)
        }
    }
}
