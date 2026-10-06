import SwiftUI

/// BPM / "set the 1" controls. Sits above the scrub wheel, which renders
/// the waveform and beat grid.
struct BeatControlsRow: View {
    @Environment(AppState.self) private var app
    @Environment(\.activeHelpTarget) private var activeHelpTarget
    @State private var bpmText = ""
    @State private var isEditingBPM = false

    var body: some View {
        // Horizontally scrollable so the full control set stays reachable at
        // any width (narrow portrait / split view), never clipped.
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    content
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
            }
            .onChange(of: activeHelpTarget, initial: true) { _, target in
                guard target == .tempo || target == .beatAlignment else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
        .frame(height: 44)
        .background(.black.opacity(0.4))
    }

    @ViewBuilder private var content: some View {
        if let grid = app.beats.grid {
            HStack(spacing: 10) {
                // Tap to type an exact BPM.
                Button {
                    bpmText = String(format: "%.1f", grid.bpm)
                    isEditingBPM = true
                } label: {
                    Text(String(format: "%.1f BPM", grid.bpm))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .frame(width: 92, alignment: .leading)
                .popover(isPresented: $isEditingBPM) {
                    HStack(spacing: 10) {
                        TextField("BPM", text: $bpmText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .onSubmit(commitTypedBPM)
                        Button("Set", action: commitTypedBPM)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    .padding(12)
                    .presentationCompactAdaptation(.popover)
                }

                adjust("−1") { $0.bpm -= 1 }
                adjust("−.1") { $0.bpm -= 0.1 }
                adjust("+.1") { $0.bpm += 0.1 }
                adjust("+1") { $0.bpm += 1 }
                adjust("½×") { $0.bpm /= 2 }
                adjust("2×") { $0.bpm *= 2 }
            }
            .id(HelpTarget.tempo)
            .helpTarget(.tempo)

            Divider().frame(height: 20)

            HStack(spacing: 10) {
                Button("Set 1") {
                    let now = app.playback.currentTime
                    app.updateGrid { $0.firstBeatTime = now }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .font(.caption)

                adjust("−10ms") { $0.firstBeatTime -= 0.01 }
                adjust("+10ms") { $0.firstBeatTime += 0.01 }
                adjust("◀ beat") { $0.firstBeatTime -= $0.beatInterval }
                adjust("beat ▶") { $0.firstBeatTime += $0.beatInterval }
            }
            .id(HelpTarget.beatAlignment)
            .helpTarget(.beatAlignment)

            Divider().frame(height: 20)

                // Tap to snap the grid back to the detected tempo.
                if let detected = app.beats.detectedBPM,
                   let confidence = app.beats.detectionConfidence {
                    Button {
                        app.updateGrid { $0.bpm = detected }
                    } label: {
                        Text(String(format: "detected %.1f · %.0f%%", detected, confidence * 100))
                            .font(.caption)
                            .foregroundStyle(
                                abs(grid.bpm - detected) < 0.05 ? Color.secondary : Color.accentColor
                            )
                    }
                    .disabled(abs(grid.bpm - detected) < 0.05)
                    .accessibilityLabel("Use detected BPM")
                }
            } else if app.beats.isAnalyzing {
                Text("Detecting tempo…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Start grid at 120 BPM") {
                    app.updateGrid { _ in }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.caption)
                .id(HelpTarget.tempo)
                .helpTarget(.tempo)
                .helpTarget(.beatAlignment)
            }
    }

    private func commitTypedBPM() {
        if let value = Double(bpmText.replacingOccurrences(of: ",", with: ".")), value > 0 {
            app.updateGrid { $0.bpm = value }
        }
        isEditingBPM = false
    }

    private func adjust(_ label: String, _ transform: @escaping (inout BeatGrid) -> Void) -> some View {
        Button(label) {
            app.updateGrid(transform)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.caption)
    }
}
