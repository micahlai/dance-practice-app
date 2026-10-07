import AVKit
import SwiftUI

struct TakeLibraryView: View {
    /// Home uses the same complete take library inside its own scroll view.
    var embedded = false
    @State private var drafts: [TakeDraft] = []
    @State private var sizes: [UUID: Int64] = [:]
    @State private var selection: TakeDraft?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if embedded { contents }
            else { ScrollView { contents.padding(24) } }
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .takeLibraryDidChange)) { _ in reload() }
        .sheet(item: $selection, onDismiss: reload) { draft in TakeDraftDetailView(draft: draft) }
        .alert("Couldn't load takes", isPresented: Binding(get: { errorMessage != nil },
                                                          set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Takes").font(.title2.weight(.bold))
                    Spacer()
                    Text("\(drafts.count) drafts · \(storageString(sizes.values.reduce(0, +))) total")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Takes").font(.title2.weight(.bold))
                    Text("\(drafts.count) drafts · \(storageString(sizes.values.reduce(0, +))) total")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if drafts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No saved takes yet", systemImage: "video")
                        .font(.headline)
                    Text("Record a take, then save it as a draft to preview and export it here.")
                        .foregroundStyle(.secondary)
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                    ForEach(drafts) { draft in
                        Button { selection = draft } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    TakeThumbnail(url: try? draft.cameraURL)
                                        .overlay(alignment: .bottomLeading) { thumbnailLabel("Take") }
                                    TakeThumbnail(url: try? draft.referenceURL, time: draft.settings.musicStart)
                                        .overlay(alignment: .bottomLeading) { thumbnailLabel("Reference") }
                                }
                                .frame(height: 156)
                                Text(draft.title).font(.headline).lineLimit(2)
                                Text("Based on \(draft.referenceTitle)")
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                HStack {
                                    Text("\(draft.finalDuration.formatted(.number.precision(.fractionLength(1))))s")
                                    Text("· \(Int(draft.settings.rate * 100))% take")
                                    Spacer(minLength: 0)
                                }
                                .font(.caption).foregroundStyle(.secondary)
                                Label(storageString(sizes[draft.id] ?? 0), systemImage: "internaldrive")
                                    .font(.subheadline)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(draft.title), based on \(draft.referenceTitle), \(storageString(sizes[draft.id] ?? 0))")
                        .accessibilityHint("Preview, export, or delete this draft")
                    }
                }
            }
        }
    }

    private func thumbnailLabel(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white)
            .padding(6).background(.black.opacity(0.75), in: Capsule()).padding(8)
    }

    private func reload() {
        do {
            drafts = try TakeDraftStore.load()
            sizes = Dictionary(uniqueKeysWithValues: drafts.map { ($0.id, TakeDraftStore.storageBytes(for: $0)) })
        } catch { errorMessage = error.localizedDescription }
    }
}

struct TakeThumbnail: View {
    let url: URL?
    var time: Double = 0
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else { Image(systemName: "film").foregroundStyle(.secondary) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { return }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 480)
            if let result = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)) {
                image = UIImage(cgImage: result.image)
            }
        }
    }
}

func storageString(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private struct SharedTake: Identifiable { let id = UUID(); let url: URL }

struct TakeDraftDetailView: View {
    let draft: TakeDraft
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var exportedURL: URL?
    @State private var sharedTake: SharedTake?
    @State private var exportTask: Task<Void, Never>?
    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let player { VideoPlayer(player: player).frame(height: 400) }
                    else if isExporting {
                        ProgressView("Preparing draft preview…").frame(maxWidth: .infinity).frame(height: 300)
                        Button("Cancel preparation", role: .cancel) { exportTask?.cancel() }.buttonStyle(.bordered)
                    } else {
                        ContentUnavailableView("Preview unavailable", systemImage: "video.slash",
                                               description: Text(errorMessage ?? "Prepare the video to review and share."))
                    }
                    Text(draft.title).font(.title2.weight(.bold))
                    HStack(alignment: .top, spacing: 16) {
                        TakeThumbnail(url: try? draft.referenceURL, time: draft.settings.musicStart)
                            .frame(width: 104, height: 128)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Based on \(draft.referenceTitle)").font(.headline)
                            Text(draft.settings.layout.title)
                            Text("Recorded at \(Int(draft.settings.rate * 100))% · \(draft.settings.adjustToNormalSpeed ? "Adjusted to 100%" : "Recording speed kept")")
                            Text("Music starts at \(draft.settings.musicStart.formatted(.number.precision(.fractionLength(2))))s")
                            Label(storageString(TakeDraftStore.storageBytes(for: draft)), systemImage: "internaldrive")
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 16) {
                        Button {
                            player?.pause()
                            if let exportedURL { sharedTake = SharedTake(url: exportedURL) }
                            else { prepareExport() }
                        } label: { Label(exportedURL == nil ? "Prepare video" : "Export / Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.borderedProminent).disabled(isExporting)
                        Button("Delete draft", role: .destructive) { confirmDelete = true }
                            .buttonStyle(.bordered).disabled(isExporting)
                    }
                    .controlSize(.large)
                    Text("Storage includes your camera take, reference video, and settings. Export opens Apple's share sheet for Save Video, Files, AirDrop, and other apps.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }
                .padding(24)
            }
            .navigationTitle("Take preview").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete this draft and its reference copy?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete draft", role: .destructive) {
                    do {
                        player?.pause()
                        try TakeDraftStore.delete(draft)
                        NotificationCenter.default.post(name: .takeLibraryDidChange, object: nil)
                        dismiss()
                    }
                    catch { errorMessage = error.localizedDescription }
                }
            } message: { Text("This frees \(storageString(TakeDraftStore.storageBytes(for: draft))). The original practice video remains in your library.") }
            .sheet(item: $sharedTake) { item in TakeShareSheet(url: item.url) }
            .onAppear { prepareExport() }
            .onDisappear {
                player?.pause()
                exportTask?.cancel()
                if let exportedURL { try? FileManager.default.removeItem(at: exportedURL) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func prepareExport() {
        guard !isExporting, exportedURL == nil else { return }
        isExporting = true
        errorMessage = nil
        exportTask = Task {
            do {
                let url = try await TakeExporter.export(draft)
                guard !Task.isCancelled else { try? FileManager.default.removeItem(at: url); isExporting = false; return }
                exportedURL = url
                player = AVPlayer(url: url)
            } catch is CancellationError { /* Saved sources remain intact. */ }
            catch { errorMessage = error.localizedDescription }
            isExporting = false
        }
    }
}

private struct TakeShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
