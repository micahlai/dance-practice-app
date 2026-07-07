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
    @State private var linkText = ""
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

            HStack(spacing: 12) {
                TextField("Paste a direct video link…", text: $linkText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .frame(maxWidth: 420)
                    .onSubmit(importLink)
                Button("Load", action: importLink)
                    .buttonStyle(.bordered)
                    .disabled(trimmedLinkURL == nil)
            }

            Text("TikTok / YouTube page links aren't supported yet — use a direct video file URL, Photos, or Files.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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

    private var trimmedLinkURL: URL? {
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
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

    private func importLink() {
        guard let url = trimmedLinkURL else { return }
        runImport {
            try await MediaImporter.importVideo(fromLink: url)
        }
    }

    private func runImport(_ work: @escaping () async throws -> VideoDocument) {
        isImporting = true
        Task {
            do {
                app.load(try await work())
                photoItem = nil
                linkText = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }
}
