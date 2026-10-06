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
    @State private var helpStepIndex = 0
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
                compactColumn
            } else {
                HStack(spacing: 0) {
                    if markerRailCollapsed {
                        CollapsedMarkerRail {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                markerRailCollapsed = false
                            }
                        }
                        .helpTarget(.markers)
                    } else {
                        MarkerRail {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                markerRailCollapsed = true
                            }
                        }
                        .helpTarget(.markers)
                    }
                    centerColumn
                    // The speed panel disappears in portrait; its gesture
                    // remains available along the video's right edge.
                    if !portrait {
                        SpeedRail()
                            .helpTarget(.speed)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: markerRailCollapsed)
            }
        }
        .environment(\.activeHelpTarget, activeHelpTarget)
        .overlayPreferenceValue(HelpTargetPreferenceKey.self) { targets in
            if showOnboarding {
                OnboardingOverlay(stepIndex: $helpStepIndex, targets: targets) {
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
            if !hasSeenOnboarding {
                helpStepIndex = 0
                showOnboarding = true
            }
        }
    }

    private var activeHelpTarget: HelpTarget? {
        guard showOnboarding, HelpTourStep.all.indices.contains(helpStepIndex) else { return nil }
        return HelpTourStep.all[helpStepIndex].target
    }

    /// Video + controls, shared by both layouts. The video area flexes to
    /// fill; the wheel/transport keep fixed heights.
    private var centerColumn: some View {
        VStack(spacing: 0) {
            videoStage
            jogControls
        }
    }

    /// On narrow screens the marker rail is constrained to the stage above
    /// the jog controls, so it never covers the wheel or transport buttons.
    private var compactColumn: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                videoSurface

                if compactMarkerPresented {
                    MarkerRail {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            compactMarkerPresented = false
                        }
                    }
                    .padding(.top, 60)
                    .helpTarget(.markers)
                    .transition(.move(edge: .leading))
                } else {
                    CollapsedMarkerRail {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            compactMarkerPresented = true
                        }
                    }
                    .padding(.top, 60)
                    .helpTarget(.markers)
                }
            }
            BeatControlsRow()
            jogControls
        }
    }

    private var videoStage: some View {
        VStack(spacing: 0) {
            videoSurface
            BeatControlsRow()
        }
    }

    private var videoSurface: some View {
        ZoomableVideoView(
            player: app.playback.player,
            interpolationActive: app.frameInterpolationActive,
            onCenterTap: { app.togglePlayPause() }
        )
            .overlay { VideoOverlays() }
            // The whole right edge of the video is the speed-gesture grab
            // zone (widened from the 56 pt rail) — and the only one in
            // portrait, where the rail is gone.
            .overlay(alignment: .trailing) {
                SpeedGestureCatcher()
                    .frame(width: 72)
                    .helpTarget(.speed)
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
                    helpStepIndex = 0
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
    }

    private var jogControls: some View {
        VStack(spacing: 0) {
            WheelHandle(
                height: $wheelHeight,
                collapsed: $wheelCollapsed,
                range: wheelRange,
                collapsedHeight: collapsedWheelHeight
            )
            ScrubWheelView()
                .frame(height: effectiveWheelHeight)
                .helpTarget(.scrubWheel)
            TransportBar()
        }
    }
}

/// Video HUDs: count-off numbers and the persistent speed affordance.
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
            } else {
                SpeedGestureIndicator()
            }
        }
        .animation(.easeOut(duration: 0.12), value: app.countOffLabel)
        .allowsHitTesting(false)
    }
}

private struct SpeedGestureIndicator: View {
    @Environment(AppState.self) private var app

    var body: some View {
        GeometryReader { geometry in
            let globalFrame = geometry.frame(in: .global)
            let restingPoint = CGPoint(x: geometry.size.width - 28, y: geometry.size.height / 2)
            let touchPoint = localPoint(app.speedGesturePoint, in: globalFrame) ?? restingPoint
            let current = CGPoint(
                x: min(max(touchPoint.x, 18), geometry.size.width - 18),
                y: min(max(touchPoint.y, 18), geometry.size.height - 18)
            )

            ZStack(alignment: .topLeading) {
                if !app.speedGestureActive {
                    Text("Change\nspeed")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.trailing)
                        .shadow(color: .black.opacity(0.8), radius: 3)
                        .position(
                            x: max(restingPoint.x - 47, 32),
                            y: restingPoint.y
                        )
                        .transition(.opacity)
                }

                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 5))
                    .shadow(color: .black.opacity(0.55), radius: 5)
                    .position(app.speedGestureActive ? current : restingPoint)
                    .animation(.spring(response: 0.22, dampingFraction: 0.78), value: app.speedGestureActive)

                if app.speedGestureActive {
                    Text("\(Int((app.playback.rate * 100).rounded()))%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 10))
                        .position(
                            x: min(max(current.x, 48), geometry.size.width - 48),
                            y: min(max(current.y - 42, 28), geometry.size.height - 28)
                        )

                    precisionCue
                        .position(
                            x: cueX(for: current.x, width: geometry.size.width),
                            y: min(max(current.y + 34, 22), geometry.size.height - 22)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
    }

    @ViewBuilder
    private var precisionCue: some View {
        if app.speedGestureIncrementPercent == 1 {
            HStack(spacing: 5) {
                Image(systemName: "arrow.left")
                Text("5%")
            }
            .modifier(PrecisionCueStyle())
        } else {
            HStack(spacing: 5) {
                Text("1%")
                Image(systemName: "arrow.right")
            }
            .modifier(PrecisionCueStyle())
        }
    }

    private func cueX(for currentX: CGFloat, width: CGFloat) -> CGFloat {
        let offset: CGFloat = app.speedGestureIncrementPercent == 1 ? -48 : 48
        return min(max(currentX + offset, 34), width - 34)
    }

    private func localPoint(_ point: CGPoint?, in frame: CGRect) -> CGPoint? {
        guard let point else { return nil }
        return CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
    }
}

private struct PrecisionCueStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.black.opacity(0.72), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
    }
}

