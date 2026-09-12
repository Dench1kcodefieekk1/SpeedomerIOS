import Foundation
import CoreLocation
import SwiftData
import Observation

enum RideState: Equatable, Sendable {
    case idle
    case recording
    case paused
}

/// The ride state machine.
///
/// The engine is `@MainActor` and `@Observable`; every published field is
/// written only here, which makes the state trivially race-free. All input is
/// consumed from three serial async loops fed by `LocationService` (location
/// fixes, authorization changes, session errors), and the moving-time clock is
/// an async sleep loop — no timers, no delegate hops, no shared mutable state
/// off the main actor.
///
/// Layering: `LocationService` owns I/O, `RideEngine` owns domain state, views
/// own presentation and read this object through the environment.
@MainActor
@Observable
final class RideEngine {

    // MARK: Observable state (consumed by the UI)

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

    // MARK: Tuning

    /// GPS speed smoothing factor: higher weights the newest fix more.
    private static let speedSmoothingAlpha = 0.6

    /// Fixes whose accuracy is worse than this are ignored while recording.
    private static let recordingAccuracyLimit: CLLocationAccuracy = 50

    /// A single distance step above this is a GPS glitch, not a jump.
    private static let maxPlausibleStepMeters: Double = 150

    /// Route display density and cap for the live map polyline.
    private static let routePointIntervalMeters: Double = 8
    private static let routePointCap = 4000

    // MARK: Dependencies & workers

    private let location: LocationService
    private var updatesTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?

    // MARK: Ride bookkeeping

    private var samples: [RidePoint] = []
    private var rideStart = Date()
    private var lastLocation: CLLocation?
    private var completedMovingSeconds: TimeInterval = 0
    private var segmentStart: Date?
    private var metersSinceLastRoutePoint: Double = 0
    private var pendingStart = false
    /// Exponential moving average that keeps the big readout calm.
    private var smoothedSpeedKmh: Double = 0

    init(location: LocationService = LocationService()) {
        self.location = location
        locationStatus = location.currentStatus
        startConsumers()
    }

    deinit {
        updatesTask?.cancel()
        authorizationTask?.cancel()
        errorTask?.cancel()
        tickerTask?.cancel()
    }

    // MARK: Public controls

    /// Starts delivering location updates whenever the app is authorized.
    /// Called on launch and whenever the scene becomes active.
    func activate() {
        locationStatus = location.currentStatus
        if location.isAuthorized {
            location.startUpdatingLocation()
        }
    }

    /// Requests When-In-Use permission on first run; starts updates otherwise.
    func requestPermission() {
        locationStatus = location.currentStatus
        location.requestPermission()
    }

    func start() {
        guard state == .idle else { return }
        guard location.isAuthorized else {
            // The permission prompt appears; the authorization stream starts
            // the ride as soon as access is granted.
            pendingStart = true
            requestPermission()
            return
        }
        beginRide()
    }

    func pause() {
        guard state == .recording else { return }
        settleSegment()
        state = .paused
        cancelTicker()
    }

    func resume() {
        guard state == .paused else { return }
        segmentStart = Date()
        state = .recording
        startTicker()
    }

    /// Ends the ride and stores it. Rides shorter than 10 m are discarded.
    @discardableResult
    func finishAndSave(into context: ModelContext) -> Ride? {
        guard state != .idle else { return nil }
        settleSegment()
        cancelTicker()
        leaveRecordingMode()

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
        cancelTicker()
        leaveRecordingMode()
        endRide()
    }

    // MARK: Consumer loops

    private func startConsumers() {
        let updates = location.updates
        let authorizationChanges = location.authorizationChanges
        let errors = location.errors

        updatesTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            for await location in updates {
                guard let self else { return }
                self.consume(location)
            }
        }

        authorizationTask = Task { @MainActor [weak self] in
            for await status in authorizationChanges {
                guard let self else { return }
                self.authorizationChanged(to: status)
            }
        }

