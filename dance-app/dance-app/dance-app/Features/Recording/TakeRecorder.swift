import AVFoundation
import Darwin
import Observation
import UIKit

@MainActor @Observable
final class TakeRecorder {
    enum Phase { case preparing, ready, starting, recording, finishing, review }
    let camera = TakeCamera()
    let reference = PlaybackEngine()
    var settings = TakeSettings()
    private(set) var phase: Phase = .preparing
    private(set) var cameraReady = false
    private(set) var elapsed: Double = 0
    private(set) var countLabel: String?
    private(set) var pendingURL: URL?
    private(set) var pendingDuration: Double = 0
    private(set) var musicDelay: Double = 0
    var errorMessage: String?
    var isSaving = false
    @ObservationIgnored private let guide = CountOffPlayer()
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var document: VideoDocument?
    @ObservationIgnored private var grid: BeatGrid?
    @ObservationIgnored private var origin: UInt64?
    @ObservationIgnored private var startedSettings = TakeSettings()
    @ObservationIgnored private var startedGrid: BeatGrid?
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var cameraActivation: UUID?
    @ObservationIgnored private var sessionObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var preparationID: UUID?
    @ObservationIgnored private var captureRequested = false

    init() {
        let center = NotificationCenter.default
        sessionObservers = [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification].map { name in
            center.addObserver(forName: name, object: camera.session, queue: .main) { [weak self] notification in
                let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
                    ?? "Camera recording was interrupted. Any playable footage can still be saved as a draft."
                MainActor.assumeIsolated { self?.handleCameraInterruption(message: message) }
            }
        }
    }

    deinit {
        for observer in sessionObservers { NotificationCenter.default.removeObserver(observer) }
    }

    var isActive: Bool { phase == .starting || phase == .recording || phase == .finishing }

    func load(document: VideoDocument?, grid: BeatGrid?, playhead: Double, rate: Double, metronome: BeatClickMode) {
        guard self.document == nil else { return }
        self.document = document
        self.grid = grid
        settings.musicStart = max(0, playhead)
        settings.countInTime = max(0, grid?.nearestBeatTime(to: playhead) ?? playhead)
        settings.rate = rate
        settings.metronome = metronome
        if let document { reference.load(url: document.videoURL) }
    }

    func prepareCamera() async {
        let activation = UUID()
        cameraActivation = activation
        do {
            try await camera.prepare()
            guard cameraActivation == activation, !Task.isCancelled else {
                if cameraActivation == nil || (cameraActivation == activation && Task.isCancelled) { camera.stopSession() }
                return
            }
            cameraReady = true
        } catch is CancellationError {
            if cameraActivation == activation { cameraReady = false; camera.stopSession() }
            return
        } catch {
            guard cameraActivation == activation else { return }
            cameraReady = false
            errorMessage = error.localizedDescription
        }
        if phase == .preparing { phase = .ready }
    }

    private func handleCameraInterruption(message: String) {
        errorMessage = message
        suspend()
    }

    func flipCamera() async {
        guard !isActive else { return }
        do { try await camera.flip() } catch { errorMessage = error.localizedDescription }
    }

    func start(orientation: UIInterfaceOrientation) {
        guard cameraReady, phase == .ready, document != nil, reference.duration > 0 else { return }
        guard settings.musicStart.isFinite, settings.countInTime.isFinite else {
            errorMessage = "Enter valid times in seconds."
            return
        }
        settings.musicStart = min(max(settings.musicStart, 0), max(0, reference.duration - 0.1))
        if let grid {
            settings.countInTime = grid.nearestBeatTime(to: max(settings.countInTime, settings.musicStart))
            if settings.countInTime < settings.musicStart { settings.countInTime += grid.beatInterval }
        }
        guard !settings.countInEnabled || grid == nil || settings.countInTime < reference.duration else {
            errorMessage = "Choose a count-in landing before the end of the reference video."
            return
        }
        startedSettings = settings
        startedGrid = grid
        phase = .starting
        let preparation = UUID()
        preparationID = preparation
        captureRequested = false
        stopRequested = false
        elapsed = 0
        countLabel = nil
        reference.setRate(settings.rate)
        let timeline = TakeTimeline(settings: settings, grid: grid)
        musicDelay = timeline.musicDelay
        tickTask = Task { [weak self] in
            guard let self else { return }
            let prepared = await self.reference.prepareForScheduledStart(at: self.settings.musicStart)
            // An old preparation may complete after Cancel start and a new
            // take. It must never reset or launch that new take's camera.
            guard self.preparationID == preparation, !Task.isCancelled, !self.stopRequested else { return }
            guard prepared else {
                self.errorMessage = "Couldn't prepare the reference video. Try again."
                self.phase = .ready
                return
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID().uuidString).mov")
            self.captureRequested = true
            self.camera.record(to: url, rotationAngle: captureRotationAngle(orientation)) { [weak self] hostTime in
                self?.captureStarted(at: hostTime, timeline: timeline)
            } onFinish: { [weak self] url, error in
                self?.captureFinished(url: url, error: error)
            }
        }
    }

