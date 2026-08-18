import CompanionCore
import Foundation
import XCTest
@testable import JoiMobile

/// `G2-J3B` — the one-turn journey attachment.
///
/// `ChatRequest` has carried `journeyAttachment` and `journeyReceipt` since G1,
/// with validation for purpose, identity, digest, validity window and
/// revocation, and `JourneyUseReceiptStore` has enforced single use. Every
/// request the app built passed `nil` for both, so the contract that keeps
/// location out of the conversation had never been exercised by the product. It
/// is exercised here.
@MainActor
final class JourneyAttachmentTests: XCTestCase {
    // MARK: - What is actually sent

    /// `J3B-01` — the payload is coarsened at construction, so the precise fix
    /// the journey owner holds has no path into Chat.
    func testTheAttachedCoordinateIsCoarsenedAwayFromTheObservedFix() throws {
        let observed = GeoCoordinate(latitude: 31.230417, longitude: 121.473695)
        let attachment = try XCTUnwrap(
            JourneyAttachment(
                journey: JourneyContextSnapshot(
                    journeyID: "journey-1",
                    routeID: "sample.riverside",
                    coordinate: observed,
                    horizontalAccuracyMeters: 5,
                    routeProgress: 0.5
                ),
                routeTitle: "示例",
                at: Date()
            )
        )
        let sent = try XCTUnwrap(attachment.payload.coordinate)
        XCTAssertNotEqual(sent.latitude, observed.latitude)
        XCTAssertNotEqual(sent.longitude, observed.longitude)
        XCTAssertEqual(sent.latitude, 31.230, accuracy: 1e-9)
        XCTAssertEqual(sent.longitude, 121.474, accuracy: 1e-9)
    }

    /// `J3B-01` — a coordinate rounded onto a ~111 m grid is not a 5 m fix, and
    /// the accuracy field says so rather than carrying the original number.
    func testAccuracyIsRaisedToTheCoarseningGridRatherThanReportingTheFix() throws {
        let attachment = try XCTUnwrap(
            JourneyAttachment(
                journey: JourneyContextSnapshot(
                    routeID: "sample.riverside",
                    coordinate: GeoCoordinate(latitude: 31.2304, longitude: 121.4737),
                    horizontalAccuracyMeters: 5
                ),
                routeTitle: "示例",
                at: Date()
            )
        )
        XCTAssertEqual(attachment.payload.horizontalAccuracyMeters, JourneyAttachment.gridMeters)
        XCTAssertGreaterThan(try XCTUnwrap(attachment.payload.horizontalAccuracyMeters), 5)
    }

    /// `J3B-02` — the preview prints the payload's own numbers. If these could
    /// drift apart, "inspectable" would mean nothing: the user would approve one
    /// position and send another.
    func testThePreviewShowsExactlyTheCoordinateThatWillBeSent() throws {
        let attachment = try XCTUnwrap(
            JourneyAttachment(
                journey: JourneyContextSnapshot(
                    routeID: "sample.riverside",
                    coordinate: GeoCoordinate(latitude: 31.230417, longitude: 121.473695),
                    routeProgress: 0.76
                ),
                routeTitle: "示例",
                at: Date()
            )
        )
        let line = try XCTUnwrap(attachment.positionLine)
        XCTAssertTrue(line.contains("31.230"), "shown latitude must be the sent one: \(line)")
        XCTAssertTrue(line.contains("121.474"), "shown longitude must be the sent one: \(line)")
        // A fourth decimal would display precision the payload does not contain.
        XCTAssertFalse(line.contains("31.2304"), "must not show more precision than is sent")
        XCTAssertEqual(attachment.progressLine, "已完成 76%")
    }

