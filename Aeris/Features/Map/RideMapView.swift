import SwiftUI
import MapKit
import SwiftData

/// Full-bleed MapKit map with floating Liquid Glass controls and panels.
struct RideMapView: View {
    @Environment(RideEngine.self) private var engine
    @Query(sort: \Ride.startDate, order: .reverse) private var rides: [Ride]
    @AppStorage("speedUnit") private var unitRaw = SpeedUnit.kilometersPerHour.rawValue

    @State private var position: MapCameraPosition = .userLocation(
        followsHeading: true,
        fallback: .automatic
    )
    @State private var showSatellite = false

    var onOpenHistory: () -> Void = {}

    private var unit: SpeedUnit {
        SpeedUnit(rawValue: unitRaw) ?? .kilometersPerHour
    }

    var body: some View {
        ZStack {
            map
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topControls
                Spacer()
                bottomPanel
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }

    private var map: some View {
        Map(position: $position) {
            UserAnnotation()
            if !engine.route.isEmpty {
                MapPolyline(coordinates: engine.route)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .mapStyle(
            showSatellite
                ? MapStyle.imagery(elevation: .realistic)
                : MapStyle.standard(elevation: .realistic)
        )
        .mapControls {
            MapUserLocationButton()
            MapScaleView()
        }
    }

    private var topControls: some View {
        HStack(alignment: .top) {
            if engine.isRecording {
                liveSpeedChip
            }
            Spacer()
            GlassButton(
                icon: showSatellite ? "map" : "globe.americas.fill",
                circle: 44
            ) {
                showSatellite.toggle()
            }
            .accessibilityLabel("Toggle map style")
        }
        .padding(.top, 8)
    }

    private var liveSpeedChip: some View {
        HStack(spacing: 7) {
            Image(systemName: "speedometer")
                .foregroundStyle(.secondary)
            Text("\(Int(engine.speedKmh.rounded())) \(unit.speedLabel)")
                .monospacedDigit()
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassSurface(in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current speed")
        .accessibilityValue("\(Int(engine.speedKmh.rounded())) \(unit.speedLabel)")
    }

    @ViewBuilder
    private var bottomPanel: some View {
        if engine.isRecording {
            HStack(spacing: 12) {
                mapStat("Distance", unit.distanceText(fromMeters: engine.distanceMeters))
                mapStat("Time", Format.shortDuration(engine.movingSeconds))
                mapStat("Avg", unit.avgSpeedText(fromKmh: engine.avgSpeedKmh))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .glassSurface(in: GlassShape.panel)
            .accessibilityElement(children: .combine)
        } else {
            Button(action: onOpenHistory) {
                lastRideContent
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var lastRideContent: some View {
        if let last = rides.first {
            HStack(spacing: 12) {
                Image(systemName: "bicycle")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last ride • \(Format.rideDate.string(from: last.startDate))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("\(unit.distanceText(fromMeters: last.distanceMeters)) • \(Format.shortDuration(last.movingSeconds))")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .glassSurface(in: GlassShape.panel, interactive: true)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "bicycle")
                    .foregroundStyle(Color.accentColor)
                Text("Start a ride from the Ride tab to see it here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .glassSurface(in: GlassShape.panel)
        }
    }

    private func mapStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
