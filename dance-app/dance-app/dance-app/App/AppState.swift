import AVFAudio
import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    private(set) var document: VideoDocument?
    let playback = PlaybackEngine()
    let beats = BeatsModel()
    let markers = MarkersModel()

    // Latency calibration (M6). Signed offset (seconds) for the current
    // output route; beat visuals shift by it so they line up with delayed
    // (Bluetooth) audio. The media timeline is never modified.
    private(set) var latencyOffset: Double = 0
    private(set) var calibrationRouteName = "Output"
    /// Auto-prompt when an uncalibrated wireless route connects.
    var showCalibrationPrompt = false
    /// Drives the calibration sheet.
    var showCalibrationSheet = false
    @ObservationIgnored private var routeObserver: NSObjectProtocol?

    init() {
        // Drive A/B looping off the master playhead.
        playback.onTick = { [weak self] time in
            self?.handlePlayheadTick(time)
        }
        refreshLatencyForCurrentRoute()
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleRouteChange() }
        }
    }

    // Timeline options (persisted so the preferences stick across launches).
    var showWaveform = UserDefaults.standard.object(forKey: "showWaveform") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showWaveform, forKey: "showWaveform") }
    }
    /// Audible DJ-scratch while scrubbing. Off = silent scrubbing.
    var scrubAudioEnabled = UserDefaults.standard.object(forKey: "scrubAudioEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(scrubAudioEnabled, forKey: "scrubAudioEnabled") }
    }
    @ObservationIgnored let scrubAudio = ScrubAudioEngine()

    // Speed control & count-off
    var speedGestureActive = false
    /// Finger location (window coords) while the speed gesture is active.
    var speedGesturePoint: CGPoint?
    var countOffEnabled = false
    /// Count-off variant: music plays during the countdown, starting N
    /// counts before the playhead and catching up to it.
    var countInMusicEnabled = false
    private(set) var countOffLabel: String?
    /// While a music count-in runs: the target time the red playhead holds
    /// (the wheel stays centered here; a yellow playhead shows actual
    /// playback catching up). nil otherwise.
    private(set) var countInTargetTime: Double?
    @ObservationIgnored private var countOffTask: Task<Void, Never>?
    @ObservationIgnored private let countOffPlayer = CountOffPlayer()

    func load(_ document: VideoDocument, restored: StoredPracticeState? = nil) {
        cancelCountOff()
        self.document = document
        playback.load(url: document.videoURL)
        playback.setRate(restored?.playbackRate ?? 1.0)
        countOffEnabled = restored?.countOffEnabled ?? false
        countInMusicEnabled = restored?.countInMusicEnabled ?? false
        beats.reset()
        beats.grid = restored?.grid
        beats.detectedBPM = restored?.detectedBPM
        beats.detectionConfidence = restored?.detectionConfidence
        markers.reset()
        markers.markers = restored?.markers ?? []
        markers.loopA = restored?.loopA
        markers.loopB = restored?.loopB
        markers.loopEnabled = restored?.loopEnabled ?? false
        saveState()
        analyze(document)
        loadScrubAudio(document)
    }

    // MARK: - Play/pause with count-off

    func togglePlayPause() {
        if countOffTask != nil {
            cancelCountOff()
            return
        }
        if playback.isPlaying {
            playback.pause()
            return
        }
        if countOffEnabled, let grid = beats.grid {
            startCountOff(grid: grid)
        } else {
            playback.play()
        }
    }

    /// Audible + visual count-off, in time with the playhead's position in
    /// the 8-count: the counts lead into the playhead's count (playhead on
    /// 1 → "5 6 7 8"; on 2 → "5 6 7 8 1"; on 8 → "5 6 7"; on 6 →
    /// "1 2 3 4 5"), at least 3 counts, always starting on 5 or 1, spaced
    /// one beat at the current practice rate so playback lands on the beat.
    private func startCountOff(grid: BeatGrid) {
        var startTime = grid.nearestBeatTime(to: playback.currentTime)
        if playback.duration > 0 {
            startTime = min(max(startTime, 0), playback.duration)
        }
        playback.seek(to: startTime)

        let sequence = Self.countOffSequence(target: grid.count(at: startTime))
        let interval = grid.beatInterval / playback.rate
        // Media time where a music count-in would begin. Falls back to
        // ticks-only when there isn't enough music before the playhead.
        let leadTime = startTime - Double(sequence.count) * grid.beatInterval
        let musicCountIn = countInMusicEnabled && leadTime >= 0

        if musicCountIn {
            countInTargetTime = startTime
            playback.seek(to: leadTime)
            playback.play()
        }
        countOffPlayer.playTicks(counts: sequence, interval: interval)
        countOffTask = Task { [weak self] in
            // Absolute deadlines from a fixed origin — no per-count drift, so
            // playback starts exactly `sequence.count` beats after tick one.
            let clock = ContinuousClock()
            let origin = clock.now
            for (i, count) in sequence.enumerated() {
                guard !Task.isCancelled else { return }
                self?.countOffLabel = String(count)
                try? await clock.sleep(
                    until: origin + .seconds(interval * Double(i + 1)),
                    tolerance: .milliseconds(2)
                )
            }
            guard !Task.isCancelled, let self else { return }
            self.countOffLabel = nil
            self.countOffTask = nil
            if musicCountIn {
                // Music has caught up to the target; the wheel resumes
                // following the (already playing) transport.
                self.countInTargetTime = nil
            } else {
                self.playback.play()
            }
        }
    }

    /// The counts to speak before a beat whose count is `target`: the run
    /// ends one count before `target`, starts on 5 or 1 (whichever gives the
    /// shortest run of at least 3 counts), wrapping through 8 → 1 as needed.
    static func countOffSequence(target: Int) -> [Int] {
        let end = target == 1 ? 8 : target - 1
        func length(from start: Int) -> Int { ((end - start + 8) % 8) + 1 }
        let candidates = [5, 1]
            .map { (start: $0, length: length(from: $0)) }
            .filter { $0.length >= 3 }
        let chosen = candidates.min { $0.length < $1.length }
            ?? (start: 5, length: length(from: 5))
        return (0..<chosen.length).map { ((chosen.start - 1 + $0) % 8) + 1 }
    }

    private func cancelCountOff() {
        countOffTask?.cancel()
        countOffTask = nil
        countOffLabel = nil
        countOffPlayer.stop()
        if countInTargetTime != nil {
            countInTargetTime = nil
            playback.pause()
        }
    }

    // MARK: - Scrubbing (wheel → transport + scratch audio)

    func beginScrub() {
        cancelCountOff()
        playback.beginScrub()
        if scrubAudioEnabled {
            scrubAudio.begin(at: playback.currentTime)
        }
    }

    func scrubMove(to time: Double) {
        playback.scrub(to: time)
        if scrubAudioEnabled {
            scrubAudio.update(time: time)
        }
    }

    func endScrub() {
        scrubAudio.end()
        playback.endScrub()
    }

    private func loadScrubAudio(_ document: VideoDocument) {
        guard let audioURL = document.audioURL else { return }
        let engine = scrubAudio
        Task.detached(priority: .utility) {
            guard let (samples, sampleRate) = try? AudioAnalyzer.readMonoSamples(from: audioURL) else { return }
            engine.load(monoSamples: samples, sampleRate: sampleRate)
        }
    }

    /// Reopen the most recently used video (with its saved grid) on launch.
    func restoreLastSession() {
        guard document == nil,
              let (restoredDocument, state) = DocumentStore.loadMostRecent() else { return }
        load(restoredDocument, restored: state)
    }

    func closeDocument() {
        cancelCountOff()
        playback.pause()
        scrubAudio.unload()
        saveState()
        document = nil
        beats.reset()
        markers.reset()
    }

    /// Mutate the beat grid (creating one if needed) and persist the change.
    func updateGrid(_ transform: (inout BeatGrid) -> Void) {
        var grid = beats.grid ?? BeatGrid(firstBeatTime: 0, bpm: beats.detectedBPM ?? 120)
        transform(&grid)
        grid.bpm = min(max(grid.bpm, 20), 300)
        beats.grid = grid
        saveState()
    }

    // MARK: - Markers & A/B loops

    /// Drop a marker at the current playhead (wheel long-press + rail button).
    func addMarkerAtPlayhead() {
        markers.markers.append(Marker(time: playback.currentTime, name: defaultMarkerName()))
        saveState()
    }

    /// Lowest positive integer not already used as a marker name, so the
    /// default names stay stable and short as markers come and go.
    private func defaultMarkerName() -> String {
        let used = Set(markers.markers.compactMap { Int($0.name) })
        var n = 1
        while used.contains(n) { n += 1 }
        return String(n)
    }

    /// Jump the playhead to a marker. Keeps playing if it was playing.
    func snapToMarker(_ marker: Marker) {
        cancelCountOff()
        playback.seek(to: marker.time)
    }

    func renameMarker(_ marker: Marker, to name: String) {
        guard let i = markers.markers.firstIndex(where: { $0.id == marker.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        markers.markers[i].name = trimmed
        saveState()
    }

    func deleteMarker(_ marker: Marker) {
        markers.markers.removeAll { $0.id == marker.id }
        saveState()
    }

    /// Move a marker up (-1) or down (+1) in the rail's order.
    func moveMarker(_ marker: Marker, by delta: Int) {
        guard let i = markers.markers.firstIndex(where: { $0.id == marker.id }) else { return }
        let j = i + delta
        guard markers.markers.indices.contains(j) else { return }
        markers.markers.swapAt(i, j)
        saveState()
    }

    func setLoopA() {
        markers.loopA = playback.currentTime
        normalizeLoop()
        saveState()
    }

    func setLoopB() {
        markers.loopB = playback.currentTime
        normalizeLoop()
        saveState()
    }

    func toggleLoop() {
        guard markers.loopRange != nil else { return }
        markers.loopEnabled.toggle()
        saveState()
    }

    func clearLoop() {
        markers.loopA = nil
        markers.loopB = nil
        markers.loopEnabled = false
        saveState()
    }

    /// Keep A before B; a loop that can't be valid can't be enabled.
    private func normalizeLoop() {
        if let a = markers.loopA, let b = markers.loopB, a > b {
            swap(&markers.loopA, &markers.loopB)
        }
        if markers.loopRange == nil { markers.loopEnabled = false }
    }

    /// Called from the master playhead each tick: wrap the loop at B.
    private func handlePlayheadTick(_ time: Double) {
        guard markers.loopEnabled, playback.isPlaying, countOffTask == nil,
              let range = markers.loopRange else { return }
        // 30 ms guard band so we wrap just before overshooting B.
        if time >= range.upperBound - 0.03 {
            loopBackToStart(range.lowerBound)
        }
    }

    private func loopBackToStart(_ start: Double) {
        // With count-off on, count back into the loop each pass (respects the
        // music-count-in variant too); otherwise just seek and keep playing.
        if countOffEnabled, let grid = beats.grid {
            playback.pause()
            playback.seek(to: start)
            startCountOff(grid: grid)
        } else {
            playback.seek(to: start)
        }
    }

    // MARK: - Latency calibration

    private func refreshLatencyForCurrentRoute() {
        latencyOffset = LatencyStore.offset(forRouteKey: LatencyStore.currentRouteKey()) ?? 0
        calibrationRouteName = LatencyStore.currentRouteName()
    }

    private func handleRouteChange() {
        let key = LatencyStore.currentRouteKey()
        latencyOffset = LatencyStore.offset(forRouteKey: key) ?? 0
        calibrationRouteName = LatencyStore.currentRouteName()
        // Nudge the user to calibrate the first time a wireless output with
        // no stored offset appears.
        if LatencyStore.currentRouteIsWireless(), LatencyStore.offset(forRouteKey: key) == nil {
            showCalibrationPrompt = true
        }
    }

    /// Store the calibrated offset for the current route and apply it live.
    func applyCalibration(offset: Double) {
        LatencyStore.setOffset(offset, forRouteKey: LatencyStore.currentRouteKey())
        latencyOffset = offset
        showCalibrationPrompt = false
    }

    func saveState() {
        guard let document else { return }
        DocumentStore.save(StoredPracticeState(
            id: document.id,
            title: document.title,
            videoFileName: document.videoURL.lastPathComponent,
            audioFileName: document.audioURL?.lastPathComponent,
            grid: beats.grid,
            detectedBPM: beats.detectedBPM,
            detectionConfidence: beats.detectionConfidence,
            playbackRate: playback.rate,
            countOffEnabled: countOffEnabled,
            countInMusicEnabled: countInMusicEnabled,
            markers: markers.markers,
            loopA: markers.loopA,
            loopB: markers.loopB,
            loopEnabled: markers.loopEnabled,
            lastOpened: .now
        ))
    }

    private func analyze(_ document: VideoDocument) {
        guard let audioURL = document.audioURL else { return }
        beats.isAnalyzing = true
        let cacheURL = (try? MediaImporter.videosDirectory())?
            .appendingPathComponent("\(document.id.uuidString).waveform.json")
        let needsTempo = beats.grid == nil

        Task { [weak self] in
            let waveform = try? await Task.detached(priority: .userInitiated) {
                try AudioAnalyzer.waveform(audioURL: audioURL, cacheURL: cacheURL)
            }.value
            let tempo: TempoEstimate? = needsTempo
                ? try? await Task.detached(priority: .userInitiated) {
                    try AudioAnalyzer.detectTempo(audioURL: audioURL)
                }.value
                : nil

            guard let self, self.document?.id == document.id else { return }
            self.beats.waveform = waveform
            if let tempo {
                self.beats.detectedBPM = tempo.bpm
                self.beats.detectionConfidence = tempo.confidence
                if self.beats.grid == nil {
                    self.beats.grid = BeatGrid(firstBeatTime: tempo.firstBeatTime, bpm: tempo.bpm)
                }
                self.saveState()
            }
            self.beats.isAnalyzing = false
        }
    }
}
