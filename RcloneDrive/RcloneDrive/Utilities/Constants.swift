import Foundation

enum Constants {
    // MARK: - Microsoft App Registration (rclone's public Client ID)
    static let clientID = "b15665d9-eda6-4092-8539-0eec376afd59"
    static let authority = "https://login.microsoftonline.com/common"
    static let tokenURL = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
    static let redirectURI = "http://localhost:53682/"

    // MARK: - Microsoft Graph API
    static let graphBaseURL = "https://graph.microsoft.com/v1.0"
    static let scopes = ["Files.ReadWrite.All", "User.Read", "offline_access"]
    static let scopeString = "Files.ReadWrite.All User.Read offline_access"

    // MARK: - Transfer Settings
    static let smallFileThreshold: Int64 = 4 * 1024 * 1024 // 4 MB
    static let chunkSize: Int = 10 * 1024 * 1024 // 10 MB (must be multiple of 320 KB)
    static let maxConcurrentTransfers = 3

    // MARK: - Sync Settings
    static let defaultBackupFolder = "/Camera Roll Backup"
    static let deltaQueryInterval: TimeInterval = 15 * 60 // 15 minutes

    // MARK: - Cache
    static let maxCacheSizeMB: Int = 500

    // MARK: - Background Tasks
    static let syncTaskIdentifier = "com.rclonedrive.app.sync"
    static let photoBackupTaskIdentifier = "com.rclonedrive.app.photobackup"

    // MARK: - Keychain
    static let keychainAccessToken = "com.rclonedrive.accessToken"
    static let keychainRefreshToken = "com.rclonedrive.refreshToken"
    static let keychainTokenExpiry = "com.rclonedrive.tokenExpiry"
}
