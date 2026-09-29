import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A movie received from the Photos picker, copied to a temp file.
struct ImportedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString)-\(received.file.lastPathComponent)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return ImportedMovie(url: dest)
        }
    }
}

struct ImportView: View {
    @Environment(AppState.self) private var app

    @State private var photoItem: PhotosPickerItem?
    @State private var showsFileImporter = false
    @State private var recentVideos: [RecentVideo] = []
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "figure.dance")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Load a video to practice")
                .font(.title2.weight(.semibold))

            HStack(spacing: 16) {
                PhotosPicker(selection: $photoItem, matching: .videos) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showsFileImporter = true
                } label: {
                    Label("Files", systemImage: "folder")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)

            recentVideosSection
        }
        .padding(40)
        .disabled(isImporting)
        .overlay {
            if isImporting {
                ProgressView("Importing…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.movie, .video]
        ) { result in
            handleFileImport(result)
        }
        .onChange(of: photoItem) { _, item in
            importPhoto(item)
        }
        .onAppear {
            recentVideos = DocumentStore.loadRecent()
        }
        .alert(
            "Import failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var recentVideosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent videos")
                .font(.headline)

            if recentVideos.isEmpty {
                Text("Videos you open will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(recentVideos) { recent in
                        Button {
                            app.load(recent.document, restored: recent.state)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.tint)
                                    .frame(width: 36, height: 36)
                                    .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(recent.document.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text(recent.lastOpened, format: .relative(presentation: .named))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHint("Opens this video for practice")
                    }
                }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func importPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        runImport {
            guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                throw MediaImportError.notPlayable
            }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            return try await MediaImporter.importVideo(from: movie.url, title: "Photos video")
        }
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        runImport {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                throw MediaImportError.notPlayable
            }
            defer { url.stopAccessingSecurityScopedResource() }
            return try await MediaImporter.importVideo(
                from: url,
                title: url.deletingPathExtension().lastPathComponent
            )
        }
    }

    private func runImport(_ work: @escaping () async throws -> VideoDocument) {
        isImporting = true
        Task {
            do {
                app.load(try await work())
                photoItem = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }
}
