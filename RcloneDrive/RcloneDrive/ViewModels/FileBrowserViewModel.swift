import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FileBrowserViewModel: ObservableObject {
    @Published var items: [DriveItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var navigationPath: [DriveItem] = []
    @Published var showNewFolderDialog = false
    @Published var newFolderName = ""
    @Published var showRenameDialog = false
    @Published var renameItemTarget: DriveItem?
    @Published var renameText = ""
    @Published var searchText = ""
    @Published var isSearching = false
    @Published var isGridView = false

    let graphService: GraphAPIService

    var currentFolderId: String? {
        navigationPath.last?.id
    }

    var title: String {
        navigationPath.last?.name ?? "My Files"
    }

    init(graphService: GraphAPIService) {
        self.graphService = graphService
    }

    func loadItems() async {
        isLoading = true
        errorMessage = nil

        do {
            items = try await graphService.listChildren(itemId: currentFolderId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func navigateToFolder(_ folder: DriveItem) {
        navigationPath.append(folder)
        Task { await loadItems() }
    }

    func navigateBack() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
        Task { await loadItems() }
    }

    func createFolder() async {
        guard !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let folder = try await graphService.createFolder(name: newFolderName, parentId: currentFolderId)
            items.insert(folder, at: 0)
            newFolderName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteItem(_ item: DriveItem) async {
        do {
            try await graphService.deleteItem(itemId: item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameItem() async {
        guard let target = renameItemTarget,
              !renameText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let updated = try await graphService.renameItem(itemId: target.id, newName: renameText)
            if let index = items.firstIndex(where: { $0.id == target.id }) {
                items[index] = updated
            }
            renameItemTarget = nil
            renameText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search() async {
        guard !searchText.isEmpty else {
            await loadItems()
            return
        }
        isSearching = true
        do {
            items = try await graphService.search(query: searchText)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }

    func uploadFile(data: Data, fileName: String) async {
        do {
            let item: DriveItem
            if data.count < Constants.smallFileThreshold {
                item = try await graphService.uploadSmall(data: data, fileName: fileName, parentId: currentFolderId)
            } else {
                item = try await uploadChunked(data: data, fileName: fileName)
            }
            items.insert(item, at: 0)
        } catch {
            errorMessage = "Upload failed: \(error.localizedDescription)"
        }
    }

    private func uploadChunked(data: Data, fileName: String) async throws -> DriveItem {
        let uploadSession = try await graphService.createUploadSession(fileName: fileName, parentId: currentFolderId)
        let chunkSize = Constants.chunkSize
        var offset = 0
        var result: DriveItem?

        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data[offset..<end]

            result = try await graphService.uploadChunk(
                uploadUrl: uploadSession.uploadUrl,
                data: Data(chunk),
                rangeStart: offset,
                totalSize: data.count
            )
            offset = end
        }

        guard let finalItem = result else {
            throw GraphError.requestFailed
        }
        return finalItem
    }
}
