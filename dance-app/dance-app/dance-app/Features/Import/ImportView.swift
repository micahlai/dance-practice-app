import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
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
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Image("ChoreoLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 132, height: 132)
                        .accessibilityHidden(true)

                    Text("Choreo Jogger")
                        .font(.largeTitle.weight(.bold))

                    Text("Load a video to practice")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

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

                Button { app.openRecording() } label: {
                    Label("Recording & drafts", systemImage: "video.badge.plus")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)

                TakeLibraryView(embedded: true)
                    .frame(maxWidth: 1000)
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .disabled(isImporting)
        .overlay {
            if isImporting {
                VStack(spacing: 12) {
                    Image("ChoreoLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                        .accessibilityHidden(true)
                    ProgressView("Importing…")
                }
                    .padding(22)
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
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(recentVideos) { recent in
                            Button {
                                app.load(recent.document, restored: recent.state)
                            } label: {
                                VStack(spacing: 7) {
                                    VideoThumbnail(videoURL: recent.document.videoURL)
                                        .frame(width: 96, height: 128)

                                    Text(recent.lastOpened, format: .relative(presentation: .named))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 96)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this video for practice")
                        }
                    }
                    .padding(.vertical, 2)
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
            return try await MediaImporter.importVideo(from: movie.url, title: "Video")
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

private struct VideoThumbnail: View {
    let videoURL: URL

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(.white.opacity(0.08))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Image(systemName: "film")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.12))
        }
        .task(id: videoURL) {
            image = await VideoThumbnailLoader.image(for: videoURL)
        }
        .accessibilityHidden(true)
    }
}

private enum VideoThumbnailLoader {
    private static let cache = NSCache<NSURL, UIImage>()

    static func image(for videoURL: URL) async -> UIImage? {
        if let cached = cache.object(forKey: videoURL as NSURL) {
            return cached
        }

        let asset = AVURLAsset(url: videoURL)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite else { return nil }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 352, height: 208)

        let middle = CMTime(
            seconds: max(durationSeconds / 2, 0),
            preferredTimescale: 600
        )

        guard let frame = try? await generator.image(at: middle).image else { return nil }
        let image = UIImage(cgImage: frame)
        cache.setObject(image, forKey: videoURL as NSURL)
        return image
    }
}
