import AVFoundation
import Darwin
import SwiftUI
import UIKit

/// All blocking capture configuration runs on a serial queue, never the UI
/// thread. Delegate notifications cross back to the main actor explicitly.
nonisolated final class TakeCamera: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "choreo.take.camera")
    private let output = AVCaptureMovieFileOutput()
    private var input: AVCaptureDeviceInput?
    private var configured = false
    private var pendingStop = false
    private var recordingRequested = false
    private var stopAfterRecording = false
    private var startCallback: (@MainActor @Sendable (UInt64) -> Void)?
    private var finishCallback: (@MainActor @Sendable (URL, String?) -> Void)?

    func prepare() async throws {
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        guard allowed else { throw CameraError.permission }
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    if !self.configured { try self.configure(position: .front) }
                    self.stopAfterRecording = false
                    if !self.session.isRunning { self.session.startRunning() }
                    guard self.session.isRunning, !self.session.isInterrupted else { throw CameraError.unavailable }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func configure(position: AVCaptureDevice.Position) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraError.unavailable
        }
        let newInput = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.automaticallyConfiguresApplicationAudioSession = false
        if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
        if let input { session.removeInput(input) }
        guard session.canAddInput(newInput) else {
            if let input, session.canAddInput(input) { session.addInput(input) }
            throw CameraError.unavailable
        }
        session.addInput(newInput)
        input = newInput
        if !configured {
            guard session.canAddOutput(output) else { throw CameraError.unavailable }
            session.addOutput(output)
        }
        // Clean source music is added during export; no microphone input,
        // speaker bleed, or change to the app's playback audio session.
        configured = true
    }

    func flip() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard !self.recordingRequested else { continuation.resume(); return }
                    try self.configure(position: self.input?.device.position == .front ? .back : .front)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func record(to url: URL, rotationAngle: CGFloat,
                onStart: @escaping @MainActor @Sendable (UInt64) -> Void,
                onFinish: @escaping @MainActor @Sendable (URL, String?) -> Void) {
        queue.async {
            guard !self.recordingRequested else {
                Task { @MainActor in onFinish(url, "Another take is still finishing. Try again in a moment.") }
                return
            }
            guard self.configured, self.session.isRunning else {
                Task { @MainActor in onFinish(url, CameraError.unavailable.localizedDescription) }
                return
            }
            self.startCallback = onStart
            self.finishCallback = onFinish
            self.pendingStop = false
            self.stopAfterRecording = false
            self.recordingRequested = true
            if let connection = self.output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(rotationAngle) { connection.videoRotationAngle = rotationAngle }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = self.input?.device.position == .front
                }
            }
            self.output.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        queue.async {
            self.pendingStop = true
            if self.output.isRecording { self.output.stopRecording() }
        }
    }

    func stopSession() {
        queue.async {
            self.stopAfterRecording = true
            if self.recordingRequested {
                self.pendingStop = true
                if self.output.isRecording { self.output.stopRecording() }
            } else if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Keep capture-connection mutations on the session queue, not in a
    /// main-thread layout pass. Resizing a preview does not need a rotation.
    func rotatePreview(_ connection: AVCaptureConnection, to angle: CGFloat) {
        let request = PreviewRotation(connection: connection, angle: angle)
        queue.async {
            guard request.connection.videoRotationAngle != request.angle,
                request.connection.isVideoRotationAngleSupported(request.angle) else { return }
            request.connection.videoRotationAngle = request.angle
        }
    }

    // The connection is passed across once; mutation is serialized on queue.
    private struct PreviewRotation: @unchecked Sendable {
        let connection: AVCaptureConnection
        let angle: CGFloat
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        let origin = mach_absolute_time()
        queue.async {
            if self.pendingStop { self.output.stopRecording() }
            let callback = self.startCallback
            Task { @MainActor in callback?(origin) }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        // Some terminal conditions (e.g. a file-size limit) carry an error
        // even when AVFoundation successfully finalized a playable movie.
        let success = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false
        let message = error != nil && !success ? error?.localizedDescription : nil
        queue.async {
            self.recordingRequested = false
            let callback = self.finishCallback
            self.startCallback = nil
            self.finishCallback = nil
            if self.stopAfterRecording, self.session.isRunning { self.session.stopRunning() }
            Task { @MainActor in callback?(outputFileURL, message) }
        }
    }
}

enum CameraError: LocalizedError {
    case permission, unavailable
    var errorDescription: String? {
        switch self {
        case .permission: "Allow camera access in Settings to record a take. You can still review and export drafts."
        case .unavailable: "No camera is available. Recording needs a physical iPad; drafts are still available."
        }
    }
}

struct TakeCameraPreview: UIViewRepresentable {
    let camera: TakeCamera

    func makeUIView(context: Context) -> Preview {
        let view = Preview()
        view.camera = camera
        view.preview.session = camera.session
        view.preview.videoGravity = .resizeAspect
        return view
    }
    func updateUIView(_ view: Preview, context: Context) { view.setOrientation() }

    final class Preview: UIView {
        weak var camera: TakeCamera?
        private var lastConnection: AVCaptureConnection?
        private var lastAngle: CGFloat?
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() { super.layoutSubviews(); setOrientation() }
        func setOrientation(force: Bool = false) {
            guard let connection = preview.connection else { return }
            let angle = captureRotationAngle(window?.windowScene?.interfaceOrientation ?? .portrait)
            guard force || connection !== lastConnection || angle != lastAngle else { return }
            lastConnection = connection
            lastAngle = angle
            camera?.rotatePreview(connection, to: angle)
        }
    }
}

func captureRotationAngle(_ orientation: UIInterfaceOrientation) -> CGFloat {
    switch orientation {
    case .landscapeLeft: 180
    case .landscapeRight: 0
    case .portraitUpsideDown: 270
    default: 90
    }
}
