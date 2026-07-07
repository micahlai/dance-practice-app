import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    private(set) var document: VideoDocument?
    let playback = PlaybackEngine()

    func load(_ document: VideoDocument) {
        self.document = document
        playback.load(url: document.videoURL)
    }

    func closeDocument() {
        playback.pause()
        document = nil
    }
}
