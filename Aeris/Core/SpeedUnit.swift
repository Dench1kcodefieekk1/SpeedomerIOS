import Foundation

/// User-facing unit preference. The engine always works in SI units
/// (meters, km/h); views convert through this enum.
enum SpeedUnit: String, CaseIterable, Identifiable {
    case kilometersPerHour = "kmh"
    case milesPerHour = "mph"

    var id: String { rawValue }

    var speedLabel: String {
        self == .kilometersPerHour ? "km/h" : "mph"
    }

    func speedValue(fromKmh value: Double) -> Double {
        self == .kilometersPerHour ? value : value / 1.609344
    }

    func distanceValue(fromMeters meters: Double) -> Double {
        self == .kilometersPerHour ? meters / 1000 : meters / 1609.344
    }

    func distanceText(fromMeters meters: Double) -> String {
        String(
            format: "%.1f %@",
            distanceValue(fromMeters: meters),
            self == .kilometersPerHour ? "km" : "mi"
        )
    }

    func avgSpeedText(fromKmh value: Double) -> String {
        guard value > 0.05 else { return "–" }
        return String(format: "%.1f %@", speedValue(fromKmh: value), speedLabel)
    }

    func maxSpeedText(fromKmh value: Double) -> String {
        avgSpeedText(fromKmh: value)
    }

    func elevationText(fromMeters meters: Double) -> String {
        self == .kilometersPerHour
            ? String(format: "%.0f m", meters)
            : String(format: "%.0f ft", meters * 3.28084)
    }
}
