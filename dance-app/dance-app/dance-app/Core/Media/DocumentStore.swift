import Foundation

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
    var lastOpened: Date
}

enum DocumentStore {
    static func save(_ state: StoredPracticeState) {
        guard let dir = try? MediaImporter.videosDirectory(),
              let data = try? JSONEncoder().encode(state) else { return }
        let url = dir.appendingPathComponent("\(state.id.uuidString).state.json")
        try? data.write(to: url, options: .atomic)
    }

    /// The most recently opened document whose video file still exists.
    static func loadMostRecent() -> (document: VideoDocument, state: StoredPracticeState)? {
        guard let dir = try? MediaImporter.videosDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        let decoder = JSONDecoder()
        let states = files
            .filter { $0.lastPathComponent.hasSuffix(".state.json") }
            .compactMap { url -> StoredPracticeState? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(StoredPracticeState.self, from: data)
            }
            .sorted { $0.lastOpened > $1.lastOpened }

        for state in states {
            let videoURL = dir.appendingPathComponent(state.videoFileName)
            guard FileManager.default.fileExists(atPath: videoURL.path) else { continue }
            let audioURL = state.audioFileName.map { dir.appendingPathComponent($0) }
            let document = VideoDocument(id: state.id, title: state.title, videoURL: videoURL, audioURL: audioURL)
            return (document, state)
        }
        return nil
    }
}
