import Foundation
import SwiftData

@MainActor
final class SyncEngine: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var syncProgress: String?

    private let graphService: GraphAPIService
    private let modelContainer: ModelContainer

    init(graphService: GraphAPIService, modelContainer: ModelContainer) {
        self.graphService = graphService
        self.modelContainer = modelContainer
    }

    /// Perform delta sync using rclone-inspired approach:
    /// 1. Query /delta endpoint for changes since last sync
    /// 2. Compare with local sync records
    /// 3. Apply changes with conflict resolution
    func performSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        syncProgress = "Starting sync..."

        let context = ModelContext(modelContainer)

        do {
            // Get all sync configurations
            let configs = try context.fetch(FetchDescriptor<SyncConfiguration>())
            let enabledConfigs = configs.filter { $0.isEnabled }

            guard !enabledConfigs.isEmpty else {
                syncProgress = "No folders configured for sync"
                isSyncing = false
                return
            }

            for config in enabledConfigs {
                syncProgress = "Syncing \(config.localFolderName)..."
                try await syncFolder(config: config, context: context)
                config.lastSyncDate = .now
            }

            try context.save()
            lastSyncDate = .now
            syncProgress = nil
        } catch {
            syncError = error.localizedDescription
        }

        isSyncing = false
    }

    private func syncFolder(config: SyncConfiguration, context: ModelContext) async throws {
        // Use delta query - rclone-style incremental sync
        let deltaLink = config.deltaLink
        let response = try await graphService.delta(deltaLink: deltaLink)

        for remoteItem in response.value {
            // Filter to items under our synced folder
            guard isItemUnderFolder(item: remoteItem, folderId: config.remoteFolderId) else {
                continue
            }

            try await processRemoteChange(item: remoteItem, config: config, context: context)
        }

        // Store the delta link for next sync
        if let newDeltaLink = response.deltaLink {
            config.deltaLink = newDeltaLink
        }

        // If there's a next page, continue
        if let nextLink = response.nextLink {
            let nextResponse = try await graphService.delta(deltaLink: nextLink)
            for item in nextResponse.value {
                guard isItemUnderFolder(item: item, folderId: config.remoteFolderId) else {
                    continue
                }
                try await processRemoteChange(item: item, config: config, context: context)
            }
            if let finalDeltaLink = nextResponse.deltaLink {
                config.deltaLink = finalDeltaLink
            }
        }
    }

    private func processRemoteChange(item: DriveItem, config: SyncConfiguration, context: ModelContext) async throws {
        let existingRecords = try context.fetch(FetchDescriptor<SyncRecord>()).filter { $0.itemId == item.id }

        if let existing = existingRecords.first {
            // Item exists locally - check for conflict
            if let remoteModified = item.lastModifiedDateTime,
               let localModified = existing.lastModifiedLocal,
               localModified > existing.lastSyncDate && remoteModified > existing.lastSyncDate {
                // Both modified since last sync - CONFLICT
                // Rclone approach: keep both, rename local with .conflict suffix
                syncProgress = "Conflict: \(item.name)"
                if let localPath = existing.localPath {
                    let conflictPath = localPath + ".conflict"
                    try? FileManager.default.moveItem(atPath: localPath, toPath: conflictPath)
                }
                // Download remote version
                if !item.isFolder {
                    try await downloadToLocal(item: item, config: config)
                }
            } else if let remoteModified = item.lastModifiedDateTime,
                      remoteModified > existing.lastSyncDate {
                // Remote is newer - download
                if !item.isFolder {
                    try await downloadToLocal(item: item, config: config)
                }
            }

            // Update sync record
            existing.name = item.name
            existing.eTag = nil // Will be updated on next fetch
            existing.lastModifiedRemote = item.lastModifiedDateTime
            existing.lastSyncDate = .now
        } else {
            // New item from remote - download it
            if !item.isFolder {
                try await downloadToLocal(item: item, config: config)
            } else {
                // Create local folder
                let localDir = syncDirectory(for: config).appendingPathComponent(item.name)
                try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
            }

            // Create sync record
            let record = SyncRecord(
                itemId: item.id,
                name: item.name,
                remotePath: item.parentReference?.path,
                lastModifiedRemote: item.lastModifiedDateTime,
                fileSize: item.size ?? 0,
                isFolder: item.isFolder
            )
            context.insert(record)
        }
    }

    private func downloadToLocal(item: DriveItem, config: SyncConfiguration) async throws {
        let localURL = try await graphService.downloadItem(item: item)
        let destDir = syncDirectory(for: config)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let destURL = destDir.appendingPathComponent(item.name)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: localURL, to: destURL)
    }

    private func syncDirectory(for config: SyncConfiguration) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Sync").appendingPathComponent(config.localFolderName)
    }

    private func isItemUnderFolder(item: DriveItem, folderId: String) -> Bool {
        return item.parentReference?.id == folderId || item.id == folderId
    }
}
