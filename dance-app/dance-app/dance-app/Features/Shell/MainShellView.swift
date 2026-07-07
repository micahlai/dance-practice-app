import SwiftUI

/// App-level shell: import screen when nothing is loaded, practice layout
/// otherwise.
struct MainShellView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if app.document != nil {
                PracticeView()
            } else {
                ImportView()
            }
        }
        .preferredColorScheme(.dark)
        .task {
            app.restoreLastSession()
        }
    }
}

/// The main practice layout: marker rail left, video center, speed zone
/// right, transport strip bottom. Rails are M5/M4 placeholders.
struct PracticeView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 0) {
            MarkerRail()
            VStack(spacing: 0) {
                ZoomableVideoView(player: app.playback.player)
                BeatControlsRow()
                ScrubWheelView()
                    .frame(height: 140)
                TransportBar()
            }
            SpeedRail()
        }
    }
}

/// Left rail: eject button now; marker snap buttons arrive in M5.
struct MarkerRail: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 16) {
            Button {
                app.closeDocument()
            } label: {
                Image(systemName: "eject.fill")
                    .font(.title3)
            }
            .padding(.top, 12)

            Spacer()

            ForEach(0..<4) { _ in
                Circle()
                    .strokeBorder(.white.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 36, height: 36)
            }

            Spacer()
        }
        .frame(width: 72)
        .background(.black.opacity(0.6))
    }
}

/// Right rail: reserved zone for the M4 hold-and-drag speed gesture.
struct SpeedRail: View {
    var body: some View {
        VStack {
            Spacer()
            Text("SPEED")
                .font(.caption2.weight(.semibold))
                .kerning(2)
                .foregroundStyle(.white.opacity(0.25))
                .rotationEffect(.degrees(90))
                .fixedSize()
            Spacer()
        }
        .frame(width: 56)
        .background(.black.opacity(0.6))
    }
}

/// Bottom transport: play/pause, time, and timeline toggles. Seeking lives
/// in the scrub wheel above.
struct TransportBar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 16) {
            Button {
                app.playback.togglePlayPause()
            } label: {
                Image(systemName: app.playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 44)
            }

            Text("\(timeString(app.playback.currentTime)) / \(timeString(app.playback.duration))")
                .monospacedDigit()
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            toggle(
                "waveform",
                isOn: app.showWaveform,
                hint: "Waveform"
            ) { app.showWaveform.toggle() }

            toggle(
                app.scrubAudioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                isOn: app.scrubAudioEnabled,
                hint: "Scrub audio"
            ) { app.scrubAudioEnabled.toggle() }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(.ultraThinMaterial)
    }

    private func toggle(
        _ systemImage: String,
        isOn: Bool,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .frame(width: 36)
        }
        .accessibilityLabel(hint)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
