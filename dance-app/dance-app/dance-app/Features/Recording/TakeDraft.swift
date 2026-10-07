import Foundation

nonisolated enum ReferenceLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case camera, sideBySide, pictureInPicture
    var id: String { rawValue }
    var title: String {
        switch self {
        case .camera: "Camera only"
        case .sideBySide: "Side by side"
        case .pictureInPicture: "Picture in picture"
        }
    }
}

nonisolated struct TakeSettings: Codable, Equatable, Sendable {
    var musicStart: Double = 0
    /// Media time the dancer lands on after the count-in.
    var countInTime: Double = 0
    var countInEnabled = true
    var rate: Double = 1
    var adjustToNormalSpeed = true
    var layout: ReferenceLayout = .camera
    var metronome: BeatClickMode = .off
}

/// Persisted capture-time settings: exports never depend on the current
/// practice session or subsequently changed controls.
nonisolated struct TakeDraft: Codable, Identifiable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    let referenceTitle: String
    let settings: TakeSettings
    let grid: BeatGrid?
    let cameraFileName: String
    let referenceFileName: String
    /// Wall seconds into the camera file at which reference playback starts.
    let musicDelay: Double
    let duration: Double

    var directory: URL { get throws { try TakeDraftStore.directory().appendingPathComponent(id.uuidString) } }
    var cameraURL: URL { get throws { try directory.appendingPathComponent(cameraFileName) } }
    var referenceURL: URL { get throws { try directory.appendingPathComponent(referenceFileName) } }
    var finalDuration: Double { duration * (settings.adjustToNormalSpeed ? settings.rate : 1) }
}

nonisolated enum TakeDraftStore {
    static func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let result = base.appendingPathComponent("Takes", isDirectory: true)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }

    static func load() throws -> [TakeDraft] {
        let root = try directory()
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .compactMap { folder -> TakeDraft? in
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("take.json")),
                      let draft = try? JSONDecoder().decode(TakeDraft.self, from: data),
                      folder.lastPathComponent == draft.id.uuidString,
                      let camera = try? draft.cameraURL, let reference = try? draft.referenceURL,
                      FileManager.default.fileExists(atPath: camera.path),
                      FileManager.default.fileExists(atPath: reference.path) else { return nil }
                return draft
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @concurrent static func save(cameraURL: URL, document: VideoDocument, settings: TakeSettings,
                                 grid: BeatGrid?, musicDelay: Double, duration: Double) async throws -> TakeDraft {
        let id = UUID()
        let root = try directory()
        let staging = root.appendingPathComponent("pending-\(id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let referenceName = "reference.\(document.videoURL.pathExtension)"
            try FileManager.default.copyItem(at: cameraURL, to: staging.appendingPathComponent("camera.mov"))
            try FileManager.default.copyItem(at: document.videoURL, to: staging.appendingPathComponent(referenceName))
            let draft = TakeDraft(id: id, title: "Take \(Date().formatted(date: .abbreviated, time: .shortened))",
                                  createdAt: Date(), referenceTitle: document.title, settings: settings,
                                  grid: grid, cameraFileName: "camera.mov", referenceFileName: referenceName,
                                  musicDelay: musicDelay, duration: duration)
            try JSONEncoder().encode(draft).write(to: staging.appendingPathComponent("take.json"), options: .atomic)
            try FileManager.default.moveItem(at: staging, to: root.appendingPathComponent(id.uuidString))
            return draft
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    static func delete(_ draft: TakeDraft) throws {
        try FileManager.default.removeItem(at: draft.directory)
    }

    static func storageBytes(for draft: TakeDraft) -> Int64 {
        guard let folder = try? draft.directory,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

extension Notification.Name {
    static let takeLibraryDidChange = Notification.Name("takeLibraryDidChange")
}

/// One timeline used by live guides, reference playback, and export.
struct TakeTimeline {
    let musicDelay: Double
    let counts: [(label: String, wallTime: Double)]

    init(settings: TakeSettings, grid: BeatGrid?) {
        guard settings.countInEnabled, let grid else {
            musicDelay = 0.25
            counts = []
            return
        }
        let sequence = CountOffSequence.counts(before: grid.count(at: settings.countInTime))
        let firstCount = settings.countInTime - Double(sequence.count) * grid.beatInterval
        let delay = 0.25 + max(0, (settings.musicStart - firstCount) / settings.rate)
        musicDelay = delay
        counts = sequence.enumerated().map { index, count in
            let time = firstCount + Double(index) * grid.beatInterval
            return (String(count), delay + (time - settings.musicStart) / settings.rate)
        } + [(String(grid.count(at: settings.countInTime)),
               delay + (settings.countInTime - settings.musicStart) / settings.rate)]
    }
}
