import Foundation
import CoreLocation
import SwiftData
import Observation

enum RideState: Equatable {
    case idle
    case recording
    case paused
}

/// Owns the location session and the live ride state machine.
/// The engine lives for the whole app run, so a ride keeps recording across
/// tab switches and while the app is backgrounded.
@MainActor
@Observable
final class RideEngine: NSObject, CLLocationManagerDelegate {

    // MARK: Live state

    private(set) var state: RideState = .idle
    private(set) var speedKmh: Double = 0
    private(set) var gpsAccuracy: CLLocationAccuracy = -1
    private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var distanceMeters: Double = 0
    private(set) var movingSeconds: TimeInterval = 0
    private(set) var maxSpeedKmh: Double = 0
    private(set) var elevationGainMeters: Double = 0

    /// Decimated route for the live map (a point roughly every 8 m).
    private(set) var route: [CLLocationCoordinate2D] = []

    var isRecording: Bool { state != .idle }

    var isLocationDenied: Bool {
        locationStatus == .denied || locationStatus == .restricted
    }

    var avgSpeedKmh: Double {
        movingSeconds > 5 ? distanceMeters / movingSeconds * 3.6 : 0
    }

    // MARK: Private

    private let manager = CLLocationManager()
    private var samples: [RidePoint] = []
    private var rideStart = Date()
    private var lastLocation: CLLocation?
    private var completedMovingSeconds: TimeInterval = 0
    private var segmentStart: Date?
    private var metersSinceLastRoutePoint: Double = 0
    private var ticker: Timer?
    private var pendingStart = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 2
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        locationStatus = manager.authorizationStatus
    }

    // MARK: Location session

    /// Starts delivering location updates whenever the app is authorized.
    /// Called on launch and whenever the scene becomes active.
    func activate() {
        locationStatus = manager.authorizationStatus
        if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    /// Requests When-In-Use permission on first run; starts updates otherwise.
    func requestPermission() {
        locationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUse()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    private var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    // MARK: Ride controls

    func start() {
        guard state == .idle else { return }
        guard isAuthorized else {
            pendingStart = true
            requestPermission()
            return
        }
        beginRide()
    }

    func pause() {
        guard state == .recording else { return }
        if let segmentStart {
            completedMovingSeconds += Date().timeIntervalSince(segmentStart)
        }
        segmentStart = nil
        movingSeconds = completedMovingSeconds
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        segmentStart = Date()
        state = .recording
    }

    /// Ends the ride and stores it. Rides shorter than 10 m are discarded.
    @discardableResult
    func finishAndSave(into context: ModelContext) -> Ride? {
        guard state != .idle else { return nil }
        if let segmentStart {
            completedMovingSeconds += Date().timeIntervalSince(segmentStart)
            segmentStart = nil
        }
        movingSeconds = completedMovingSeconds
        manager.allowsBackgroundLocationUpdates = false
        stopTicker()

        var saved: Ride?
        if distanceMeters > 10 {
            let ride = Ride(
                startDate: rideStart,
                endDate: Date(),
                movingSeconds: movingSeconds,
                distanceMeters: distanceMeters,
                maxSpeedKmh: maxSpeedKmh,
                elevationGainMeters: elevationGainMeters,
                points: samples
            )
            context.insert(ride)
            saved = ride
        }
        endRide()
        return saved
    }

    func discard() {
        guard state != .idle else { return }
        manager.allowsBackgroundLocationUpdates = false
        stopTicker()
        endRide()
    }

    // MARK: State machine internals

    private func beginRide() {
        pendingStart = false
        rideStart = Date()
        samples = []
        route = []
        distanceMeters = 0
        movingSeconds = 0
        completedMovingSeconds = 0
        segmentStart = Date()
        maxSpeedKmh = 0
        elevationGainMeters = 0
        metersSinceLastRoutePoint = 0
        lastLocation = nil
        state = .recording
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        startTicker()
    }

    private func endRide() {
        samples = []
        route = []
        distanceMeters = 0
        movingSeconds = 0
        completedMovingSeconds = 0
        segmentStart = nil
        maxSpeedKmh = 0
        elevationGainMeters = 0
        metersSinceLastRoutePoint = 0
        lastLocation = nil
        state = .idle
    }

    // Moving time is derived from wall-clock segments, so a suspension while
    // backgrounded is picked up correctly on the next tick.
    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advanceMovingTime()
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func advanceMovingTime() {
        guard state == .recording, let segmentStart else { return }
        movingSeconds = completedMovingSeconds + Date().timeIntervalSince(segmentStart)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.consume(locations)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.locationStatus = manager.authorizationStatus
            if self.isAuthorized {
                self.manager.startUpdatingLocation()
                if self.pendingStart, self.state == .idle {
                    self.beginRide()
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Missed fixes are expected around tunnels and indoors; the next
        // update recovers, so there is nothing to surface here.
    }

    // MARK: Processing

    private func consume(_ locations: [CLLocation]) {
        for location in locations {
            gpsAccuracy = location.horizontalAccuracy
            if location.speed >= 0 {
                let kmh = location.speed * 3.6
                speedKmh = kmh
                if state == .recording, kmh > maxSpeedKmh {
                    maxSpeedKmh = kmh
                }
            }
            if state == .recording {
                record(location)
            } else {
                lastLocation = location
            }
        }
    }

    private func record(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else { return }
        defer { lastLocation = location }

        guard let previous = lastLocation else {
            guard location.timestamp.timeIntervalSinceNow > -5 else { return }
            samples.append(point(from: location))
            route.append(location.coordinate)
            return
        }

        guard location.timestamp >= previous.timestamp else { return }
        let step = previous.distance(from: location)
        guard step < 150 else { return }

        distanceMeters += step

        if location.verticalAccuracy >= 5 {
            let climb = location.altitude - previous.altitude
            if climb > 0, climb < 30 {
                elevationGainMeters += climb
            }
        }

        samples.append(point(from: location))
        metersSinceLastRoutePoint += step
        if metersSinceLastRoutePoint >= 8 {
            metersSinceLastRoutePoint = 0
            route.append(location.coordinate)
            decimateRouteIfNeeded()
        }
    }

    private func point(from location: CLLocation) -> RidePoint {
        RidePoint(
            t: location.timestamp.timeIntervalSince(rideStart),
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            alt: location.altitude,
            v: max(0, location.speed) * 3.6
        )
    }

    private func decimateRouteIfNeeded() {
        guard route.count > 4000 else { return }
        var halved = route.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
        if let last = route.last, halved.last?.latitude != last.latitude || halved.last?.longitude != last.longitude {
            halved.append(last)
        }
        route = halved
    }
}
