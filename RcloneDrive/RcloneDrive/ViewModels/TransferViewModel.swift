import Foundation
import SwiftUI

@MainActor
final class TransferViewModel: ObservableObject {
    @Published var activeTransfers: [TransferItem] = []
    @Published var completedTransfers: [TransferItem] = []

    private let graphService: GraphAPIService
    private var runningCount = 0

    init(graphService: GraphAPIService) {
        self.graphService = graphService
    }

    func uploadFile(data: Data, fileName: String, parentId: String? = nil) {
        let transfer = TransferItem(fileName: fileName, type: .upload, totalBytes: Int64(data.count))
        activeTransfers.append(transfer)

        Task {
            await processUpload(transfer: transfer, data: data, fileName: fileName, parentId: parentId)
        }
    }

    func downloadFile(item: DriveItem) {
        let transfer = TransferItem(fileName: item.name, type: .download, totalBytes: item.size ?? 0)
        activeTransfers.append(transfer)

        Task {
            await processDownload(transfer: transfer, item: item)
        }
    }

    func clearCompleted() {
        completedTransfers.removeAll()
    }

    private func processUpload(transfer: TransferItem, data: Data, fileName: String, parentId: String?) async {
        transfer.status = .inProgress

        do {
            if data.count < Constants.smallFileThreshold {
                _ = try await graphService.uploadSmall(data: data, fileName: fileName, parentId: parentId)
                transfer.bytesTransferred = Int64(data.count)
            } else {
                let session = try await graphService.createUploadSession(fileName: fileName, parentId: parentId)
                let chunkSize = Constants.chunkSize
                var offset = 0

                while offset < data.count {
                    let end = min(offset + chunkSize, data.count)
                    let chunk = data[offset..<end]

                    _ = try await graphService.uploadChunk(
                        uploadUrl: session.uploadUrl,
                        data: Data(chunk),
                        rangeStart: offset,
                        totalSize: data.count
                    )
                    offset = end
                    transfer.bytesTransferred = Int64(offset)
                }
            }
            transfer.status = .completed
        } catch {
            transfer.status = .failed
            transfer.errorMessage = error.localizedDescription
        }

        moveToCompleted(transfer)
    }

    private func processDownload(transfer: TransferItem, item: DriveItem) async {
        transfer.status = .inProgress

        do {
            _ = try await graphService.downloadItem(item: item)
            transfer.bytesTransferred = item.size ?? 0
            transfer.status = .completed
        } catch {
            transfer.status = .failed
            transfer.errorMessage = error.localizedDescription
        }

        moveToCompleted(transfer)
    }

    private func moveToCompleted(_ transfer: TransferItem) {
        activeTransfers.removeAll { $0.id == transfer.id }
        completedTransfers.insert(transfer, at: 0)
    }
}
