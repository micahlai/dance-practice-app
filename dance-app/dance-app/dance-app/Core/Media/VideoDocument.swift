import Foundation

/// One imported video and its extracted audio track.
nonisolated struct VideoDocument: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var videoURL: URL
    /// Extracted audio (m4a) used for waveform/tempo analysis; nil when the
    /// video has no audio track.
    var audioURL: URL?
}
