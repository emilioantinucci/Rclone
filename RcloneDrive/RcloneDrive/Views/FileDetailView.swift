import SwiftUI
import AVKit
import PDFKit
import QuickLook

struct FileDetailView: View {
    let item: DriveItem
    let graphService: GraphAPIService

    @State private var localFileURL: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var downloadURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading preview...")
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Preview Unavailable", systemImage: "eye.slash")
                    } description: {
                        Text(error)
                    }
                } else {
                    previewContent
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let url = localFileURL {
                        ShareLink(item: url)
                    }
                }
            }
        }
        .task { await loadPreview() }
    }

    @ViewBuilder
    private var previewContent: some View {
        VStack {
            if item.name.isImageFile, let url = localFileURL {
                imagePreview(url: url)
            } else if item.name.isVideoFile, let url = downloadURL {
                videoPreview(url: url)
            } else if item.name.isPDFFile, let url = localFileURL {
                pdfPreview(url: url)
            } else if let url = localFileURL {
                quickLookPreview(url: url)
            } else {
                fileInfoView
            }
        }
    }

    private func imagePreview(url: URL) -> some View {
        ScrollView {
            if let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
            fileInfoSection
        }
    }

    private func videoPreview(url: URL) -> some View {
        VStack {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
            fileInfoSection
        }
    }

    private func pdfPreview(url: URL) -> some View {
        PDFKitView(url: url)
    }

    private func quickLookPreview(url: URL) -> some View {
        VStack {
            Image(systemName: item.iconName)
                .font(.system(size: 60))
                .foregroundStyle(item.iconColor)
                .padding()

            fileInfoSection
        }
    }

    private var fileInfoView: some View {
        VStack(spacing: 16) {
            Image(systemName: item.iconName)
                .font(.system(size: 60))
                .foregroundStyle(item.iconColor)
            fileInfoSection
        }
    }

    private var fileInfoSection: some View {
        GroupBox("File Info") {
            VStack(alignment: .leading, spacing: 8) {
                infoRow("Name", value: item.name)
                if let size = item.size {
                    infoRow("Size", value: size.formattedFileSize)
                }
                if let modified = item.lastModifiedDateTime {
                    infoRow("Modified", value: modified.shortFormatted)
                }
                if let created = item.createdDateTime {
                    infoRow("Created", value: created.shortFormatted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
        }
        .font(.subheadline)
    }

    private func loadPreview() async {
        isLoading = true
        do {
            if item.name.isVideoFile {
                // For video, get streaming URL instead of downloading
                downloadURL = try await graphService.getDownloadURL(itemId: item.id)
            } else {
                // Download file for preview
                localFileURL = try await graphService.downloadItem(item: item)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// PDFKit wrapper for SwiftUI
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
