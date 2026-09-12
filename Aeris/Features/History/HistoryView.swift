import SwiftUI
import SwiftData

/// Ride history: a native grouped list rendered on glass surfaces, with
/// month sections, swipe-to-delete and push navigation into ride details.
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ride.startDate, order: .reverse) private var rides: [Ride]
    @AppStorage("speedUnit") private var unitRaw = SpeedUnit.kilometersPerHour.rawValue

    private var unit: SpeedUnit {
        SpeedUnit(rawValue: unitRaw) ?? .kilometersPerHour
    }

    private var sections: [(month: String, rides: [Ride])] {
        let grouped = Dictionary(grouping: rides) {
            Format.monthSection.string(from: $0.startDate)
        }
        var order: [String] = []
        for ride in rides {
            let key = Format.monthSection.string(from: ride.startDate)
            if !order.contains(key) {
                order.append(key)
            }
        }
        return order.map { (month: $0, rides: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if rides.isEmpty {
                    ContentUnavailableView(
                        "No Rides Yet",
                        systemImage: "bicycle",
                        description: Text("Start your first ride from the Ride tab.")
                    )
                } else {
                    rideList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("History")
            .navigationDestination(for: Ride.self) { ride in
                RideDetailView(ride: ride)
            }
        }
    }

    private var rideList: some View {
        List {
            ForEach(sections, id: \.month) { section in
                Section(section.month) {
                    ForEach(section.rides) { ride in
                        NavigationLink(value: ride) {
                            RideRow(ride: ride, unit: unit)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                withAnimation { modelContext.delete(ride) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Row

struct RideRow: View {
    let ride: Ride
    let unit: SpeedUnit

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bicycle")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(Format.rideDate.string(from: ride.startDate))
                    .font(.headline)
                    .lineLimit(1)
                Text("\(unit.distanceText(fromMeters: ride.distanceMeters)) • \(Format.shortDuration(ride.movingSeconds))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(unit.avgSpeedText(fromKmh: ride.avgSpeedKmh))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text("avg")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
        .listRowSeparator(.hidden)
        .listRowBackground(GlassRowBackground())
    }
}

// MARK: - Glass row background

/// Liquid Glass row backing: native `glassEffect` on iOS 26+, ultra-thin
/// material elsewhere.
struct GlassRowBackground: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.clear)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}
