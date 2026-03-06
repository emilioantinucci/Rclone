import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct RcloneDriveApp: App {
    @StateObject private var authService = AuthService()
    private let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([SyncRecord.self, SyncConfiguration.self, BackedUpAsset.self])
            modelContainer = try ModelContainer(for: schema)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .modelContainer(modelContainer)
        }
    }

    @ViewBuilder
    private var rootView: some View {
        if authService.isAuthenticated {
            let graphService = GraphAPIService(authService: authService)
            MainTabView(authService: authService, graphService: graphService)
        } else {
            LoginView(viewModel: AuthViewModel(authService: authService))
        }
    }

    // MARK: - Background Tasks

    private func registerBackgroundTasks() {
        // Delta sync task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Constants.syncTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleSyncTask(refreshTask)
        }

        // Photo backup task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Constants.photoBackupTaskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            self.handlePhotoBackupTask(processingTask)
        }

        scheduleBackgroundSync()
        schedulePhotoBackup()
    }

    private func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: Constants.syncTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Constants.deltaQueryInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func schedulePhotoBackup() {
        let request = BGProcessingTaskRequest(identifier: Constants.photoBackupTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleSyncTask(_ task: BGAppRefreshTask) {
        scheduleBackgroundSync() // Schedule next

        let graphService = GraphAPIService(authService: authService)
        let syncEngine = SyncEngine(graphService: graphService, modelContainer: modelContainer)

        task.expirationHandler = { }

        Task { @MainActor in
            await syncEngine.performSync()
            task.setTaskCompleted(success: syncEngine.syncError == nil)
        }
    }

    private func handlePhotoBackupTask(_ task: BGProcessingTask) {
        schedulePhotoBackup() // Schedule next

        let graphService = GraphAPIService(authService: authService)
        let backupService = PhotoBackupService(graphService: graphService, modelContainer: modelContainer)

        task.expirationHandler = { }

        Task { @MainActor in
            await backupService.performBackup()
            task.setTaskCompleted(success: true)
        }
    }
}
