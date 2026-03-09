import Foundation
import SwiftData

@MainActor
final class SyncSettingsViewModel: ObservableObject {
    @Published var syncConfigs: [SyncConfiguration] = []
    @Published var isLoading = false
    @Published var showAddFolder = false
    @Published var availableFolders: [DriveItem] = []

    private let graphService: GraphAPIService
    private let modelContainer: ModelContainer

    init(graphService: GraphAPIService, modelContainer: ModelContainer) {
        self.graphService = graphService
        self.modelContainer = modelContainer
        loadConfigs()
    }

    func loadConfigs() {
        let context = ModelContext(modelContainer)
        do {
            syncConfigs = try context.fetch(FetchDescriptor<SyncConfiguration>())
        } catch {
            print("Failed to load sync configs: \(error)")
        }
    }

    func loadAvailableFolders() async {
        isLoading = true
        do {
            let items = try await graphService.listChildren()
            availableFolders = items.filter { $0.isFolder }
        } catch {
            print("Failed to load folders: \(error)")
        }
        isLoading = false
    }

    func addSyncFolder(_ folder: DriveItem) {
        let context = ModelContext(modelContainer)
        let config = SyncConfiguration(
            remoteFolderPath: folder.parentReference?.path ?? "" + "/" + folder.name,
            remoteFolderId: folder.id,
            localFolderName: folder.name
        )
        context.insert(config)
        try? context.save()
        loadConfigs()
    }

    func removeSyncFolder(_ config: SyncConfiguration) {
        let context = ModelContext(modelContainer)
        let configId = config.id
        if let toDelete = try? context.fetch(
            FetchDescriptor<SyncConfiguration>(predicate: #Predicate { $0.id == configId })
        ).first {
            context.delete(toDelete)
            try? context.save()
        }
        loadConfigs()
    }

    func toggleSync(_ config: SyncConfiguration) {
        let context = ModelContext(modelContainer)
        let configId = config.id
        if let toUpdate = try? context.fetch(
            FetchDescriptor<SyncConfiguration>(predicate: #Predicate { $0.id == configId })
        ).first {
            toUpdate.isEnabled.toggle()
            try? context.save()
        }
        loadConfigs()
    }
}
