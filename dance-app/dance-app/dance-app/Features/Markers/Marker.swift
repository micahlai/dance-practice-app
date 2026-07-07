import Foundation
import Observation

/// A user-set cue point on the timeline. `time` is media seconds.
struct Marker: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var time: Double
    var name: String
}

/// Markers + A/B loop for the current video. Owned by `AppState`; the rail
/// and the scroller both render from here, and `AppState` persists it.
@MainActor
@Observable
final class MarkersModel {
    /// User-ordered cue points. The rail respects this order (rename /
    /// reorder / delete); the scroller draws each at its time regardless.
    var markers: [Marker] = []

    /// A/B loop bounds (media seconds) and whether looping is active.
    var loopA: Double?
    var loopB: Double?
    var loopEnabled = false

    /// A usable loop needs both ends with B strictly after A.
    var loopRange: ClosedRange<Double>? {
        guard let a = loopA, let b = loopB, b > a else { return nil }
        return a...b
    }

    func reset() {
        markers = []
        loopA = nil
        loopB = nil
        loopEnabled = false
    }
}
