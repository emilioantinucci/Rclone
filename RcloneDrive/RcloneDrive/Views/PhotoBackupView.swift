import SwiftUI

struct PhotoBackupView: View {
    @ObservedObject var viewModel: PhotoBackupViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Auto Backup Photos", isOn: $viewModel.backupService.isEnabled)
                    Toggle("Wi-Fi Only", isOn: $viewModel.backupService.wifiOnly)
                        .disabled(!viewModel.backupService.isEnabled)
                }

                Section("Backup Folder") {
                    HStack {
                        Text("OneDrive folder")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(viewModel.backupService.backupFolderName)
                    }
                }

                Section("Status") {
                    if viewModel.backupService.isBackingUp {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Backing up...")
                            }
                            ProgressView(value: viewModel.backupService.progress)
                            if let fileName = viewModel.backupService.currentFileName {
                                Text(fileName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    HStack {
                        Text("Photos backed up")
                        Spacer()
                        Text("\(viewModel.backupService.backedUpCount) / \(viewModel.backupService.totalAssets)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                if viewModel.backupService.isEnabled && !viewModel.backupService.isBackingUp {
                    Section {
                        Button("Backup Now") {
                            viewModel.startBackup()
                        }
                    }
                }
            }
            .navigationTitle("Photo Backup")
        }
    }
}
