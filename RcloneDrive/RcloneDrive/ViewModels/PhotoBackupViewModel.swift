import Foundation
import SwiftData

@MainActor
final class PhotoBackupViewModel: ObservableObject {
    let backupService: PhotoBackupService

    init(graphService: GraphAPIService, modelContainer: ModelContainer) {
        self.backupService = PhotoBackupService(graphService: graphService, modelContainer: modelContainer)
    }

    func startBackup() {
        Task {
            await backupService.performBackup()
        }
    }
}
