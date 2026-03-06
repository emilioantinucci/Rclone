import SwiftUI
import UniformTypeIdentifiers

struct FileBrowserView: View {
    @ObservedObject var viewModel: FileBrowserViewModel
    @State private var showDocumentPicker = false
    @State private var selectedItem: DriveItem?
    @State private var showDeleteConfirm = false
    @State private var itemToDelete: DriveItem?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("Loading...")
                } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await viewModel.loadItems() } }
                    }
                } else if viewModel.items.isEmpty {
                    ContentUnavailableView("No Files",
                        systemImage: "folder",
                        description: Text("This folder is empty"))
                } else {
                    fileList
                }
            }
            .navigationTitle(viewModel.title)
            .searchable(text: $viewModel.searchText, prompt: "Search files")
            .onSubmit(of: .search) { Task { await viewModel.search() } }
            .refreshable { await viewModel.loadItems() }
            .toolbar { toolbarContent }
            .sheet(item: $selectedItem) { item in
                FileDetailView(item: item, graphService: viewModel.graphService)
            }
            .alert("New Folder", isPresented: $viewModel.showNewFolderDialog) {
                TextField("Folder name", text: $viewModel.newFolderName)
                Button("Create") { Task { await viewModel.createFolder() } }
                Button("Cancel", role: .cancel) { }
            }
            .alert("Rename", isPresented: $viewModel.showRenameDialog) {
                TextField("New name", text: $viewModel.renameText)
                Button("Rename") { Task { await viewModel.renameItem() } }
                Button("Cancel", role: .cancel) { }
            }
            .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let item = itemToDelete {
                        Task { await viewModel.deleteItem(item) }
                    }
                }
            }
            .fileImporter(isPresented: $showDocumentPicker,
                          allowedContentTypes: [.data],
                          allowsMultipleSelection: true) { result in
                handleFileImport(result)
            }
        }
        .task { await viewModel.loadItems() }
    }

    @ViewBuilder
    private var fileList: some View {
        if viewModel.isGridView {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 16) {
                    ForEach(viewModel.items) { item in
                        gridCell(for: item)
                    }
                }
                .padding()
            }
        } else {
            List {
                ForEach(viewModel.items) { item in
                    listRow(for: item)
                }
            }
            .listStyle(.plain)
        }
    }

    private func listRow(for item: DriveItem) -> some View {
        Button {
            if item.isFolder {
                viewModel.navigateToFolder(item)
            } else {
                selectedItem = item
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.iconName)
                    .foregroundStyle(item.iconColor)
                    .font(.title3)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .lineLimit(1)
                    HStack {
                        if let size = item.size, !item.isFolder {
                            Text(size.formattedFileSize)
                        }
                        if let date = item.lastModifiedDateTime {
                            Text(date.relativeFormatted)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if item.isFolder {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                itemToDelete = item
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                viewModel.renameItemTarget = item
                viewModel.renameText = item.name
                viewModel.showRenameDialog = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }

    private func gridCell(for item: DriveItem) -> some View {
        Button {
            if item.isFolder {
                viewModel.navigateToFolder(item)
            } else {
                selectedItem = item
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: item.iconName)
                    .font(.largeTitle)
                    .foregroundStyle(item.iconColor)
                    .frame(height: 50)
                Text(item.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .contextMenu {
            Button {
                viewModel.renameItemTarget = item
                viewModel.renameText = item.name
                viewModel.showRenameDialog = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                itemToDelete = item
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    viewModel.isGridView.toggle()
                } label: {
                    Label(viewModel.isGridView ? "List View" : "Grid View",
                          systemImage: viewModel.isGridView ? "list.bullet" : "square.grid.2x2")
                }

                Button {
                    viewModel.showNewFolderDialog = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }

                Button {
                    showDocumentPicker = true
                } label: {
                    Label("Upload File", systemImage: "arrow.up.doc")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }

        if !viewModel.navigationPath.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.navigateBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                Task {
                    if let data = try? Data(contentsOf: url) {
                        await viewModel.uploadFile(data: data, fileName: url.lastPathComponent)
                    }
                }
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

