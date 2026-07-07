import AVFAudio
import Foundation

/// Per-audio-route latency offsets (seconds, signed). Bluetooth/AirPlay
/// routes delay the audio the dancer hears; we shift the beat *visuals* by
/// the stored offset so they line up with the sound. Per CLAUDE.md, the
/// media timeline itself is never modified — only the display shifts.
///
/// Offsets persist in UserDefaults keyed by a stable route identifier, so a
/// calibrated pair of headphones stays calibrated across launches.
enum LatencyStore {
    private static let defaultsKey = "latencyOffsets"

    private static let wirelessPorts: Set<AVAudioSession.Port> = [
        .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .airPlay,
    ]

    /// A stable key for the current output route: port type + the port's
    /// UID (stable per physical device for BT/wired; a fixed string for
    /// built-in output, which can also be calibrated).
    static func currentRouteKey() -> String {
        guard let port = AVAudioSession.sharedInstance().currentRoute.outputs.first else {
            return "unknown"
        }
        return "\(port.portType.rawValue)|\(port.uid)"
    }

    static func currentRouteName() -> String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "Output"
    }

    /// True when the current output is a wireless route where latency is
    /// large enough to be worth calibrating.
    static func currentRouteIsWireless() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs
            .contains { wirelessPorts.contains($0.portType) }
    }

    static func offset(forRouteKey key: String) -> Double? {
        stored()[key]
    }

    static func setOffset(_ seconds: Double, forRouteKey key: String) {
        var dict = stored()
        dict[key] = seconds
        UserDefaults.standard.set(dict, forKey: defaultsKey)
    }

    static func clearOffset(forRouteKey key: String) {
        var dict = stored()
        dict[key] = nil
        UserDefaults.standard.set(dict, forKey: defaultsKey)
    }

    private static func stored() -> [String: Double] {
        (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double]) ?? [:]
    }
}
