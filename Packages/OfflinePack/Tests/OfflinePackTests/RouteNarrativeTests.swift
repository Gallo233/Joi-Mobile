import CompanionCore
import XCTest
@testable import OfflinePack

/// `G2-J4B` — the ordered story a cached route tells.
///
/// `JM-P0-012` is the last of Map's four pillars with nothing behind it:
/// `RouteProgressEngine` could say how far along a line you were, and no type
/// anywhere knew that the line had stops, an order, a next one, or anything to
/// say when you got there.
final class RouteNarrativeTests: XCTestCase {
    /// `J4B-01` — stops are ordered by the route, not by the order a pack
    /// happened to list them in.
    func testStopsAreOrderedByTheRouteRatherThanByAuthoring() throws {
        let narrative = try Self.narrative(stopIndices: [4, 0, 2])
        XCTAssertEqual(narrative.stops.map(\.stop.stopID), ["stop.0", "stop.2", "stop.4"])
        XCTAssertEqual(
            narrative.stops.map(\.progressAlongRoute).sorted(),
            narrative.stops.map(\.progressAlongRoute),
            "route order is ascending progress"
        )
    }

    /// A stop that is not on this route is a broken pack, not a shorter tour.
    func testAStopOffTheRouteIsRefusedRatherThanDropped() throws {
        let engine = try Self.engine()
        let stray = RouteStop(
            stopID: "stop.stray",
            name: "不在路线上",
            // Latitude far outside any valid coordinate, so it cannot project.
            coordinate: GeoCoordinate(latitude: 999, longitude: 999),
            narration: "……",
            suggestedDurationSeconds: 60
        )
        XCTAssertThrowsError(try RouteNarrative(engine: engine, stops: [stray]))
    }

    func testATourWithNoStopsIsRefused() throws {
        XCTAssertThrowsError(try RouteNarrative(engine: Self.engine(), stops: []))
    }

    /// `J4B-02` — completion, the next stop and pacing all follow from progress.
    func testCompletionNextStopAndPacingFollowProgress() throws {
        let narrative = try Self.narrative(stopIndices: [0, 2, 4])

        let atStart = narrative.state(currentProgress: 0, furthestProgress: 0)
        XCTAssertEqual(atStart.completedCount, 1, "standing at the first stop counts as reaching it")
        XCTAssertEqual(atStart.nextStop?.stopID, "stop.2")
        XCTAssertFalse(atStart.isComplete)

        let midway = narrative.state(currentProgress: 0.6, furthestProgress: 0.6)
        XCTAssertEqual(midway.currentStop?.stopID, "stop.2")
        XCTAssertEqual(midway.nextStop?.stopID, "stop.4")
        XCTAssertLessThan(
            midway.remainingSuggestedSeconds,
            atStart.remainingSuggestedSeconds,
            "pacing counts down as stops are reached"
        )

        let finished = narrative.state(currentProgress: 1, furthestProgress: 1)
        XCTAssertTrue(finished.isComplete)
        XCTAssertNil(finished.nextStop)
        XCTAssertEqual(finished.completedCount, 3)
        XCTAssertEqual(finished.remainingSuggestedSeconds, 0)
    }

    /// `J4B-03` — walking back to look at something again does not un-visit the
    /// stops beyond it. Completion follows the furthest point reached.
    func testDoublingBackDoesNotUnvisitStops() throws {
        let narrative = try Self.narrative(stopIndices: [0, 2, 4])
        let reachedEnd = narrative.state(currentProgress: 1, furthestProgress: 1)
        XCTAssertEqual(reachedEnd.completedCount, 3)

        let walkedBack = narrative.state(currentProgress: 0.1, furthestProgress: 1)
        XCTAssertEqual(walkedBack.completedCount, 3, "the tour was still walked")
        XCTAssertTrue(walkedBack.isComplete)
        XCTAssertEqual(walkedBack.currentStop?.stopID, "stop.0", "but you are standing back at the first")
    }

    /// `J4B-03` — pause and resume. The state is a pure function of the two
    /// progress values, so nothing is lost by stopping and starting again.
    func testPausingAndResumingPreservesTheWalk() throws {
        let narrative = try Self.narrative(stopIndices: [0, 2, 4])
        let before = narrative.state(currentProgress: 0.6, furthestProgress: 0.6)
        // A pause changes nothing; a resume asks the same question again.
        let after = narrative.state(currentProgress: 0.6, furthestProgress: 0.6)
        XCTAssertEqual(before, after)

        // And resuming from a standstill after the walk was already partly done
        // keeps what was covered.
        let resumed = narrative.state(currentProgress: 0, furthestProgress: 0.6)
        XCTAssertEqual(resumed.completedCount, before.completedCount)
    }