        errorTask = Task { @MainActor [weak self] in
            for await error in errors {
                guard let self else { return }
                self.handleSessionError(error)
            }
        }
    }

    private func authorizationChanged(to status: CLAuthorizationStatus) {
        locationStatus = status
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            location.startUpdatingLocation()
            if pendingStart, state == .idle {
                beginRide()
            }
        case .denied, .restricted:
            // Permission revoked mid-ride: pause instead of silently
            // recording nothing, and drop any queued auto-start.
            pendingStart = false
            if state == .recording {
                pause()
            }
        default:
            break
        }
    }

    private func handleSessionError(_ error: LocationSessionError) {
        switch error {
        case .permissionDenied:
            if state == .recording {
                pause()
            }
        case .failed:
            // Transient GPS failures recover with the next fix; the GPS chip
            // already communicates degraded accuracy to the rider.
            break
        }
    }

    // MARK: Location consumption

    private func consume(_ location: CLLocation) {
        gpsAccuracy = location.horizontalAccuracy

        if location.speed >= 0 {
            let rawKmh = location.speed * 3.6
            updateSmoothedSpeed(withRawKmh: rawKmh)
            speedKmh = smoothedSpeedKmh
            if state == .recording, rawKmh > maxSpeedKmh {
                // Max speed always uses the raw value, never the average.
                maxSpeedKmh = rawKmh
            }
        }

        guard state == .recording else {
            lastLocation = location
            return
        }
        record(location)
    }

    private func updateSmoothedSpeed(withRawKmh rawKmh: Double) {
        // Snap to zero quickly when stationary instead of decaying slowly,
        // so the readout does not linger above 0 after stopping.
        if rawKmh < 1 {
            smoothedSpeedKmh = rawKmh < 0.4 ? 0 : smoothedSpeedKmh * 0.5
        } else {
            let alpha = Self.speedSmoothingAlpha
            smoothedSpeedKmh = alpha * rawKmh + (1 - alpha) * smoothedSpeedKmh
        }
    }

    private func record(_ location: CLLocation) {
        guard location.horizontalAccuracy <= Self.recordingAccuracyLimit else { return }
        defer { lastLocation = location }

        guard let previous = lastLocation else {
            // First fix of the ride: reject stale cache deliveries.
            guard location.timestamp.timeIntervalSinceNow > -5 else { return }
            samples.append(point(from: location))
            route.append(location.coordinate)
            return
        }

        guard location.timestamp >= previous.timestamp else { return }
        let step = previous.distance(from: location)
        guard step < Self.maxPlausibleStepMeters else { return }

        distanceMeters += step

        if location.verticalAccuracy >= 5 {
            let climb = location.altitude - previous.altitude
            if climb > 0, climb < 30 {
                elevationGainMeters += climb
            }
        }

        samples.append(point(from: location))
        metersSinceLastRoutePoint += step
        if metersSinceLastRoutePoint >= Self.routePointIntervalMeters {
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
        guard route.count > Self.routePointCap else { return }
        var halved = route.enumerated()
            .filter { $0.offset.isMultiple(of: 2) }
            .map(\.element)
        if let last = route.last,
           halved.last?.latitude != last.latitude || halved.last?.longitude != last.longitude {
            halved.append(last)
        }
        route = halved
    }

    // MARK: Moving time

    /// Wall-clock moving-time segments: if iOS suspends the app in the
    /// background, the elapsed time is picked up correctly on the next tick
    /// because each segment is anchored to a real date.
    private func settleSegment() {
        if let start = segmentStart {
            completedMovingSeconds += Date().timeIntervalSince(start)
        }
        segmentStart = nil
        movingSeconds = completedMovingSeconds
    }

    private func advanceMovingTime() {
        guard state == .recording, let segmentStart else { return }
        movingSeconds = completedMovingSeconds + Date().timeIntervalSince(segmentStart)
    }

    private func startTicker() {
        cancelTicker()
        tickerTask = Task(priority: .utility) { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.advanceMovingTime()
            }
        }
    }

    private func cancelTicker() {
        tickerTask?.cancel()
        tickerTask = nil
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

        location.setBackgroundDeliveryEnabled(true)
        location.setDesiredAccuracy(kCLLocationAccuracyBest)
        location.startUpdatingLocation()
        startTicker()
    }

    /// Steps the hardware back down to idle-mode settings.
    private func leaveRecordingMode() {
        location.setBackgroundDeliveryEnabled(false)
        location.setDesiredAccuracy(LocationService.idleAccuracy)
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
}
