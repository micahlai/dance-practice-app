import SwiftUI

/// Waveform strip with the beat grid overlaid, plus the "set the 1" / BPM
/// controls. Lives between the video and the transport bar; the strip is
/// the precursor to the M3 scrub wheel.
struct BeatWorkbenchView: View {
    var body: some View {
        VStack(spacing: 0) {
            WaveformStripView()
                .frame(height: 84)
            BeatControlsRow()
        }
        .background(.black.opacity(0.4))
    }
}

struct WaveformStripView: View {
    @Environment(AppState.self) private var app

    /// Seconds of audio shown across the strip.
    private let window: Double = 8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            Canvas { context, size in
                draw(in: context, size: size)
            }
        }
        .overlay {
            if app.beats.isAnalyzing && app.beats.waveform == nil {
                ProgressView("Analyzing audio…")
                    .font(.caption)
            }
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let start = app.playback.currentTime - window / 2
        func x(_ time: Double) -> CGFloat {
            CGFloat((time - start) / window) * size.width
        }

        if let waveform = app.beats.waveform {
            var path = Path()
            let midY = size.height / 2
            let firstBin = max(0, Int(start * waveform.binsPerSecond))
            let lastBin = min(waveform.peaks.count - 1, Int((start + window) * waveform.binsPerSecond))
            if lastBin >= firstBin {
                for bin in firstBin...lastBin {
                    let time = Double(bin) / waveform.binsPerSecond
                    let px = x(time)
                    let h = max(1, CGFloat(waveform.peaks[bin]) * size.height * 0.9)
                    path.move(to: CGPoint(x: px, y: midY - h / 2))
                    path.addLine(to: CGPoint(x: px, y: midY + h / 2))
                }
                context.stroke(path, with: .color(.white.opacity(0.45)), lineWidth: 1.5)
            }
        }

        if let grid = app.beats.grid {
            for tick in grid.ticks(in: start...(start + window)) {
                let px = x(tick.time)
                if tick.isAnd {
                    var path = Path()
                    path.move(to: CGPoint(x: px, y: 0))
                    path.addLine(to: CGPoint(x: px, y: size.height * 0.2))
                    context.stroke(path, with: .color(.white.opacity(0.3)), lineWidth: 1)
                } else {
                    let isOne = tick.count == 1
                    var path = Path()
                    path.move(to: CGPoint(x: px, y: 0))
                    path.addLine(to: CGPoint(x: px, y: size.height))
                    context.stroke(
                        path,
                        with: .color(isOne ? Color.accentColor.opacity(0.9) : .white.opacity(0.35)),
                        lineWidth: isOne ? 2 : 1
                    )
                    context.draw(
                        Text(tick.label)
                            .font(.caption2.weight(isOne ? .bold : .regular))
                            .foregroundStyle(isOne ? Color.accentColor : .white.opacity(0.7)),
                        at: CGPoint(x: px + 7, y: 8)
                    )
                }
            }
        }

        // Playhead, fixed at center.
        var playhead = Path()
        playhead.move(to: CGPoint(x: size.width / 2, y: 0))
        playhead.addLine(to: CGPoint(x: size.width / 2, y: size.height))
        context.stroke(playhead, with: .color(.red), lineWidth: 1.5)
    }
}

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
