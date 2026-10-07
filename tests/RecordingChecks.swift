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
