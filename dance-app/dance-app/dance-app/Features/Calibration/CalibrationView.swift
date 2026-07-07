import SwiftUI

/// Tap-to-beat latency calibration. The user puts on their headphones, taps
/// the pad in time with the click, and we store the median offset for the
/// current route so beat visuals line up with the delayed audio.
struct CalibrationView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var calibrator = LatencyCalibrator()
    @State private var touchDown = false

    var body: some View {
        VStack(spacing: 20) {
            header

            tapPad

            readout

            controls
        }
        .padding(28)
        .frame(maxWidth: 560)
        .onDisappear { calibrator.stop() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Calibrate beat latency")
                .font(.title2.weight(.bold))
            Text("Playing over **\(app.calibrationRouteName)**. Put on your headphones, then tap the pad in time with the click.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var tapPad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(touchDown ? Color.accentColor : Color.accentColor.opacity(0.18))
            Text(calibrator.isRunning ? "Tap on the beat" : "Press Start")
                .font(.headline)
                .foregroundStyle(calibrator.isRunning && touchDown ? .white : .secondary)
        }
        .frame(height: 220)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !touchDown else { return }
                    touchDown = true
                    calibrator.registerTap()
                }
                .onEnded { _ in touchDown = false }
        )
        .disabled(!calibrator.isRunning)
        .animation(.easeOut(duration: 0.06), value: touchDown)
    }

    private var readout: some View {
        HStack(spacing: 28) {
            stat("Taps", "\(calibrator.tapCount)")
            stat("Offset", offsetText)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var offsetText: String {
        guard let offset = calibrator.estimatedOffset else { return "—" }
        return String(format: "%+.0f ms", offset * 1000)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.bordered)

            Spacer()

            if calibrator.isRunning {
                Button("Restart") { calibrator.start() }
                    .buttonStyle(.bordered)
            } else {
                Button("Start") { calibrator.start() }
                    .buttonStyle(.borderedProminent)
            }

            Button("Save") {
                if let offset = calibrator.estimatedOffset {
                    app.applyCalibration(offset: offset)
                }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!calibrator.canSave)
        }
    }
}
