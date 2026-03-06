import SwiftUI
import SwiftData

struct SettingsView: View {
    let authService: AuthService
    let graphService: GraphAPIService
    @Environment(\.modelContext) private var modelContext
    @State private var cacheSizeMB = CacheManager.shared.currentCacheSizeMB
    @State private var showSignOutConfirm = false
    @State private var syncConfigs: [SyncConfiguration] = []
    @State private var showAddSync = false
    @State private var availableFolders: [DriveItem] = []

    var body: some View {
        NavigationStack {
            List {
                accountSection
                syncSection
                cacheSection
                aboutSection
            }
            .navigationTitle("Settings")
            .confirmationDialog("Sign Out?", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    authService.signOut()
                }
            } message: {
                Text("You will need to sign in again to access your files.")
            }
            .sheet(isPresented: $showAddSync) {
                addSyncFolderSheet
            }
            .onAppear { loadSyncConfigs() }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if let name = authService.userDisplayName {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.title)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text(name).fontWeight(.medium)
                        if let email = authService.userEmail {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Button("Sign Out", role: .destructive) {
                showSignOutConfirm = true
            }
        }
    }

    private var syncSection: some View {
        Section("Offline Sync Folders") {
            if syncConfigs.isEmpty {
                Text("No folders configured for offline sync")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(syncConfigs, id: \.id) { config in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(config.localFolderName)
                            if let lastSync = config.lastSyncDate {
                                Text("Last sync: \(lastSync.relativeFormatted)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { config.isEnabled },
                            set: { newValue in
                                config.isEnabled = newValue
                                try? modelContext.save()
                            }
                        ))
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(syncConfigs[index])
                    }
                    try? modelContext.save()
                    loadSyncConfigs()
                }
            }

            Button {
                showAddSync = true
                Task { await loadAvailableFolders() }
            } label: {
                Label("Add Sync Folder", systemImage: "plus")
            }
        }
    }

    private var cacheSection: some View {
        Section("Cache") {
            HStack {
                Text("Cache Size")
                Spacer()
                Text("\(cacheSizeMB) MB / \(Constants.maxCacheSizeMB) MB")
                    .foregroundStyle(.secondary)
            }

            Button("Clear Cache") {
                CacheManager.shared.clearCache()
                cacheSizeMB = 0
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Inspired by")
                Spacer()
                Text("rclone")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var addSyncFolderSheet: some View {
        NavigationStack {
            List {
                if availableFolders.isEmpty {
                    ProgressView("Loading folders...")
                } else {
                    ForEach(availableFolders) { folder in
                        Button {
                            addSyncFolder(folder)
                            showAddSync = false
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                Text(folder.name)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Folder")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showAddSync = false }
                }
            }
        }
    }

    private func loadSyncConfigs() {
        syncConfigs = (try? modelContext.fetch(FetchDescriptor<SyncConfiguration>())) ?? []
    }

    private func loadAvailableFolders() async {
        do {
            let items = try await graphService.listChildren()
            availableFolders = items.filter { $0.isFolder }
        } catch {
            print("Failed to load folders: \(error)")
        }
    }

    private func addSyncFolder(_ folder: DriveItem) {
        let config = SyncConfiguration(
            remoteFolderPath: (folder.parentReference?.path ?? "") + "/" + folder.name,
            remoteFolderId: folder.id,
            localFolderName: folder.name
        )
        modelContext.insert(config)
        try? modelContext.save()
        loadSyncConfigs()
    }
}
