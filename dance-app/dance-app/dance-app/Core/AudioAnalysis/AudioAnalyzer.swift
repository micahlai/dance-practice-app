import AVFoundation
import Accelerate
import Foundation

/// Peak amplitudes per fixed-duration bin, normalized 0...1.
/// nonisolated: encoded/decoded off the main actor by AudioAnalyzer.
nonisolated struct WaveformData: Codable, Sendable {
    let binsPerSecond: Double
    let peaks: [Float]

    var duration: Double { Double(peaks.count) / binsPerSecond }
}

struct TempoEstimate: Sendable {
    let bpm: Double
    /// 0...1, autocorrelation strength at the chosen tempo.
    let confidence: Double
    /// Suggested beat-aligned anchor. It's *a* beat, not necessarily the "1" —
    /// the user picks the downbeat by shifting whole beats.
    let firstBeatTime: Double
}

enum AudioAnalysisError: Error {
    case unreadableAudio
}

/// Offline audio analysis (waveform peaks, tempo). Everything here is
/// nonisolated — call from a detached task, not the main actor.
enum AudioAnalyzer {

    // MARK: - Waveform

    nonisolated static func waveform(audioURL: URL, cacheURL: URL?) throws -> WaveformData {
        if let cacheURL,
           let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(WaveformData.self, from: data) {
            return cached
        }

        let (samples, sampleRate) = try readMonoSamples(from: audioURL)
        let nominalBinsPerSecond = 50.0
        let binSize = max(1, Int(sampleRate / nominalBinsPerSecond))
        let binCount = samples.count / binSize
        guard binCount > 0 else { throw AudioAnalysisError.unreadableAudio }

        var peaks = [Float](repeating: 0, count: binCount)
        samples.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!
            for bin in 0..<binCount {
                var peak: Float = 0
                vDSP_maxmgv(base + bin * binSize, 1, &peak, vDSP_Length(binSize))
                peaks[bin] = peak
            }
        }
        var maxPeak: Float = 0
        vDSP_maxv(peaks, 1, &maxPeak, vDSP_Length(binCount))
        if maxPeak > 0 {
            var scale = 1 / maxPeak
            vDSP_vsmul(peaks, 1, &scale, &peaks, 1, vDSP_Length(binCount))
        }

