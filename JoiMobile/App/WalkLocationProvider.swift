import CompanionCore
import CoreLocation
import Foundation
import OSLog

private let walkLog = Logger(subsystem: "com.joi.mobile", category: "walk")

/// Foreground-only location for a cached cultural walk.
///
/// When-in-use only, started by a deliberate tap and stopped when the walk ends:
/// Trust & Safety's standing condition is that this product never holds a
/// background location authorisation, and the way to keep that true is to never
/// ask for one. Nothing here writes to memory or to the transcript — location
/// reaches the rest of the app only as a `LocationObservation` that
/// `JourneyContextStore` reduces (DEC-002).
@MainActor
@Observable
final class WalkLocationProvider: NSObject, CLLocationManagerDelegate {
    /// Why the walk cannot follow the user, in the terms the UI shows.
    enum Availability: Equatable {
        case idle
        case waitingForPermission
        case following
        case denied
        case unavailable
    }

    private(set) var availability: Availability = .idle
    private(set) var latest: LocationObservation?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var onUpdate: ((LocationObservation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // A walking route does not need every metre; this is the coarsest filter
        // that still moves progress smoothly on foot.
        manager.distanceFilter = 5
    }

    func start(onUpdate: @escaping (LocationObservation) -> Void) {
        self.onUpdate = onUpdate
        switch manager.authorizationStatus {
        case .notDetermined:
            availability = .waitingForPermission
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginUpdates()
        case .denied, .restricted:
            availability = .denied
        @unknown default:
            availability = .unavailable
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        onUpdate = nil
        availability = .idle
        walkLog.notice("walk: stopped following")
    }

    private func beginUpdates() {
        guard CLLocationManager.locationServicesEnabled() else {
            availability = .unavailable
            return
        }
        availability = .following
        manager.startUpdatingLocation()
        walkLog.notice("walk: following location")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self, availability != .idle else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: beginUpdates()
            case .denied, .restricted: availability = .denied
            case .notDetermined: availability = .waitingForPermission
            @unknown default: availability = .unavailable
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        let observation = LocationObservation(
            coordinate: GeoCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ),
            horizontalAccuracyMeters: max(location.horizontalAccuracy, 0),
            observedAt: location.timestamp
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            latest = observation
            onUpdate?(observation)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // The coordinate is deliberately absent from the log: a location is the
        // one thing in this app that must not end up in a diagnostic file.
        walkLog.error("walk: location update failed")
    }
}
