import Foundation

final class CacheManager {
    static let shared = CacheManager()

    private let cacheDirectory: URL
    private let maxSizeBytes: Int64

    private init() {
        cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FileCache")
        maxSizeBytes = Int64(Constants.maxCacheSizeMB) * 1024 * 1024

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func cachedFileURL(for itemId: String, fileName: String) -> URL {
        cacheDirectory.appendingPathComponent("\(itemId)_\(fileName)")
    }

    func hasCachedFile(for itemId: String, fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: cachedFileURL(for: itemId, fileName: fileName).path)
    }

    func cacheFile(data: Data, itemId: String, fileName: String) throws {
        let url = cachedFileURL(for: itemId, fileName: fileName)
        try data.write(to: url)
        evictIfNeeded()
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    var currentCacheSizeMB: Int {
        let size = directorySize(url: cacheDirectory)
        return Int(size / (1024 * 1024))
    }

    /// LRU eviction: remove oldest files until under max size
    private func evictIfNeeded() {
        let currentSize = directorySize(url: cacheDirectory)
        guard currentSize > maxSizeBytes else { return }

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentAccessDateKey, .fileSizeKey]) else { return }

        // Sort by last access date (oldest first)
        let sorted = files.sorted { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? .distantPast
            return dateA < dateB
        }

        var freed: Int64 = 0
        let target = currentSize - maxSizeBytes + (maxSizeBytes / 10) // Free 10% extra

        for file in sorted {
            guard freed < target else { break }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try? fm.removeItem(at: file)
            freed += Int64(size)
        }
    }

    private func directorySize(url: URL) -> Int64 {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.reduce(0) { total, file in
            total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}
