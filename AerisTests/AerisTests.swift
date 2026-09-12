import XCTest
@testable import Aeris

/// Unit tests for Aeris' pure logic: formatting, unit conversion and the
/// SwiftData ride model. No location permissions or GPS required.
final class AerisUnitTests: XCTestCase {

    // MARK: Duration formatting

    func testShortDurationUnderOneHour() {
        XCTAssertEqual(Format.shortDuration(0), "0:00")
        XCTAssertEqual(Format.shortDuration(59), "0:59")
        XCTAssertEqual(Format.shortDuration(761), "12:41")
    }

    func testShortDurationWithHours() {
        XCTAssertEqual(Format.shortDuration(4360), "1:12:40")
        XCTAssertEqual(Format.shortDuration(36000), "10:00:00")
    }

    // MARK: Unit conversion

    func testSpeedConversion() {
        XCTAssertEqual(SpeedUnit.kilometersPerHour.speedValue(fromKmh: 87), 87, accuracy: 0.0001)
        XCTAssertEqual(SpeedUnit.milesPerHour.speedValue(fromKmh: 100), 62.1371, accuracy: 0.001)
    }

    func testDistanceConversion() {
        XCTAssertEqual(SpeedUnit.kilometersPerHour.distanceValue(fromMeters: 1500), 1.5, accuracy: 0.0001)
        XCTAssertEqual(SpeedUnit.milesPerHour.distanceValue(fromMeters: 1609.344), 1.0, accuracy: 0.0001)
    }

    func testDistanceText() {
        XCTAssertEqual(SpeedUnit.kilometersPerHour.distanceText(fromMeters: 32_400), "32.4 km")
    }

    func testAvgSpeedPlaceholderWhenIdle() {
        XCTAssertEqual(SpeedUnit.kilometersPerHour.avgSpeedText(fromKmh: 0), "–")
    }

    // MARK: Ride model

    private func makeRide() -> Ride {
        Ride(
            startDate: Date(timeIntervalSince1970: 1_760_000_000),
            endDate: Date(timeIntervalSince1970: 1_760_000_000 + 3_600),
            movingSeconds: 3_600,
            distanceMeters: 28_800,
            maxSpeedKmh: 45.2,
            elevationGainMeters: 210,
            points: [
                RidePoint(t: 0, lat: 52.5200, lon: 13.4050, alt: 40, v: 0),
                RidePoint(t: 60, lat: 52.5210, lon: 13.4060, alt: 42, v: 22.4)
            ]
        )
    }

    func testAverageSpeedCalculation() {
        // 28 800 m in 3 600 s = 28.8 km/h
        XCTAssertEqual(makeRide().avgSpeedKmh, 28.8, accuracy: 0.0001)
    }

    func testAverageSpeedZeroForVeryShortRides() {
        let ride = Ride(
            startDate: Date(),
            endDate: Date(),
            movingSeconds: 4,
            distanceMeters: 50,
            maxSpeedKmh: 20,
            elevationGainMeters: 0,
            points: []
        )
        XCTAssertEqual(ride.avgSpeedKmh, 0)
    }

    func testRidePointPersistenceRoundTrip() {
        let decoded = makeRide().points()
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[1].t, 60, accuracy: 0.0001)
        XCTAssertEqual(decoded[1].lat, 52.5210, accuracy: 0.000001)
        XCTAssertEqual(decoded[1].lon, 13.4060, accuracy: 0.000001)
        XCTAssertEqual(decoded[1].alt, 42, accuracy: 0.0001)
        XCTAssertEqual(decoded[1].v, 22.4, accuracy: 0.0001)
    }
}