/// Bottom transport: play/pause, time, and timeline toggles. Seeking lives
/// in the scrub wheel above.
struct TransportBar: View {
    @Environment(AppState.self) private var app
    @Environment(\.activeHelpTarget) private var activeHelpTarget

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 700

            if compact {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        controlsRow(includeSpacer: false)
                            .padding(.horizontal, 12)
                    }
                    .onChange(of: activeHelpTarget, initial: true) { _, target in
                        guard let target, transportTargets.contains(target) else { return }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
                }
            } else {
                controlsRow(includeSpacer: true)
                    .padding(.horizontal, 20)
            }
        }
        .frame(height: 64)
        .background(.ultraThinMaterial)
    }

    private func controlsRow(includeSpacer: Bool) -> some View {
        HStack(spacing: includeSpacer ? 16 : 12) {
            Button {
                app.togglePlayPause()
            } label: {
                transportIcon(
                    app.playback.isPlaying ? "pause.fill" : "play.fill",
                    label: app.playback.isPlaying ? "Pause" : "Play",
                    isOn: true,
                    prominent: true
                )
            }
            .id(HelpTarget.playback)
            .helpTarget(.playback)

            Text("\(timeString(app.playback.currentTime)) / \(timeString(app.playback.duration))")
                .monospacedDigit()
                .font(.callout)
                .foregroundStyle(.secondary)

            if app.playback.rate < 1 {
                Button {
                    app.setPlaybackRate(1.0)
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
                .id(HelpTarget.countOff)
                .helpTarget(.countOff)

            toggle(
                "music.note",
                isOn: app.countOffEnabled && app.countInMusicEnabled,
                hint: "Play music during count-off"
            ) { app.countInMusicEnabled.toggle(); app.saveState() }
                .disabled(!app.countOffEnabled)
                .opacity(app.countOffEnabled ? 1 : 0.4)
                .id(HelpTarget.musicCountIn)
                .helpTarget(.musicCountIn)

            beatClickButton
                .id(HelpTarget.beatClicks)
                .helpTarget(.beatClicks)

            Button {
                app.showCalibrationSheet = true
            } label: {
                transportIcon(
                    "headphones",
                    label: "Sync",
                    isOn: app.latencyOffset != 0
                )
            }
            .accessibilityLabel("Calibrate beat latency")
            .id(HelpTarget.calibration)
            .helpTarget(.calibration)

            toggle(
                "slowmo",
                isOn: app.frameInterpolationEnabled,
                hint: "Smooth motion while scrubbing or slowed (frame blending)"
            ) { app.frameInterpolationEnabled.toggle() }
                .id(HelpTarget.smoothMotion)
                .helpTarget(.smoothMotion)

            toggle(
                "waveform",
                isOn: app.showWaveform,
                hint: "Waveform"
            ) { app.showWaveform.toggle() }
                .id(HelpTarget.waveform)
                .helpTarget(.waveform)

            toggle(
                app.musicMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                isOn: !app.musicMuted,
                hint: "Music audio"
            ) { app.musicMuted.toggle() }
                .id(HelpTarget.musicAudio)
                .helpTarget(.musicAudio)

            toggle(
                app.scrubAudioEnabled ? "opticaldisc.fill" : "opticaldisc",
                isOn: app.scrubAudioEnabled,
                hint: "Scrub audio"
            ) { app.scrubAudioEnabled.toggle() }
                .id(HelpTarget.scrubAudio)
                .helpTarget(.scrubAudio)
        }
        .frame(minHeight: 64)
    }

    private func toggle(
        _ systemImage: String,
        isOn: Bool,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            transportIcon(systemImage, label: shortLabel(for: hint), isOn: isOn)
        }
        .accessibilityLabel(hint)
    }

    private var beatClickButton: some View {
        Button {
            app.cycleBeatClickMode()
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.body)
                        .foregroundStyle(app.beatClickMode == .off ? .secondary : Color.accentColor)
                        .frame(width: 40, height: 25)

                    if app.beatClickMode != .off {
                        Text(app.beatClickMode == .beats ? "1" : "&")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Color.accentColor, in: Circle())
                    }
                }
                Text("Clicks")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 48)
        }
        .accessibilityLabel("Beat clicks")
        .accessibilityValue(app.beatClickMode.accessibilityValue)
        .accessibilityHint("Tap to cycle between every beat, beat and half count, and off")
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func transportIcon(
        _ systemImage: String,
        label: String,
        isOn: Bool,
        prominent: Bool = false
    ) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(prominent ? .title3 : .body)
                .frame(height: 25)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(isOn ? Color.accentColor : .secondary)
        .frame(width: prominent ? 46 : 44, height: 48)
    }

    private func shortLabel(for hint: String) -> String {
        switch hint {
        case "Count-off": "Count"
        case "Play music during count-off": "Count-in"
        case "Smooth motion while scrubbing or slowed (frame blending)": "Smooth"
        case "Waveform": "Wave"
        case "Music audio": "Music"
        case "Scrub audio": "Scrub"
        default: hint
        }
    }

    private var transportTargets: Set<HelpTarget> {
        [.beatClicks, .playback, .countOff, .musicCountIn, .calibration, .smoothMotion, .waveform, .musicAudio, .scrubAudio]
    }
}
