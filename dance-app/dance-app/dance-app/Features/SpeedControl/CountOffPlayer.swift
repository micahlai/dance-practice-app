import AVFoundation

/// Plays the audible "5, 6, 7, 8" count-off. Each tick is a short sine
/// click padded with silence to exactly one beat interval, so scheduling
/// the buffers back-to-back gives sample-accurate spacing at any rate.
final class CountOffPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    /// One tick per count; counts landing on 1 or 5 are accented.
    func playTicks(counts: [Int], interval: Double) {
        guard !counts.isEmpty, interval > 0.05 else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        node.stop()
        for count in counts {
            if let buffer = makePaddedClick(interval: interval, accent: count == 1 || count == 5) {
                node.scheduleBuffer(buffer)
            }
        }
        node.play()
    }

    func stop() {
        node.stop()
        engine.pause()
    }

    /// Play one short guide click while the video is running. Half-count
    /// clicks are quieter and lower so the main beat remains easy to feel.
    func playGuideClick(accent: Bool, isHalfCount: Bool) {
        if !engine.isRunning {
            try? engine.start()
        }
        node.stop()
        guard let buffer = makePaddedClick(
            interval: 0.05,
            accent: accent,
            volume: isHalfCount ? 0.42 : 0.72,
            frequency: isHalfCount ? 850 : nil
        ) else { return }
        node.scheduleBuffer(buffer)
        node.play()
    }

    private func makePaddedClick(
        interval: Double,
        accent: Bool,
        volume: Double = 0.8,
        frequency frequencyOverride: Double? = nil
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let totalFrames = AVAudioFrameCount(interval * sampleRate)
        guard totalFrames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = totalFrames

        let clickFrames = min(Int(0.04 * sampleRate), Int(totalFrames))
        let frequency = frequencyOverride ?? (accent ? 1500.0 : 1000.0)
        for i in 0..<Int(totalFrames) {
            if i < clickFrames {
                let t = Double(i) / sampleRate
                let envelope = exp(-t / 0.012)
                data[i] = Float(volume * envelope * sin(2 * .pi * frequency * t))
            } else {
                data[i] = 0
            }
        }
        return buffer
    }
}
