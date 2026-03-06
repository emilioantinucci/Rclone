import Foundation

extension Int64 {
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: .now)
    }

    var shortFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

extension String {
    var fileExtension: String {
        (self as NSString).pathExtension.lowercased()
    }

    var isImageFile: Bool {
        ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "bmp", "tiff"].contains(fileExtension)
    }

    var isVideoFile: Bool {
        ["mp4", "mov", "avi", "mkv", "m4v", "wmv"].contains(fileExtension)
    }

    var isPDFFile: Bool {
        fileExtension == "pdf"
    }
}

extension URLRequest {
    mutating func setAuthHeader(_ token: String) {
        setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}
