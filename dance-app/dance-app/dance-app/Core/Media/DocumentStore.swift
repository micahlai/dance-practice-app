import Foundation

/// Audible guide played during normal video playback.
enum BeatClickMode: Int, Codable, CaseIterable {
    case off
    case beats
    case beatsAndHalf

    var next: Self {
        switch self {
        case .off: .beats
        case .beats: .beatsAndHalf
        case .beatsAndHalf: .off
        }
    }

    var accessibilityValue: String {
        switch self {
        case .off: "Off"
        case .beats: "One click per beat"
        case .beatsAndHalf: "Clicks on the beat and half count"
        }
    }
}

/// Sidecar JSON persisted next to each imported video (`<id>.state.json`).
/// Stores filenames, not absolute URLs — the container path changes across
/// app updates.
struct StoredPracticeState: Codable {
    var id: UUID
    var title: String
    var videoFileName: String
    var audioFileName: String?
    var grid: BeatGrid?
    var detectedBPM: Double?
    var detectionConfidence: Double?
    var playbackRate: Double?
    var countOffEnabled: Bool?
    var countInMusicEnabled: Bool?
    var beatClickMode: BeatClickMode? = nil
    // M5 — markers & A/B loop (optional so pre-M5 sidecars still decode).
    var markers: [Marker]? = nil
    var loopA: Double? = nil
    var loopB: Double? = nil
    var loopEnabled: Bool? = nil
    var lastOpened: Date
}

/// A saved practice session that can be reopened from the home screen.
struct RecentVideo: Identifiable {
    let document: VideoDocument
    let state: StoredPracticeState

    var id: UUID { document.id }
    var lastOpened: Date { state.lastOpened }
}

enum DocumentStore {
    static func save(_ state: StoredPracticeState) {
        guard let dir = try? MediaImporter.videosDirectory(),
              let data = try? JSONEncoder().encode(state) else { return }
        let url = dir.appendingPathComponent("\(state.id.uuidString).state.json")
        try? data.write(to: url, options: .atomic)
    }

    /// Saved videos ordered by most recently opened, excluding entries whose
    /// video file has been removed outside the app.
    static func loadRecent(limit: Int = 6) -> [RecentVideo] {
        guard let dir = try? MediaImporter.videosDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        let states = files
            .filter { $0.lastPathComponent.hasSuffix(".state.json") }
            .compactMap { url -> StoredPracticeState? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(StoredPracticeState.self, from: data)
            }
            .sorted { $0.lastOpened > $1.lastOpened }

        return states.lazy.compactMap { state in
            let videoURL = dir.appendingPathComponent(state.videoFileName)
            guard FileManager.default.fileExists(atPath: videoURL.path) else { return nil }
            let audioURL = state.audioFileName.map { dir.appendingPathComponent($0) }
            let document = VideoDocument(
                id: state.id,
                title: state.title,
                videoURL: videoURL,
                audioURL: audioURL
            )
            return RecentVideo(document: document, state: state)
        }
        .prefix(max(0, limit))
        .map { $0 }
    }

    /// The most recently opened document whose video file still exists.
    static func loadMostRecent() -> (document: VideoDocument, state: StoredPracticeState)? {
        guard let recent = loadRecent(limit: 1).first else { return nil }
        return (recent.document, recent.state)
    }
}
