import SwiftUI
import UIKit

/// Everything the wheel needs to draw one frame.
struct WheelRenderState {
    let time: Double
    let duration: Double
    let waveform: WaveformData?
    let grid: BeatGrid?
    let showWaveform: Bool
    /// Non-nil during a music count-in: the wheel holds centered here (red
    /// playhead) while a yellow playhead shows `time` catching up.
    let countInTarget: Double?
    let markers: [Marker]
    /// A/B loop bounds, and whether looping is currently armed.
    let loop: ClosedRange<Double>?
    let loopActive: Bool
    /// Latency compensation (seconds): beat ticks draw shifted by this so
    /// they cross the playhead when the (delayed) audio is actually heard.
    let beatVisualOffset: Double
}

/// The DJ-board timeline: pan to scrub (with inertia), pinch to zoom the
/// time scale. UIKit-backed — gesture velocity and per-frame drawing need
/// more control than SwiftUI gestures give.
struct ScrubWheelView: UIViewRepresentable {
    @Environment(AppState.self) private var app

    func makeUIView(context: Context) -> WheelView {
        let view = WheelView()
        connect(view)
        return view
    }

    func updateUIView(_ view: WheelView, context: Context) {
        connect(view)
    }

    private func connect(_ view: WheelView) {
        let app = self.app
        view.dataSource = {
            WheelRenderState(
                time: app.playback.currentTime,
                duration: app.playback.duration,
                waveform: app.beats.waveform,
                grid: app.beats.grid,
                showWaveform: app.showWaveform,
                countInTarget: app.countInTargetTime,
                markers: app.markers.markers,
                loop: app.markers.loopRange,
                loopActive: app.markers.loopEnabled,
                beatVisualOffset: app.latencyOffset
            )
        }
        view.onScrubBegin = { app.beginScrub() }
        view.onScrubMove = { app.scrubMove(to: $0) }
        view.onScrubEnd = { app.endScrub() }
        view.onLongPress = { app.addMarkerAtPlayhead() }
    }
}

final class WheelView: UIView {
    var dataSource: (() -> WheelRenderState)?
    var onScrubBegin: (() -> Void)?
    var onScrubMove: ((Double) -> Void)?
    var onScrubEnd: (() -> Void)?
    /// Stationary press-and-hold: drop a marker at the playhead.
    var onLongPress: (() -> Void)?
    private let markerHaptics = UIImpactFeedbackGenerator(style: .medium)

    private enum Mode {
        case follow    // rendering the transport's playhead
        case dragging  // finger down
        case coasting  // released with velocity, inertia active
    }

