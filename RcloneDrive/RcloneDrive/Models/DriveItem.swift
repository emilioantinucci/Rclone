import Foundation

struct DriveItem: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let size: Int64?
    let lastModifiedDateTime: Date?
    let createdDateTime: Date?
    let webUrl: String?
    let folder: FolderFacet?
    let file: FileFacet?
    let parentReference: ParentReference?
    let downloadUrl: String?

    var isFolder: Bool { folder != nil }

    var iconName: String {
        if isFolder { return "folder.fill" }
        if name.isImageFile { return "photo" }
        if name.isVideoFile { return "video" }
        if name.isPDFFile { return "doc.richtext" }
        return "doc"
    }

    var iconColor: SwiftUIColor {
        if isFolder { return .blue }
        if name.isImageFile { return .green }
        if name.isVideoFile { return .purple }
        if name.isPDFFile { return .red }
        return .gray
    }

    enum CodingKeys: String, CodingKey {
        case id, name, size, lastModifiedDateTime, createdDateTime, webUrl
        case folder, file, parentReference
        case downloadUrl = "@microsoft.graph.downloadUrl"
    }
}

// Use a typealias to avoid importing SwiftUI in a model file
import SwiftUI
typealias SwiftUIColor = Color

struct FolderFacet: Codable, Hashable {
    let childCount: Int?
}

struct FileFacet: Codable, Hashable {
    let mimeType: String?
    let hashes: FileHashes?
}

struct FileHashes: Codable, Hashable {
    let sha1Hash: String?
    let sha256Hash: String?
    let quickXorHash: String?
}

struct ParentReference: Codable, Hashable {
    let driveId: String?
    let id: String?
    let path: String?
}

struct DriveItemCollection: Codable {
    let value: [DriveItem]
    let nextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

struct DeltaResponse: Codable {
    let value: [DriveItem]
    let nextLink: String?
    let deltaLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
        case deltaLink = "@odata.deltaLink"
    }
}

struct UploadSession: Codable {
    let uploadUrl: String
    let expirationDateTime: String?
}
