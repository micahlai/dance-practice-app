import AVFoundation
import CoreImage.CIFilterBuiltins
import MetalKit
import UIKit

/// Doubles the apparent frame rate by cross-blending the two most recently
/// decoded frames at every display refresh (frame blending — not optical
/// flow, which can't run in real time at 4K on-device). Sits over the player
/// layer and is only made active while scrubbing or playing slowed down; at
/// 1× normal playback the plain AVPlayerLayer shows.
///
/// Trade-off: blending is between the two frames *behind* the playhead (the
/// next frame isn't decoded yet), so the picture runs one source frame late
/// while active. At practice speeds that's imperceptible next to the
/// smoothness gain.
final class FrameInterpolationView: MTKView {
    private weak var attachedPlayer: AVPlayer?
    private weak var attachedItem: AVPlayerItem?
    private var output: AVPlayerItemVideoOutput?
    private var ciContext: CIContext?
    private var commandQueue: MTLCommandQueue?
    private let renderColorSpace = CGColorSpaceCreateDeviceRGB()

    private var currentFrame: CIImage?
    private var previousFrame: CIImage?
    private var currentFrameHostTime: CFTimeInterval = 0
    /// Host-time spacing of the last two frame arrivals — the denominator for
    /// the blend fraction. Measuring it (instead of assuming source fps)
    /// adapts to the practice rate and to irregular arrivals while scrubbing.
    private var frameSpacing: CFTimeInterval = 1.0 / 30.0

    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            isPaused = !isActive
            isHidden = !isActive
            if !isActive {
                currentFrame = nil
                previousFrame = nil
                currentFrameHostTime = 0
            }
        }
    }

    init() {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)
        commandQueue = device?.makeCommandQueue()
        if let device {
            ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        framebufferOnly = false
        // Transparent when there's nothing to draw (and in the letterbox
        // regions) so the player layer beneath shows through instead of a
        // black flash while the first frame arrives.
        isOpaque = false
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        preferredFramesPerSecond = UIScreen.main.maximumFramesPerSecond
        isPaused = true
        isHidden = true
        isUserInteractionEnabled = false
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func attach(to player: AVPlayer) {
        attachedPlayer = player
    }

    override func draw(_ rect: CGRect) {
        guard isActive, let queue = commandQueue, let ciContext,
              let drawable = currentDrawable else { return }
        syncOutputToCurrentItem()
        guard let output else { return }

        let host = CACurrentMediaTime()
        let itemTime = output.itemTime(forHostTime: host)
        if output.hasNewPixelBuffer(forItemTime: itemTime),
           let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
            previousFrame = currentFrame
            if currentFrameHostTime > 0 {
                frameSpacing = min(max(host - currentFrameHostTime, 1.0 / 120.0), 0.5)
            }
            currentFrame = CIImage(cvPixelBuffer: buffer)
            currentFrameHostTime = host
        }
        guard let current = currentFrame else { return }

        // Dissolve previous → current as host time approaches the expected
        // next-frame arrival: every display refresh between two source frames
        // shows a distinct intermediate image.
        var image = current
        if let previous = previousFrame, previous.extent == current.extent {
            let fraction = min(max((host - currentFrameHostTime) / frameSpacing, 0), 1)
            let blend = CIFilter.dissolveTransition()
            blend.inputImage = previous
            blend.targetImage = current
            blend.time = Float(fraction)
            image = blend.outputImage ?? current
        }

        // Aspect-fit into the drawable (matches the player layer's
        // .resizeAspect); pixels outside the image render transparent.
        let target = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        let scale = min(target.width / image.extent.width, target.height / image.extent.height)
        image = image.transformed(by: .init(scaleX: scale, y: scale))
        image = image.transformed(by: .init(
            translationX: (target.width - image.extent.width) / 2 - image.extent.minX,
            y: (target.height - image.extent.height) / 2 - image.extent.minY
        ))

        guard let commandBuffer = queue.makeCommandBuffer() else { return }
        ciContext.render(
            image,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: CGRect(origin: .zero, size: target),
            colorSpace: renderColorSpace
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// (Re)attach the video output whenever the player's item changes, and
    /// seed the current frame so activation never starts on a blank.
    private func syncOutputToCurrentItem() {
        guard let item = attachedPlayer?.currentItem else { return }
        if item !== attachedItem || output == nil {
            if let output, let attachedItem { attachedItem.remove(output) }
            let fresh = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
            item.add(fresh)
            output = fresh
            attachedItem = item
            currentFrame = nil
            previousFrame = nil
            currentFrameHostTime = 0
        }
        if currentFrame == nil, let output {
            let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
            if let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
                currentFrame = CIImage(cvPixelBuffer: buffer)
                currentFrameHostTime = CACurrentMediaTime()
            }
        }
    }
}