    private var mode: Mode = .follow
    private var scrubTime: Double = 0
    /// Coast velocity in media-seconds per real second.
    private var velocity: Double = 0
    private var secondsPerScreen: Double = 8
    private var pinchStartSeconds: Double = 8
    private var displayLink: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isOpaque = true
        contentMode = .redraw

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        addGestureRecognizer(pinch)
        // A deliberate hold (no drag) drops a marker; a quick tap-drag still
        // scrubs because the pan fires first once the finger moves.
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.4
        addGestureRecognizer(longPress)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        if window != nil {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    // MARK: - Gestures

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard bounds.width > 0 else { return }
        let secondsPerPoint = secondsPerScreen / Double(bounds.width)
        switch pan.state {
        case .began:
            // Touching during a coast keeps the same scrub session.
            if mode == .follow {
                scrubTime = dataSource?().time ?? 0
                onScrubBegin?()
            }
            velocity = 0
            mode = .dragging
            pan.setTranslation(.zero, in: self)
        case .changed:
            let dx = pan.translation(in: self).x
            pan.setTranslation(.zero, in: self)
            // Dragging the tape right pulls the playhead back.
            scrubTime = clampToMedia(scrubTime - Double(dx) * secondsPerPoint)
            onScrubMove?(scrubTime)
        case .ended:
            velocity = -Double(pan.velocity(in: self).x) * secondsPerPoint
            // Slow releases stop dead — no lingering "slowdown" tail.
            if abs(velocity) > 1.0 {
                mode = .coasting
            } else {
                finishScrub()
            }
        case .cancelled, .failed:
            finishScrub()
        default:
            break
        }
    }

    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began, onLongPress != nil else { return }
        markerHaptics.impactOccurred()
        onLongPress?()
    }

    @objc private func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        switch pinch.state {
        case .began:
            pinchStartSeconds = secondsPerScreen
        case .changed:
            guard pinch.scale > 0 else { return }
            secondsPerScreen = min(max(pinchStartSeconds / Double(pinch.scale), 1.5), 40)
        default:
            break
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        if mode == .coasting {
            let dt = link.targetTimestamp - link.timestamp
            scrubTime += velocity * dt
            velocity *= exp(-dt / 0.18)
            let clamped = clampToMedia(scrubTime)
            if clamped != scrubTime {
                scrubTime = clamped
                velocity = 0
            }
            onScrubMove?(scrubTime)
            if abs(velocity) < 0.4 {
                finishScrub()
            }
        }
        setNeedsDisplay()
    }

    /// Stop dragging/coasting before an external control commits or seeks.
    func stopScrubbing() { finishScrub() }

    private func finishScrub() {
        guard mode != .follow else { return }
        mode = .follow
        velocity = 0
        onScrubEnd?()
    }

    private func clampToMedia(_ time: Double) -> Double {
        let duration = dataSource?().duration ?? 0
        return duration > 0 ? min(max(time, 0), duration) : max(time, 0)
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let state = dataSource?() else { return }
        let width = bounds.width
        let height = bounds.height
        guard width > 0 else { return }

        // During a music count-in the wheel holds on the target; otherwise
        // it follows the transport (or the finger).
        let time = state.countInTarget ?? (mode == .follow ? state.time : scrubTime)
        let start = time - secondsPerScreen / 2
        func x(_ t: Double) -> CGFloat {
            CGFloat((t - start) / secondsPerScreen) * width
        }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(bounds)

        // Shade the void outside the media.
        context.setFillColor(UIColor(white: 0.12, alpha: 1).cgColor)
        if start < 0 {
            context.fill(CGRect(x: 0, y: 0, width: x(0), height: height))
        }
        if state.duration > 0, start + secondsPerScreen > state.duration {
            let dx = x(state.duration)
            context.fill(CGRect(x: dx, y: 0, width: width - dx, height: height))
        }

        // A/B loop shading sits behind the waveform/grid.
        if let loop = state.loop {
            let ax = x(loop.lowerBound)
            let bx = x(loop.upperBound)
            context.setFillColor(UIColor.systemGreen.withAlphaComponent(state.loopActive ? 0.18 : 0.07).cgColor)
            context.fill(CGRect(x: ax, y: 0, width: bx - ax, height: height))
        }

        if state.showWaveform, let waveform = state.waveform {
            drawWaveform(waveform, context: context, x: x, width: width, height: height, start: start)
        }
        if let grid = state.grid {
            drawGrid(grid, context: context, x: x, height: height, start: start, offset: state.beatVisualOffset)
        }
        drawMarkers(state.markers, context: context, x: x, width: width, height: height, start: start)
        if let loop = state.loop {
            drawLoopBounds(loop, active: state.loopActive, context: context, x: x, height: height)
        }

        // Yellow catch-up playhead during a music count-in: actual playback
        // position approaching the held red playhead.
        if state.countInTarget != nil {
            let px = x(state.time)
            if px >= 0, px <= width {
                context.setStrokeColor(UIColor.systemYellow.cgColor)
                context.setLineWidth(2)
                context.move(to: CGPoint(x: px, y: 0))
                context.addLine(to: CGPoint(x: px, y: height))
                context.strokePath()
            }
        }

        // Playhead, fixed at center.
        context.setStrokeColor(UIColor.systemRed.cgColor)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: width / 2, y: 0))
        context.addLine(to: CGPoint(x: width / 2, y: height))
        context.strokePath()
    }

    private func drawWaveform(
        _ waveform: WaveformData,
        context: CGContext,
        x: (Double) -> CGFloat,
        width: CGFloat,
        height: CGFloat,
        start: Double
    ) {
        let firstBin = max(0, Int(start * waveform.binsPerSecond))
        let lastBin = min(waveform.peaks.count - 1, Int((start + secondsPerScreen) * waveform.binsPerSecond))
        guard lastBin >= firstBin else { return }

        let mid = height * 0.55
        let binWidth = width / CGFloat(secondsPerScreen * waveform.binsPerSecond)
        context.setStrokeColor(UIColor(white: 1, alpha: 0.4).cgColor)
        context.setLineWidth(max(1, binWidth * 0.7))
        for bin in firstBin...lastBin {
            let px = x(Double(bin) / waveform.binsPerSecond)
            let h = max(1, CGFloat(waveform.peaks[bin]) * height * 0.62)
            context.move(to: CGPoint(x: px, y: mid - h / 2))
            context.addLine(to: CGPoint(x: px, y: mid + h / 2))
        }
        context.strokePath()
    }

    private func drawGrid(
        _ grid: BeatGrid,
        context: CGContext,
        x: (Double) -> CGFloat,
        height: CGFloat,
        start: Double,
        offset: Double
    ) {
        // Latency compensation shifts where ticks are drawn; the underlying
        // grid times (media timeline) are untouched. Query a window shifted
        // by -offset and draw each tick at +offset.
        let showAndLabels = secondsPerScreen < 12
        let accent = tintColor ?? .systemBlue
        let beatAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor(white: 1, alpha: 0.75),
        ]
        let oneAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold),
            .foregroundColor: accent,
        ]
        let andAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor(white: 1, alpha: 0.45),
        ]

        for tick in grid.ticks(in: (start - offset)...(start - offset + secondsPerScreen)) {
            let px = x(tick.time + offset)
            if tick.isAnd {
                context.setStrokeColor(UIColor(white: 1, alpha: 0.25).cgColor)
                context.setLineWidth(1)
                context.move(to: CGPoint(x: px, y: 0))
                context.addLine(to: CGPoint(x: px, y: height * 0.16))
                context.strokePath()
                if showAndLabels {
                    ("&" as NSString).draw(at: CGPoint(x: px + 3, y: 2), withAttributes: andAttributes)
                }
            } else {
                let isOne = tick.count == 1
                context.setStrokeColor(
                    isOne ? accent.withAlphaComponent(0.9).cgColor : UIColor(white: 1, alpha: 0.3).cgColor
                )
                context.setLineWidth(isOne ? 2 : 1)
                context.move(to: CGPoint(x: px, y: 0))
                context.addLine(to: CGPoint(x: px, y: height))
                context.strokePath()
                ("\(tick.count)" as NSString).draw(
                    at: CGPoint(x: px + 4, y: 2),
                    withAttributes: isOne ? oneAttributes : beatAttributes
                )
            }
        }
    }

    private func drawMarkers(
        _ markers: [Marker],
        context: CGContext,
        x: (Double) -> CGFloat,
        width: CGFloat,
        height: CGFloat,
        start: Double
    ) {
        let visible = start...(start + secondsPerScreen)
        let orange = UIColor.systemOrange
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor.white,
        ]
        for marker in markers where visible.contains(marker.time) {
            let px = x(marker.time)
            context.setStrokeColor(orange.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(1.5)
            context.move(to: CGPoint(x: px, y: 0))
            context.addLine(to: CGPoint(x: px, y: height))
            context.strokePath()

            // Name chip at the bottom, clear of the beat-count labels up top.
            let name = marker.name as NSString
            let textSize = name.size(withAttributes: nameAttributes)
            let pad: CGFloat = 3
            let chip = CGRect(
                x: min(px + 2, width - textSize.width - pad * 2 - 1),
                y: height - textSize.height - 6,
                width: textSize.width + pad * 2,
                height: textSize.height + 2
            )
            context.setFillColor(orange.withAlphaComponent(0.92).cgColor)
            context.addPath(UIBezierPath(roundedRect: chip, cornerRadius: 3).cgPath)
            context.fillPath()
            name.draw(at: CGPoint(x: chip.minX + pad, y: chip.minY + 1), withAttributes: nameAttributes)
        }
    }

    private func drawLoopBounds(
        _ loop: ClosedRange<Double>,
        active: Bool,
        context: CGContext,
        x: (Double) -> CGFloat,
        height: CGFloat
    ) {
        let color = UIColor.systemGreen.withAlphaComponent(active ? 0.95 : 0.5)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: color,
        ]
        for (time, label) in [(loop.lowerBound, "A"), (loop.upperBound, "B")] {
            let px = x(time)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(2)
            context.move(to: CGPoint(x: px, y: 0))
            context.addLine(to: CGPoint(x: px, y: height))
            context.strokePath()
            (label as NSString).draw(
                at: CGPoint(x: px + 3, y: height * 0.5 - 8),
                withAttributes: labelAttributes
            )
        }
    }
}
