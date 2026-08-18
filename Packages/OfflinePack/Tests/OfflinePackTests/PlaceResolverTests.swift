import CompanionCore
import XCTest
@testable import OfflinePack

/// `G2-J5D` — proposing which stop the walker has reached.
///
/// `JM-P0-009` wants location, accuracy and route progress combined into a
/// place proposal, with confirmation required when the identity is ambiguous or
/// weak. The place database is the pack's own stop list: a cached tour already
/// declares what its places are and where they sit.
final class PlaceResolverTests: XCTestCase {
    /// Standing on a stop, with a good fix, and nothing else nearby.
    func testStandingOnAnIsolatedStopIsConfident() {
        let resolver = PlaceResolver(stops: [Self.stop(id: "a", at: Self.bund), Self.stop(id: "far", at: Self.faraway)])

        guard case let .confident(candidate) = resolver.propose(Self.fix(at: Self.bund, accuracy: 5)) else {
            return XCTFail("an isolated stop underfoot is not ambiguous")
        }
        XCTAssertEqual(candidate.stop.stopID, "a")
        XCTAssertGreaterThan(candidate.identityConfidence, PlaceResolver.confidenceFloor)
        XCTAssertLessThan(candidate.distanceMeters, 1)
    }

    /// `FAIL-017` — two stops close together are two answers, and the product
    /// asks rather than picks.
    func testTwoNearbyStopsAreAmbiguousRatherThanGuessed() {
        let resolver = PlaceResolver(stops: [
            Self.stop(id: "left", at: Self.offset(Self.bund, metresNorth: -6)),
            Self.stop(id: "right", at: Self.offset(Self.bund, metresNorth: 6)),
        ])

        guard case let .ambiguous(candidates) = resolver.propose(Self.fix(at: Self.bund, accuracy: 5)) else {
            return XCTFail("two equally plausible stops must not auto-confirm")
        }
        XCTAssertEqual(candidates.count, 2, "the candidate set is preserved for the user to choose from")
        XCTAssertEqual(
            candidates.map(\.stop.stopID).sorted(),
            ["left", "right"],
            "both are shown, not just the marginal winner"
        )
    }

    /// Most of a walk is spent between stops, and that is not a failure.
    func testBeingNowhereNearAStopProposesNothing() {
        let resolver = PlaceResolver(stops: [Self.stop(id: "a", at: Self.bund)])
        XCTAssertEqual(resolver.propose(Self.fix(at: Self.faraway, accuracy: 5)), .betweenStops)
    }

    /// The property that keeps a bad fix from becoming a confident answer: a
    /// worse fix may only ever make the proposal less certain.
    func testAWorseFixNeverIncreasesConfidence() {
        let resolver = PlaceResolver(stops: [Self.stop(id: "a", at: Self.bund)])
        let position = Self.offset(Self.bund, metresNorth: 20)

        var previous = 1.0
        for accuracy in [1.0, 10, 50, 200, 1_000] {
            let proposal = resolver.propose(Self.fix(at: position, accuracy: accuracy))
            let confidence: Double
            switch proposal {
            case let .confident(candidate): confidence = candidate.identityConfidence
            case let .ambiguous(candidates): confidence = candidates.first?.identityConfidence ?? 0
            case .betweenStops: confidence = 0
            }
            XCTAssertLessThanOrEqual(
                confidence,
                previous + 1e-9,
                "accuracy \(accuracy) m produced more confidence than a better fix"
            )
            previous = confidence
        }
    }

    /// A fix too poor to single out a stop must not assert one, even standing
    /// directly on it. This is the auto-confirm that `FAIL-017` forbids.
    func testAVeryPoorFixDoesNotAssertAStopEvenStandingOnIt() {
        let resolver = PlaceResolver(stops: [Self.stop(id: "a", at: Self.bund)])
        let proposal = resolver.propose(Self.fix(at: Self.bund, accuracy: 2_000))

        guard case .ambiguous = proposal else {
            return XCTFail("a 2 km fix cannot confirm a 40 m place: \(proposal)")
        }
    }

    /// An unusable accuracy proposes nothing rather than being treated as
    /// perfect — the same refusal `RouteProgressEngine` makes.
    func testAnUnusableAccuracyProposesNothing() {
        let resolver = PlaceResolver(stops: [Self.stop(id: "a", at: Self.bund)])
        for accuracy in [Double.nan, -1] {
            XCTAssertEqual(resolver.propose(Self.fix(at: Self.bund, accuracy: accuracy)), .betweenStops)
        }
    }

    /// A tour with no stops proposes nothing rather than trapping.
    func testAnEmptyTourProposesNothing() {
        XCTAssertEqual(
            PlaceResolver(stops: []).propose(Self.fix(at: Self.bund, accuracy: 5)),
            .betweenStops
        )
    }

    /// `FAIL-018` — a correction is authoritative immediately. It is not a
    /// weaker kind of confirmation; it differs only in recording that the user
    /// overrode the proposal.
    func testACorrectionIsAsAuthoritativeAsAConfirmation() {
        let stop = Self.stop(id: "a", at: Self.bund)
        XCTAssertEqual(ConfirmedPlace.confirmed(stop).stop, stop)
        XCTAssertEqual(ConfirmedPlace.corrected(stop).stop, stop)
        XCTAssertFalse(ConfirmedPlace.confirmed(stop).wasCorrected)
        XCTAssertTrue(ConfirmedPlace.corrected(stop).wasCorrected)
    }

    // MARK: - Helpers

    private static let bund = GeoCoordinate(latitude: 31.2304, longitude: 121.4737)
    private static let faraway = GeoCoordinate(latitude: 31.5000, longitude: 121.9000)

    private static func offset(_ coordinate: GeoCoordinate, metresNorth: Double) -> GeoCoordinate {
        GeoCoordinate(
            latitude: coordinate.latitude + metresNorth / 111_320,
            longitude: coordinate.longitude
        )
    }

    private static func stop(id: String, at coordinate: GeoCoordinate) -> RouteStop {
        RouteStop(
            stopID: id,
            name: "站点 \(id)",
            coordinate: coordinate,
            narration: "关于 \(id) 的叙述。",
            suggestedDurationSeconds: 60
        )
    }

    private static func fix(at coordinate: GeoCoordinate, accuracy: Double) -> LocationObservation {
        LocationObservation(coordinate: coordinate, horizontalAccuracyMeters: accuracy, observedAt: Date())
    }
}
