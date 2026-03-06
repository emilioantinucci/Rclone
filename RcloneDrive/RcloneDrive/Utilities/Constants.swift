import Foundation

enum Constants {
    // MARK: - Microsoft App Registration
    // Replace with your own Client ID from Microsoft Entra (Azure AD) App Registration
    static let clientID = "YOUR_CLIENT_ID_HERE"
    static let redirectURI = "msauth.com.rclonedrive.app://auth"
    static let authority = "https://login.microsoftonline.com/common"

    // MARK: - Microsoft Graph API
    static let graphBaseURL = "https://graph.microsoft.com/v1.0"
    static let scopes = ["Files.ReadWrite.All", "User.Read", "offline_access"]

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
}
