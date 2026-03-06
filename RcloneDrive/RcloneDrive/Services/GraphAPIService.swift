import Foundation

final class GraphAPIService {
    private let authService: AuthService
    private let session = URLSession.shared
    private let baseURL = Constants.graphBaseURL

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(authService: AuthService) {
        self.authService = authService
    }

    // MARK: - List Items

    func listChildren(itemId: String? = nil) async throws -> [DriveItem] {
        let path: String
        if let itemId = itemId {
            path = "/me/drive/items/\(itemId)/children"
        } else {
            path = "/me/drive/root/children"
        }

        var allItems: [DriveItem] = []
        var nextLink: String? = "\(baseURL)\(path)?$top=200&$orderby=name"

        while let url = nextLink {
            let collection: DriveItemCollection = try await get(url: url)
            allItems.append(contentsOf: collection.value)
            nextLink = collection.nextLink
        }

        return allItems
    }

    // MARK: - Get Item

    func getItem(itemId: String) async throws -> DriveItem {
        return try await get(url: "\(baseURL)/me/drive/items/\(itemId)")
    }

    // MARK: - Create Folder

    func createFolder(name: String, parentId: String? = nil) async throws -> DriveItem {
        let path: String
        if let parentId = parentId {
            path = "/me/drive/items/\(parentId)/children"
        } else {
            path = "/me/drive/root/children"
        }

        let body: [String: Any] = [
            "name": name,
            "folder": [:],
            "@microsoft.graph.conflictBehavior": "rename"
        ]

        return try await post(url: "\(baseURL)\(path)", body: body)
    }

    // MARK: - Delete Item

    func deleteItem(itemId: String) async throws {
        let token = try await authService.acquireTokenSilently()
        var request = URLRequest(url: URL(string: "\(baseURL)/me/drive/items/\(itemId)")!)
        request.httpMethod = "DELETE"
        request.setAuthHeader(token)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GraphError.requestFailed
        }
    }

    // MARK: - Rename / Move

    func renameItem(itemId: String, newName: String) async throws -> DriveItem {
        let body: [String: Any] = ["name": newName]
        return try await patch(url: "\(baseURL)/me/drive/items/\(itemId)", body: body)
    }

    func moveItem(itemId: String, newParentId: String) async throws -> DriveItem {
        let body: [String: Any] = [
            "parentReference": ["id": newParentId]
        ]
        return try await patch(url: "\(baseURL)/me/drive/items/\(itemId)", body: body)
    }

    // MARK: - Simple Upload (< 4MB)

    func uploadSmall(data: Data, fileName: String, parentId: String? = nil) async throws -> DriveItem {
        let token = try await authService.acquireTokenSilently()

        let path: String
        if let parentId = parentId {
            path = "/me/drive/items/\(parentId):/\(fileName):/content"
        } else {
            path = "/me/drive/root:/\(fileName):/content"
        }

        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "PUT"
        request.setAuthHeader(token)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GraphError.requestFailed
        }
        return try decoder.decode(DriveItem.self, from: responseData)
    }

    // MARK: - Chunked Upload (>= 4MB, rclone-style)

    func createUploadSession(fileName: String, parentId: String? = nil) async throws -> UploadSession {
        let token = try await authService.acquireTokenSilently()

        let path: String
        if let parentId = parentId {
            path = "/me/drive/items/\(parentId):/\(fileName):/createUploadSession"
        } else {
            path = "/me/drive/root:/\(fileName):/createUploadSession"
        }

        let body: [String: Any] = [
            "item": [
                "@microsoft.graph.conflictBehavior": "replace",
                "name": fileName
            ]
        ]

        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "POST"
        request.setAuthHeader(token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GraphError.requestFailed
        }
        return try decoder.decode(UploadSession.self, from: data)
    }

    func uploadChunk(uploadUrl: String, data: Data, rangeStart: Int, totalSize: Int) async throws -> DriveItem? {
        let rangeEnd = rangeStart + data.count - 1

        var request = URLRequest(url: URL(string: uploadUrl)!)
        request.httpMethod = "PUT"
        request.setValue("bytes \(rangeStart)-\(rangeEnd)/\(totalSize)", forHTTPHeaderField: "Content-Range")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = data

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GraphError.requestFailed
        }

        if httpResponse.statusCode == 202 {
            // More chunks needed
            return nil
        } else if (200...201).contains(httpResponse.statusCode) {
            // Upload complete
            return try decoder.decode(DriveItem.self, from: responseData)
        } else {
            throw GraphError.uploadFailed(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Download

    func downloadItem(item: DriveItem) async throws -> URL {
        let token = try await authService.acquireTokenSilently()
        var request = URLRequest(url: URL(string: "\(baseURL)/me/drive/items/\(item.id)/content")!)
        request.setAuthHeader(token)

        let (tempURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...399).contains(httpResponse.statusCode) else {
            throw GraphError.requestFailed
        }

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let destURL = cacheDir.appendingPathComponent(item.name)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        return destURL
    }

    func getDownloadURL(itemId: String) async throws -> URL {
        let token = try await authService.acquireTokenSilently()
        var request = URLRequest(url: URL(string: "\(baseURL)/me/drive/items/\(itemId)/content")!)
        request.httpMethod = "HEAD"
        request.setAuthHeader(token)

        // The Graph API redirects to the actual download URL
        let config = URLSessionConfiguration.default
        let noRedirectSession = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)

        let (_, response) = try await noRedirectSession.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           let location = httpResponse.value(forHTTPHeaderField: "Location"),
           let url = URL(string: location) {
            return url
        }
        throw GraphError.requestFailed
    }

    // MARK: - Delta Query (rclone-style sync)

    func delta(deltaLink: String? = nil) async throws -> DeltaResponse {
        let url = deltaLink ?? "\(baseURL)/me/drive/root/delta"
        return try await get(url: url)
    }

    // MARK: - Search

    func search(query: String) async throws -> [DriveItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let collection: DriveItemCollection = try await get(
            url: "\(baseURL)/me/drive/root/search(q='\(encoded)')"
        )
        return collection.value
    }

    // MARK: - Private Helpers

    private func get<T: Decodable>(url: String) async throws -> T {
        let token = try await authService.acquireTokenSilently()
        var request = URLRequest(url: URL(string: url)!)
        request.setAuthHeader(token)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GraphError.requestFailed
        }
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable>(url: String, body: [String: Any]) async throws -> T {
        let token = try await authService.acquireTokenSilently()
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setAuthHeader(token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GraphError.requestFailed
        }
        return try decoder.decode(T.self, from: data)
    }

    private func patch<T: Decodable>(url: String, body: [String: Any]) async throws -> T {
        let token = try await authService.acquireTokenSilently()
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "PATCH"
        request.setAuthHeader(token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GraphError.requestFailed
        }
        return try decoder.decode(T.self, from: data)
    }
}

// Prevent URLSession from following redirects (used for getting download URLs)
private class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum GraphError: LocalizedError {
    case requestFailed
    case uploadFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .requestFailed: return "The request to OneDrive failed."
        case .uploadFailed(let code): return "Upload failed with status code \(code)."
        }
    }
}
