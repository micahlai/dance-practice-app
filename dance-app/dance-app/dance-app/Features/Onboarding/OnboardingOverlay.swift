import SwiftUI

/// First-run coach marks for the non-obvious gestures. Shown once over the
/// practice layout, dismissed with "Got it" (persisted via `@AppStorage`).
struct OnboardingOverlay: View {
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            // Callouts sit over the zones they describe: rails left/right,
            // wheel along the bottom.
            HStack {
                callout(
                    icon: "flag.fill",
                    title: "Markers",
                    detail: "Tap + to drop a cue, or long-press the wheel. Tap a marker to jump; set A/B to loop a section.",
                    align: .leading
                )
                Spacer()
                callout(
                    icon: "speedometer",
                    title: "Speed",
                    detail: "Hold the right edge and drag up/down to change speed. Slide in first for 5% steps.",
                    align: .trailing
                )
            }
            .padding(.horizontal, 24)

            VStack {
                Spacer()
                callout(
                    icon: "hand.draw.fill",
                    title: "Scrub wheel",
                    detail: "Drag to scrub with inertia; pinch to zoom the timeline. Playing follows along.",
                    align: .center
                )
                .frame(maxWidth: 460)
                .padding(.bottom, 168)

                Button(action: dismiss) {
                    Text("Got it")
                        .font(.headline)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 40)
            }
        }
        .transition(.opacity)
    }

    private func callout(
        icon: String,
        title: String,
        detail: String,
        align: HorizontalAlignment
    ) -> some View {
        VStack(alignment: align, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.white)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(align == .trailing ? .trailing : .leading)
        }
        .frame(maxWidth: 300, alignment: align == .center ? .center : (align == .trailing ? .trailing : .leading))
        .padding(16)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}
