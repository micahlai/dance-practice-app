import Observation

@MainActor
@Observable
final class BeatsModel {
    var waveform: WaveformData?
    var grid: BeatGrid?
    var detectedBPM: Double?
    var detectionConfidence: Double?
    var isAnalyzing = false

    func reset() {
        waveform = nil
        grid = nil
        detectedBPM = nil
        detectionConfidence = nil
        isAnalyzing = false
    }
}
