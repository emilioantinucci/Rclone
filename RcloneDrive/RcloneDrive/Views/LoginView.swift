import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

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

            VStack(spacing: 16) {
                Button(action: { viewModel.signIn() }) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.badge.key.fill")
                        Text("Sign in with Microsoft")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(viewModel.isSigningIn)

                if viewModel.isSigningIn {
                    ProgressView("Signing in...")
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
                .frame(height: 60)
        }
    }
}
