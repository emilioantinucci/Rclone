import Foundation
import SwiftData

@MainActor
final class PhotoBackupViewModel: ObservableObject {
    var backupService: PhotoBackupService

    init(graphService: GraphAPIService, modelContainer: ModelContainer) {
        self.backupService = PhotoBackupService(graphService: graphService, modelContainer: modelContainer)
    }

    func startBackup() {
        Task {
            await backupService.performBackup()
        }
    }
}
