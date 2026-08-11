import XCTest
@testable import CompanionCore

final class StateOwnerTests: XCTestCase {
    func testSurfaceIndependentSessionIdentityRemainsStable() async {
        let store = CompanionSessionStore(characterID: "joi", threadID: "thread-1", sessionID: "session-1")
        let before = await store.current()
        await store.accept(eventID: "event-1")
        await store.accept(eventID: "event-1")
        let after = await store.current()

        XCTAssertEqual(before.characterID, after.characterID)
        XCTAssertEqual(before.threadID, after.threadID)
        XCTAssertEqual(after.acceptedEventIDs, ["event-1"])
    }

    func testJourneyStoreRejectsStaleNavigationSession() async {
        let store = JourneyContextStore()
        let active = NavigationSessionID()
        let stale = NavigationSessionID()
        let route = AcceptedNavigationRoute(
            routeID: "route",
            coordinates: [GeoCoordinate(latitude: 31.23, longitude: 121.47)],
            cached: true
        )
        await store.begin(route: route, session: active)

        let accepted = await store.reduce(
            NavigationObservation(
                sessionID: stale,
                candidateProgress: 1,
                distanceToRouteMeters: 0,
                offRoute: false,
                nearestCoordinate: route.coordinates[0]
            )
        )

        XCTAssertFalse(accepted)
        let snapshot = await store.current()
        XCTAssertEqual(snapshot.routeProgress, 0)
    }

    func testSpeechRejectsStaleCompletion() async {
        let coordinator = SpeechCoordinator()
        let cue = SpeechCue(
            cueID: "cue",
            text: "Hello",
            displayLocale: "en",
            voiceLocale: "en",
            priority: .conversation,
            sessionID: "session",
            characterID: "joi"
        )
        let result = await coordinator.begin(cue)
        let generation = try! XCTUnwrap(result.acceptedGeneration)
        await coordinator.cancel(reason: .userStopped)
        let accepted = await coordinator.acceptsCompletion(for: generation)
        XCTAssertFalse(accepted)
    }

    func testSpeechRejectsLowerPriorityAndPreemptsWithRoutePriority() async throws {
        let coordinator = SpeechCoordinator()
        let narration = SpeechCue(
            cueID: "place",
            text: "Place",
            displayLocale: "zh-Hans",
            voiceLocale: "zh-Hans",
            priority: .placeNarration,
            sessionID: "session",
            characterID: "joi"
        )
        let conversation = SpeechCue(
            cueID: "chat",
            text: "Chat",
            displayLocale: "zh-Hans",
            voiceLocale: "zh-Hans",
            priority: .conversation,
            sessionID: "session",
            characterID: "joi"
        )
        let route = SpeechCue(
            cueID: "route",
            text: "Turn",
            displayLocale: "zh-Hans",
            voiceLocale: "zh-Hans",
            priority: .routeManeuver,
            sessionID: "session",
            characterID: "joi"
        )

        let first = await coordinator.begin(narration)
        let firstGeneration = try XCTUnwrap(first.acceptedGeneration)
        let rejected = await coordinator.begin(conversation)
        XCTAssertEqual(rejected, .rejected(active: firstGeneration))

        let routeResult = await coordinator.begin(route)
        guard case let .preempted(new, cancelled) = routeResult else {
            return XCTFail("Expected route cue to preempt narration")
        }
        XCTAssertEqual(cancelled, firstGeneration)
        let acceptsNew = await coordinator.acceptsCompletion(for: new)
        let acceptsOld = await coordinator.acceptsCompletion(for: firstGeneration)
        XCTAssertTrue(acceptsNew)
        XCTAssertFalse(acceptsOld)
    }

    func testPreciseLocationIsNeverSyncEligibleByLocalSave() {
        let record = MemoryRecordV1(
            recordID: "memory",
            characterID: "joi",
            category: .preciseLocation,
            classification: .sensitiveLocation,
            value: "The Bund",
            provenance: .userEntered,
            reason: "User saved this place",
            precision: "place",
            authorizationDigest: "digest",
            createdAt: Date(),
            updatedAt: Date(),
            syncEligible: true
        )
        XCTAssertFalse(record.syncEligible)
    }
}
