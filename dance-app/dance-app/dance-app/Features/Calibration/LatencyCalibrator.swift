import AVFoundation
import Observation
import QuartzCore

/// Drives the tap-to-beat calibration: plays a steady metronome and records
/// how far the user's taps land from the beat. The offset estimate is the
/// median signed error, which folds the route's output latency and the
/// dancer's own timing bias into one number — exactly what "feels on beat"
/// needs. Runs on the main actor; taps come from the UI, clicks from a
/// display link.
@MainActor
@Observable
final class LatencyCalibrator {
    private(set) var isRunning = false
    private(set) var tapCount = 0
    /// Running median of tap errors (seconds, signed). Positive = the user
    /// taps late, i.e. the audio they're following is delayed.
    private(set) var estimatedOffset: Double?

    /// Fixed calibration tempo — slow enough to tap comfortably.
    private let bpm = 100.0
    private var interval: Double { 60 / bpm }
    /// Taps needed before the estimate is trustworthy enough to save.
    let minimumTaps = 6

    @ObservationIgnored private let click = ClickPlayer()
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var startHostTime: CFTimeInterval = 0
    @ObservationIgnored private var nextBeatIndex = 0
    @ObservationIgnored private var errors: [Double] = []

    var canSave: Bool { tapCount >= minimumTaps && estimatedOffset != nil }

    func start() {
        stop()
        isRunning = true
        tapCount = 0
        estimatedOffset = nil
        errors = []
        nextBeatIndex = 0
        startHostTime = CACurrentMediaTime() + 0.4 // brief lead-in
        click.prepare()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        isRunning = false
        displayLink?.invalidate()
        displayLink = nil
        click.stop()
    }

    /// Register a tap the moment the finger goes down.
    func registerTap() {
        guard isRunning else { return }
        let now = CACurrentMediaTime()
        guard now >= startHostTime else { return }
        // Signed error against the nearest scheduled beat (works for both
        // early and late taps, unlike matching only beats already played).
        let k = ((now - startHostTime) / interval).rounded()
        let error = now - (startHostTime + k * interval)
        errors.append(error)
        tapCount = errors.count
        estimatedOffset = median(errors)
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        while startHostTime + Double(nextBeatIndex) * interval <= now {
            click.play()
            nextBeatIndex += 1
        }
    }

    private func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        let mid = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }
}

/// A single short metronome click, played immediately on demand.
@MainActor
final class ClickPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private let buffer: AVAudioPCMBuffer?

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        buffer = Self.makeClick(format: format)
    }

    func prepare() {
        if !engine.isRunning { try? engine.start() }
    }

    func play() {
        guard let buffer else { return }
        // `.interrupts` so each click fires now rather than queuing behind
        // the previous one.
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !node.isPlaying { node.play() }
    }

    func stop() {
        node.stop()
        engine.pause()
    }

    private static func makeClick(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frames = AVAudioFrameCount(0.05 * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let envelope = exp(-t / 0.010)
            data[i] = Float(0.8 * envelope * sin(2 * .pi * 1200 * t))
        }
        return buffer
    }
}
