import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    private(set) var document: VideoDocument?
    let playback = PlaybackEngine()
    let beats = BeatsModel()

    func load(_ document: VideoDocument, restored: StoredPracticeState? = nil) {
        self.document = document
        playback.load(url: document.videoURL)
        beats.reset()
        beats.grid = restored?.grid
        beats.detectedBPM = restored?.detectedBPM
        beats.detectionConfidence = restored?.detectionConfidence
        saveState()
        analyze(document)
    }

    /// Reopen the most recently used video (with its saved grid) on launch.
    func restoreLastSession() {
        guard document == nil,
              let (restoredDocument, state) = DocumentStore.loadMostRecent() else { return }
        load(restoredDocument, restored: state)
    }

    func closeDocument() {
        playback.pause()
        saveState()
        document = nil
        beats.reset()
    }

    /// Mutate the beat grid (creating one if needed) and persist the change.
    func updateGrid(_ transform: (inout BeatGrid) -> Void) {
        var grid = beats.grid ?? BeatGrid(firstBeatTime: 0, bpm: beats.detectedBPM ?? 120)
        transform(&grid)
        grid.bpm = min(max(grid.bpm, 20), 300)
        beats.grid = grid
        saveState()
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
