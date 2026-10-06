import SwiftUI
import UIKit

/// Right-edge rail: hold and drag inward (left) to slow playback, snapping
/// to 5% increments with a haptic tick per snap. Drag back toward the edge
/// to speed up. The rate holds after release.
struct SpeedRail: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                Spacer()

                Text(ratePercent)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(app.playback.rate < 1 ? Color.accentColor : .white.opacity(0.72))

                Text("\(app.speedGestureIncrementPercent)% increments")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(app.speedGestureActive ? Color.black : Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        app.speedGestureActive ? Color.accentColor : Color.white.opacity(0.12),
                        in: Capsule()
                    )

                Image(systemName: "arrow.up.and.down")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.68))

                Text("Hold and drag for speed change")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)

                Divider()
                    .overlay(.white.opacity(0.12))
                    .frame(width: 72)

                Image(systemName: "arrow.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))

                Text("Move horizontally to change increments")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(.horizontal, 12)
            SpeedGestureCatcher()
        }
        .frame(width: 132)
        .background(.black.opacity(0.6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Speed control, \(ratePercent), \(app.speedGestureIncrementPercent) percent increments. Hold and drag vertically to change speed. Move horizontally to change increments."
        )
    }

    private var ratePercent: String {
        "\(Int((app.playback.rate * 100).rounded()))%"
    }
}

/// Floating reset-to-100% affordance at the video's bottom-right, just above
/// the wheel. Shows the current rate; tapping restores full speed. Hidden at
/// 100% (nothing to reset). Works mid-playback — `setRate` applies live.
struct SpeedResetButton: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if app.playback.rate < 1 {
            Button {
                app.setPlaybackRate(1.0)
                app.saveState()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("\(Int((app.playback.rate * 100).rounded()))%")
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
            }
            .padding([.trailing, .bottom], 16)
            .accessibilityLabel("Reset speed to 100%")
        }
    }
}

/// Transparent gesture layer. UIKit so the drag keeps tracking after the
/// finger leaves the rail (it will — the gesture moves inward across the
/// video).
struct SpeedGestureCatcher: UIViewRepresentable {
    @Environment(AppState.self) private var app

    func makeUIView(context: Context) -> SpeedGestureUIView {
        let view = SpeedGestureUIView()
        connect(view)
        return view
    }

    func updateUIView(_ view: SpeedGestureUIView, context: Context) {
        connect(view)
    }

    private func connect(_ view: SpeedGestureUIView) {
        let app = self.app
        view.currentRate = { app.playback.rate }
        view.onBegin = {
            app.speedGestureActive = true
            app.speedGestureIncrementPercent = 1
        }
        view.onChange = { app.setPlaybackRate($0) }
        view.onIncrementChange = { app.speedGestureIncrementPercent = $0 }
        view.onMove = { app.speedGesturePoint = $0 }
        view.onEnd = {
            app.speedGestureActive = false
            app.speedGestureIncrementPercent = 1
            app.speedGesturePoint = nil
            app.saveState()
        }
    }
}

final class SpeedGestureUIView: UIView {
    var currentRate: (() -> Double)?
    var onBegin: (() -> Void)?
    var onChange: ((Double) -> Void)?
    var onIncrementChange: ((Int) -> Void)?
    /// Finger location in window coordinates, for positioning the HUD.
    var onMove: ((CGPoint) -> Void)?
    var onEnd: (() -> Void)?

    /// Hold to engage; vertical travel changes the rate (up = faster,
    /// down = slower). Horizontal position only selects the increment:
    /// near the rail = 1% steps, slid left past `fineZoneWidth` = 5% steps.
    private enum Zone { case fine, coarse }

    /// Points of vertical travel per 5% step (coarse).
    private let pointsPerCoarseStep: CGFloat = 14
    /// Points of vertical travel per 1% step (fine).
    private let pointsPerFineStep: CGFloat = 8
    /// Inward (leftward) travel beyond this switches to 5% steps.
    private let fineZoneWidth: CGFloat = 20

    private var zone: Zone = .fine
    private var startX: CGFloat = 0
    private var anchorY: CGFloat = 0
    private var anchorRate: Double = 1
    private var lastSnapped: Double = 1
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress))
        press.minimumPressDuration = 0.12
        addGestureRecognizer(press)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func handlePress(_ press: UILongPressGestureRecognizer) {
        let location = press.location(in: self)
        switch press.state {
        case .began:
            startX = location.x
            anchorY = location.y
            anchorRate = currentRate?() ?? 1
            lastSnapped = anchorRate
            zone = .fine
            haptics.prepare()
            onBegin?()
            onIncrementChange?(1)
            onMove?(convert(location, to: nil))
        case .changed:
            let newZone: Zone = (startX - location.x) > fineZoneWidth ? .coarse : .fine
            if newZone != zone {
                // Re-anchor on zone change so the rate never jumps.
                zone = newZone
                anchorY = location.y
                anchorRate = lastSnapped
                onIncrementChange?(zone == .coarse ? 5 : 1)
            }

            // Vertical travel changes the rate; up (smaller y) = faster.
            let step = zone == .coarse ? 0.05 : 0.01
            let pointsPerStep = zone == .coarse ? pointsPerCoarseStep : pointsPerFineStep
            let raw = anchorRate - Double((location.y - anchorY) / pointsPerStep) * step
            var snapped = (raw / step).rounded() * step
            snapped = min(max(snapped, 0.25), 1.0)
            if abs(snapped - lastSnapped) > 0.001 {
                lastSnapped = snapped
                haptics.impactOccurred(intensity: zone == .coarse ? 1.0 : 0.6)
                onChange?(snapped)
            }
            onMove?(convert(location, to: nil))
        case .ended, .cancelled, .failed:
            onEnd?()
        default:
            break
        }
    }
}
