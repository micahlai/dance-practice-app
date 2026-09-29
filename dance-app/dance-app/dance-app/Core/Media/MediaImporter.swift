import AVFoundation
import Foundation

enum MediaImportError: LocalizedError {
    case notPlayable
    case audioExportFailed

    var errorDescription: String? {
        switch self {
        case .notPlayable:
            "This file can't be played as a video."
        case .audioExportFailed:
            "Couldn't extract the audio track."
        }
    }
}

/// Copies videos into the app library and extracts their audio track.
enum MediaImporter {
    static func videosDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("Videos", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copies the source video into the app library and extracts its audio.
    static func importVideo(from sourceURL: URL, title: String) async throws -> VideoDocument {
        guard try await AVURLAsset(url: sourceURL).load(.isPlayable) else {
            throw MediaImportError.notPlayable
        }
        let id = UUID()
        let dir = try videosDirectory()
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let videoURL = dir.appendingPathComponent("\(id.uuidString).\(ext)")
        try FileManager.default.copyItem(at: sourceURL, to: videoURL)
        let audioURL = try await extractAudio(from: videoURL, id: id, into: dir)
        return VideoDocument(id: id, title: title, videoURL: videoURL, audioURL: audioURL)
    }

    private static func extractAudio(from videoURL: URL, id: UUID, into dir: URL) async throws -> URL? {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { return nil }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MediaImportError.audioExportFailed
        }
        let audioURL = dir.appendingPathComponent("\(id.uuidString).m4a")
        if #available(iOS 18, *) {
            do {
                try await session.export(to: audioURL, as: .m4a)
            } catch {
                throw MediaImportError.audioExportFailed
            }
        } else {
            session.outputURL = audioURL
            session.outputFileType = .m4a
            await session.export()
            guard session.status == .completed else {
                throw MediaImportError.audioExportFailed
            }
        }
        return audioURL
    }
}
