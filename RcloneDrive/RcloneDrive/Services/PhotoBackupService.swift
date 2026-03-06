import Foundation
import Photos
import SwiftData
import Network

@MainActor
final class PhotoBackupService: NSObject, ObservableObject {
    @Published var isBackingUp = false
    @Published var totalAssets = 0
    @Published var backedUpCount = 0
    @Published var currentFileName: String?
    @Published var isEnabled = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "photoBackupEnabled")
            if isEnabled { requestAccessAndStart() }
        }
    }
    @Published var wifiOnly = true {
        didSet {
            UserDefaults.standard.set(wifiOnly, forKey: "photoBackupWifiOnly")
        }
    }
    @Published var backupFolderName: String = Constants.defaultBackupFolder {
        didSet {
            UserDefaults.standard.set(backupFolderName, forKey: "photoBackupFolder")
        }
    }

    var progress: Double {
        guard totalAssets > 0 else { return 0 }
        return Double(backedUpCount) / Double(totalAssets)
    }

    private let graphService: GraphAPIService
    private let modelContainer: ModelContainer
    private let networkMonitor = NWPathMonitor()
    private var isWifiConnected = true

    init(graphService: GraphAPIService, modelContainer: ModelContainer) {
        self.graphService = graphService
        self.modelContainer = modelContainer
        super.init()

        isEnabled = UserDefaults.standard.bool(forKey: "photoBackupEnabled")
        wifiOnly = UserDefaults.standard.object(forKey: "photoBackupWifiOnly") as? Bool ?? true
        backupFolderName = UserDefaults.standard.string(forKey: "photoBackupFolder") ?? Constants.defaultBackupFolder

        startNetworkMonitoring()
    }

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isWifiConnected = path.usesInterfaceType(.wifi)
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }

    func requestAccessAndStart() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            Task { @MainActor in
                if status == .authorized || status == .limited {
                    self?.registerChangeObserver()
                    await self?.performBackup()
                }
            }
        }
    }

    private func registerChangeObserver() {
        PHPhotoLibrary.shared().register(self)
    }

    func performBackup() async {
        guard isEnabled, !isBackingUp else { return }
        if wifiOnly && !isWifiConnected { return }

        isBackingUp = true

        let context = ModelContext(modelContainer)

        // Get all photo/video assets
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allAssets = PHAsset.fetchAssets(with: fetchOptions)

        totalAssets = allAssets.count

        // Get already backed up identifiers
        let backedUp = (try? context.fetch(FetchDescriptor<BackedUpAsset>())) ?? []
        let backedUpIds = Set(backedUp.map { $0.localIdentifier })
        backedUpCount = backedUpIds.count

        // Ensure backup folder exists
        let backupFolder = try? await ensureBackupFolder()

        // Process each asset that hasn't been backed up
        allAssets.enumerateObjects { [weak self] asset, index, stop in
            guard let self = self else {
                stop.pointee = true
                return
            }

            if backedUpIds.contains(asset.localIdentifier) { return }

            Task { @MainActor in
                if self.wifiOnly && !self.isWifiConnected {
                    self.isBackingUp = false
                    return
                }

                await self.backupAsset(asset, parentId: backupFolder?.id, context: context)
            }
        }

        isBackingUp = false
    }

    private func ensureBackupFolder() async throws -> DriveItem {
        // Try to find or create the backup folder
        let items = try await graphService.listChildren()
        let folderName = backupFolderName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if let existing = items.first(where: { $0.name == folderName && $0.isFolder }) {
            return existing
        }

        return try await graphService.createFolder(name: folderName)
    }

    private func backupAsset(_ asset: PHAsset, parentId: String?, context: ModelContext) async {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first else { return }

        let fileName = resource.originalFilename
        currentFileName = fileName

        do {
            let data = try await loadAssetData(resource: resource)

            if Int64(data.count) < Constants.smallFileThreshold {
                let item = try await graphService.uploadSmall(data: data, fileName: fileName, parentId: parentId)
                recordBackup(asset: asset, remoteId: item.id, fileName: fileName, context: context)
            } else {
                let session = try await graphService.createUploadSession(fileName: fileName, parentId: parentId)
                let chunkSize = Constants.chunkSize
                var offset = 0
                var result: DriveItem?

                while offset < data.count {
                    let end = min(offset + chunkSize, data.count)
                    let chunk = data[offset..<end]
                    result = try await graphService.uploadChunk(
                        uploadUrl: session.uploadUrl,
                        data: Data(chunk),
                        rangeStart: offset,
                        totalSize: data.count
                    )
                    offset = end
                }

                if let item = result {
                    recordBackup(asset: asset, remoteId: item.id, fileName: fileName, context: context)
                }
            }

            backedUpCount += 1
        } catch {
            print("Failed to backup \(fileName): \(error)")
        }

        currentFileName = nil
    }

    private func loadAssetData(resource: PHAssetResource) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            var data = Data()
            PHAssetResourceManager.default().requestData(for: resource, options: nil) { chunk in
                data.append(chunk)
            } completionHandler: { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    private func recordBackup(asset: PHAsset, remoteId: String, fileName: String, context: ModelContext) {
        let record = BackedUpAsset(
            localIdentifier: asset.localIdentifier,
            remoteItemId: remoteId,
            fileName: fileName
        )
        context.insert(record)
        try? context.save()
    }
}

// MARK: - PHPhotoLibraryChangeObserver
extension PhotoBackupService: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            if isEnabled {
                await performBackup()
            }
        }
    }
}
