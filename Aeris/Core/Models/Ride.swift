import Foundation
import SwiftData
import CoreLocation

/// One recorded GPS sample, stored compactly inside the ride.
struct RidePoint: Codable {
    /// Seconds since the ride started.
    var t: TimeInterval
    var lat: Double
    var lon: Double
    /// Meters above sea level.
    var alt: Double
    /// km/h
    var v: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

@Model
final class Ride {
    var startDate: Date
    var endDate: Date
    var movingSeconds: TimeInterval
    var distanceMeters: Double
    var maxSpeedKmh: Double
    var elevationGainMeters: Double
    private var pointsData: Data

    /// Distance divided by moving time, in km/h.
    var avgSpeedKmh: Double {
        movingSeconds > 5 ? distanceMeters / movingSeconds * 3.6 : 0
    }

    init(
        startDate: Date,
        endDate: Date,
        movingSeconds: TimeInterval,
        distanceMeters: Double,
        maxSpeedKmh: Double,
        elevationGainMeters: Double,
        points: [RidePoint]
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.movingSeconds = movingSeconds
        self.distanceMeters = distanceMeters
        self.maxSpeedKmh = maxSpeedKmh
        self.elevationGainMeters = elevationGainMeters
        self.pointsData = (try? JSONEncoder().encode(points)) ?? Data()
    }

    func points() -> [RidePoint] {
        (try? JSONDecoder().decode([RidePoint].self, from: pointsData)) ?? []
    }
}
