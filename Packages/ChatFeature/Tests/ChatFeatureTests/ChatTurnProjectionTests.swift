import CompanionCore
import XCTest
@testable import ChatFeature

final class ChatTurnProjectionTests: XCTestCase {
    private let projection = ChatTurnProjection()

    private func event(
        eventID: String = "e1",
        phase: CompanionPublicPhase,
        contentState: CompanionContentState,
        displayText: String? = "文本",
        memoryEligibility: MemoryEligibility = .none,
        errorCode: String? = nil
    ) -> CompanionEventV1 {
        CompanionEventV1(
            eventID: eventID,
            requestID: "r1",
            threadID: "t1",
            sessionID: "s1",
            characterID: "c1",
            timestamp: Date(timeIntervalSince1970: 0),
            phase: phase,
            contentState: contentState,
            displayText: displayText,
            memoryEligibility: memoryEligibility,
            errorCode: errorCode
        )
    }

    func testPartialAndStreamingDraftAreReplaceableProjectionsOnly() {
        XCTAssertEqual(
            projection.effect(of: event(phase: .understanding, contentState: .partial, displayText: "半句")),
            .draft("半句")
        )
        XCTAssertEqual(
            projection.effect(of: event(phase: .thinking, contentState: .streamingDraft, displayText: "草稿")),
            .draft("草稿")
        )
    }

    func testAcceptedInputAndFinalBecomeAuthoredTranscriptEntries() {
        guard case let .append(input) = projection.effect(
            of: event(phase: .received, contentState: .acceptedInput, displayText: "你好")
        ) else { return XCTFail("acceptedInput must append") }
        XCTAssertEqual(input.author, .user)
        XCTAssertEqual(input.text, "你好")
        XCTAssertEqual(input.memoryEligibility, .none)

        guard case let .append(final) = projection.effect(
            of: event(
                eventID: "e2",
                phase: .done,
                contentState: .acceptedFinal,
                displayText: "回复",
                memoryEligibility: .proposalAllowed
            )
        ) else { return XCTFail("acceptedFinal must append") }
        XCTAssertEqual(final.author, .companion)
        XCTAssertEqual(final.memoryEligibility, .proposalAllowed)
    }

    func testCancelledAndFailedAreDiagnosticOnly() {
        XCTAssertEqual(
            projection.effect(of: event(phase: .failed, contentState: .failed, errorCode: "upstream")),
            .diagnostic(phase: .failed, errorCode: "upstream")
        )
        XCTAssertEqual(
            projection.effect(of: event(phase: .paused, contentState: .cancelled)),
            .diagnostic(phase: .paused, errorCode: nil)
        )
    }

    func testAcceptedEventWithoutTextDoesNotAppendAnEmptyLine() {
        XCTAssertEqual(
            projection.effect(of: event(phase: .done, contentState: .acceptedFinal, displayText: nil)),
            .status(.done)
        )
        XCTAssertEqual(
            projection.effect(of: event(phase: .done, contentState: .acceptedFinal, displayText: "")),
            .status(.done)
        )
    }

    func testUnknownContentStateFailsToDecodeInsteadOfBeingAccepted() throws {
        let json = """
        {"schema":"joi.companion-event.v1","eventID":"e9","requestID":"r1","threadID":"t1",
        "sessionID":"s1","characterID":"c1","timestamp":"2026-08-11T00:00:00Z","phase":"done",
        "contentState":"someFutureState","displayText":"不应被接受","memoryEligibility":"proposalAllowed",
        "sources":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(CompanionEventV1.self, from: Data(json.utf8)))
    }

    func testStoreAppendsEachAcceptedEventOnceAndRejectsForeignThread() async {
        let store = CompanionSessionStore(characterID: "c1", threadID: "t1", sessionID: "s1")
        guard case let .append(entry) = projection.effect(
            of: event(phase: .received, contentState: .acceptedInput, displayText: "你好")
        ) else { return XCTFail("expected append") }

        let first = await store.appendAccepted(entry, threadID: "t1")
        let duplicate = await store.appendAccepted(entry, threadID: "t1")
        let foreign = await store.appendAccepted(
            TranscriptEntry(
                eventID: "other",
                requestID: "r1",
                author: .companion,
                text: "别的线程",
                timestamp: Date(timeIntervalSince1970: 0)
            ),
            threadID: "t-other"
        )
        let snapshot = await store.current()

        XCTAssertTrue(first)
        XCTAssertFalse(duplicate)
        XCTAssertFalse(foreign)
        XCTAssertEqual(snapshot.transcript.map(\.text), ["你好"])
        XCTAssertEqual(snapshot.acceptedEventIDs, ["e1"])
    }
}
