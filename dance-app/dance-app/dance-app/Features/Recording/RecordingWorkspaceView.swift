import AVKit
import SwiftUI

struct RecordingWorkspaceView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var recorder = TakeRecorder()
    @State private var selectedTab = 0
    @State private var showDiscard = false
    @State private var reviewPlayer: AVPlayer?
    @State private var reviewTask: Task<Void, Never>?
    @State private var reviewURL: URL?

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                recordingTab
                    .tabItem { Label("Record", systemImage: "record.circle") }
                    .tag(0)
                TakeLibraryView()
                    .tabItem { Label("Drafts", systemImage: "square.stack") }
                    .tag(1)
            }
            .navigationTitle(selectedTab == 0 ? "Record a take" : "Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back to practice", systemImage: "chevron.left") {
                        if recorder.phase == .review { showDiscard = true } else { dismiss() }
                    }
                    .disabled(recorder.isActive || recorder.isSaving)
                }
            }
            .confirmationDialog("Discard this unsaved take?", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("Discard take and leave", role: .destructive) {
                    recorder.discard()
                    dismiss()
                }
                Button("Keep reviewing", role: .cancel) {}
            }
            .alert(
                "Recording",
                isPresented: Binding(
                    get: { recorder.errorMessage != nil },
                    set: { if !$0 { recorder.errorMessage = nil } })
            ) {
                if !recorder.cameraReady {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(recorder.errorMessage ?? "")
            }
            .task {
                recorder.load(
                    document: app.document, grid: app.beats.grid, playhead: app.playback.currentTime,
                    rate: app.playback.rate, metronome: app.beatClickMode)
                if app.document == nil { selectedTab = 1 } else { await recorder.prepareCamera() }
            }
            .onChange(of: recorder.pendingURL) { _, url in
                clearReview()
                guard url != nil else { return }
                reviewTask = Task {
                    do {
                        let rendered = try await recorder.renderPendingTake()
                        guard !Task.isCancelled else {
                            try? FileManager.default.removeItem(at: rendered)
                            return
                        }
                        reviewURL = rendered
                        reviewPlayer = AVPlayer(url: rendered)
                    } catch is CancellationError {} catch {
                        // Keep the raw take reviewable and saveable even if
                        // composition/export fails (e.g. low disk space).
                        if !Task.isCancelled {
                            reviewPlayer = url.map { AVPlayer(url: $0) }
                            recorder.errorMessage =
                                "Couldn't prepare the full preview. You can still review the camera video and save your draft. \(error.localizedDescription)"
                        }
                    }
                }
            }
            .onChange(of: selectedTab) { old, new in
                if recorder.isActive || recorder.isSaving {
                    selectedTab = old
                    return
                }
                if new == 1 {
                    recorder.suspend()
                    reviewPlayer?.pause()
                } else if app.document != nil {
                    Task { await recorder.prepareCamera() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    recorder.suspend()
                    reviewPlayer?.pause()
                } else if selectedTab == 0, app.document != nil {
                    Task { await recorder.prepareCamera() }
                }
            }
            .onDisappear {
                recorder.suspend()
                clearReview()
            }
            .interactiveDismissDisabled(recorder.isActive || recorder.phase == .review || recorder.isSaving)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var recordingTab: some View {
        if app.document == nil {
            ContentUnavailableView(
                "Choose a reference video", systemImage: "film",
                description: Text("Open a video from the home page, then press Recording next to Help."))
        } else {
            GeometryReader { geometry in
                if geometry.size.width >= 900 {
                    HStack(spacing: 0) {
                        VStack(spacing: 16) {
                            stage
                            transport
                        }.padding(24)
                        settingsPanel.frame(width: 340)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            stage.frame(height: max(260, geometry.size.height * 0.46))
                            transport
                            settingsContents
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.black)
        }
    }

    private var stage: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if recorder.phase == .review {
                    if let reviewPlayer { VideoPlayer(player: reviewPlayer) } else { ProgressView("Preparing take preview…") }
                } else if recorder.settings.layout == .sideBySide {
                    HStack(spacing: 8) {
                        cameraSurface
                        TakePlayerSurface(player: recorder.reference.player)
                            .overlay(alignment: .bottomLeading) { stageLabel("Reference") }
                    }
                } else {
                    cameraSurface
                    if recorder.settings.layout == .pictureInPicture {
                        TakePlayerSurface(player: recorder.reference.player)
                            .frame(width: geometry.size.width * 0.28, height: geometry.size.height * 0.28)
                            .background(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.5)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(16)
                    }
                }
                if let label = recorder.countLabel {
                    Text(label)
                        .font(.system(size: 96, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 12)
                        .allowsHitTesting(false)
                }
                if recorder.phase == .recording {
                    Label("REC · \(recorder.elapsed.formatted(.number.precision(.fractionLength(1))))s", systemImage: "record.circle.fill")
                        .font(.headline.monospacedDigit())
                        .padding(12)
                        .background(.black.opacity(0.75), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(16)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.18)))
        }
    }

    private var cameraSurface: some View {
        ZStack {
            TakeCameraPreview(session: recorder.camera.session)
            if !recorder.cameraReady {
                VStack(spacing: 16) {
                    Image(systemName: "video.slash").font(.largeTitle)
                    Text(recorder.phase == .preparing ? "Preparing camera…" : "Camera unavailable")
                    if recorder.phase == .preparing {
                        ProgressView()
                    } else {
                        Button("Try again") { Task { await recorder.prepareCamera() } }
                            .buttonStyle(.bordered).controlSize(.large)
                    }
                }
                .padding(24)
                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .overlay(alignment: .bottomLeading) { stageLabel("You") }
    }

    private func stageLabel(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).padding(8)
            .background(.black.opacity(0.7), in: Capsule()).padding(12)
    }

    @ViewBuilder private var transport: some View {
        if recorder.phase == .review {
            VStack(spacing: 12) {
                Text("Review your take")
                    .font(.headline)
                Text("Save this take as a draft, or discard it and try again.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: 16) {
                    Button("Discard", role: .destructive) {
                        clearReview()
                        recorder.discard()
                    }
                    .buttonStyle(.bordered)
                    Button {
                        reviewPlayer?.pause()
                        Task { if await recorder.saveDraft() != nil { selectedTab = 1 } }
                    } label: {
                        if recorder.isSaving {
                            ProgressView("Saving draft…")
                        } else {
                            Label("Save as draft", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
                .disabled(recorder.isSaving)
            }
        } else {
            HStack(spacing: 24) {
                Button {
                    Task { await recorder.flipCamera() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title2).frame(width: 48, height: 48)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Switch camera")
                .disabled(!recorder.cameraReady || recorder.isActive)
                Button {
                    if recorder.phase == .recording || recorder.phase == .starting {
                        recorder.stop()
                    } else {
                        let orientation =
                            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.interfaceOrientation
                            ?? .portrait
                        recorder.start(orientation: orientation)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: recorder.isActive ? "stop.fill" : "record.circle.fill")
                        Text(
                            recorder.phase == .finishing
                                ? "Finishing…"
                                : recorder.phase == .starting ? "Cancel start" : recorder.phase == .recording ? "Stop take" : "Record take")
                    }
                    .font(.headline)
                    .frame(minWidth: 180, minHeight: 48)
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(!recorder.cameraReady || recorder.phase == .finishing || recorder.reference.duration <= 0)
            }
        }
    }

    private var settingsPanel: some View {
        ScrollView { settingsContents }
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Portrait uses the workspace's outer scroll view; landscape gives
    /// these controls their own bounded rail. Avoid nested vertical scrolls.
    private var settingsContents: some View {
        @Bindable var recorder = recorder
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(app.document?.title ?? "Reference").font(.title3.weight(.semibold))
                Text("Set up your take before recording.").foregroundStyle(.secondary)
            }
            timingControl("Music starts at", value: $recorder.settings.musicStart)
            Toggle("Count-in", isOn: $recorder.settings.countInEnabled)
                .disabled(app.beats.grid == nil)
            if app.beats.grid == nil {
                Text("Set the beat grid in practice to enable count-in and metronome.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if recorder.settings.countInEnabled {
                timingControl("Count-in lands at", value: $recorder.settings.countInTime)
                Text(
                    "Music can start before the counts. The count-in follows the reference video's 1–8 grid and lands on the nearest beat."
                )
                .font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recording speed").font(.headline)
                    Spacer()
                    Text("\(Int((recorder.settings.rate * 100).rounded()))%")
                        .monospacedDigit()
                }
                Slider(value: $recorder.settings.rate, in: 0.25...1, step: 0.01)
                    .accessibilityLabel("Recording speed")
                HStack {
                    ForEach([0.5, 0.75, 1.0], id: \.self) { rate in
                        Button("\(Int(rate * 100))%") { recorder.settings.rate = rate }
                            .buttonStyle(.bordered).frame(minHeight: 44)
                    }
                }
                Toggle("Adjust final video to 100%", isOn: $recorder.settings.adjustToNormalSpeed)
                Text(
                    recorder.settings.adjustToNormalSpeed && recorder.settings.rate != 1
                        ? "The final take is sped up so the music plays at its original speed."
                        : "The final take keeps your recording speed."
                )
                .font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Reference layout").font(.headline)
                Picker("Reference layout", selection: $recorder.settings.layout) {
                    ForEach(ReferenceLayout.allCases) { layout in Text(layout.title).tag(layout) }
                }
                .pickerStyle(.menu).frame(minHeight: 44)
                Text("This layout is included in your exported video.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Picker("Metronome", selection: $recorder.settings.metronome) {
                Text("Off").tag(BeatClickMode.off)
                Text("1–8").tag(BeatClickMode.beats)
                Text("1 & 2 &").tag(BeatClickMode.beatsAndHalf)
            }
            .pickerStyle(.segmented).disabled(app.beats.grid == nil)
            Text("Metronome is a live guide. Drafts use clean reference audio.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(24)
        .disabled(recorder.isActive || recorder.phase == .review || recorder.isSaving)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func timingControl(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            HStack {
                TextField("Seconds", value: value, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                    .accessibilityLabel("\(title), seconds").frame(minHeight: 44)
                Text("s").foregroundStyle(.secondary)
                Button("Playhead") { value.wrappedValue = app.playback.currentTime }
                    .buttonStyle(.bordered).frame(minHeight: 44)
            }
            Slider(
                value: Binding(
                    get: { min(max(value.wrappedValue, 0), max(0.1, recorder.reference.duration)) },
                    set: { value.wrappedValue = $0 }),
                in: 0...max(0.1, recorder.reference.duration), step: 0.01
            )
            .accessibilityLabel(title)
            .onChange(of: value.wrappedValue) { _, time in
                if !recorder.isActive, title == "Music starts at" { recorder.reference.seek(to: time) }
            }
        }
    }

    private func clearReview() {
        reviewTask?.cancel()
        reviewTask = nil
        reviewPlayer?.pause()
        reviewPlayer = nil
        if let reviewURL { try? FileManager.default.removeItem(at: reviewURL) }
        reviewURL = nil
    }
}

struct TakePlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.layerPlayer.player = player
        return view
    }
    func updateUIView(_ view: Surface, context: Context) { view.layerPlayer.player = player }
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var layerPlayer: AVPlayerLayer { layer as! AVPlayerLayer }
        override init(frame: CGRect) {
            super.init(frame: frame)
            layerPlayer.videoGravity = .resizeAspect
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}
