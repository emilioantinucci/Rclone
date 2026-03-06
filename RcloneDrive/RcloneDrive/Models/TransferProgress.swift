import Foundation

enum TransferType: String {
    case upload
    case download
}

enum TransferStatus: String {
    case queued
    case inProgress
    case completed
    case failed
}

@MainActor
final class TransferItem: ObservableObject, Identifiable {
    let id = UUID()
    let fileName: String
    let type: TransferType
    let totalBytes: Int64

    @Published var bytesTransferred: Int64 = 0
    @Published var status: TransferStatus = .queued
    @Published var errorMessage: String?

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesTransferred) / Double(totalBytes)
    }

    var isActive: Bool {
        status == .queued || status == .inProgress
    }

    init(fileName: String, type: TransferType, totalBytes: Int64) {
        self.fileName = fileName
        self.type = type
        self.totalBytes = totalBytes
    }
}
