import CompanionCore
import XCTest
@testable import OfflinePack

final class RouteProgressEngineTests: XCTestCase {
    private let route = AcceptedNavigationRoute(
        routeID: "cached-walk",
        coordinates: [
            GeoCoordinate(latitude: 0, longitude: 0),
            GeoCoordinate(latitude: 0, longitude: 0.001),
        ],
        cached: true
    )

    func testProjectsLocationToDeterministicRouteProgress() throws {
        let engine = try RouteProgressEngine(route: route)
        let observation = try engine.observe(
            try location(latitude: 0, longitude: 0.0005),
            session: NavigationSessionID()
        )

        XCTAssertEqual(observation.navigationObservation.candidateProgress, 0.5, accuracy: 0.001)
        XCTAssertEqual(observation.navigationObservation.distanceToRouteMeters, 0, accuracy: 0.01)
        XCTAssertFalse(observation.navigationObservation.offRoute)
        XCTAssertFalse(observation.arrived)
        XCTAssertNil(observation.returnGuidance)
    }

    func testEndpointIsArrivalWithoutInventingETAOrManeuver() throws {
        let engine = try RouteProgressEngine(route: route)
        let observation = try engine.observe(
            try location(latitude: 0, longitude: 0.001),
            session: NavigationSessionID()
        )

        XCTAssertEqual(observation.navigationObservation.candidateProgress, 1, accuracy: 0.000_001)
        XCTAssertTrue(observation.arrived)
        XCTAssertFalse(observation.navigationObservation.offRoute)
    }

    func testDriftEmitsReturnToAcceptedRouteGuidance() throws {
        let engine = try RouteProgressEngine(
            route: route,
            configuration: RouteProgressConfiguration(
                offRouteThresholdMeters: 20,
                arrivalThresholdMeters: 8,
                maximumAccuracyAllowanceMeters: 0
            )
        )
        let observation = try engine.observe(
            try location(latitude: 0.001, longitude: 0.0005, accuracy: 0),
            session: NavigationSessionID()
        )

        XCTAssertTrue(observation.navigationObservation.offRoute)
        XCTAssertFalse(observation.arrived)
        XCTAssertEqual(observation.navigationObservation.candidateProgress, 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(observation.navigationObservation.distanceToRouteMeters, 100)
        XCTAssertLessThan(observation.navigationObservation.distanceToRouteMeters, 115)
        let guidance = try XCTUnwrap(observation.returnGuidance)
        XCTAssertEqual(guidance.nearestRouteCoordinate.latitude, 0, accuracy: 0.000_001)
        XCTAssertEqual(guidance.bearingToRouteDegrees, 180, accuracy: 1)
    }

    func testAdapterRejectsStaleSessionAndStoppedSession() async throws {
        let adapter = FerrostarCachedNavigationAdapter()
        let activeSession = NavigationSessionID()
        let staleSession = NavigationSessionID()
        try await adapter.start(route, session: activeSession, mode: .cachedRouteOnly)

        do {
            _ = try await adapter.observeChecked(
                try location(latitude: 0, longitude: 0.0005),
                session: staleSession
            )
            XCTFail("Expected staleSession")
        } catch {
            XCTAssertEqual(error as? NavigationError, .staleSession)
        }

        await adapter.stop(session: activeSession, reason: .userStopped)
        do {
            _ = try await adapter.observeChecked(
                try location(latitude: 0, longitude: 0.0005),
                session: activeSession
            )
            XCTFail("Expected cancelled")
        } catch {
            XCTAssertEqual(error as? NavigationError, .cancelled)
        }
    }

    func testStoppedProtocolObservationCannotCommitToJourneyStore() async throws {
        let adapter = FerrostarCachedNavigationAdapter()
        let session = NavigationSessionID()
        let store = JourneyContextStore()
        await store.begin(route: route, session: session)
        try await adapter.start(route, session: session, mode: .cachedRouteOnly)
        await adapter.stop(session: session, reason: .userStopped)

        let rejected = await adapter.observe(
            try location(latitude: 0, longitude: 0.0005),
            session: session
        )

        XCTAssertNotEqual(rejected.sessionID, session)
        let didCommit = await store.reduce(rejected)
        XCTAssertFalse(didCommit)
        let snapshot = await store.current()
        XCTAssertEqual(snapshot.routeProgress, 0)
    }

    func testPlanningSeamExplicitlyRejectsNewOfflineRoute() async throws {
        let planner = FerrostarCachedRoutePlanningAdapter()
        let request = RouteRequest(
            origin: GeoCoordinate(latitude: 0, longitude: 0),
            destination: GeoCoordinate(latitude: 1, longitude: 1),
            mode: "walking"
        )

        do {
            _ = try await planner.plan(request, availability: .cachedRouteOnly)
            XCTFail("Expected newRouteUnavailableOffline")
        } catch {
            XCTAssertEqual(error as? NavigationError, .newRouteUnavailableOffline)
        }
    }

    private func location(
        latitude: Double,
        longitude: Double,
        accuracy: Double = 3
    ) throws -> LocationObservation {
        LocationObservation(
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
            horizontalAccuracyMeters: accuracy,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