        let waveform = WaveformData(binsPerSecond: sampleRate / Double(binSize), peaks: peaks)
        if let cacheURL, let data = try? JSONEncoder().encode(waveform) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        return waveform
    }

    // MARK: - Tempo

    nonisolated static func detectTempo(audioURL: URL) throws -> TempoEstimate {
        let (samples, sampleRate) = try readMonoSamples(from: audioURL)
        let frameSize = 1024
        let hop = 512
        guard samples.count >= frameSize * 8 else {
            return TempoEstimate(bpm: 120, confidence: 0, firstBeatTime: 0)
        }

        var flux = onsetEnvelope(samples: samples, frameSize: frameSize, hop: hop)
        let envelopeRate = sampleRate / Double(hop)
        detrend(&flux, window: Int(envelopeRate))

        // Autocorrelate over the 60–200 BPM lag range; keep 2x lags around for
        // harmonic (half-tempo) support.
        let minLag = max(1, Int(envelopeRate * 60 / 200))
        let maxLag = Int(envelopeRate * 60 / 60)
        let acfMax = min(flux.count - 1, maxLag * 2)
        guard acfMax > minLag, maxLag > minLag else {
            return TempoEstimate(bpm: 120, confidence: 0, firstBeatTime: 0)
        }

        var acf = [Float](repeating: 0, count: acfMax + 1)
        flux.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!
            var r0: Float = 0
            vDSP_dotpr(base, 1, base, 1, &r0, vDSP_Length(flux.count))
            guard r0 > 0 else { return }
            for lag in minLag...acfMax {
                var r: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &r, vDSP_Length(flux.count - lag))
                acf[lag] = r / r0
            }
        }

        // Score candidates with harmonic support and a mild log-normal prior
        // centered near dance tempos.
        var bestLag = 0
        var bestScore: Float = -1
        for lag in minLag...maxLag {
            let bpm = envelopeRate * 60 / Double(lag)
            let harmonic = lag * 2 <= acfMax ? acf[lag * 2] : 0
            let prior = Float(exp(-0.5 * pow(log2(bpm / 120) / 1.2, 2)))
            let score = (acf[lag] + 0.5 * harmonic) * prior
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        guard bestLag > 0 else {
            return TempoEstimate(bpm: 120, confidence: 0, firstBeatTime: 0)
        }

        // Parabolic interpolation for a fractional-lag (fractional-BPM) peak.
        var lagF = Double(bestLag)
        if bestLag > minLag, bestLag + 1 <= acfMax {
            let y0 = Double(acf[bestLag - 1])
            let y1 = Double(acf[bestLag])
            let y2 = Double(acf[bestLag + 1])
            let denom = y0 - 2 * y1 + y2
            if abs(denom) > 1e-12 {
                lagF += 0.5 * (y0 - y2) / denom
            }
        }
        let bpm = envelopeRate * 60 / lagF
        let confidence = Double(min(max(acf[bestLag], 0), 1))

        // Beat phase: the comb offset that collects the most onset energy.
        let lag = max(1, Int(lagF.rounded()))
        var bestPhase = 0
        var bestPhaseScore: Float = -1
        for phase in 0..<lag {
            var score: Float = 0
            var i = phase
            while i < flux.count {
                score += flux[i]
                i += lag
            }
            if score > bestPhaseScore {
                bestPhaseScore = score
                bestPhase = phase
            }
        }
        let firstBeatTime = (Double(bestPhase) * Double(hop) + Double(frameSize) / 2) / sampleRate

        return TempoEstimate(bpm: bpm, confidence: confidence, firstBeatTime: firstBeatTime)
    }

    // MARK: - Internals

    /// Spectral-flux onset strength envelope, one value per hop.
    nonisolated private static func onsetEnvelope(samples: [Float], frameSize: Int, hop: Int) -> [Float] {
        let log2n = vDSP_Length(log2(Float(frameSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        let half = frameSize / 2
        var window = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&window, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))

        let realp = UnsafeMutablePointer<Float>.allocate(capacity: half)
        let imagp = UnsafeMutablePointer<Float>.allocate(capacity: half)
        defer {
            realp.deallocate()
            imagp.deallocate()
        }
        var split = DSPSplitComplex(realp: realp, imagp: imagp)

        var windowed = [Float](repeating: 0, count: frameSize)
        var magnitudes = [Float](repeating: 0, count: half)
        var previous = [Float](repeating: 0, count: half)
        var flux: [Float] = []
        flux.reserveCapacity((samples.count - frameSize) / hop + 1)

        samples.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!
            var start = 0
            while start + frameSize <= samples.count {
                vDSP_vmul(base + start, 1, window, 1, &windowed, 1, vDSP_Length(frameSize))
                windowed.withUnsafeBufferPointer { windowedBuffer in
                    windowedBuffer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
                var count = Int32(half)
                vvsqrtf(&magnitudes, magnitudes, &count)

                var sum: Float = 0
                for bin in 0..<half {
                    let rise = magnitudes[bin] - previous[bin]
                    if rise > 0 { sum += rise }
                }
                flux.append(sum)
                swap(&previous, &magnitudes)
                start += hop
            }
        }
        return flux
    }

    /// Subtract a moving-average baseline and half-wave rectify, so sustained
    /// loudness doesn't drown out onsets.
    nonisolated private static func detrend(_ envelope: inout [Float], window: Int) {
        guard envelope.count > 2, window > 1 else { return }
        let half = window / 2
        var prefix = [Double](repeating: 0, count: envelope.count + 1)
        for i in 0..<envelope.count {
            prefix[i + 1] = prefix[i] + Double(envelope[i])
        }
        for i in 0..<envelope.count {
            let lo = max(0, i - half)
            let hi = min(envelope.count, i + half + 1)
            let mean = (prefix[hi] - prefix[lo]) / Double(hi - lo)
            let value = Double(envelope[i]) - mean
            envelope[i] = value > 0 ? Float(value) : 0
        }
    }

    /// Decodes the whole file to mono float samples at its native rate.
    /// Also used by ScrubAudioEngine to feed the scratch buffer.
    nonisolated static func readMonoSamples(from url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioAnalysisError.unreadableAudio
        }
        try file.read(into: buffer)
        let n = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        guard n > 0, channels > 0, let channelData = buffer.floatChannelData else {
            throw AudioAnalysisError.unreadableAudio
        }
        var mono = [Float](repeating: 0, count: n)
        for channel in 0..<channels {
            vDSP_vadd(mono, 1, channelData[channel], 1, &mono, 1, vDSP_Length(n))
        }
        var scale = 1 / Float(channels)
        vDSP_vsmul(mono, 1, &scale, &mono, 1, vDSP_Length(n))
        return (mono, format.sampleRate)
    }
}
