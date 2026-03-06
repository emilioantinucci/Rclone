import Foundation
import SwiftData

@Model
final class SyncRecord {
    @Attribute(.unique) var itemId: String
    var name: String
    var localPath: String?
    var remotePath: String?
    var eTag: String?
    var lastSyncDate: Date
    var lastModifiedRemote: Date?
    var lastModifiedLocal: Date?
    var fileSize: Int64
    var isFolder: Bool
    var isDeleted: Bool

    init(itemId: String, name: String, localPath: String? = nil, remotePath: String? = nil,
         eTag: String? = nil, lastSyncDate: Date = .now, lastModifiedRemote: Date? = nil,
         lastModifiedLocal: Date? = nil, fileSize: Int64 = 0, isFolder: Bool = false,
         isDeleted: Bool = false) {
        self.itemId = itemId
        self.name = name
        self.localPath = localPath
        self.remotePath = remotePath
        self.eTag = eTag
        self.lastSyncDate = lastSyncDate
        self.lastModifiedRemote = lastModifiedRemote
        self.lastModifiedLocal = lastModifiedLocal
        self.fileSize = fileSize
        self.isFolder = isFolder
        self.isDeleted = isDeleted
    }
}

@Model
final class SyncConfiguration {
    @Attribute(.unique) var id: String
    var remoteFolderPath: String
    var remoteFolderId: String
    var localFolderName: String
    var isEnabled: Bool
    var deltaLink: String?
    var lastSyncDate: Date?

    init(id: String = UUID().uuidString, remoteFolderPath: String, remoteFolderId: String,
         localFolderName: String, isEnabled: Bool = true, deltaLink: String? = nil,
         lastSyncDate: Date? = nil) {
        self.id = id
        self.remoteFolderPath = remoteFolderPath
        self.remoteFolderId = remoteFolderId
        self.localFolderName = localFolderName
        self.isEnabled = isEnabled
        self.deltaLink = deltaLink
        self.lastSyncDate = lastSyncDate
    }
}

@Model
final class BackedUpAsset {
    @Attribute(.unique) var localIdentifier: String
    var remoteItemId: String?
    var uploadDate: Date
    var fileName: String

    init(localIdentifier: String, remoteItemId: String? = nil, uploadDate: Date = .now, fileName: String) {
        self.localIdentifier = localIdentifier
        self.remoteItemId = remoteItemId
        self.uploadDate = uploadDate
        self.fileName = fileName
    }
}
