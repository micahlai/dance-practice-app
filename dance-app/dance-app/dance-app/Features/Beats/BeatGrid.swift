import Foundation

/// The beat grid is a pure function of (firstBeatTime, bpm). Counts cycle
/// 1–8 from the "1"; half-beats are "and" counts.
struct BeatGrid: Codable, Equatable, Sendable {
    var firstBeatTime: Double
    var bpm: Double

    var beatInterval: Double { 60 / bpm }

    struct Tick: Identifiable, Sendable {
        /// Half-beat index relative to the "1" (even = beat, odd = "and").
        let id: Int
        let time: Double
        let isAnd: Bool
        /// 1...8 count of the owning beat.
        let count: Int

        var label: String { isAnd ? "&" : String(count) }
    }

    func ticks(in range: ClosedRange<Double>, includeAnds: Bool = true) -> [Tick] {
        guard bpm > 0 else { return [] }
        let halfInterval = beatInterval / 2
        let firstIndex = Int(floor((range.lowerBound - firstBeatTime) / halfInterval))
        let lastIndex = Int(ceil((range.upperBound - firstBeatTime) / halfInterval))
        guard lastIndex >= firstIndex else { return [] }

        var result: [Tick] = []
        for halfBeat in firstIndex...lastIndex {
            let time = firstBeatTime + Double(halfBeat) * halfInterval
            guard range.contains(time) else { continue }
            let isAnd = ((halfBeat % 2) + 2) % 2 != 0
            if isAnd && !includeAnds { continue }
            let beatIndex = Int(floor(Double(halfBeat) / 2))
            let count = ((beatIndex % 8) + 8) % 8 + 1
            result.append(Tick(id: halfBeat, time: time, isAnd: isAnd, count: count))
        }
        return result
    }

    func nearestBeatTime(to time: Double) -> Double {
        guard bpm > 0 else { return time }
        let k = ((time - firstBeatTime) / beatInterval).rounded()
        return firstBeatTime + k * beatInterval
    }

    /// The 1...8 count of the beat nearest to `time`.
    func count(at time: Double) -> Int {
        guard bpm > 0 else { return 1 }
        let index = Int(((time - firstBeatTime) / beatInterval).rounded())
        return ((index % 8) + 8) % 8 + 1
    }
}
