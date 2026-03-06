import SwiftUI
import SwiftData

struct MainTabView: View {
    let authService: AuthService
    let graphService: GraphAPIService

    @Environment(\.modelContext) private var modelContext
    @StateObject private var fileBrowserVM: FileBrowserViewModel
    @StateObject private var transferVM: TransferViewModel

    init(authService: AuthService, graphService: GraphAPIService) {
        self.authService = authService
        self.graphService = graphService
        _fileBrowserVM = StateObject(wrappedValue: FileBrowserViewModel(graphService: graphService))
        _transferVM = StateObject(wrappedValue: TransferViewModel(graphService: graphService))
    }

    var body: some View {
        TabView {
            FileBrowserView(viewModel: fileBrowserVM)
                .tabItem {
                    Label("Files", systemImage: "folder")
                }

            TransferListView(viewModel: transferVM)
                .tabItem {
                    Label("Transfers", systemImage: "arrow.up.arrow.down")
                }

            PhotoBackupView(viewModel: PhotoBackupViewModel(
                graphService: graphService,
                modelContainer: modelContext.container
            ))
                .tabItem {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }

            SettingsView(authService: authService, graphService: graphService)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