    private func captureStarted(at hostTime: UInt64, timeline: TakeTimeline) {
        guard phase == .starting, !stopRequested else { camera.stopRecording(); return }
        phase = .recording
        origin = hostTime
        UIApplication.shared.isIdleTimerDisabled = true
        let musicHost = hostTime + AVAudioTime.hostTime(forSeconds: timeline.musicDelay)
        reference.playPrepared(at: startedSettings.musicStart, rate: startedSettings.rate, hostTime: musicHost)

        // Count-in and live beats use exactly the same synthesis/accent
        // handler as practice, scheduled against the capture host clock.
        if let grid = startedGrid {
            for event in timeline.counts {
                let count = Int(event.label) ?? 1
                guide.scheduleGuideClick(accent: count == 1 || count == 5, isHalfCount: false,
                                         at: hostTime + AVAudioTime.hostTime(forSeconds: event.wallTime))
            }
            if startedSettings.metronome != .off {
                let includeAnds = startedSettings.metronome == .beatsAndHalf
                let from = max(startedSettings.musicStart, startedSettings.countInEnabled ? startedSettings.countInTime : startedSettings.musicStart)
                // A short lookahead loop below queues beats incrementally;
                // no memory growth for long references.
                scheduleLiveGuide(grid: grid, includeAnds: includeAnds, from: from,
                                  timeline: timeline, origin: hostTime)
                return
            }
        }
        startTicks(timeline: timeline, origin: hostTime)
    }

    private func scheduleLiveGuide(grid: BeatGrid, includeAnds: Bool, from: Double,
                                   timeline: TakeTimeline, origin: UInt64) {
        startTicks(timeline: timeline, origin: origin, guideGrid: grid, includeAnds: includeAnds, guideFrom: from)
    }

    private func startTicks(timeline: TakeTimeline, origin: UInt64, guideGrid: BeatGrid? = nil,
                            includeAnds: Bool = false, guideFrom: Double = 0) {
        tickTask = Task { [weak self] in
            var lastIndex: Int?
            while !Task.isCancelled {
                guard let self, self.phase == .recording else { return }
                let now = mach_absolute_time()
                self.elapsed = now > origin ? AVAudioTime.seconds(forHostTime: now - origin) : 0
                let event = timeline.counts.last { $0.wallTime <= self.elapsed }
                self.countLabel = event.flatMap { self.elapsed < $0.wallTime + (self.startedGrid?.beatInterval ?? 0.5) / self.startedSettings.rate ? $0.label : nil }
                if let grid = guideGrid {
                    let mediaNow = self.startedSettings.musicStart + (self.elapsed - timeline.musicDelay) * self.startedSettings.rate
                    let lower = max(guideFrom, mediaNow)
                    for tick in grid.ticks(in: lower...(lower + 0.2 * self.startedSettings.rate), includeAnds: includeAnds) {
                        guard tick.time < self.reference.duration,
                              lastIndex == nil || tick.id > lastIndex!,
                              // The count-in already queues its landing.
                              !(self.startedSettings.countInEnabled && abs(tick.time - self.startedSettings.countInTime) < 0.001) else { continue }
                        let wall = timeline.musicDelay + (tick.time - self.startedSettings.musicStart) / self.startedSettings.rate
                        guard wall > self.elapsed else { continue }
                        self.guide.scheduleGuideClick(accent: !tick.isAnd && (tick.count == 1 || tick.count == 5),
                                                      isHalfCount: tick.isAnd,
                                                      at: origin + AVAudioTime.hostTime(forSeconds: wall))
                        lastIndex = tick.id
                    }
                }
                let end = timeline.musicDelay + (self.reference.duration - self.startedSettings.musicStart) / self.startedSettings.rate
                if self.elapsed >= end { self.stop(); return }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    func stop() {
        guard phase == .starting || phase == .recording else { return }
        let preparingReference = phase == .starting && !captureRequested
        stopRequested = true
        tickTask?.cancel()
        reference.pause()
        guide.stop()
        countLabel = nil
        UIApplication.shared.isIdleTimerDisabled = false
        if preparingReference {
            preparationID = nil
            reference.cancelScheduledPreparation()
            phase = .ready
        } else {
            // The camera remembers stop requests until didStart arrives.
            camera.stopRecording()
            phase = .finishing
        }
    }

    private func captureFinished(url: URL, error message: String?) {
        tickTask?.cancel()
        reference.pause()
        guide.stop()
        origin = nil
        captureRequested = false
        preparationID = nil
        countLabel = nil
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .finishing
        Task {
            do {
                let duration = try await AVURLAsset(url: url).load(.duration).seconds
                guard duration.isFinite, duration > 0 else { throw TakeExportError.invalidVideo }
                pendingURL = url
                pendingDuration = duration
                phase = .review
                if let message { errorMessage = "Recording ended early. Your playable take is available to review and save. \(message)" }
            } catch {
                errorMessage = message ?? error.localizedDescription
                phase = .ready
            }
        }
    }

    func saveDraft() async -> TakeDraft? {
        guard let url = pendingURL, let document, !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let draft = try await TakeDraftStore.save(cameraURL: url, document: document, settings: startedSettings,
                                              grid: startedGrid, musicDelay: musicDelay, duration: pendingDuration)
            try? FileManager.default.removeItem(at: url)
            pendingURL = nil
            pendingDuration = 0
            phase = .ready
            NotificationCenter.default.post(name: .takeLibraryDidChange, object: nil)
            return draft
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    func renderPendingTake() async throws -> URL {
        guard let pendingURL, let document else { throw TakeExportError.invalidVideo }
        return try await TakeExporter.render(cameraURL: pendingURL, referenceURL: document.videoURL,
                                             settings: startedSettings, musicDelay: musicDelay)
    }

    func discard() {
        guard phase == .review, !isSaving else { return }
        if let pendingURL { try? FileManager.default.removeItem(at: pendingURL) }
        pendingURL = nil
        pendingDuration = 0
        phase = .ready
    }

    func suspend() {
        cameraActivation = nil
        cameraReady = false
        if phase == .preparing { phase = .ready }
        if phase == .starting || phase == .recording { stop() }
        reference.pause()
        guide.stop()
        camera.stopSession()
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
