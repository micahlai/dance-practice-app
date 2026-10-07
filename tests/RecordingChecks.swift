import AVFoundation
import Foundation

// The standalone harness links the production recording sources. This
// dependency is only needed to compile DocumentStore; no practice library
// or app sandbox is opened by these checks.
enum MediaImporter {
    static func videosDirectory() throws -> URL { throw CocoaError(.fileReadNoSuchFile) }
}

@main struct RecordingChecks {
    @MainActor static func main() async throws {
        let fixtureDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let grid = BeatGrid(firstBeatTime: 0, bpm: 120)
        for rate in [0.25, 0.5, 0.75, 1.0] {
            for landingCount in 1...8 {
                var settings = TakeSettings()
                settings.rate = rate
                settings.musicStart = 0
                settings.countInTime = 8 + Double(landingCount - 1) * 0.5
                let timeline = TakeTimeline(settings: settings, grid: grid)
                let landing = timeline.counts.last!
                assert(landing.label == String(landingCount))
                assert(abs(landing.wallTime - timeline.musicDelay - settings.countInTime / rate) < 0.0001)
                assert(timeline.counts.first!.wallTime >= 0)
                assert(timeline.counts.count >= 4)
                for pair in zip(timeline.counts, timeline.counts.dropFirst()) {
                    assert(abs(pair.1.wallTime - pair.0.wallTime - 0.5 / rate) < 0.0001)
                }
            }
        }
        var preRoll = TakeSettings()
        preRoll.rate = 0.5
        let early = TakeTimeline(settings: preRoll, grid: grid)
        assert(abs(early.musicDelay - 4.25) < 0.0001)
        assert(abs(early.counts.first!.wallTime - 0.25) < 0.0001)
        preRoll.countInEnabled = false
        assert(TakeTimeline(settings: preRoll, grid: grid).counts.isEmpty)
        assert(TakeTimeline(settings: preRoll, grid: nil).counts.isEmpty)
        print("PASS: independent count-in / music timing across four speeds and all eight landing counts")

        let cameraURL = fixtureDirectory.appendingPathComponent("choreo-camera.mov")
        let referenceURL = fixtureDirectory.appendingPathComponent("choreo-reference.mp4")
        let draftRoot = fixtureDirectory.appendingPathComponent("draft-library", isDirectory: true)
        var savedSettings = TakeSettings()
        savedSettings.rate = 0.5
        savedSettings.layout = .sideBySide
        let document = VideoDocument(id: UUID(), title: "Reference fixture", videoURL: referenceURL, audioURL: nil)
        let draft = try await TakeDraftStore.save(cameraURL: cameraURL, document: document, settings: savedSettings,
                                                 grid: grid, musicDelay: 0.5, duration: 4, into: draftRoot)
        savedSettings.rate = 1
        let restored = try TakeDraftStore.load(from: draftRoot)
        assert(restored.count == 1 && restored[0].id == draft.id)
        assert(restored[0].settings.rate == 0.5 && restored[0].settings.layout == .sideBySide)
        assert(restored[0].grid == grid && restored[0].musicDelay == 0.5)
        let savedFolder = draftRoot.appendingPathComponent(draft.id.uuidString)
        let savedFiles = try FileManager.default.contentsOfDirectory(at: savedFolder, includingPropertiesForKeys: nil)
        let expectedSize = try savedFiles.reduce(Int64(0)) { total, url in total + Int64(try Data(contentsOf: url).count) }
        assert(TakeDraftStore.storageBytes(for: draft, in: draftRoot) == expectedSize)
        let cameraMatches = try Data(contentsOf: savedFolder.appendingPathComponent(draft.cameraFileName)) == Data(contentsOf: cameraURL)
        let referenceMatches = try Data(contentsOf: savedFolder.appendingPathComponent(draft.referenceFileName)) == Data(contentsOf: referenceURL)
        assert(cameraMatches && referenceMatches)
        print("PASS: draft sources and capture settings survive save/reload; storage includes every saved byte")

        let beforeFailure = try FileManager.default.contentsOfDirectory(atPath: draftRoot.path)
        let missingReference = VideoDocument(id: UUID(), title: "Missing", videoURL: fixtureDirectory.appendingPathComponent("missing.mp4"), audioURL: nil)
        do {
            _ = try await TakeDraftStore.save(cameraURL: cameraURL, document: missingReference, settings: savedSettings,
                                              grid: grid, musicDelay: 0.5, duration: 4, into: draftRoot)
            assertionFailure("Saving a missing reference must fail")
        } catch {
            let afterFailure = try FileManager.default.contentsOfDirectory(atPath: draftRoot.path)
            assert(Set(afterFailure) == Set(beforeFailure))
        }
        let broken = draftRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("invalid draft metadata".utf8).write(to: broken.appendingPathComponent("take.json"))
        let validDrafts = try TakeDraftStore.load(from: draftRoot)
        assert(validDrafts.count == 1 && validDrafts[0].id == draft.id)
        try TakeDraftStore.delete(draft, from: draftRoot)
        let remainingDrafts = try TakeDraftStore.load(from: draftRoot)
        assert(remainingDrafts.isEmpty && TakeDraftStore.storageBytes(for: draft, in: draftRoot) == 0)
        assert(FileManager.default.fileExists(atPath: cameraURL.path) && FileManager.default.fileExists(atPath: referenceURL.path))
        print("PASS: failed save is atomic, invalid drafts are skipped, and deletion preserves source footage")

        let cancelled = Task { @MainActor in
            try await TakeExporter.render(cameraURL: cameraURL, referenceURL: referenceURL, settings: savedSettings, musicDelay: 0.5)
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            assertionFailure("An already-cancelled export must not run")
        } catch is CancellationError {}
        let exporting = Task { @MainActor in
            try await TakeExporter.render(cameraURL: cameraURL, referenceURL: referenceURL, settings: savedSettings, musicDelay: 0.5)
        }
        try await Task.sleep(for: .milliseconds(30))
        exporting.cancel()
        do {
            _ = try await exporting.value
            assertionFailure("A cancelled export must not return a movie")
        } catch is CancellationError {}
        print("PASS: cancellation before and during export does not return an unused video")

        for layout in ReferenceLayout.allCases {
            for normalize in [false, true] {
                var settings = TakeSettings()
                settings.rate = 0.5
                settings.musicStart = 1
                settings.layout = layout
                settings.adjustToNormalSpeed = normalize
                let output = try await TakeExporter.render(cameraURL: fixtureDirectory.appendingPathComponent("choreo-camera.mov"),
                                                           referenceURL: fixtureDirectory.appendingPathComponent("choreo-reference.mp4"),
                                                           settings: settings, musicDelay: 0.5)
                let asset = AVURLAsset(url: output)
                let duration = try await asset.load(.duration).seconds
                assert(abs(duration - (normalize ? 2 : 4)) < 0.08)
                let audio = try await asset.loadTracks(withMediaType: .audio)
                assert(audio.count == 1)
                let video = try await asset.loadTracks(withMediaType: .video)
                let size = try await video[0].load(.naturalSize)
                assert(size == CGSize(width: 1920, height: 1080))
                let destination = fixtureDirectory.appendingPathComponent("\(layout.rawValue)-\(normalize ? "normal" : "slow").mp4")
                try FileManager.default.moveItem(at: output, to: destination)
                print("PASS: \(layout.rawValue), \(normalize ? "normalized" : "original speed"), \(duration)s, one clean audio track")
            }
        }
        // A take stopped before the music starts must still export its
        // camera track and must not read past the reference's duration.
        var settings = TakeSettings()
        settings.layout = .pictureInPicture
        let silent = try await TakeExporter.render(cameraURL: fixtureDirectory.appendingPathComponent("choreo-camera.mov"),
                                                   referenceURL: fixtureDirectory.appendingPathComponent("choreo-reference.mp4"),
                                                   settings: settings, musicDelay: 10)
        let silentAudio = try await AVURLAsset(url: silent).loadTracks(withMediaType: .audio)
        assert(silentAudio.isEmpty)
        try FileManager.default.moveItem(at: silent, to: fixtureDirectory.appendingPathComponent("stopped-before-music.mp4"))
        print("PASS: stop before music starts exports a valid silent take")
    }
}
