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

            if let userCode = viewModel.authService.userCode {
                // Device code flow — show code and instructions
                deviceCodeView(userCode: userCode)
            } else {
                // Initial sign-in button
                signInButton
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

    private var signInButton: some View {
        VStack(spacing: 16) {
            Button(action: { viewModel.startSignIn() }) {
                HStack(spacing: 12) {
                    Image(systemName: "person.badge.key.fill")
                    Text("Sign in with Microsoft")
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
        }
    }

    private func deviceCodeView(userCode: String) -> some View {
        VStack(spacing: 20) {
            Text("Enter this code:")
                .font(.headline)

            // Big code display
            Text(userCode)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

            Button {
                viewModel.copyCode()
            } label: {
                Label("Copy Code", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }

            Text("at microsoft.com/devicelogin")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Open browser button
            Button {
                viewModel.openVerificationURL()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "safari")
                    Text("Open in Browser")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            if viewModel.authService.isPolling {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting for sign-in...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Cancel") {
                viewModel.cancel()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
    }
}
