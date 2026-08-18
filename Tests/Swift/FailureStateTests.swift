import CompanionCore
import Foundation
import OfflinePack
import XCTest
@testable import JoiMobile

/// `G2-J4A` — named failure states held to their declared semantics.
///
/// PRD §7 names 32 degraded states and §7.1 gives each one a `FAIL-NNN` fixture
/// ID and an exact cancellation rule. Until now `FAIL-001`…`FAIL-032` appeared
/// nowhere outside that document: the "32 failure fixtures" the Product Design
/// scheme gate records as closing G0 rework were two tables, not fixtures.
/// `Contracts/failure-states.json` is now the executable map, and these cover
/// the states whose declared rules nothing else was checking.
@MainActor
final class FailureStateTests: XCTestCase {
    // MARK: - FAIL-015 locationDenied

    /// `FAIL-015` — "Stop collection request; clear pending exact snapshot and
    /// keep manual actions."
    ///
    /// The defect this closes: a walk begins its journey before the system has
    /// answered about permission, because a reading needs somewhere to be
    /// reduced into. When the answer was "no", nothing undid that. The walk
    /// stayed nominally in progress and `JourneyContextStore` kept a snapshot
    /// for a route nothing was tracking.
    func testADeniedLocationClearsTheJourneySnapshotItAlreadyOpened() async throws {
        let model = AppModel()
        model.startWalk()
        try await Self.waitForJourney(model)

        // The state the defect left behind: a live journey for an untracked walk.
        let opened = await model.journeyContext.current()
        XCTAssertNotNil(opened.routeID)
        XCTAssertTrue(model.isWalking)

        model.endWalkWithoutLocation()

        XCTAssertFalse(model.isWalking, "a walk nothing is tracking is not in progress")
        var cleared = false
        for _ in 0..<300 {
            if await model.journeyContext.current().routeID == nil {
                cleared = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(cleared, "the pending exact snapshot must be cleared")
    }

    /// `FAIL-015` — and the conversation is not offered a context that no longer
    /// exists. This is the part that mattered: Map kept offering to carry the
    /// walk into Chat.
    func testADeniedLocationWithdrawsTheOfferToCarryContextIntoChat() async throws {
        let model = AppModel()
        model.startWalk()
        try await Self.waitForJourney(model)
        await model.offerJourneyAttachment()
        XCTAssertNotNil(model.pendingJourneyAttachment, "the offer exists while the walk does")
        XCTAssertTrue(model.canOfferJourneyAttachment)

        model.endWalkWithoutLocation()

        XCTAssertNil(model.pendingJourneyAttachment, "an un-sent offer goes with the walk")
        XCTAssertFalse(model.canOfferJourneyAttachment, "there is no context left to offer")
    }

    /// "Keep manual actions" — the surface must still be able to say *why* the
    /// walk ended, so the provider's availability is deliberately not reset.
    func testEndingAWalkWithoutLocationDoesNotEraseTheExplanation() async throws {
        let model = AppModel()
        model.startWalk()
        try await Self.waitForJourney(model)
        let duringWalk = model.walkLocation.availability

        model.endWalkWithoutLocation()

        XCTAssertEqual(
            model.walkLocation.availability,
            duringWalk,
            "resetting availability would take the reason for the failure with it"
        )
    }

    /// Ending a walk that never started is inert, so a late unavailability
    /// callback cannot clear a journey that a *different* walk has since begun.
    func testEndingAWalkThatIsNotRunningChangesNothing() async {
        let model = AppModel()
        let before = await model.journeyContext.current()
        model.endWalkWithoutLocation()
        let after = await model.journeyContext.current()
        XCTAssertEqual(before, after)
        XCTAssertFalse(model.isWalking)
    }

    // MARK: - FAIL-016 locationUnavailable

    /// `FAIL-016` — "Reject stale/inaccurate sample". The half that holds: an
    /// accuracy that is not a usable number is refused as `locationUnavailable`
    /// rather than treated as a perfect fix.
    func testAnUnusableAccuracyIsRefused() throws {
        let walk = CachedWalk.sample
        let onRoute = try XCTUnwrap(walk.route.coordinates.first)

        for accuracy in [Double.nan, -1, -Double.infinity] {
            XCTAssertThrowsError(
                try walk.engine.observe(
                    LocationObservation(
                        coordinate: onRoute,
                        horizontalAccuracyMeters: accuracy,
                        observedAt: Date()
                    ),
                    session: NavigationSessionID()
                ),
                "accuracy \(accuracy) is not a measurement"
            ) { error in
                XCTAssertEqual(error as? NavigationError, .locationUnavailable)
            }
        }
    }

    /// `FAIL-016` — the half that does **not** hold, recorded rather than hidden.
    ///
    /// A fix accurate to a kilometre is accepted and advances progress; its
    /// accuracy only widens the off-route allowance. Sample age is never looked
    /// at at all. Choosing an accuracy ceiling and a staleness window is a field
    /// decision (G4), so neither is invented here — but this test pins the
    /// current behaviour, so adding one has to be a deliberate change rather
    /// than a silent one. `Contracts/failure-states.json` carries the same gap.
    func testAWildlyInaccurateOrStaleSampleIsCurrentlyStillAccepted() throws {
        let walk = CachedWalk.sample
        let onRoute = try XCTUnwrap(walk.route.coordinates.first)
        let session = NavigationSessionID()

        let inaccurate = try walk.engine.observe(
            LocationObservation(coordinate: onRoute, horizontalAccuracyMeters: 1_000, observedAt: Date()),
            session: session
        )
        XCTAssertFalse(inaccurate.navigationObservation.offRoute, "recorded gap: a 1 km fix still counts")

        let ancient = try walk.engine.observe(
            LocationObservation(
                coordinate: onRoute,
                horizontalAccuracyMeters: 5,
                observedAt: Date(timeIntervalSince1970: 0)
            ),
            session: session
        )
        XCTAssertEqual(
            ancient.navigationObservation.candidateProgress,
            inaccurate.navigationObservation.candidateProgress,
            accuracy: 0.001,
            "recorded gap: a 1970 timestamp is treated exactly like a fresh one"
        )
    }

    // MARK: - FAIL-002 responseCancelled

    /// `FAIL-002` — "Reject late events; preserve accepted transcript and
    /// request a new ID on retry."
    ///
    /// The turn has to be stopped **while it is in flight**. Stopping a finished
    /// one is a no-op — `stopChatTurn` returns early once the request ID is
    /// cleared — so a test that stops afterwards proves nothing about
    /// cancellation, which is how the first draft of this test passed its own
    /// author and failed the assertion.
    func testStoppingAnInFlightTurnRejectsLateEventsAndRetriesUnderANewID() async throws {
        let gateway = HeldGateway()
        let model = AppModel(chatGateway: gateway)

        // One completed turn, so there is accepted history to preserve.
        model.chatDraft = "第一句"
        model.sendChatMessage()
        try await Self.waitUntil { !model.chatTurnState.isPending && !model.chatTranscript.isEmpty }
        let accepted = model.chatTranscript
        XCTAssertFalse(accepted.isEmpty)

        // A second turn, held open, then stopped mid-flight.
        await gateway.hold()
        model.chatDraft = "会被停掉"
        model.sendChatMessage()
        try await Self.waitUntil { model.chatTurnState.isPending }
        let cancelledIDs = await gateway.requestIDs
        let cancelledID = try XCTUnwrap(cancelledIDs.last)

        model.stopChatTurn()
        XCTAssertEqual(model.chatTurnState, .cancelled)
        XCTAssertEqual(model.chatTranscript, accepted, "a stop discards the failing turn, not history")

        // Its terminal event now arrives late, and must not extend anything.
        await gateway.release()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.chatTranscript, accepted, "a late terminal event must not append")
        XCTAssertEqual(model.chatTurnState, .cancelled)

        // The retry is a new request, not a resumed one.
        model.chatDraft = "重试"
        model.sendChatMessage()
        try await Self.waitUntil { model.chatTranscript.count > accepted.count }
        let allIDs = await gateway.requestIDs
        XCTAssertEqual(allIDs.count, 3)
        XCTAssertNotEqual(allIDs[2], cancelledID, "a retry must not reuse the cancelled turn's identity")
        XCTAssertEqual(Set(allIDs).count, 3, "every turn has its own request ID")
    }

    // MARK: - Helpers

    private static func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("condition never held")
    }