    // MARK: - Recap

    /// `J4B-04` — the recap covers what was walked, not what the pack contains.
    func testTheRecapCoversOnlyStopsThatWereReached() throws {
        let narrative = try Self.narrative(stopIndices: [0, 2, 4])
        XCTAssertEqual(narrative.recap(furthestProgress: 0).map(\.stopID), ["stop.0"])
        XCTAssertEqual(narrative.recap(furthestProgress: 1).count, 3)
    }

    /// `J4B-05` — the rule this slice exists for: a recap separates sourced fact
    /// from the character talking, and the two cannot be confused.
    func testTheRecapKeepsSourcedFactsApartFromReflection() throws {
        let engine = try Self.engine()
        let coordinates = Self.route.coordinates
        let narrative = try RouteNarrative(
            engine: engine,
            stops: [
                RouteStop(
                    stopID: "stop.sourced",
                    name: "有来源",
                    coordinate: coordinates[0],
                    narration: "这段外滩堤岸建于二十世纪初。",
                    sourceRevisionIDs: ["fixture://sources/bund-history@2026-08-18"],
                    suggestedDurationSeconds: 120
                ),
                RouteStop(
                    stopID: "stop.reflective",
                    name: "只是感想",
                    coordinate: coordinates[4],
                    narration: "这里的风比刚才大一些，我喜欢。",
                    suggestedDurationSeconds: 60
                ),
            ]
        )

        let recap = narrative.recap(furthestProgress: 1)
        XCTAssertEqual(recap.count, 2)

        guard case let .fact(_, _, _, revisions) = recap[0] else {
            return XCTFail("a stop with source revisions is a fact")
        }
        XCTAssertFalse(revisions.isEmpty, "a fact without a revision is not representable")

        guard case .reflection = recap[1] else {
            return XCTFail("a stop with no source is the character talking, not an unsupported fact")
        }
        XCTAssertEqual(recap.filter(\.isFact).count, 1)
    }

    /// A stop with no source is not an unsupported claim — it is not a claim.
    /// The distinction matters because `sourceUnsupported` (`FAIL-022`) is about
    /// factual narration that has lost its evidence, which this is not.
    func testAnUnsourcedStopIsNotAClaimAtAll() {
        let reflective = RouteStop(
            stopID: "stop.1",
            name: "散步",
            coordinate: Self.route.coordinates[0],
            narration: "走到这里，江风就换了个方向。",
            suggestedDurationSeconds: 60
        )
        XCTAssertFalse(reflective.isFactual)

        let sourced = RouteStop(
            stopID: "stop.2",
            name: "史料",
            coordinate: Self.route.coordinates[0],
            narration: "这栋楼落成于 1923 年。",
            sourceRevisionIDs: ["fixture://sources/one@2026-08-18"],
            suggestedDurationSeconds: 60
        )
        XCTAssertTrue(sourced.isFactual)
    }

    // MARK: - Helpers

    private static let route = AcceptedNavigationRoute(
        routeID: "test.route",
        coordinates: [
            GeoCoordinate(latitude: 31.2304, longitude: 121.4737),
            GeoCoordinate(latitude: 31.2312, longitude: 121.4749),
            GeoCoordinate(latitude: 31.2325, longitude: 121.4761),
            GeoCoordinate(latitude: 31.2338, longitude: 121.4770),
            GeoCoordinate(latitude: 31.2351, longitude: 121.4776),
        ],
        cached: true
    )

    private static func engine() throws -> RouteProgressEngine {
        try RouteProgressEngine(route: route, configuration: RouteProgressConfiguration())
    }

    private static func narrative(stopIndices: [Int]) throws -> RouteNarrative {
        try RouteNarrative(
            engine: engine(),
            stops: stopIndices.map { index in
                RouteStop(
                    stopID: "stop.\(index)",
                    name: "第 \(index) 站",
                    coordinate: route.coordinates[index],
                    narration: "第 \(index) 站的叙述。",
                    suggestedDurationSeconds: 60
                )
            }
        )
    }
}
