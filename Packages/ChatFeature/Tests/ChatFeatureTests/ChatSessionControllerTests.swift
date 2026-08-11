import CompanionCore
import XCTest
@testable import ChatFeature

final class ChatSessionControllerTests: XCTestCase {
    func testMockRequestUsesSameCharacterAndThread() async throws {
        let controller = ChatSessionController(gateway: MockChatGateway())
        let request = try ChatRequest(
            requestID: "request",
            threadID: "thread",
            sessionID: "session",
            characterID: "joi",
            text: "Hello",
            displayLocale: "en",
            voiceLocale: "en"
        )
        let events = try await controller.send(request)
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { $0.threadID == "thread" && $0.characterID == "joi" })
    }

    func testRejectsForeignEventIdentity() async throws {
        let controller = ChatSessionController(gateway: ForeignEventGateway())
        let request = try makeRequest()

        do {
            _ = try await controller.send(request)
            XCTFail("Expected foreign event rejection")
        } catch {
            XCTAssertEqual(error as? ChatSessionError, .foreignEvent)
        }
    }

    func testCancelOwnsAndClosesStreamingTask() async throws {
        let probe = StreamProbe()
        let controller = ChatSessionController(gateway: NeverFinishingGateway(probe: probe))
        let request = try makeRequest()
        let sendTask = Task { try await controller.send(request) }

        await probe.waitUntilStarted()
        await controller.cancel(requestID: request.requestID)

        do {
            _ = try await sendTask.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }

    private func makeRequest() throws -> ChatRequest {
        try ChatRequest(
            requestID: "request",
            threadID: "thread",
            sessionID: "session",
            characterID: "joi",
            text: "你好",
            displayLocale: "zh-Hans",
            voiceLocale: "zh-Hans"
        )
    }
}

private struct ForeignEventGateway: ChatGateway {
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<CompanionEventV1, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                CompanionEventV1(
                    eventID: "foreign",
                    requestID: request.requestID,
                    threadID: "another-thread",
                    sessionID: request.sessionID,
                    characterID: request.characterID,
                    phase: .done,
                    contentState: .acceptedFinal
                )
            )
            continuation.finish()
        }
    }
}

private struct NeverFinishingGateway: ChatGateway {
    let probe: StreamProbe

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<CompanionEventV1, Error> {
        AsyncThrowingStream { continuation in
            Task { await probe.markStarted() }
            continuation.yield(
                CompanionEventV1(
                    eventID: "received",
                    requestID: request.requestID,
                    threadID: request.threadID,
                    sessionID: request.sessionID,
                    characterID: request.characterID,
                    phase: .received,
                    contentState: .acceptedInput
                )
            )
        }
    }
}

private actor StreamProbe {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        started = true
        let current = waiters
        waiters.removeAll()
        current.forEach { $0.resume() }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