    /// `J3B-03` — the payload states the scope it was approved under, and the
    /// digest covers that field, so the same coordinates carrying any other
    /// scope produce a different digest and fail receipt validation. The
    /// authorisation binds to the purpose, not merely to the position.
    func testScopeIsPartOfThePayloadAndThereforeOfTheDigest() throws {
        let attachment = try XCTUnwrap(
            JourneyAttachment(
                journey: JourneyContextSnapshot(
                    routeID: "sample.riverside",
                    coordinate: GeoCoordinate(latitude: 31.2304, longitude: 121.4737),
                    consentScope: "ephemeral"
                ),
                routeTitle: "示例",
                at: Date()
            )
        )
        XCTAssertEqual(attachment.payload.consentScope, "chat-one-turn")

        let sameFactsOtherScope = JourneyContextSnapshot(
            routeID: attachment.payload.routeID,
            coordinate: attachment.payload.coordinate,
            horizontalAccuracyMeters: attachment.payload.horizontalAccuracyMeters,
            consentScope: "long-term-memory"
        )
        XCTAssertNotEqual(
            attachment.payload.payloadDigest(),
            sameFactsOtherScope.payloadDigest(),
            "a memory-scoped payload must not satisfy a chat-scoped receipt"
        )
    }

    /// A walk that is not running has no fact to hand over, so no attachment can
    /// be constructed for one.
    func testNoRouteMeansNoAttachment() {
        XCTAssertNil(
            JourneyAttachment(journey: .empty, routeTitle: "示例", at: Date()),
            "an empty journey must not become an attachment"
        )
    }

    // MARK: - Reaching the request

    /// `J3B-04` — the attachment reaches the request with a receipt bound to
    /// that request's own thread and ID, and the receipt validates.
    func testSendingAttachesThePayloadWithAReceiptBoundToThatRequest() async throws {
        let gateway = RecordingChatGateway()
        let model = AppModel(chatGateway: gateway)
        try await model.offerWalkAttachment()

        model.chatDraft = "这附近有什么可看的？"
        model.sendChatMessage()
        let request = try await recordedRequest(from: gateway)

        let payload = try XCTUnwrap(request.journeyAttachment)
        let receipt = try XCTUnwrap(request.journeyReceipt)
        XCTAssertEqual(receipt.purpose, .chatOneTurn)
        XCTAssertEqual(receipt.threadID, request.threadID)
        XCTAssertEqual(receipt.requestID, request.requestID)
        XCTAssertEqual(receipt.payloadDigest, payload.payloadDigest())
        XCTAssertEqual(receipt.precision, JourneyAttachment.precision)
        XCTAssertFalse(receipt.userAction.isEmpty)
        // Built by the same rules the contract validates against, so this must
        // hold rather than merely look right.
        XCTAssertNoThrow(try request.validate())
    }

    /// `J3B-05` — one approval authorises one turn. The offer is gone after the
    /// send, and the receipt behind it is spent.
    func testOneApprovalAuthorisesExactlyOneTurn() async throws {
        let gateway = RecordingChatGateway()
        let model = AppModel(chatGateway: gateway)
        try await model.offerWalkAttachment()
        let approved = try XCTUnwrap(model.pendingJourneyAttachment)

        model.chatDraft = "第一句"
        model.sendChatMessage()
        _ = try await recordedRequest(from: gateway)
        XCTAssertNil(model.pendingJourneyAttachment, "the offer ends with the send")

        // The second turn carries no location at all. It has to wait for the
        // first to settle: one turn at a time is an existing rule, and sending
        // into a pending turn is refused rather than queued.
        try await waitUntilTurnSettles(model)
        await gateway.reset()
        model.chatDraft = "第二句"
        model.sendChatMessage()
        let second = try await recordedRequest(from: gateway)
        XCTAssertNil(second.journeyAttachment)
        XCTAssertNil(second.journeyReceipt)

        // And the approval itself cannot be replayed: presenting the same
        // receipt again is refused by the store, not by App bookkeeping.
        let store = JourneyUseReceiptStore()
        let replay = try ChatRequest(
            requestID: "request-replay",
            threadID: "thread.local",
            sessionID: "session.local",
            characterID: "joi.starter",
            text: "重放",
            displayLocale: "zh-Hans",
            voiceLocale: "zh-CN",
            journeyAttachment: approved.payload,
            journeyReceipt: approved.receipt(threadID: "thread.local", requestID: "request-replay")
        )
        try await store.consume(for: replay)
        do {
            try await store.consume(for: replay)
            XCTFail("a spent receipt must not be accepted twice")
        } catch let error as ChatRequestValidationError {
            XCTAssertEqual(error, .receiptAlreadyUsed)
        }
    }

