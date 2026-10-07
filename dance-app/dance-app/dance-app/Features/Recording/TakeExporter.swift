import AVFoundation

enum TakeExportError: LocalizedError {
    case invalidVideo, cannotExport, failed(String)
    var errorDescription: String? {
        switch self {
        case .invalidVideo: "This take does not contain a playable video."
        case .cannotExport: "Couldn't prepare this take for export."
        case .failed(let message): message
        }
    }
}

/// Reconstructs a take from the immutable camera + reference sources.
/// Scaling the camera by rate (0.5 → half duration) restores normal music
/// speed. The source soundtrack avoids amplified metronome/speaker bleed.
enum TakeExporter {
    static func export(_ draft: TakeDraft) async throws -> URL {
        try await render(cameraURL: draft.cameraURL, referenceURL: draft.referenceURL,
                         settings: draft.settings, musicDelay: draft.musicDelay)
    }

    /// Also supports rendering a just-recorded take before it is saved.
    static func render(cameraURL: URL, referenceURL: URL, settings: TakeSettings,
                       musicDelay captureMusicDelay: Double) async throws -> URL {
        try Task.checkCancellation()
        let cameraAsset = AVURLAsset(url: cameraURL)
        let referenceAsset = AVURLAsset(url: referenceURL)
        guard let cameraSource = try await cameraAsset.loadTracks(withMediaType: .video).first else {
            throw TakeExportError.invalidVideo
        }
        let rawDuration = try await cameraAsset.load(.duration).seconds
        guard rawDuration.isFinite, rawDuration > 0, settings.rate.isFinite, settings.rate > 0,
              settings.musicStart.isFinite, settings.musicStart >= 0,
              captureMusicDelay.isFinite, captureMusicDelay >= 0 else {
            throw TakeExportError.invalidVideo
        }
        let factor = settings.adjustToNormalSpeed ? settings.rate : 1
        let finalDuration = rawDuration * factor
        let musicDelay = min(finalDuration, max(0, captureMusicDelay * factor))
        let composition = AVMutableComposition()
        guard let camera = composition.addMutableTrack(withMediaType: .video,
                                                       preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw TakeExportError.cannotExport
        }
        try camera.insertTimeRange(range(0, rawDuration), of: cameraSource, at: .zero)
        camera.scaleTimeRange(range(0, rawDuration), toDuration: time(finalDuration))

        let referenceDuration = try await referenceAsset.load(.duration).seconds
        let mediaDuration = min(max(0, referenceDuration - settings.musicStart),
                                max(0, rawDuration - captureMusicDelay) * settings.rate)
        let referenceWallDuration = mediaDuration / settings.rate * factor
        let referenceRange = range(settings.musicStart, mediaDuration)
        if mediaDuration > 0,
           let source = try await referenceAsset.loadTracks(withMediaType: .audio).first,
           let music = composition.addMutableTrack(withMediaType: .audio,
                                                   preferredTrackID: kCMPersistentTrackID_Invalid) {
            // Intersect with the actual audio track to support delayed/short
            // soundtracks without inserting time outside their valid range.
            let available = try await source.load(.timeRange)
            let audioRange = CMTimeRangeGetIntersection(referenceRange, otherRange: available)
            if audioRange.duration.seconds > 0 {
                let delay = musicDelay + (audioRange.start.seconds - settings.musicStart)
                    / settings.rate * factor
                let audioLength = audioRange.duration.seconds / settings.rate * factor
                try music.insertTimeRange(audioRange, of: source, at: time(delay))
                music.scaleTimeRange(range(delay, audioRange.duration.seconds), toDuration: time(audioLength))
            }
        }

        let cameraSize = try await cameraSource.load(.naturalSize)
        let cameraTransform = try await cameraSource.load(.preferredTransform)
        let cameraBounds = CGRect(origin: .zero, size: cameraSize).applying(cameraTransform)
        let portrait = abs(cameraBounds.height) > abs(cameraBounds.width)
        let canvas = settings.layout == .sideBySide || !portrait
            ? CGSize(width: 1920, height: 1080) : CGSize(width: 1080, height: 1920)
        let cameraRect = settings.layout == .sideBySide
            ? CGRect(x: 0, y: 0, width: canvas.width / 2, height: canvas.height)
            : CGRect(origin: .zero, size: canvas)
        let cameraLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: camera)
        cameraLayer.setTransform(fit(size: cameraSize, transform: cameraTransform, into: cameraRect), at: .zero)
        var layers = [cameraLayer]
        if settings.layout != .camera, mediaDuration > 0,
           let source = try await referenceAsset.loadTracks(withMediaType: .video).first,
           let reference = composition.addMutableTrack(withMediaType: .video,
                                                       preferredTrackID: kCMPersistentTrackID_Invalid) {
            try reference.insertTimeRange(referenceRange, of: source, at: time(musicDelay))
            reference.scaleTimeRange(range(musicDelay, mediaDuration), toDuration: time(referenceWallDuration))
            let rect: CGRect
            if settings.layout == .sideBySide {
                rect = CGRect(x: canvas.width / 2, y: 0, width: canvas.width / 2, height: canvas.height)
            } else {
                let width = canvas.width * 0.28
                rect = CGRect(x: canvas.width - width - 32, y: 32, width: width, height: canvas.height * 0.28)
            }
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: reference)
            let size = try await source.load(.naturalSize)
            let transform = try await source.load(.preferredTransform)
            layer.setTransform(fit(size: size, transform: transform, into: rect), at: .zero)
            layer.setOpacity(0, at: .zero)
            layer.setOpacity(1, at: time(musicDelay))
            layer.setOpacity(0, at: time(musicDelay + referenceWallDuration))
            layers.insert(layer, at: 0)
        }
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = range(0, finalDuration)
        instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
        instruction.layerInstructions = layers
        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw TakeExportError.cannotExport
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Take-\(UUID().uuidString).mp4")
        export.outputURL = url
        export.outputFileType = .mp4
        export.videoComposition = videoComposition
        export.audioTimePitchAlgorithm = .timeDomain
        export.shouldOptimizeForNetworkUse = true
        let cancellation = ExportCancellation(session: export)
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if !cancellation.start(completion: { continuation.resume() }) { continuation.resume() }
            }
        } onCancel: {
            cancellation.cancel()
        }
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: url)
            throw CancellationError()
        }
        guard export.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            if Task.isCancelled { throw CancellationError() }
            throw TakeExportError.failed(export.error?.localizedDescription ?? "The video export failed. Your draft is still saved.")
        }
        return url
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 60_000)
    }
    private static func range(_ start: Double, _ duration: Double) -> CMTimeRange {
        CMTimeRange(start: time(start), duration: time(duration))
    }
    private static func fit(size: CGSize, transform: CGAffineTransform, into rect: CGRect) -> CGAffineTransform {
        let bounds = CGRect(origin: .zero, size: size).applying(transform)
        let scale = min(rect.width / abs(bounds.width), rect.height / abs(bounds.height))
        return transform
            .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: rect.minX + (rect.width - abs(bounds.width) * scale) / 2,
                                            y: rect.minY + (rect.height - abs(bounds.height) * scale) / 2))
    }
}

/// AVAssetExportSession permits cancelling from another queue. This wrapper
/// exposes only that thread-safe operation to the cancellation handler.
nonisolated private final class ExportCancellation: @unchecked Sendable {
    private let session: AVAssetExportSession
    private let lock = NSLock()
    private var cancelled = false
    init(session: AVAssetExportSession) { self.session = session }
    func start(completion: @escaping @Sendable () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        session.exportAsynchronously(completionHandler: completion)
        return true
    }
    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        session.cancelExport()
    }
}
