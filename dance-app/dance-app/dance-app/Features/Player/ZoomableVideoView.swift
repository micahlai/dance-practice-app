import AVFoundation
import SwiftUI
import UIKit

/// Video surface with pinch-to-zoom and pan (UIScrollView-backed).
/// Double-tap resets zoom.
struct ZoomableVideoView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> ZoomScrollView {
        let view = ZoomScrollView()
        view.delegate = context.coordinator
        view.videoView.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: ZoomScrollView, context: Context) {
        uiView.videoView.playerLayer.player = player
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        minimumZoomScale = 1
        maximumZoomScale = 6
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = .black
        addSubview(videoView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(resetZoom))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1 {
            videoView.frame = bounds
            contentSize = bounds.size
        }
    }

    @objc private func resetZoom() {
        setZoomScale(1, animated: true)
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
