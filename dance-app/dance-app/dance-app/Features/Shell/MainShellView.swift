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

/// Bottom transport: play/pause + seek slider. This strip is the stand-in
/// for the M3 scrub wheel.
struct TransportBar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 16) {
            Button {
                app.playback.togglePlayPause()
            } label: {
                Image(systemName: app.playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
                    .frame(width: 44)
            }

            Text(timeString(app.playback.currentTime))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { app.playback.currentTime },
                    set: { app.playback.seek(to: $0) }
                ),
                in: 0...max(app.playback.duration, 0.01)
            )

            Text(timeString(app.playback.duration))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .frame(height: 96)
        .background(.ultraThinMaterial)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
