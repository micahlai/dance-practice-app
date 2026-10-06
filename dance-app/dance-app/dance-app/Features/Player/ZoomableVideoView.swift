import AVFoundation
import SwiftUI
import UIKit

/// Video surface with pinch-to-zoom and pan (UIScrollView-backed).
/// Double-tap resets zoom.
struct ZoomableVideoView: UIViewRepresentable {
    let player: AVPlayer
    /// Frame-blending overlay (doubles apparent fps) — active only while
    /// scrubbing or playing slowed down.
    let interpolationActive: Bool
    let onCenterTap: () -> Void

    func makeUIView(context: Context) -> ZoomScrollView {
        let view = ZoomScrollView()
        view.delegate = context.coordinator
        view.videoView.playerLayer.player = player
        view.interpolationView.attach(to: player)
        view.interpolationView.isActive = interpolationActive
        view.onCenterTap = onCenterTap
        return view
    }

    func updateUIView(_ uiView: ZoomScrollView, context: Context) {
        uiView.videoView.playerLayer.player = player
        uiView.interpolationView.attach(to: player)
        uiView.interpolationView.isActive = interpolationActive
        uiView.onCenterTap = onCenterTap
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomScrollView)?.videoView
        }
    }
}

final class ZoomScrollView: UIScrollView {
    let videoView = PlayerLayerView()
    // Inside videoView so pinch zoom/pan carries the overlay along.
    let interpolationView = FrameInterpolationView()
    var onCenterTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        minimumZoomScale = 1
        maximumZoomScale = 6
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = .black
        addSubview(videoView)
        videoView.addSubview(interpolationView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(resetZoom))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let centerTap = UITapGestureRecognizer(target: self, action: #selector(handleCenterTap(_:)))
        centerTap.require(toFail: doubleTap)
        addGestureRecognizer(centerTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1 {
            videoView.frame = bounds
            contentSize = bounds.size
        }
        interpolationView.frame = videoView.bounds
    }

    @objc private func resetZoom() {
        setZoomScale(1, animated: true)
    }

    @objc private func handleCenterTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        let centerRegion = bounds.insetBy(dx: bounds.width * 0.2, dy: bounds.height * 0.2)
        guard centerRegion.contains(point) else { return }
        onCenterTap?()
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
