import SwiftUI

/// Left rail: eject, the marker snap list (tap to jump, long-press for
/// rename / reorder / delete), an add button, and the A/B loop controls.
struct MarkerRail: View {
    @Environment(AppState.self) private var app
    @State private var renaming: Marker?
    @State private var draftName = ""

    var body: some View {
        VStack(spacing: 10) {
            Button {
                app.closeDocument()
            } label: {
                Image(systemName: "eject.fill")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
            }

            divider

            markerList

            Button {
                app.addMarkerAtPlayhead()
            } label: {
                Label("Mark", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            divider

            loopSection
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(width: 112)
        .background(.black.opacity(0.6))
        .alert("Rename marker", isPresented: renamingPresented) {
            TextField("Name", text: $draftName)
            Button("Save") {
                if let marker = renaming { app.renameMarker(marker, to: draftName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var markerList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(app.markers.markers) { marker in
                    markerChip(marker)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func markerChip(_ marker: Marker) -> some View {
        Button {
            app.snapToMarker(marker)
        } label: {
            VStack(spacing: 1) {
                Text(marker.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(timeString(marker.time))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        }
        .contextMenu {
            Button {
                draftName = marker.name
                renaming = marker
            } label: { Label("Rename", systemImage: "pencil") }
            Button {
                app.moveMarker(marker, by: -1)
            } label: { Label("Move Up", systemImage: "arrow.up") }
            Button {
                app.moveMarker(marker, by: 1)
            } label: { Label("Move Down", systemImage: "arrow.down") }
            Button(role: .destructive) {
                app.deleteMarker(marker)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var loopSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                loopEndButton("A", time: app.markers.loopA) { app.setLoopA() }
                loopEndButton("B", time: app.markers.loopB) { app.setLoopB() }
            }
            Button {
                app.toggleLoop()
            } label: {
                Label("Loop", systemImage: "repeat")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        app.markers.loopEnabled ? Color.green.opacity(0.9) : Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .foregroundStyle(app.markers.loopEnabled ? .black : (canLoop ? .white : .secondary))
            }
            .disabled(!canLoop)

            if app.markers.loopA != nil || app.markers.loopB != nil {
                Button("Clear loop", role: .destructive) {
                    app.clearLoop()
                }
                .font(.caption2)
            }
        }
    }

    private func loopEndButton(
        _ label: String,
        time: Double?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(label)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(time != nil ? Color.green : .white)
                Text(time.map(timeShort) ?? "set")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .frame(height: 1)
    }

    private var canLoop: Bool { app.markers.loopRange != nil }

    private var renamingPresented: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Compact m:ss for the tight A/B tiles.
    private func timeShort(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
