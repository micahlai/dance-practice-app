import AVFoundation
import Darwin

/// Owns the single audio clock used by both the count-off and live beat
/// guide. Scheduling every click against host time keeps their phase intact
/// across the handoff into playback.
final class CountOffPlayer {
    static let schedulingLeadTime = 0.12

    struct CountOffSchedule {
        let firstCountHostTime: UInt64
        let landingHostTime: UInt64
    }

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    /// Schedule every count backward from one authoritative landing time.
    /// Both playback and the visual count use the returned clock anchors.
    func scheduleCountOff(
        counts: [Int],
        interval: Double,
        landingCount: Int?
    ) -> CountOffSchedule? {
        guard !counts.isEmpty, interval > 0.05, startEngineIfNeeded() else { return nil }
        node.stop()
        let firstCountHostTime = mach_absolute_time()
            + AVAudioTime.hostTime(forSeconds: Self.schedulingLeadTime)
        let landingHostTime = firstCountHostTime
            + AVAudioTime.hostTime(forSeconds: interval * Double(counts.count))

        for (index, count) in counts.enumerated() {
            if let buffer = makeClick(accent: count == 1 || count == 5) {
                let beatsBeforeLanding = counts.count - index
                schedule(
                    buffer,
                    at: landingHostTime - AVAudioTime.hostTime(
                        forSeconds: interval * Double(beatsBeforeLanding)
                    )
                )
            }
        }
        if let landingCount, let buffer = makeClick(accent: landingCount == 1 || landingCount == 5) {
            schedule(buffer, at: landingHostTime)
        }
        node.play()
        return CountOffSchedule(
            firstCountHostTime: firstCountHostTime,
            landingHostTime: landingHostTime
        )
    }

    func stop() {
        node.stop()
        engine.pause()
    }

    /// Queue a live guide click at an exact host time. The node is deliberately
    /// not stopped here: queued beats remain sample-aligned with one another.
    func scheduleGuideClick(accent: Bool, isHalfCount: Bool, at hostTime: UInt64) {
        guard startEngineIfNeeded(),
              let buffer = makeClick(
            accent: accent,
            volume: isHalfCount ? 0.42 : 0.72,
            frequency: isHalfCount ? 850 : nil
        ) else { return }
        schedule(buffer, at: hostTime)
        if !node.isPlaying { node.play() }
    }

    static func hostTime(after seconds: Double) -> UInt64 {
        mach_absolute_time() + AVAudioTime.hostTime(forSeconds: max(0, seconds))
    }

    static func seconds(until hostTime: UInt64) -> Double {
        let now = mach_absolute_time()
        guard hostTime > now else { return 0 }
        return AVAudioTime.seconds(forHostTime: hostTime - now)
    }

    private func startEngineIfNeeded() -> Bool {
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                return false
            }
        }
        return true
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, at hostTime: UInt64) {
        node.scheduleBuffer(buffer, at: AVAudioTime(hostTime: hostTime), options: [])
    }

    private func makeClick(
        accent: Bool,
        volume: Double = 0.8,
        frequency frequencyOverride: Double? = nil
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let totalFrames = AVAudioFrameCount(0.05 * sampleRate)
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
