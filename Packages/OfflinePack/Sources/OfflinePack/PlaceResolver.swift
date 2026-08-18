import CompanionCore
import Foundation

/// A stop that might be where the walker is standing, and how sure that is.
public struct PlaceCandidate: Equatable, Sendable {
    public let stop: RouteStop
    public let distanceMeters: Double
    /// How well this stop's position explains the reading, 0…1.
    ///
    /// Identity confidence only. `JM-P0-013` and PRD §8.1 keep it apart from
    /// source authority and evidence support, and nothing here mixes them: this
    /// answers "is this the place", not "is what we say about it true".
    public let identityConfidence: Double
}

/// What the walker's position says about where they are.
public enum PlaceProposal: Equatable, Sendable {
    /// Nothing on this route is close enough to propose. Not a failure — most
    /// of a walk is spent between stops.
    case betweenStops
    /// One stop explains the reading well, and better than any other.
    case confident(PlaceCandidate)
    /// More than one stop remains plausible, or the best one is not good
    /// enough to act on alone (`FAIL-017`). Carries every candidate, because
    /// the user is being asked to choose and needs to see what from.
    case ambiguous([PlaceCandidate])

    /// Everything still in the running, whichever shape the proposal took.
    public var candidates: [PlaceCandidate] {
        switch self {
        case .betweenStops: []
        case let .confident(candidate): [candidate]
        case let .ambiguous(candidates): candidates
        }
    }

    /// Whether the user has to choose before anything is settled.
    public var needsConfirmation: Bool {
        if case .ambiguous = self { return true }
        return false
    }
}

/// Proposes which stop the walker has arrived at.
///
/// `JM-P0-009`. The place database this needs is the pack's own stop list: a
/// cached tour already declares what its places are and where they sit, so
/// arrive-and-tell over a downloaded route needs no external gazetteer and no
/// network. Resolving arbitrary places in the world is a different problem with
/// a different data source, and this deliberately does not pretend to it.
public struct PlaceResolver: Sendable {
    /// How close counts as "at" a stop when the fix is perfect.
    public static let baseRadiusMeters = 40.0
    /// Below this, an identity is not good enough to act on without asking.
    public static let confidenceFloor = 0.5
    /// How much better the best candidate must be before the runner-up stops
    /// mattering. Two stops a few metres apart in confidence are two answers,
    /// not one — and saying so is the whole of `FAIL-017`.
    public static let decisiveMargin = 0.2

    private let stops: [RouteStop]

    public init(stops: [RouteStop]) {
        self.stops = stops
    }

    /// The proposal for one reading.
    ///
    /// Accuracy widens the search rather than being ignored: a fix good to 200 m
    /// cannot single out a stop 40 m away, and pretending otherwise is how a
    /// product auto-confirms the wrong place. A worse fix can therefore only
    /// ever make the answer less certain, never more — which is a property worth
    /// testing rather than trusting.
    public func propose(_ location: LocationObservation) -> PlaceProposal {
        guard location.horizontalAccuracyMeters.isFinite,
              location.horizontalAccuracyMeters >= 0
        else { return .betweenStops }

        // The search widens with a poor fix — more stops become worth
        // considering — while confidence falls with it. Those pull in opposite
        // directions on purpose: a vague reading should surface more candidates
        // and assert none of them.
        let radius = Self.baseRadiusMeters + location.horizontalAccuracyMeters
        let candidates = stops
            .map { stop -> PlaceCandidate in
                let distance = Self.distanceMeters(stop.coordinate, location.coordinate)
                return PlaceCandidate(
                    stop: stop,
                    distanceMeters: distance,
                    identityConfidence: Self.confidence(
                        distanceMeters: distance,
                        accuracyMeters: location.horizontalAccuracyMeters
                    )
                )
            }
            .filter { $0.distanceMeters <= radius }
            .sorted { $0.identityConfidence > $1.identityConfidence }

        guard let best = candidates.first else { return .betweenStops }
        guard best.identityConfidence >= Self.confidenceFloor else {
            // Close enough to be worth mentioning, not close enough to assert.
            return .ambiguous(candidates)
        }
        let runnerUp = candidates.dropFirst().first
        guard let runnerUp else { return .confident(best) }
        guard best.identityConfidence - runnerUp.identityConfidence >= Self.decisiveMargin else {
            return .ambiguous(candidates)
        }
        return .confident(best)
    }

    /// How much a stop at `distanceMeters` stands out, given a fix worth
    /// `accuracyMeters`.
    ///
    /// Falls with both, which is the property that matters: an uncertain fix
    /// cannot single out a place, however close that place happens to be. The
    /// first version of this divided by a radius that *grew* with accuracy, so a
    /// worse fix produced a more confident answer — inverted, and caught by the
    /// monotonicity test rather than by reading it.
    static func confidence(distanceMeters: Double, accuracyMeters: Double) -> Double {
        baseRadiusMeters / (baseRadiusMeters + max(0, distanceMeters) + max(0, accuracyMeters))
    }

    /// Equirectangular distance. The distances that matter here are tens of
    /// metres, where the approximation is worth far less than the GPS error it
    /// is being compared against.
    static func distanceMeters(_ lhs: GeoCoordinate, _ rhs: GeoCoordinate) -> Double {
        let earthRadius = 6_371_000.0
        let meanLatitude = (lhs.latitude + rhs.latitude) / 2 * .pi / 180
        let deltaLatitude = (lhs.latitude - rhs.latitude) * .pi / 180
        let deltaLongitude = (lhs.longitude - rhs.longitude) * .pi / 180 * cos(meanLatitude)
        return earthRadius * (deltaLatitude * deltaLatitude + deltaLongitude * deltaLongitude).squareRoot()
    }
}

/// What the walker has settled on, and how it got settled.
///
/// A correction is not a lesser kind of confirmation: `FAIL-018` requires a
/// correction to take effect locally and immediately, so both cases produce the
/// same authoritative answer and differ only in what they record about it.
public enum ConfirmedPlace: Equatable, Sendable {
    case confirmed(RouteStop)
    case corrected(RouteStop)

    public var stop: RouteStop {
        switch self {
        case let .confirmed(stop), let .corrected(stop): stop
        }
    }

    public var wasCorrected: Bool {
        if case .corrected = self { return true }
        return false
    }
}
