import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// Ride detail: a large route map as the hero element with translucent
/// Liquid Glass stat chips on top, followed by a glass stat grid and the
/// speed graph.
struct RideDetailView: View {
    let ride: Ride

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speedUnit") private var unitRaw = SpeedUnit.kilometersPerHour.rawValue

    @State private var points: [RidePoint]
    @State private var position: MapCameraPosition
    @State private var showDeleteDialog = false
    @State private var showSatellite = false

    private var unit: SpeedUnit {
        SpeedUnit(rawValue: unitRaw) ?? .kilometersPerHour
    }

    init(ride: Ride) {
        self.ride = ride
        let decoded = ride.points()
        _points = State(initialValue: decoded)
        _position = State(initialValue: Self.camera(for: decoded))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                mapCard
                statGrid
                SpeedChartView(points: points, startDate: ride.startDate, unit: unit)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Format.rideDate.string(from: ride.startDate))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteDialog = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete ride")
            }
        }
        .confirmationDialog("Delete Ride", isPresented: $showDeleteDialog, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(ride)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This ride will be permanently removed.")
        }
    }

    // MARK: Map

    private var coordinates: [CLLocationCoordinate2D] {
        points.map(\.coordinate)
    }

    private var mapCard: some View {
        Map(position: $position) {
            if !coordinates.isEmpty {
                MapPolyline(coordinates: coordinates)
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
        .frame(height: 330)
        .clipShape(GlassShape.panel)
        .overlay(alignment: .bottom) {
            HStack(spacing: 8) {
                overlayChip(unit.distanceText(fromMeters: ride.distanceMeters))
                overlayChip(Format.shortDuration(ride.movingSeconds))
                overlayChip(unit.avgSpeedText(fromKmh: ride.avgSpeedKmh))
            }
            .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            GlassButton(
                icon: showSatellite ? "map" : "globe.americas.fill",
                circle: 40
            ) {
                showSatellite.toggle()
            }
            .padding(12)
            .accessibilityLabel("Toggle map style")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Route map")
    }

    private func overlayChip(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassSurface(in: Capsule())
            .frame(maxWidth: .infinity)
    }

    // MARK: Statistics

    private var statGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            StatTile(label: "Distance", value: unit.distanceText(fromMeters: ride.distanceMeters))
            StatTile(label: "Moving Time", value: Format.shortDuration(ride.movingSeconds))
            StatTile(label: "Avg Speed", value: unit.avgSpeedText(fromKmh: ride.avgSpeedKmh))
            StatTile(label: "Max Speed", value: unit.maxSpeedText(fromKmh: ride.maxSpeedKmh))
            StatTile(label: "Elevation", value: unit.elevationText(fromMeters: ride.elevationGainMeters))
            StatTile(label: "Started", value: Format.clockTime.string(from: ride.startDate))
        }
    }

    // MARK: Camera

    private static func camera(for points: [RidePoint]) -> MapCameraPosition {
        guard !points.isEmpty else { return .automatic }
        var rect = MKMapRect.null
        for point in points {
            let mapPoint = MKMapPoint(
                CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
            )
            rect = rect.union(MKMapRect(origin: mapPoint, size: MKMapSize(width: 0, height: 0)))
        }
        return .rect(rect)
    }
}
