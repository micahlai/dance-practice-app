import SwiftUI

/// First-run and replayable tour of the practice controls.
struct OnboardingOverlay: View {
    let dismiss: () -> Void

    @State private var stepIndex = 0

    private let steps = OnboardingStep.all

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(spacing: 20) {
                HStack {
                    Text("Controls")
                        .font(.headline)
                    Spacer()
                    Text("\(stepIndex + 1) of \(steps.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close help")
                }

                ProgressView(value: Double(stepIndex + 1), total: Double(steps.count))
                    .tint(.accentColor)

                VStack(spacing: 14) {
                    Image(systemName: currentStep.icon)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(height: 48)

                    if let location = currentStep.location {
                        Text(location)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(currentStep.title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text(currentStep.detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 180)
                .id(stepIndex)
                .transition(.opacity)

                HStack(spacing: 12) {
                    Button("Back") {
                        move(to: stepIndex - 1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(stepIndex == 0)

                    Spacer()

                    Button(stepIndex == steps.count - 1 ? "Done" : "Next") {
                        if stepIndex == steps.count - 1 {
                            dismiss()
                        } else {
                            move(to: stepIndex + 1)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(.white.opacity(0.12))
            }
            .padding(24)
        }
        .transition(.opacity)
    }

    private var currentStep: OnboardingStep {
        steps[stepIndex]
    }

    private func move(to index: Int) {
        withAnimation(.easeInOut(duration: 0.16)) {
            stepIndex = min(max(index, 0), steps.count - 1)
        }
    }
}

private struct OnboardingStep {
    let icon: String
    let location: String?
    let title: String
    let detail: String

    static let all: [OnboardingStep] = [
        OnboardingStep(
            icon: "play.fill",
            location: "Bottom-left",
            title: "Playback",
            detail: "Tap Play or Pause to control the video. The time display shows your current position and the video's duration. When practice speed is below 100%, tap the percentage to reset it."
        ),
        OnboardingStep(
            icon: "metronome",
            location: "Above the scrub wheel",
            title: "Beat grid",
            detail: "Tap the BPM value to type a tempo, use the small adjustment buttons to fine-tune it, and tap Set 1 to align count 1 with the playhead."
        ),
        OnboardingStep(
            icon: "hand.draw.fill",
            location: "Bottom-center",
            title: "Scrub wheel",
            detail: "Drag the wheel to move through the video with inertia, and pinch to zoom the timeline. Drag the handle above it to resize or collapse the wheel."
        ),
        OnboardingStep(
            icon: "flag.fill",
            location: "Left side",
            title: "Markers and loops",
            detail: "Tap the chevron to hide the marker panel. Tap Mark to save the current moment, then tap a marker to jump back to it. Use A and B to choose a section and enable the loop to repeat it. The Home button above the video returns to recent videos."
        ),
        OnboardingStep(
            icon: "speedometer",
            location: "Right edge",
            title: "Practice speed",
            detail: "Hold the right edge and drag up or down to change speed. Move horizontally to switch between 1% and 5% increments. Tap the floating percentage on the video to return to 100%."
        ),
        OnboardingStep(
            icon: "metronome",
            location: "Bottom-right · 1 of 6",
            title: "Count-off",
            detail: "The metronome button adds a counted lead-in before playback so you can get ready and enter on the beat."
        ),
        OnboardingStep(
            icon: "music.note",
            location: "Bottom-right · 2 of 6",
            title: "Music count-in",
            detail: "The music-note button uses the video's audio during the lead-in. It becomes available after Count-off is turned on."
        ),
        OnboardingStep(
            icon: "headphones",
            location: "Bottom-right · 3 of 6",
            title: "Audio calibration",
            detail: "The headphones button opens latency calibration. Use it with Bluetooth headphones or speakers when beat markers look slightly ahead of the sound."
        ),
        OnboardingStep(
            icon: "slowmo",
            location: "Bottom-right · 4 of 6",
            title: "Smooth motion",
            detail: "The slow-motion button blends adjacent frames while scrubbing or playing below full speed for smoother movement."
        ),
        OnboardingStep(
            icon: "waveform",
            location: "Bottom-right · 5 of 6",
            title: "Waveform",
            detail: "The waveform button shows or hides the audio waveform behind the scrub wheel."
        ),
        OnboardingStep(
            icon: "speaker.wave.2.fill",
            location: "Bottom-right · 6 of 6",
            title: "Scrub audio",
            detail: "The speaker button turns sound while scrubbing on or off. Use silent scrubbing when you only want visual positioning."
        )
    ]
}