    /// `J3B-06` — revoking withdraws the location and leaves the question alone.
    func testRevokingRemovesTheLocationAndKeepsTheDraft() async throws {
        let model = AppModel(chatGateway: RecordingChatGateway())
        try await model.offerWalkAttachment()
        model.chatDraft = "这是什么建筑？"

        model.revokeJourneyAttachment()
        XCTAssertNil(model.pendingJourneyAttachment)
        XCTAssertEqual(model.chatDraft, "这是什么建筑？", "revoking a location is not abandoning the question")
    }

    /// `J3B-07` — an expired attachment refuses the send with a named state and
    /// keeps the draft, rather than sending the message with the location
    /// silently dropped.
    func testAnExpiredAttachmentRefusesTheSendInsteadOfSendingWithoutIt() async throws {
        let gateway = RecordingChatGateway()
        let model = AppModel(chatGateway: gateway)
        let issued = Date()
        try await model.offerWalkAttachment(now: issued)
        model.chatDraft = "这附近有什么？"

        let afterExpiry = issued.addingTimeInterval(JourneyAttachment.lifetime + 1)
        model.sendChatMessage(now: afterExpiry)

        guard case let .failed(message, retryable) = model.chatTurnState else {
            return XCTFail("expected a named failure, got \(model.chatTurnState)")
        }
        XCTAssertFalse(retryable, "resending unchanged cannot work; the fact has to be re-taken")
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(model.chatDraft, "这附近有什么？", "the sentence survives the refusal")
        XCTAssertNil(model.pendingJourneyAttachment, "expiry ends the offer")
        let sent = await gateway.lastRequest
        XCTAssertNil(sent, "nothing may be sent for a refused turn")
    }

    /// `J3B-08` — PRD §6.5: switching surfaces is a presentation action. A
    /// pending attachment is not a casualty of looking at the map again.
    func testSwitchingSurfacesPreservesThePendingAttachment() async throws {
        let model = AppModel(chatGateway: RecordingChatGateway())
        try await model.offerWalkAttachment()
        let before = try XCTUnwrap(model.pendingJourneyAttachment)

        model.select(.map)
        model.select(.chat)

        XCTAssertEqual(model.pendingJourneyAttachment, before)
    }

