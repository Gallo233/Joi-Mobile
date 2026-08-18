import CompanionCore
import XCTest
@testable import JoiMobile

/// `G2-J3A`. The route engine and the journey store were both already built and
/// tested; what had never existed was anything joining them to a surface. These
/// cover the joining — that the bundled route is usable, that progress is the
/// store's to record, and that leaving the route produces guidance a person can
/// actually walk.
@MainActor
final class CachedWalkTests: XCTestCase {
    /// `CachedWalk.sample` is force-tried at a `static let`, so this is what keeps
    /// that safe: an edit that makes the constant invalid fails here instead of
    /// trapping on a device.
    func testTheBundledSampleWalkIsAUsableCachedRoute() throws {
        let walk = CachedWalk.sample
        XCTAssertTrue(walk.route.cached, "a walk that is not cached cannot be followed offline")
        XCTAssertGreaterThanOrEqual(walk.route.coordinates.count, 2)
        XCTAssertFalse(walk.title.isEmpty)

        // The engine it built is the thing that decides progress; prove it runs.
        let start = try XCTUnwrap(walk.route.coordinates.first)
        let observed = try walk.engine.observe(
            LocationObservation(coordinate: start, horizontalAccuracyMeters: 5, observedAt: Date()),
            session: NavigationSessionID()
        )
        XCTAssertFalse(observed.navigationObservation.offRoute, "standing on the route is not off it")
        XCTAssertEqual(observed.navigationObservation.candidateProgress, 0, accuracy: 0.02)
    }

    /// Walking the route end to end moves progress from nothing to complete, and
    /// the far end reads as arrival rather than as 100% with no acknowledgement.
    func testWalkingTheRouteProgressesAndArrives() throws {
        let walk = CachedWalk.sample
        let session = NavigationSessionID()
        let end = try XCTUnwrap(walk.route.coordinates.last)

        let arrival = try walk.engine.observe(
            LocationObservation(coordinate: end, horizontalAccuracyMeters: 5, observedAt: Date()),
            session: session
        )
        XCTAssertEqual(arrival.navigationObservation.candidateProgress, 1, accuracy: 0.02)
        XCTAssertTrue(arrival.arrived)
        XCTAssertNil(arrival.returnGuidance, "arriving is not departing")
    }

    /// Leaving the corridor produces a distance and a bearing back, which is the
    /// whole of what DEC-004 promises for departure.
    func testLeavingTheRouteProducesGuidanceBack() throws {
        let walk = CachedWalk.sample
        let onRoute = try XCTUnwrap(walk.route.coordinates.dropFirst(2).first)
        // Well east of the corridor.
        let away = GeoCoordinate(latitude: onRoute.latitude, longitude: onRoute.longitude + 0.004)

        let observed = try walk.engine.observe(
            LocationObservation(coordinate: away, horizontalAccuracyMeters: 5, observedAt: Date()),
            session: NavigationSessionID()
        )
        XCTAssertTrue(observed.navigationObservation.offRoute)
        let guidance = try XCTUnwrap(observed.returnGuidance)
        XCTAssertGreaterThan(guidance.distanceMeters, 100)
        // Standing east of the route, the way back has a westward component. It
        // is not exactly due west: this route runs southwest to northeast, so the
        // shortest way back to it from due east is northwest.
        let back = AppModel.compass(guidance.bearingToRouteDegrees)
        XCTAssertTrue(["西", "西北", "西南"].contains(back), "expected a westward return, got \(back)")
    }

    /// A bearing in degrees is not walkable, so it is turned into one of eight
    /// points — including the wrap either side of north.
    func testCompassCoversTheCircleIncludingTheWrapAtNorth() {
        XCTAssertEqual(AppModel.compass(0), "北")
        XCTAssertEqual(AppModel.compass(90), "东")
        XCTAssertEqual(AppModel.compass(180), "南")
        XCTAssertEqual(AppModel.compass(270), "西")
        XCTAssertEqual(AppModel.compass(359), "北", "just short of north is still north")
        XCTAssertEqual(AppModel.compass(-90), "西", "a negative bearing is normalised")
        XCTAssertEqual(AppModel.compass(720), "北", "so is one past a full turn")
    }

    /// `JourneyContextStore` stays the only writer of progress: starting a walk
    /// registers the route with it, and ending one drops the context entirely so
    /// a finished walk leaves nothing behind.
    func testStartingAndEndingAWalkOwnsTheJourneyContext() async throws {
        let model = AppModel()
        let before = await model.journeyContext.current()
        XCTAssertNil(before.routeID)

        model.startWalk()
        XCTAssertTrue(model.isWalking)
        var registered = false
        for _ in 0..<100 {
            let snapshot = await model.journeyContext.current()
            if snapshot.routeID == CachedWalk.sample.route.routeID { registered = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(registered, "the walk must register its route with the journey store")

        model.stopWalk()
        XCTAssertFalse(model.isWalking)
        XCTAssertNil(model.walkObservation)
        var cleared = false
        for _ in 0..<100 {
            let snapshot = await model.journeyContext.current()
            if snapshot.routeID == nil { cleared = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(cleared, "ending a walk drops the journey context")
    }

    /// Nothing about a walk touches the conversation. Location is journey state,
    /// and DEC-002 keeps it out of the thread and the transcript.
    func testWalkingChangesNothingAboutTheConversation() async throws {
        let model = AppModel()
        let session = await model.companionSession.current()

        model.startWalk()
        model.stopWalk()

        let after = await model.companionSession.current()
        XCTAssertEqual(after, session)
        XCTAssertTrue(model.chatTranscript.isEmpty)
    }
}
