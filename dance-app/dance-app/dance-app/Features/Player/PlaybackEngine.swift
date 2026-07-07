import AVFoundation
import Observation

/// Wraps AVPlayer and owns the master playhead state. All UI renders from
/// `currentTime`/`duration` here — no other component owns "current time".
@MainActor
@Observable
final class PlaybackEngine {
    let player = AVPlayer()

    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    init() {
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTime = time.seconds
            }
        }
    }

    func load(url: URL) {
        let item = AVPlayerItem(url: url)
        // Preserves pitch at practice speeds (M4 speed control).
        item.audioTimePitchAlgorithm = .timeDomain
        player.replaceCurrentItem(with: item)
        isPlaying = false
        currentTime = 0
        duration = 0

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPlaying = false
            }
        }

        Task { [weak self] in
            if let seconds = try? await item.asset.load(.duration).seconds, seconds.isFinite {
                self?.duration = seconds
            }
        }
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        // Restart from the top if we're parked at the end.
        if duration > 0, currentTime >= duration - 0.05 {
            seek(to: 0)
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) {
        let clamped = max(0, duration > 0 ? min(seconds, duration) : seconds)
        currentTime = clamped
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
