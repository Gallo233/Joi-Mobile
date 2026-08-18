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

/// `G2-J5C` — `FAIL-024 networkDegraded`.
///
/// "Cancel/supersede timed-out operation; keep cached/accepted state." A stream
/// that stops producing used to hold the turn open forever: `send` awaited the
/// gateway with no bound on silence, so a connection that died mid-stream left
/// the composer pending until the user noticed.
final class ChatStallTimeoutTests: XCTestCase {
    /// A turn that goes silent is cancelled and reported as a timeout, rather
    /// than waiting indefinitely.
    ///
    /// Run under an outer deadline on purpose. The behaviour under test is
    /// "this ends"; without the watchdog it does not, and an unbounded test
    /// would hang the whole run instead of failing it — which is exactly what
    /// the first version of this test did when the watchdog was mutated away.
    func testASilentStreamTimesOutInsteadOfHangingForever() async throws {
        let controller = ChatSessionController(
            gateway: StallingGateway(eventsBeforeStalling: 1),
            stallTimeout: .milliseconds(80)
        )
        let request = try Self.request()

        // Polled rather than raced in a task group. A stalled turn is stuck
        // inside an *unstructured* task, so cancelling the caller cannot reach
        // it and `withTaskGroup` — which always awaits its children — would hang
        // on the very failure this test exists to report. Watching a box the
        // turn writes into never awaits the stuck task at all.
        let box = OutcomeBox()
        let turn = Task {
            do {
                _ = try await controller.send(request)
                await box.set(.completed)
            } catch {
                await box.set(.threw(error))
            }
        }
        defer { turn.cancel() }

        var outcome: TurnOutcome = .neverEnded
        for _ in 0..<500 {
            if let settled = await box.value() {
                outcome = settled
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        switch outcome {
        case .neverEnded:
            XCTFail("a stalled turn never ended; the stall watchdog is not running")
        case .completed:
            XCTFail("a stalled stream must not complete")
        case let .threw(error):
            XCTAssertEqual(error as? ChatSessionError, .timedOut)
        }
    }

    /// What became of a turn run under an outer deadline.
    private enum TurnOutcome: Sendable {
        case completed
        case threw(Error)
        case neverEnded
    }

    /// Where a turn reports what became of it, without anyone awaiting it.
    private actor OutcomeBox {
        private var outcome: TurnOutcome?
        func set(_ value: TurnOutcome) { outcome = value }
        func value() -> TurnOutcome? { outcome }
    }


    /// A stream that keeps producing is not timed out, so the bound is on
    /// silence rather than on how long a turn may take. Six events at half the
    /// timeout each run well past it in total.
    func testASlowButLiveStreamIsNotTimedOut() async throws {
        let controller = ChatSessionController(
            gateway: SlowGateway(events: 6, gap: .milliseconds(40)),
            stallTimeout: .milliseconds(80)
        )
        let events = try await controller.send(try Self.request())
        XCTAssertEqual(events.count, 6, "a live stream completes however long it takes")
    }

    /// A user stop is not a timeout. Both arrive as cancellation, and telling
    /// the user the network failed when they pressed stop would be a lie.
    func testAUserStopIsNotReportedAsATimeout() async throws {
        let controller = ChatSessionController(
            gateway: StallingGateway(eventsBeforeStalling: 1),
            stallTimeout: .seconds(30)
        )
        let request = try Self.request()

        let turn = Task { try await controller.send(request) }
        try await Task.sleep(for: .milliseconds(120))
        await controller.cancel(requestID: request.requestID)

        do {
            _ = try await turn.value
            XCTFail("a stopped turn must not complete")
        } catch let error as ChatSessionError {
            XCTFail("a user stop reported as \(error)")
        } catch {
            XCTAssertTrue(error is CancellationError, "a stop is a cancellation, got \(error)")
        }
    }

    private static func request() throws -> ChatRequest {
        try ChatRequest(
            requestID: "request-stall",
            threadID: "thread-1",
            sessionID: "session-1",
            characterID: "joi.starter",
            text: "在吗？",
            displayLocale: "zh-Hans",
            voiceLocale: "zh-CN"
        )
    }
}

/// Yields a few events and then never finishes, like a connection that dropped
/// without closing.
private struct StallingGateway: ChatGateway {
    let eventsBeforeStalling: Int

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<CompanionEventV1, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for index in 0..<eventsBeforeStalling {
                    continuation.yield(Self.event(request, index: index))
                }
                // Deliberately never finished.
            }
        }
    }

    static func event(_ request: ChatRequest, index: Int) -> CompanionEventV1 {
        CompanionEventV1(
            eventID: "\(request.requestID)-\(index)",
            requestID: request.requestID,
            threadID: request.threadID,
            sessionID: request.sessionID,
            characterID: request.characterID,
            phase: .received,
            contentState: .acceptedInput,
            displayText: request.text
        )
    }
}

/// Produces steadily, but slowly.
private struct SlowGateway: ChatGateway {
    let events: Int
    let gap: Duration

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<CompanionEventV1, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for index in 0..<events {
                    try? await Task.sleep(for: gap)
                    continuation.yield(StallingGateway.event(request, index: index))
                }
                continuation.finish()
            }
        }
    }
}
