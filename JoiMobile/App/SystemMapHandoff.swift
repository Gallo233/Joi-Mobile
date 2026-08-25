import CoreLocation
import MapKit
import Observation

/// The external boundary for driving directions.
///
/// It receives only the Apple-search display result that the person inspected.
/// Joi's route, journey, transcript, memory and last location stay outside this
/// interface; Apple Maps owns route planning and any later location permission.
@MainActor
protocol SystemMapOpening {
    func openDrivingDirections(to destination: MapSearchResult) -> Bool
}

@MainActor
struct AppleSystemMapOpener: SystemMapOpening {
    func openDrivingDirections(to destination: MapSearchResult) -> Bool {
        let coordinate = CLLocationCoordinate2D(
            latitude: destination.coordinate.latitude,
            longitude: destination.coordinate.longitude
        )
        guard CLLocationCoordinate2DIsValid(coordinate) else { return false }

        let item = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
        item.name = destination.name
        return item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}

enum SystemMapHandoffPhase: Equatable, Sendable {
    case idle
    case confirming(MapSearchResult)
    case failed(MapSearchResult)
}

/// One explicit, retryable handoff from Map presentation to Apple Maps.
///
/// `proposeDriving` is inspect-only. `confirm` consumes the proposal before it
/// invokes the adapter, preventing a repeated callback from launching Maps
/// twice. A refusal keeps the destination available, but never silently retries.
@MainActor
@Observable
final class SystemMapHandoffModel {
    private(set) var phase: SystemMapHandoffPhase = .idle

    @ObservationIgnored private let opener: any SystemMapOpening

    init(opener: any SystemMapOpening = AppleSystemMapOpener()) {
        self.opener = opener
    }

    func proposeDriving(to destination: MapSearchResult) {
        phase = .confirming(destination)
    }

    func cancel() {
        guard case .confirming = phase else { return }
        phase = .idle
    }

    /// Clears a stale refusal/proposal when Map returns to its cultural route
    /// or selects a different search result.
    func reset() {
        phase = .idle
    }

    @discardableResult
    func confirm() -> Bool {
        guard case let .confirming(destination) = phase else { return false }

        // Consume before crossing the application boundary, so a repeated UI
        // callback cannot open the system app twice.
        phase = .idle
        let coordinate = CLLocationCoordinate2D(
            latitude: destination.coordinate.latitude,
            longitude: destination.coordinate.longitude
        )
        guard CLLocationCoordinate2DIsValid(coordinate),
              opener.openDrivingDirections(to: destination)
        else {
            phase = .failed(destination)
            return false
        }
        return true
    }
}
