import SwiftUI
import CoreLocation
import UIKit

/// The speedometer — the app's centerpiece. The live speed is the dominant
/// element; everything else is a floating Liquid Glass accessory.
struct SpeedometerView: View {
    @Environment(RideEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("speedUnit") private var unitRaw = SpeedUnit.kilometersPerHour.rawValue

    @State private var showEndDialog = false
    @State private var pulse = false
    @Namespace private var controlsNamespace
    @ScaledMetric(relativeTo: .largeTitle) private var speedFontSize: CGFloat = 100

    private var unit: SpeedUnit {
        SpeedUnit(rawValue: unitRaw) ?? .kilometersPerHour
    }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            Spacer(minLength: 4)
            speedCluster
            Spacer(minLength: 4)
            gpsChip
            Spacer(minLength: 12)
            statsRow
            controls
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear { engine.requestPermission() }
        .confirmationDialog("End Ride", isPresented: $showEndDialog, titleVisibility: .visible) {
            Button("Save Ride") {
                withAnimation(Animation.glass(reduceMotion)) {
                    if engine.finishAndSave(into: modelContext) != nil {
                        Haptics.success()
                    }
                }
            }
            Button("Discard Ride", role: .destructive) {
                withAnimation(Animation.glass(reduceMotion)) { engine.discard() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save this ride to your history?")
        }
    }

    // MARK: Status chip

    private var statusHeader: some View {
        ZStack {
            if engine.state != .idle {
                rideStatusChip
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(height: 44)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: engine.state)
        .onAppear { pulse = true }
    }

    private var rideStatusChip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(engine.state == .recording ? Color.red : Color.yellow)
                .frame(width: 8, height: 8)
                .scaleEffect(pulse ? 1.4 : 0.8)
                .opacity(pulse ? 0.55 : 1)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1).repeatForever(autoreverses: true),
                    value: pulse
                )
            Text(engine.state == .recording ? "Recording" : "Paused")
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassSurface(in: Capsule())
        .accessibilityElement(children: .combine)
    }

    // MARK: Speed cluster

    private var speedCluster: some View {
        ZStack {
            SpeedArc(progress: arcProgress)
                .padding(26)
            VStack(spacing: 0) {
                Text("\(Int(engine.speedKmh.rounded()))")
                    .font(.system(size: speedFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: engine.speedKmh)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(unit.speedLabel)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 44)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 330)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current speed")
        .accessibilityValue("\(Int(engine.speedKmh.rounded())) \(unit.speedLabel)")
    }

    /// The arc saturates at a typical riding pace so it stays meaningful.
    private var arcProgress: Double {
        let scale: Double = unit == .kilometersPerHour ? 70 : 45
        let raw = min(max(engine.speedKmh / scale, 0), 1)
        return (raw * 200).rounded() / 200
    }

    // MARK: GPS chip

    @ViewBuilder
    private var gpsChip: some View {
        if engine.isLocationDenied {
            Button {
                openLocationSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "location.slash.fill")
                    Text("Enable Location")
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassSurface(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Enable location in Settings")
        } else {
            GPSStatusView(accuracy: engine.gpsAccuracy, status: engine.locationStatus)
        }
    }

    private func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Statistics

    private var statsRow: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 72, spacing: 8), spacing: 8)],
            spacing: 8
        ) {
            StatTile(label: "Distance", value: unit.distanceText(fromMeters: engine.distanceMeters))
            StatTile(label: "Avg", value: unit.avgSpeedText(fromKmh: engine.avgSpeedKmh))
            StatTile(label: "Max", value: unit.maxSpeedText(fromKmh: engine.maxSpeedKmh))
            StatTile(label: "Time", value: Format.shortDuration(engine.movingSeconds))
        }
    }

    // MARK: Controls

    private var controls: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 18) {
                controlsContent
            }
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var controlsContent: some View {
        switch engine.state {
        case .idle:
            GlassButton(
                title: "Start",
                icon: "play.fill",
                prominent: true,
                large: true,
                morphID: "primary",
                namespace: controlsNamespace
            ) {
                Haptics.tap()
                withAnimation(Animation.glass(reduceMotion)) { engine.start() }
            }
            .accessibilityLabel("Start ride")

        case .recording:
            GlassButton(
                icon: "pause.fill",
                circle: 64,
                morphID: "primary",
                namespace: controlsNamespace
            ) {
                Haptics.tap()
                withAnimation(Animation.glass(reduceMotion)) { engine.pause() }
            }
            .accessibilityLabel("Pause ride")
            GlassButton(
                icon: "stop.fill",
                circle: 64,
                tint: .red,
                morphID: "secondary",
                namespace: controlsNamespace
            ) {
                Haptics.tap()
                showEndDialog = true
            }
            .accessibilityLabel("End ride")

        case .paused:
            GlassButton(
                icon: "play.fill",
                circle: 64,
                morphID: "primary",
                namespace: controlsNamespace
            ) {
                Haptics.tap()
                withAnimation(Animation.glass(reduceMotion)) { engine.resume() }
            }
            .accessibilityLabel("Resume ride")
            GlassButton(
                icon: "stop.fill",
                circle: 64,
                tint: .red,
                morphID: "secondary",
                namespace: controlsNamespace
            ) {
                showEndDialog = true
            }
            .accessibilityLabel("End ride")
        }
    }
}

// MARK: - Speed arc

/// A quiet circular arc behind the speed readout. It fills with pace and
/// respects Reduce Motion.
struct SpeedArc: View {
    var progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.primary.opacity(0.08),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(
                    Color.accentColor.opacity(0.85),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: progress)
        }
    }
}

// MARK: - GPS status

struct GPSStatusView: View {
    var accuracy: CLLocationAccuracy
    var status: CLAuthorizationStatus

    private var label: String {
        switch status {
        case .denied, .restricted:
            return "Off"
        case .notDetermined:
            return "Waiting"
        default:
            if accuracy < 0 { return "Searching" }
            if accuracy <= 8 { return "Excellent" }
            if accuracy <= 18 { return "Good" }
            if accuracy <= 40 { return "Fair" }
            return "Poor"
        }
    }

    private var dotColor: Color {
        switch label {
        case "Excellent", "Good": return .green
        case "Fair", "Waiting": return .yellow
        case "Poor": return .orange
        default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text("GPS • \(label)")
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassSurface(in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("GPS signal")
        .accessibilityValue(label)
    }
}
