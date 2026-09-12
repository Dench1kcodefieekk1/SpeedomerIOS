import Foundation
import CoreLocation

/// Errors surfaced by the location session.
enum LocationSessionError: Error, Equatable {
    /// The user (or the system) revoked location permission.
    case permissionDenied
    /// A non-transient failure worth surfacing; the session keeps running.
    case failed(CLError.Code)
}

/// Bridges the callback-based `CLLocationManager` API into async/await.
///
/// `CLLocationManager` must be created and driven from a single thread, so the
/// whole service is `@MainActor`. Delegate callbacks arrive on the main thread
/// (the manager is created there), and are re-imported into the actor with
/// `MainActor.assumeIsolated` — no task hops, strictly ordered delivery.
///
/// Each stream has a single consumer (`RideEngine`). Values are yielded
/// serially and buffered, so nothing is dropped and the consumer observes the
/// exact arrival order, including the initial authorization status.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {

    // MARK: Streams (single consumer each)

    /// Location fixes with a valid `horizontalAccuracy`, in arrival order.
    let updates: AsyncStream<CLLocation>
    /// Authorization transitions; seeded with the status at creation time.
    let authorizationChanges: AsyncStream<CLAuthorizationStatus>
    /// Session failures that are not self-recovering transient noise.
    let errors: AsyncStream<LocationSessionError>

    // MARK: Private

    private let manager: CLLocationManager
    private var updatesContinuation: AsyncStream<CLLocation>.Continuation!
    private var authorizationContinuation: AsyncStream<CLAuthorizationStatus>.Continuation!
    private var errorsContinuation: AsyncStream<LocationSessionError>.Continuation!

    /// Accuracy tier used whenever a ride is not being recorded.
    static let idleAccuracy = kCLLocationAccuracyNearestTenMeters

    override init() {
        let manager = CLLocationManager()
        self.manager = manager

        var updatesContinuation: AsyncStream<CLLocation>.Continuation!
        updates = AsyncStream(bufferingPolicy: .unbounded) { updatesContinuation = $0 }
        self.updatesContinuation = updatesContinuation

        var authorizationContinuation: AsyncStream<CLAuthorizationStatus>.Continuation!
        authorizationChanges = AsyncStream(bufferingPolicy: .unbounded) {
            authorizationContinuation = $0
        }
        self.authorizationContinuation = authorizationContinuation

        var errorsContinuation: AsyncStream<LocationSessionError>.Continuation!
        errors = AsyncStream(bufferingPolicy: .unbounded) { errorsContinuation = $0 }
        self.errorsContinuation = errorsContinuation

        super.init()

        manager.delegate = self
        manager.desiredAccuracy = Self.idleAccuracy
        manager.activityType = .fitness
        manager.distanceFilter = 2
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true

        // Seed the stream so the first consumer immediately observes the
        // current authorization state.
        authorizationContinuation.yield(manager.authorizationStatus)
    }

    // MARK: Session state

    var currentStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    var isPermissionDenied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    // MARK: Session control

    /// Requests When-In-Use permission on first run; starts updates otherwise.
    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatingLocation()
        default:
            break
        }
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    /// Turns background delivery on while a ride is being recorded and off
    /// afterwards. Guarded: enabling `allowsBackgroundLocationUpdates` without
    /// the "location" background mode crashes at runtime.
    func setBackgroundDeliveryEnabled(_ enabled: Bool) {
        let hasBackgroundMode = Bundle.main
            .object(forInfoDictionaryKey: "UIBackgroundModes") != nil
        manager.allowsBackgroundLocationUpdates = enabled && hasBackgroundMode
    }

    /// Recording rides at rest uses top accuracy; idle speed display does not
    /// need it, which saves a meaningful amount of battery.
    func setDesiredAccuracy(_ accuracy: CLLocationAccuracy) {
        manager.desiredAccuracy = accuracy
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            for location in locations where location.horizontalAccuracy >= 0 {
                updatesContinuation.yield(location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            guard let clerror = error as? CLError else { return }
            switch clerror.code {
            case .locationUnknown:
                // Transient — happens around tunnels and cold starts; the
                // next fix recovers, so it is not worth surfacing.
                break
            case .denied:
                errorsContinuation.yield(.permissionDenied)
            default:
                errorsContinuation.yield(.failed(cerror.code))
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            authorizationContinuation.yield(manager.authorizationStatus)
        }
    }
}