    /// `startWalk` opens its journey on a detached task, so a test that inspects
    /// the owner immediately would race it.
    private static func waitForJourney(_ model: AppModel) async throws {
        for _ in 0..<300 {
            if await model.journeyContext.current().routeID != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("starting a walk must begin a journey")
    }
}

/// Records the request ID of every turn, and can hold a stream open between its
/// accepted-input and terminal events so a turn can be stopped mid-flight.
private actor HeldGateway: ChatGateway {
    private(set) var requestIDs: [String] = []
    private var holding = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func hold() { holding = true }

    func release() {
        holding = false
        let resumed = waiters
        waiters.removeAll()
        for waiter in resumed { waiter.resume() }
    }

    private func record(_ id: String) { requestIDs.append(id) }

    private func waitIfHolding() async {
        guard holding else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    nonisolated func stream(_ request: ChatRequest) -> AsyncThrowingStream<CompanionEventV1, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await record(request.requestID)
                continuation.yield(
                    CompanionEventV1(
                        eventID: "\(request.requestID)-received",
                        requestID: request.requestID,
                        threadID: request.threadID,
                        sessionID: request.sessionID,
                        characterID: request.characterID,
                        phase: .received,
                        contentState: .acceptedInput,
                        displayText: request.text
                    )
                )
                await waitIfHolding()
                continuation.yield(
                    CompanionEventV1(
                        eventID: "\(request.requestID)-done",
                        requestID: request.requestID,
                        threadID: request.threadID,
                        sessionID: request.sessionID,
                        characterID: request.characterID,
                        phase: .done,
                        contentState: .acceptedFinal,
                        displayText: "好的。"
                    )
                )
                continuation.finish()
            }
        }
    }
}
