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
    private(set) var isScrubbing = false

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var wasPlayingBeforeScrub = false
    @ObservationIgnored private var seekInFlight = false
    @ObservationIgnored private var pendingScrubSeek: Double?

    init() {
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                self.currentTime = time.seconds
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

    // MARK: - Scrubbing

    /// Wheel touch-down: remember transport state and take over the playhead.
    func beginScrub() {
        guard !isScrubbing else { return }
        wasPlayingBeforeScrub = isPlaying
        pause()
        isScrubbing = true
    }

    /// Continuous playhead updates while dragging/coasting. Video seeks are
    /// throttled (one in flight, latest wins) with loose tolerance for speed.
    func scrub(to seconds: Double) {
        guard isScrubbing else { return }
        let clamped = max(0, duration > 0 ? min(seconds, duration) : seconds)
        currentTime = clamped
        if seekInFlight {
            pendingScrubSeek = clamped
        } else {
            issueScrubSeek(clamped)
        }
    }

    /// Wheel release (after inertia): precise final seek, restore transport.
    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        pendingScrubSeek = nil
        seek(to: currentTime)
        if wasPlayingBeforeScrub {
            play()
        }
    }

    private func issueScrubSeek(_ seconds: Double) {
        seekInFlight = true
        let tolerance = CMTime(seconds: 0.04, preferredTimescale: 600)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.seekInFlight = false
                if let pending = self.pendingScrubSeek, self.isScrubbing {
                    self.pendingScrubSeek = nil
                    self.issueScrubSeek(pending)
                }
            }
        }
    }
}
