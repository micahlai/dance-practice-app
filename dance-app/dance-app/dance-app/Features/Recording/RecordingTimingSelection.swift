import Foundation

enum RecordingTimingTarget: String, Identifiable {
    case musicStart, countIn
    var id: String { rawValue }
    var title: String { self == .musicStart ? "Music starts at" : "Count-in lands at" }

    /// A landing must be a real beat at/after music start and before the
    /// media ends. Return nil when no such beat exists, rather than silently
    /// choosing an out-of-range beat or a non-beat endpoint.
    func selection(at time: Double, musicStart: Double, duration: Double, grid: BeatGrid?) -> Double? {
        guard time.isFinite, musicStart.isFinite, duration.isFinite, duration > 0 else { return nil }
        if self == .musicStart { return min(max(time, 0), max(0, duration - 0.1)) }
        guard let grid, grid.bpm.isFinite, grid.bpm > 0, grid.firstBeatTime.isFinite else { return nil }
        let interval = grid.beatInterval
        guard interval.isFinite, interval > 0 else { return nil }
        let first = ceil((max(0, musicStart) - grid.firstBeatTime) / interval)
        // Strictly less than duration, even when the end falls on a beat.
        let last = ceil((duration - grid.firstBeatTime) / interval) - 1
        guard first <= last else { return nil }
        let nearest = ((time - grid.firstBeatTime) / interval).rounded()
        return grid.firstBeatTime + min(max(nearest, first), last) * interval
    }
}