    /// Ending the walk withdraws an un-sent offer. PRD §6.5 does not list this
    /// among the endings, but leaving a staged position behind after the user
    /// has visibly stopped sharing is the surprise this product refuses.
    func testStoppingTheWalkWithdrawsAnUnsentOffer() async throws {
        let model = AppModel(chatGateway: RecordingChatGateway())
        // This one needs the real walk flag, so it goes through `startWalk`, whose
        // journey begins on a detached task. Wait for the owner to hold a route
        // before offering: an attachment needs a journey, not a reading.
        model.startWalk()
        var began = false
        for _ in 0..<300 {
            if await model.journeyContext.current().routeID != nil {
                began = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(began, "starting a walk must begin a journey")

        await model.offerJourneyAttachment()
        XCTAssertNotNil(model.pendingJourneyAttachment)

        model.stopWalk()
        XCTAssertNil(model.pendingJourneyAttachment)
    }

    /// `J3B-09` — the transcript is text. A sent attachment is metadata on the
    /// request, and no coordinate becomes a line the user reads back later or
    /// that any later memory proposal could scrape.
    func testTheSentCoordinateNeverBecomesATranscriptLine() async throws {
        let gateway = RecordingChatGateway()
        let model = AppModel(chatGateway: gateway)
        try await model.offerWalkAttachment()
        model.chatDraft = "这附近有什么可看的？"
        model.sendChatMessage()
        _ = try await recordedRequest(from: gateway)

        var settled = false
        for _ in 0..<300 {
            if !model.chatTranscript.isEmpty, !model.chatTurnState.isPending {
                settled = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(settled, "the turn should reach a settled transcript")

        let transcript = model.chatTranscript.map(\.text).joined(separator: "\n")
        for fragment in ["31.2", "121.4", "chat-one-turn", "coarse-"] {
            XCTAssertFalse(
                transcript.contains(fragment),
                "\(fragment) must not appear in the transcript: \(transcript)"
            )
        }
    }

    /// `J3B-10` — a journey attachment authorises a chat turn and nothing else.
    /// The contract offers exactly one purpose, and the walk's own record is
    /// untouched by having been asked about.
    func testAnAttachmentCannotAuthoriseAnythingButOneChatTurn() async throws {
        let gateway = RecordingChatGateway()
        let model = AppModel(chatGateway: gateway)
        try await model.offerWalkAttachment()
        let journeyBefore = await model.journeyContext.current()

        model.chatDraft = "这附近有什么？"
        model.sendChatMessage()
        let request = try await recordedRequest(from: gateway)

        XCTAssertEqual(request.journeyReceipt?.purpose, .chatOneTurn)
        let journeyAfter = await model.journeyContext.current()
        XCTAssertEqual(journeyBefore, journeyAfter, "asking about a walk does not change the walk's record")
        XCTAssertEqual(
            journeyAfter.consentScope,
            "ephemeral",
            "the journey owner's own scope is unaffected by a one-turn chat approval"
        )
    }
}

// MARK: - Helpers

private extension AppModel {
    /// Records one reading through the journey owner and offers the result.
    ///
    /// `startWalk()` is deliberately not used: it begins its own journey on a
    /// detached task, under a session this test cannot name, which would race
    /// with — and overwrite — the reading being seeded here. What the Map does is
    /// begin a journey and reduce observations into it, and that is what this
    /// does, through the same owner.
    func offerWalkAttachment(now: Date = Date()) async throws {
        let session = NavigationSessionID()
        await journeyContext.begin(route: walk.route, session: session)
        let observation = try walk.engine.observe(
            LocationObservation(
                coordinate: GeoCoordinate(latitude: 31.230417, longitude: 121.473695),
                horizontalAccuracyMeters: 5,
                observedAt: now
            ),
            session: session
        )
        let recorded = await journeyContext.reduce(observation.navigationObservation)
        XCTAssertTrue(recorded, "the journey owner must accept a reading for its own session")
        await offerJourneyAttachment(now: now)
    }
}

/// Records the request the app actually built. `MockChatGateway` answers a turn
/// but discards its input, and the input is the whole subject here.
private actor RecordingChatGateway: ChatGateway {
    private(set) var lastRequest: ChatRequest?

    func reset() { lastRequest = nil }

    private func record(_ request: ChatRequest) { lastRequest = request }

    nonisolated func stream(_ request: ChatRequest) -> AsyncThrowingStream<CompanionEventV1, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await record(request)
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
                continuation.yield(
                    CompanionEventV1(
                        eventID: "\(request.requestID)-done",
                        requestID: request.requestID,
                        threadID: request.threadID,
                        sessionID: request.sessionID,
                        characterID: request.characterID,
                        phase: .done,
                        contentState: .acceptedFinal,
                        displayText: "这附近有一段旧码头。",
                        memoryEligibility: .proposalAllowed
                    )
                )
                continuation.finish()
            }
        }
    }
}

private enum TestTimeout: Error {
    case noRequestRecorded
    case turnDidNotSettle
}

/// Waits for the gateway to see a request and returns it.
///
/// Bounded rather than a continuation: a send the app declines — because a turn
/// is still in flight, say — must fail this suite in five seconds instead of
/// hanging the whole test run, which is exactly what an unbounded wait did here.
private func recordedRequest(from gateway: RecordingChatGateway) async throws -> ChatRequest {
    for _ in 0..<500 {
        if let request = await gateway.lastRequest { return request }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw TestTimeout.noRequestRecorded
}

/// Waits until the turn is no longer in flight, so a following send is not
/// silently refused by the one-turn-at-a-time guard.
@MainActor
private func waitUntilTurnSettles(_ model: AppModel) async throws {
    for _ in 0..<500 {
        if !model.chatTurnState.isPending { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw TestTimeout.turnDidNotSettle
}
