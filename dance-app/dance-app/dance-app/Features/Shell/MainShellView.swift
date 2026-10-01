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

/// The main practice layout. Adapts to orientation / aspect ratio: in
/// landscape both side rails flank the video; in portrait the video takes
/// the width and the speed rail collapses (the speed gesture stays live on
/// the video's right edge).
struct PracticeView: View {
    @Environment(AppState.self) private var app
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("markerRailCollapsed") private var markerRailCollapsed = false
    @AppStorage("wheelHeight") private var wheelHeight = 140.0
    @AppStorage("wheelCollapsed") private var wheelCollapsed = false
    @State private var showOnboarding = false
    @State private var compactMarkerPresented = false

    private let wheelRange: ClosedRange<Double> = 64...340
    private let collapsedWheelHeight = 40.0

    private var effectiveWheelHeight: Double {
        wheelCollapsed ? collapsedWheelHeight : min(max(wheelHeight, wheelRange.lowerBound), wheelRange.upperBound)
    }

    var body: some View {
        @Bindable var app = app
        GeometryReader { geo in
            let portrait = geo.size.height > geo.size.width
            let compactLayout = geo.size.width < 900

            if compactLayout {
                ZStack(alignment: .leading) {
                    centerColumn

                    if compactMarkerPresented {
                        MarkerRail {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                compactMarkerPresented = false
                            }
                        }
                        .transition(.move(edge: .leading))
                    } else {
                        CollapsedMarkerRail {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                compactMarkerPresented = true
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 0) {
                    if markerRailCollapsed {
                        CollapsedMarkerRail {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                markerRailCollapsed = false
                            }
                        }
                    } else {
                        MarkerRail {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                markerRailCollapsed = true
                            }
                        }
                    }
                    centerColumn
                    // The speed panel disappears in portrait; its gesture
                    // remains available along the video's right edge.
                    if !portrait {
                        SpeedRail()
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: markerRailCollapsed)
            }
        }
        .overlay {
            if showOnboarding {
                OnboardingOverlay {
                    hasSeenOnboarding = true
                    withAnimation { showOnboarding = false }
                }
            }
        }
        .sheet(isPresented: $app.showCalibrationSheet) {
            CalibrationView()
                .environment(app)
                .presentationDetents([.medium, .large])
        }
        .alert("New audio output", isPresented: $app.showCalibrationPrompt) {
            Button("Calibrate") { app.showCalibrationSheet = true }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Beat markers may drift over \(app.calibrationRouteName). Calibrate so they feel on beat.")
        }
        .task {
            if !hasSeenOnboarding { showOnboarding = true }
        }
    }

    /// Video + controls, shared by both layouts. The video area flexes to
    /// fill; the wheel/transport keep fixed heights.
    private var centerColumn: some View {
        VStack(spacing: 0) {
            ZoomableVideoView(
                player: app.playback.player,
                interpolationActive: app.frameInterpolationActive
            )
                .overlay { VideoOverlays() }
                // The whole right edge of the video is the speed-gesture grab
                // zone (widened from the 56 pt rail) — and the only one in
                // portrait, where the rail is gone.
                .overlay(alignment: .trailing) {
                    SpeedGestureCatcher()
                        .frame(width: 44)
                }
                // Reset-to-100% sits at the bottom-right, above the wheel.
                .overlay(alignment: .bottomTrailing) {
                    SpeedResetButton()
                }
                .overlay(alignment: .topLeading) {
                    Button {
                        app.closeDocument()
                    } label: {
                        Image(systemName: "house.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.58), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.18)))
                    }
                    .padding(16)
                    .accessibilityLabel("Return home")
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation { showOnboarding = true }
                    } label: {
                        Image(systemName: "questionmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.58), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.18)))
                    }
                    .padding(16)
                    .accessibilityLabel("Show control guide")
                }
            BeatControlsRow()
            WheelHandle(
                height: $wheelHeight,
                collapsed: $wheelCollapsed,
                range: wheelRange,
                collapsedHeight: collapsedWheelHeight
            )
            ScrubWheelView()
                .frame(height: effectiveWheelHeight)
            TransportBar()
        }
    }
}

/// Transient HUDs over the video: count-off numbers and the speed readout
/// while the right-edge gesture is active.
struct VideoOverlays: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            if let label = app.countOffLabel {
                Text(label)
                    .font(.system(size: 140, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 12)
                    .transition(.scale.combined(with: .opacity))
                    .id(label)
            } else if app.speedGestureActive {
                // Rides just left of the finger.
                GeometryReader { geo in
                    let frame = geo.frame(in: .global)
                    let point = app.speedGesturePoint ?? CGPoint(x: frame.maxX, y: frame.midY)
                    let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
                    Text("\(Int((app.playback.rate * 100).rounded()))%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
                        .position(
                            x: min(max(local.x - 52, 40), geo.size.width - 40),
                            y: min(max(local.y, 22), geo.size.height - 22)
                        )
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: app.countOffLabel)
        .allowsHitTesting(false)
    }
}

/// Bottom transport: play/pause, time, and timeline toggles. Seeking lives
/// in the scrub wheel above.
struct TransportBar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 700

            if compact {
                ScrollView(.horizontal, showsIndicators: false) {
                    controlsRow(includeSpacer: false)
                        .padding(.horizontal, 12)
                }
            } else {
                controlsRow(includeSpacer: true)
                    .padding(.horizontal, 20)
            }
        }
        .frame(height: 56)
        .background(.ultraThinMaterial)
    }

    private func controlsRow(includeSpacer: Bool) -> some View {
        HStack(spacing: includeSpacer ? 16 : 12) {
            Button {
                app.togglePlayPause()
            } label: {
                Image(systemName: app.playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 44)
            }

            Text("\(timeString(app.playback.currentTime)) / \(timeString(app.playback.duration))")
                .monospacedDigit()
                .font(.callout)
                .foregroundStyle(.secondary)

            if app.playback.rate < 1 {
                Button {
                    app.playback.setRate(1.0)
                    app.saveState()
                } label: {
                    Text("\(Int((app.playback.rate * 100).rounded()))%")
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityLabel("Reset speed to 100%")
            }

            if includeSpacer {
                Spacer()
            }

            toggle(
                "metronome",
                isOn: app.countOffEnabled,
                hint: "Count-off"
            ) { app.countOffEnabled.toggle(); app.saveState() }

            toggle(
                "music.note",
                isOn: app.countOffEnabled && app.countInMusicEnabled,
                hint: "Play music during count-off"
            ) { app.countInMusicEnabled.toggle(); app.saveState() }
                .disabled(!app.countOffEnabled)
                .opacity(app.countOffEnabled ? 1 : 0.4)

            Button {
                app.showCalibrationSheet = true
            } label: {
                Image(systemName: "headphones")
                    .font(.body)
                    .foregroundStyle(app.latencyOffset != 0 ? Color.accentColor : .secondary)
                    .frame(width: 36)
            }
            .accessibilityLabel("Calibrate beat latency")

            toggle(
                "slowmo",
                isOn: app.frameInterpolationEnabled,
                hint: "Smooth motion while scrubbing or slowed (frame blending)"
            ) { app.frameInterpolationEnabled.toggle() }

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
        .frame(minHeight: 56)
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
