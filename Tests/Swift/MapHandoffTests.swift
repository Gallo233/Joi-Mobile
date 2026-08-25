import CompanionCore
import XCTest
@testable import JoiMobile

/// `G2-J5M` — an inspected, transient Chat → Map place-intent handoff.
@MainActor
final class MapHandoffTests: XCTestCase {
    func testOnlyAcceptedUserLinesInTheActiveTranscriptCanBeOffered() async throws {
        let model = try await modelWithTurn("我想去上海博物馆看看")
        let user = try XCTUnwrap(model.chatTranscript.first { $0.author == .user })
        let companion = try XCTUnwrap(model.chatTranscript.first { $0.author == .companion })
        let invented = TranscriptEntry(
            eventID: "not-in-this-transcript",
            requestID: user.requestID,
            author: .user,
            text: user.text,
            timestamp: user.timestamp
        )

        XCTAssertTrue(model.canOpenInMap(user))
        XCTAssertFalse(model.canOpenInMap(companion), "companion prose is not promoted to user intent")
        XCTAssertFalse(model.canOpenInMap(invented), "a caller cannot fabricate an active-conversation line")
    }

    func testProposingAndCancellingLeaveChatAndItsOwnersUnchanged() async throws {
        let model = try await modelWithTurn("帮我找人民广场附近的博物馆")
        let user = try XCTUnwrap(model.chatTranscript.first { $0.author == .user })
        let transcriptBefore = model.chatTranscript
        let sessionBefore = await model.companionSession.current()
        let journeyBefore = await model.journeyContext.current()
        model.presentTranscript()

        model.proposeMapHandoff(from: user)

        XCTAssertEqual(model.mapHandoffDraft?.id, user.eventID)
        XCTAssertEqual(model.mapHandoffQuery, user.text)
        XCTAssertEqual(model.selectedSurface, .chat)
        XCTAssertTrue(model.isTranscriptPresented)
        XCTAssertNil(model.pendingMapSearchQuery)

        model.rejectMapHandoff()

        XCTAssertNil(model.mapHandoffDraft)
        XCTAssertEqual(model.mapHandoffQuery, "")
        XCTAssertEqual(model.selectedSurface, .chat)
        XCTAssertTrue(model.isTranscriptPresented, "cancel returns to the same open transcript")
        XCTAssertEqual(model.chatTranscript, transcriptBefore)
        let sessionAfter = await model.companionSession.current()
        let journeyAfter = await model.journeyContext.current()
        XCTAssertEqual(sessionAfter, sessionBefore)
        XCTAssertEqual(journeyAfter, journeyBefore)
    }

    func testAnEmptyEditedQueryCannotCrossTheSurfaceBoundary() async throws {
        let model = try await modelWithTurn("去外滩")
        let user = try XCTUnwrap(model.chatTranscript.first { $0.author == .user })
        model.proposeMapHandoff(from: user)
        model.mapHandoffQuery = "  \n "

        XCTAssertFalse(model.acceptMapHandoff())
        XCTAssertNotNil(model.mapHandoffDraft)
        XCTAssertEqual(model.selectedSurface, .chat)
        XCTAssertNil(model.pendingMapSearchQuery)
    }

    func testAcceptanceKeepsTheSameConversationAndIssuesOneEditedMapQuery() async throws {
        let selection = CharacterSelection(characterID: "joi.test", displayName: "桃濑日和")
        let model = try await modelWithTurn(
            "我想去上海博物馆看看",
            initialSelection: selection,
            threadID: "thread-map-handoff",
            sessionID: "session-map-handoff"
        )
        let user = try XCTUnwrap(model.chatTranscript.first { $0.author == .user })
        let transcriptBefore = model.chatTranscript
        let sessionBefore = await model.companionSession.current()
        model.presentTranscript()
        model.proposeMapHandoff(from: user)
        model.mapHandoffQuery = "  上海博物馆 人民广场馆  "

        XCTAssertTrue(model.acceptMapHandoff())

        XCTAssertEqual(model.selectedSurface, .map)
        XCTAssertFalse(model.isTranscriptPresented)
        XCTAssertNil(model.mapHandoffDraft)
        XCTAssertEqual(model.mapHandoffQuery, "")
        XCTAssertEqual(model.pendingMapSearchQuery, "上海博物馆 人民广场馆")
        XCTAssertEqual(model.currentCharacterName, selection.displayName)
        XCTAssertEqual(model.chatTranscript, transcriptBefore)
        let sessionAfter = await model.companionSession.current()
        XCTAssertEqual(sessionAfter, sessionBefore)

        XCTAssertEqual(model.consumePendingMapSearchQuery(), "上海博物馆 人民广场馆")
        XCTAssertNil(model.consumePendingMapSearchQuery(), "the inspected query is delivered exactly once")
    }

    private func modelWithTurn(
        _ text: String,
        initialSelection: CharacterSelection = CharacterSelection(characterID: "joi.starter", displayName: "Joi"),
        threadID: String = "thread.local",
        sessionID: String = "session.local"
    ) async throws -> AppModel {
        let model = AppModel(
            chatGateway: HandoffGateway(),
            initialSelection: initialSelection,
            threadID: threadID,
            sessionID: sessionID
        )
        await model.runChatTurn(text: text)
        XCTAssertEqual(model.chatTranscript.count, 2)
        return model
    }
}

private struct HandoffGateway: ChatGateway {
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<CompanionEventV1, Error> {
        AsyncThrowingStream { continuation in
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
                    displayText: "好，我们先在地图里确认具体地点。"
                )
            )
            continuation.finish()
        }
    }
}
