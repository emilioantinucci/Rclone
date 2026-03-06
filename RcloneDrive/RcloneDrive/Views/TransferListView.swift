import SwiftUI

struct TransferListView: View {
    @ObservedObject var viewModel: TransferViewModel

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.activeTransfers.isEmpty {
                    Section("Active") {
                        ForEach(viewModel.activeTransfers) { transfer in
                            TransferRow(transfer: transfer)
                        }
                    }
                }

                if !viewModel.completedTransfers.isEmpty {
                    Section("Completed") {
                        ForEach(viewModel.completedTransfers) { transfer in
                            TransferRow(transfer: transfer)
                        }
                    }
                }

                if viewModel.activeTransfers.isEmpty && viewModel.completedTransfers.isEmpty {
                    ContentUnavailableView("No Transfers",
                        systemImage: "arrow.up.arrow.down",
                        description: Text("Upload or download files to see them here"))
                }
            }
            .navigationTitle("Transfers")
            .toolbar {
                if !viewModel.completedTransfers.isEmpty {
                    Button("Clear") {
                        viewModel.clearCompleted()
                    }
                }
            }
        }
    }
}

struct TransferRow: View {
    @ObservedObject var transfer: TransferItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transfer.type == .upload ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(statusColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(transfer.fileName)
                    .lineLimit(1)

                if transfer.status == .inProgress {
                    ProgressView(value: transfer.progress)
                    Text("\(transfer.bytesTransferred.formattedFileSize) / \(transfer.totalBytes.formattedFileSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if transfer.status == .failed {
                    Text(transfer.errorMessage ?? "Failed")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if transfer.status == .completed {
                    Text(transfer.totalBytes.formattedFileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            statusBadge
        }
    }

    private var statusColor: Color {
        switch transfer.status {
        case .queued: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch transfer.status {
        case .queued:
            Text("Queued")
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.gray.opacity(0.2), in: Capsule())
        case .inProgress:
            Text("\(Int(transfer.progress * 100))%")
                .font(.caption2)
                .monospacedDigit()
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
