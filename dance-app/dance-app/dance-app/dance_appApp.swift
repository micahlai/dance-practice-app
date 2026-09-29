import AVFAudio
import SwiftUI

@main
struct dance_appApp: App { 
    @State private var appState = AppState()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            MainShellView()
                .environment(appState)
        }
    }
}
