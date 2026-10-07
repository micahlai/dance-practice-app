import SwiftUI

/// Selection stays local until Done. The preview does not operate the
/// practice transport, count-off, metronome, marker editing, or A/B looping.
struct RecordingTimingPicker: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let target: RecordingTimingTarget
    let videoURL: URL
    let initialTime: Double
    let musicStart: Double
    let duration: Double
    let rate: Double
    let onSelection: (Double) -> Void
    @State private var playback = PlaybackEngine()
    @State private var wheel = TimingWheelHandle()

    private var selection: Double? {
        target.selection(at: playback.currentTime, musicStart: musicStart, duration: duration, grid: app.beats.grid)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 16) {
                    TakePlayerSurface(player: playback.player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Reference video preview")
                    VStack(spacing: 8) {
                        Text(selection.map { "\($0.formatted(.number.precision(.fractionLength(2)))) s" } ?? "No available beat")
                            .font(.title2.monospacedDigit().weight(.semibold))
                        if let grid = app.beats.grid, let selection {
                            Text("Beat \(grid.count(at: selection))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    RecordingTimingWheel(playback: playback, duration: duration, handle: wheel)
                        .frame(height: min(180, max(110, geometry.size.height * 0.24)))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Timing jog wheel")
                        .accessibilityHint("Drag to seek, pinch to zoom. Adjustment buttons are available below.")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { previewButton; adjustmentButtons }
                        VStack(spacing: 8) { previewButton; adjustmentButtons }
                    }
                    Text(target == .countIn
                         ? "Drag to choose a beat at or after music start. Markers and A/B loop are visual guides only."
                         : "Drag to choose music start; pinch to zoom. Markers and A/B loop are visual guides only.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if target == .countIn, selection == nil {
                        Text("No beat remains after music start. Choose an earlier music start first.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                .padding(16)
            }
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { stopPreview(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        stopPreview()
                        if let selection { onSelection(selection) }
                        dismiss()
                    }
                    .disabled(selection == nil)
                }
            }
            .task {
                playback.load(url: videoURL)
                playback.setRate(rate)
                playback.seek(to: target.selection(at: initialTime, musicStart: musicStart,
                    duration: duration, grid: app.beats.grid) ?? min(max(initialTime, 0), duration))
            }
            .onDisappear { stopPreview() }
            .onChange(of: appScenePhase) { _, phase in
                if phase != .active { stopPreview() }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @Environment(\.scenePhase) private var appScenePhase

    private var previewButton: some View {
        Button {
            let wasPlaying = playback.isPlaying
            stopPreview()
            if !wasPlaying { playback.play() }
        } label: {
            Label(playback.isPlaying ? "Pause" : "Preview", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(playback.duration <= 0)
    }

    private var adjustmentButtons: some View {
        HStack(spacing: 8) {
            if let grid = app.beats.grid {
                adjustButton("−beat", seconds: -grid.beatInterval, label: "Previous beat")
                adjustButton("+beat", seconds: grid.beatInterval, label: "Next beat")
            }
            if target == .musicStart {
                adjustButton("−0.1s", seconds: -0.1, label: "Back one tenth of a second")
                adjustButton("+0.1s", seconds: 0.1, label: "Forward one tenth of a second")
            }
        }
        .buttonStyle(.bordered)
    }

    private func adjustButton(_ title: String, seconds: Double, label: String) -> some View {
        Button(title) {
            stopPreview()
            let candidate = (selection ?? playback.currentTime) + seconds
            playback.seek(to: target.selection(at: candidate, musicStart: musicStart,
                duration: duration, grid: app.beats.grid) ?? min(max(candidate, 0), duration))
        }
        .frame(minHeight: 44)
        .accessibilityLabel(label)
    }

    private func stopPreview() {
        wheel.view?.stopScrubbing()
        playback.endScrub()
        playback.pause()
    }
}

/// Non-observed weak handle lets buttons stop wheel inertia before committing
/// a selection; it does not introduce a second owner of the playhead.
final class TimingWheelHandle {
    weak var view: WheelView?
}

private struct RecordingTimingWheel: UIViewRepresentable {
    @Environment(AppState.self) private var app
    let playback: PlaybackEngine
    let duration: Double
    let handle: TimingWheelHandle

    func makeUIView(context: Context) -> WheelView {
        let view = WheelView()
        handle.view = view
        connect(view)
        return view
    }

    func updateUIView(_ view: WheelView, context: Context) { connect(view) }

    private func connect(_ view: WheelView) {
        let app = app
        view.dataSource = {
            WheelRenderState(time: playback.currentTime, duration: duration,
                waveform: app.beats.waveform, grid: app.beats.grid, showWaveform: true,
                countInTarget: nil, markers: app.markers.markers, loop: app.markers.loopRange,
                loopActive: app.markers.loopEnabled, beatVisualOffset: 0)
        }
        view.onScrubBegin = { playback.beginScrub() }
        view.onScrubMove = { playback.scrub(to: $0) }
        view.onScrubEnd = { playback.endScrub() }
        view.onLongPress = nil
    }

    static func dismantleUIView(_ view: WheelView, coordinator: ()) {
        // onDisappear ends/pauses the local engine; do not resume audio
        // during UIKit teardown if dismissal interrupts an inertial scrub.
        view.onScrubEnd = nil
        view.stopScrubbing()
        view.dataSource = nil
        view.onScrubBegin = nil
        view.onScrubMove = nil
        view.onScrubEnd = nil
    }
}
