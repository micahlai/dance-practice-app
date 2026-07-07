import SwiftUI

/// BPM / "set the 1" controls. Sits above the scrub wheel, which renders
/// the waveform and beat grid.
struct BeatControlsRow: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            if let grid = app.beats.grid {
                Text(String(format: "%.1f BPM", grid.bpm))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 92, alignment: .leading)

                adjust("−1") { $0.bpm -= 1 }
                adjust("−.1") { $0.bpm -= 0.1 }
                adjust("+.1") { $0.bpm += 0.1 }
                adjust("+1") { $0.bpm += 1 }
                adjust("½×") { $0.bpm /= 2 }
                adjust("2×") { $0.bpm *= 2 }

                Divider().frame(height: 20)

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

                Spacer()

                if let detected = app.beats.detectedBPM,
                   let confidence = app.beats.detectionConfidence {
                    Text(String(format: "detected %.1f · %.0f%%", detected, confidence * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if app.beats.isAnalyzing {
                Text("Detecting tempo…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Button("Start grid at 120 BPM") {
                    app.updateGrid { _ in }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.caption)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.black.opacity(0.4))
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
