import AVFoundation
import SwiftUI

/// One persistent pair of video surfaces. Layout changes move their frames;
/// they never tear down/reconnect the capture session or AVPlayer layer.
struct RecordingPreviewStage: UIViewRepresentable {
    let camera: TakeCamera
    let player: AVPlayer
    let layout: ReferenceLayout
    let cameraRevision: Int

    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.cameraView.camera = camera
        view.cameraView.preview.session = camera.session
        view.referenceView.layerPlayer.player = player
        view.setLayout(layout)
        return view
    }

    func updateUIView(_ view: Surface, context: Context) {
        if view.referenceView.layerPlayer.player !== player { view.referenceView.layerPlayer.player = player }
        view.setLayout(layout)
        view.cameraView.setOrientation(force: view.cameraRevision != cameraRevision)
        view.cameraRevision = cameraRevision
    }

    final class Surface: UIView {
        let cameraView = TakeCameraPreview.Preview()
        let referenceView = TakePlayerSurface.Surface()
        var cameraRevision: Int?
        private let cameraLabel = UILabel()
        private let referenceLabel = UILabel()
        private var referenceLayout: ReferenceLayout = .camera

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            cameraView.preview.videoGravity = .resizeAspect
            referenceView.backgroundColor = .black
            referenceView.clipsToBounds = true
            addSubview(cameraView)
            addSubview(referenceView)
            for (label, text, parent) in [(cameraLabel, "You", cameraView), (referenceLabel, "Reference", referenceView)] {
                label.text = text
                label.font = .preferredFont(forTextStyle: .caption1)
                label.adjustsFontForContentSizeCategory = true
                label.textColor = .white
                label.backgroundColor = .black.withAlphaComponent(0.7)
                label.textAlignment = .center
                label.layer.cornerRadius = 8
                label.clipsToBounds = true
                parent.addSubview(label)
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func setLayout(_ layout: ReferenceLayout) {
            guard referenceLayout != layout else { return }
            referenceLayout = layout
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            referenceView.isHidden = referenceLayout == .camera
            referenceLabel.isHidden = referenceLayout != .sideBySide
            referenceView.layer.cornerRadius = referenceLayout == .pictureInPicture ? 12 : 0
            referenceView.layer.borderWidth = referenceLayout == .pictureInPicture ? 1 : 0
            referenceView.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
            if referenceLayout == .sideBySide {
                let half = max(0, (bounds.width - 8) / 2)
                cameraView.frame = CGRect(x: 0, y: 0, width: half, height: bounds.height)
                referenceView.frame = CGRect(x: half + 8, y: 0, width: half, height: bounds.height)
            } else {
                cameraView.frame = bounds
                let width = bounds.width * 0.28
                referenceView.frame = CGRect(x: max(0, bounds.width - width - 16), y: 16,
                    width: width, height: bounds.height * 0.28)
            }
            for (label, parent) in [(cameraLabel, cameraView), (referenceLabel, referenceView)] {
                let size = label.sizeThatFits(parent.bounds.size)
                let height = size.height + 16
                label.frame = CGRect(x: 12, y: max(0, parent.bounds.height - height - 12),
                    width: min(size.width + 16, max(0, parent.bounds.width - 24)), height: height)
            }
            CATransaction.commit()
        }
    }
}
