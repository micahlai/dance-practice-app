import AVFoundation
import os

/// DJ-scratch audio for the scrub wheel. A source node chases a target
/// position through the loaded track; playback rate (and therefore pitch)
/// follows scrub velocity, and negative rates play backwards — which
/// AVAudioUnitVarispeed can't do, hence the custom sample reader.
///
/// nonisolated: `update(time:)` is called from gesture/display-link code and
/// the render block runs on the audio thread. Shared state is guarded by an
/// unfair lock held only for microseconds per render callback.
nonisolated final class ScrubAudioEngine {
    private let engine = AVAudioEngine()
    private let renderSampleRate: Double = 48000
    private let lockPtr: UnsafeMutablePointer<os_unfair_lock_s>

    // Protected by lockPtr:
    private var samples: [Float] = []
    private var sampleRate: Double = 44100
    private var playheadSamples: Double = 0
    private var targetSamples: Double = 0
    private var previousTargetSamples: Double = 0
    private var active = false

    init() {
        lockPtr = .allocate(capacity: 1)
        lockPtr.initialize(to: os_unfair_lock_s())

        let format = AVAudioFormat(standardFormatWithSampleRate: renderSampleRate, channels: 1)!
        let source = AVAudioSourceNode(format: format) { [weak self] isSilence, _, frameCount, audioBufferList -> OSStatus in
            guard let self else {
                isSilence.pointee = true
                return noErr
            }
            return self.render(isSilence: isSilence, frameCount: frameCount, audioBufferList: audioBufferList)
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
    }

    deinit {
        lockPtr.deallocate()
    }

    func load(monoSamples: [Float], sampleRate: Double) {
        os_unfair_lock_lock(lockPtr)
        samples = monoSamples
        self.sampleRate = sampleRate
        playheadSamples = 0
        targetSamples = 0
        active = false
        os_unfair_lock_unlock(lockPtr)
    }

    func unload() {
        os_unfair_lock_lock(lockPtr)
        samples = []
        active = false
        os_unfair_lock_unlock(lockPtr)
        engine.stop()
    }

    func begin(at time: Double) {
        if !engine.isRunning {
            try? engine.start()
        }
        os_unfair_lock_lock(lockPtr)
        playheadSamples = time * sampleRate
        targetSamples = playheadSamples
        previousTargetSamples = playheadSamples
        active = true
        os_unfair_lock_unlock(lockPtr)
    }

    func update(time: Double) {
        os_unfair_lock_lock(lockPtr)
        targetSamples = time * sampleRate
        os_unfair_lock_unlock(lockPtr)
    }

    func end() {
        os_unfair_lock_lock(lockPtr)
        active = false
        os_unfair_lock_unlock(lockPtr)
        engine.pause()
    }

    private func render(
        isSilence: UnsafeMutablePointer<ObjCBool>,
        frameCount: AVAudioFrameCount,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard let out = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        let n = Int(frameCount)

        os_unfair_lock_lock(lockPtr)
        defer { os_unfair_lock_unlock(lockPtr) }

        guard active, samples.count > 1 else {
            for i in 0..<n { out[i] = 0 }
            isSilence.pointee = true
            return noErr
        }

        // No chasing: play at the finger's actual rate (target movement since
        // the last callback), and if we've fallen out of the sync window,
        // skip straight to where the playhead is.
        let target = targetSamples
        let maxStep = 3.0 * sampleRate / renderSampleRate
        let syncWindow = 0.04 * sampleRate
        var position = playheadSamples
        if abs(position - target) > syncWindow {
            position = target
        }
        var step = (target - previousTargetSamples) / Double(n)
        step = min(max(step, -maxStep), maxStep)
        previousTargetSamples = target
        var silent = true

        for i in 0..<n {
            position += step
            let index = Int(position)
            guard abs(step) > 0.02, index >= 0, index + 1 < samples.count else {
                out[i] = 0
                continue
            }
            let fraction = Float(position - Double(index))
            out[i] = (samples[index] * (1 - fraction) + samples[index + 1] * fraction) * 0.9
            silent = false
        }
        playheadSamples = position
        isSilence.pointee = ObjCBool(silent)
        return noErr
    }
}
