import SwiftUI

enum HelpTarget: String, Hashable {
    case beatClicks, tempo, beatAlignment, playback, scrubWheel, markers, speed
    case countOff, musicCountIn, calibration, smoothMotion, waveform, musicAudio, scrubAudio
}

private struct ActiveHelpTargetKey: EnvironmentKey {
    static let defaultValue: HelpTarget? = nil
}

extension EnvironmentValues {
    var activeHelpTarget: HelpTarget? {
        get { self[ActiveHelpTargetKey.self] }
        set { self[ActiveHelpTargetKey.self] = newValue }
    }
}

struct HelpTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [HelpTarget: Anchor<CGRect>] = [:]

    static func reduce(value: inout [HelpTarget: Anchor<CGRect>], nextValue: () -> [HelpTarget: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    func helpTarget(_ target: HelpTarget) -> some View {
        anchorPreference(key: HelpTargetPreferenceKey.self, value: .bounds) { [target: $0] }
    }
}

struct HelpTourStep {
    let target: HelpTarget
    let icon: String
    let eyebrow: String
    let title: String
    let detail: String

    static let all: [HelpTourStep] = [
        .init(target: .beatClicks, icon: "waveform.path.ecg", eyebrow: "BEAT SETUP · 1 OF 3", title: "First, check the pulse", detail: "Tap Beat clicks once, then press Play. Listen through several parts of the song: every click should land on the music's steady pulse, not just match at the beginning."),
        .init(target: .tempo, icon: "metronome", eyebrow: "BEAT SETUP · 2 OF 3", title: "Fix tempo drift", detail: "If clicks gradually move away from the music, the BPM is wrong. Tap the BPM to enter it, use ±1 or ±.1 to fine-tune, and try ½× or 2× when detection chose half or double time."),
        .init(target: .beatAlignment, icon: "scope", eyebrow: "BEAT SETUP · 3 OF 3", title: "Align count 1", detail: "If the clicks stay evenly spaced but all feel early or late, pause on a clear downbeat and tap Set 1. Use ±10 ms for tiny corrections or the beat arrows to shift a full beat."),
        .init(target: .playback, icon: "play.fill", eyebrow: "PLAYBACK", title: "Play and pause", detail: "Tap the center of the video for quick play or pause, or use this button. The time beside it shows your position and the video's full duration."),
        .init(target: .scrubWheel, icon: "hand.draw.fill", eyebrow: "TIMELINE", title: "Find an exact moment", detail: "Drag the wheel to move through the video with inertia, and pinch to zoom the timeline. Drag the handle above it to resize or collapse the wheel."),
        .init(target: .markers, icon: "flag.fill", eyebrow: "LEFT SIDE", title: "Save marks and loops", detail: "Tap Mark to save the current moment. Set A and B around a section, then turn on Loop to repeat it. Use the chevron to hide or show this panel."),
        .init(target: .speed, icon: "speedometer", eyebrow: "RIGHT EDGE", title: "Change practice speed", detail: "Hold anywhere in the Change speed area, then drag vertically. Follow the 5% arrow for larger steps; once there, follow the 1% arrow to return to fine control. Tap the floating percentage to return to 100%."),
        .init(target: .countOff, icon: "metronome", eyebrow: "BOTTOM CONTROLS · 1 OF 8", title: "Count-off", detail: "Turn on a counted lead-in before playback so you have time to get ready and enter on the beat."),
        .init(target: .musicCountIn, icon: "music.note", eyebrow: "BOTTOM CONTROLS · 2 OF 8", title: "Music count-in", detail: "Include the video's music during the lead-in. This button becomes available after Count-off is turned on."),
        .init(target: .beatClicks, icon: "waveform.path.ecg", eyebrow: "BOTTOM CONTROLS · 3 OF 8", title: "Beat clicks", detail: "Tap once for one click per beat, again for clicks on the beat and half count (&), and a third time to turn clicks off. The badge shows the active mode."),
        .init(target: .calibration, icon: "headphones", eyebrow: "BOTTOM CONTROLS · 4 OF 8", title: "Audio calibration", detail: "Open latency calibration when Bluetooth headphones or speakers make clicks sound slightly ahead of or behind the beat markers."),
        .init(target: .smoothMotion, icon: "slowmo", eyebrow: "BOTTOM CONTROLS · 5 OF 8", title: "Smooth motion", detail: "Blend adjacent frames while scrubbing or playing below full speed for smoother-looking movement."),
        .init(target: .waveform, icon: "waveform", eyebrow: "BOTTOM CONTROLS · 6 OF 8", title: "Waveform", detail: "Show or hide the audio waveform behind the scrub wheel to make musical events easier to find."),
        .init(target: .musicAudio, icon: "speaker.slash.fill", eyebrow: "BOTTOM CONTROLS · 7 OF 8", title: "Music audio", detail: "Mute or restore the video's music without changing beat clicks or the separate sound used while scrubbing."),
        .init(target: .scrubAudio, icon: "opticaldisc", eyebrow: "BOTTOM CONTROLS · 8 OF 8", title: "Scrub audio", detail: "The optical-disc button controls only the sound heard while turning the scrub wheel. The filled disc means scrub sound is on.")
    ]
}

struct OnboardingOverlay: View {
    @Binding var stepIndex: Int
    let targets: [HelpTarget: Anchor<CGRect>]
    let dismiss: () -> Void

    private let steps = HelpTourStep.all

    var body: some View {
        GeometryReader { geometry in
            let targetFrame = resolvedTarget(in: geometry)
            let cardAbove = targetFrame.midY > geometry.size.height * 0.52
            let shortScreen = geometry.size.height < 500
            let cardWidth = min(shortScreen ? 640 : 420, geometry.size.width - 28)

            ZStack {
                SpotlightMask(cutout: targetFrame.insetBy(dx: -7, dy: -7))
                    .fill(Color.black.opacity(0.76), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()
                    .onTapGesture { }

                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .frame(width: targetFrame.width + 14, height: targetFrame.height + 14)
                    .position(x: targetFrame.midX, y: targetFrame.midY)
                    .shadow(color: Color.accentColor.opacity(0.75), radius: 9)
                    .allowsHitTesting(false)

                CoachConnector(
                    start: connectorStart(in: geometry, cardAbove: cardAbove, shortScreen: shortScreen),
                    end: CGPoint(x: targetFrame.midX, y: cardAbove ? targetFrame.minY - 9 : targetFrame.maxY + 9)
                )
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)

                coachCard
                    .frame(maxWidth: cardWidth)
                    .padding(.horizontal, 14)
                    .frame(maxHeight: .infinity, alignment: cardAbove ? .top : .bottom)
                    .padding(.top, cardAbove ? geometry.safeAreaInsets.top + 14 : 0)
                    .padding(.bottom, cardAbove ? 0 : geometry.safeAreaInsets.bottom + 14)
            }
        }
        .transition(.opacity)
    }

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: currentStep.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(currentStep.eyebrow)
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(Color.accentColor)
                    Text(currentStep.title)
                        .font(.title3.weight(.bold))
                }
                Spacer(minLength: 4)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close help")
            }

            Text(currentStep.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: Double(stepIndex + 1), total: Double(steps.count))
                .tint(.accentColor)

            HStack(spacing: 12) {
                Text("\(stepIndex + 1) of \(steps.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Back") { move(to: stepIndex - 1) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(stepIndex == 0)
                Button(stepIndex == steps.count - 1 ? "Done" : "Next") {
                    if stepIndex == steps.count - 1 { dismiss() } else { move(to: stepIndex + 1) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.14)) }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .id(stepIndex)
    }

    private var currentStep: HelpTourStep {
        steps[min(max(stepIndex, 0), steps.count - 1)]
    }

    private func resolvedTarget(in geometry: GeometryProxy) -> CGRect {
        targets[currentStep.target].map { geometry[$0] }
            ?? CGRect(x: geometry.size.width / 2 - 50, y: geometry.size.height - 74, width: 100, height: 44)
    }

    private func connectorStart(in geometry: GeometryProxy, cardAbove: Bool, shortScreen: Bool) -> CGPoint {
        let estimatedCardHeight: CGFloat = shortScreen ? 158 : 250
        return CGPoint(
            x: geometry.size.width / 2,
            y: cardAbove
                ? geometry.safeAreaInsets.top + estimatedCardHeight
                : geometry.size.height - geometry.safeAreaInsets.bottom - estimatedCardHeight
        )
    }

    private func move(to index: Int) {
        withAnimation(.easeInOut(duration: 0.22)) {
            stepIndex = min(max(index, 0), steps.count - 1)
        }
    }
}

private struct SpotlightMask: Shape {
    let cutout: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: cutout, cornerSize: CGSize(width: 12, height: 12))
        return path
    }
}

private struct CoachConnector: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        let bend = CGPoint(x: end.x, y: start.y + (end.y - start.y) * 0.55)
        path.addLine(to: bend)
        path.addLine(to: end)

        let angle = atan2(end.y - bend.y, end.x - bend.x)
        for offset in [CGFloat.pi * 0.82, -CGFloat.pi * 0.82] {
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x + cos(angle + offset) * 10, y: end.y + sin(angle + offset) * 10))
        }
        return path
    }
}
