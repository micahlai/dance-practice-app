import SwiftUI

/// Slim grabber bar above the scrub wheel: drag it up/down to resize the
/// wheel (and its waveform), or tap the chevron to collapse to a compact
/// strip. Both the size and collapsed state persist.
struct WheelHandle: View {
    @Binding var height: Double
    @Binding var collapsed: Bool
    let range: ClosedRange<Double>
    /// The compact height used while collapsed (for the drag baseline).
    let collapsedHeight: Double

    @State private var dragBaseline: Double?

    var body: some View {
        HStack(spacing: 0) {
            // Wide drag region — resize the wheel.
            Color.clear
                .frame(maxWidth: .infinity)
                .overlay {
                    Capsule()
                        .fill(.white.opacity(0.35))
                        .frame(width: 44, height: 5)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragBaseline == nil {
                                dragBaseline = collapsed ? collapsedHeight : height
                            }
                            collapsed = false
                            // Drag up (negative translation) grows the wheel.
                            let base = dragBaseline ?? height
                            height = min(max(base - value.translation.height, range.lowerBound), range.upperBound)
                        }
                        .onEnded { _ in dragBaseline = nil }
                )
                .accessibilityLabel("Resize wheel")

            // Collapse / expand.
            Button {
                withAnimation(.easeOut(duration: 0.2)) { collapsed.toggle() }
            } label: {
                Image(systemName: collapsed ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 24)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(collapsed ? "Expand wheel" : "Collapse wheel")
        }
        .frame(height: 22)
        .background(.black.opacity(0.5))
    }
}
