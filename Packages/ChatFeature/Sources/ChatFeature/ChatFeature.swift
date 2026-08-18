import CompanionCore
import Foundation

public actor ChatSessionController {
    private let gateway: any ChatGateway
    private let receiptStore: JourneyUseReceiptStore
    private let stallTimeout: Duration
    private var currentRequestID: String?
    private var currentTask: Task<[CompanionEventV1], Error>?

    /// How long a turn may produce nothing before it is treated as stalled.
    ///
    /// `FAIL-024` calls for a timed-out operation to be cancelled rather than
    /// left open. Twenty seconds is long enough for a slow first token on a poor
    /// connection and short enough that a dead stream does not hold the composer
    /// indefinitely — a turn that is still alive resets it with every event, so
    /// this bounds silence, not total duration.
    public static let defaultStallTimeout = Duration.seconds(20)

    public init(
        gateway: any ChatGateway,
        receiptStore: JourneyUseReceiptStore = JourneyUseReceiptStore(),
        stallTimeout: Duration = ChatSessionController.defaultStallTimeout
    ) {
        self.gateway = gateway
        self.receiptStore = receiptStore
        self.stallTimeout = stallTimeout
    }

    public func send(_ request: ChatRequest) async throws -> [CompanionEventV1] {
        try await send(request) { _ in }
    }

    /// Streaming variant: `onEvent` runs for each event that passes identity
    /// filtering, as it arrives, so a caller can show progress instead of
    /// waiting for the terminal event. The returned array is unchanged, so the
    /// non-streaming `send(_:)` above stays behaviourally identical.
    public func send(
        _ request: ChatRequest,
        onEvent: @escaping @Sendable (CompanionEventV1) async -> Void
    ) async throws -> [CompanionEventV1] {
        try await receiptStore.consume(for: request)
        currentTask?.cancel()
        currentRequestID = request.requestID
        let watch = StallWatch()
        let task = Task { [gateway] in
            defer { Task { await watch.finish() } }
            var events: [CompanionEventV1] = []
            for try await event in gateway.stream(request) {
                try Task.checkCancellation()
                // Progress, of any kind, resets the silence this bounds.
                await watch.tick()
                guard event.requestID == request.requestID,
                      event.threadID == request.threadID,
                      event.sessionID == request.sessionID,
                      event.characterID == request.characterID else {
                    throw ChatSessionError.foreignEvent
                }
                events.append(event)
                await onEvent(event)
            }
            try Task.checkCancellation()
            return events
        }
        currentTask = task
        let watchdog = Task { [stallTimeout] in
            if await watch.waitForStall(timeout: stallTimeout) { task.cancel() }
        }
        defer { watchdog.cancel() }
        do {
            let events = try await task.value
            if currentRequestID == request.requestID {
                currentTask = nil
                currentRequestID = nil
            }
            return events
        } catch {
            if currentRequestID == request.requestID {
                currentTask = nil
                currentRequestID = nil
            }
            // A user stop and a stall both surface as cancellation. Only the
            // watchdog knows which, and only it can say so: reporting a stop as
            // a timeout would tell the user the network failed when they were
            // the one who stopped it.
            if error is CancellationError, await watch.didStall() {
                throw ChatSessionError.timedOut
            }
            throw error
        }
    }

    public func cancel(requestID: String) {
        guard currentRequestID == requestID else { return }
        currentTask?.cancel()
        currentTask = nil
        currentRequestID = nil
    }
}

public enum ChatSessionError: Error, Equatable, Sendable {
    case foreignEvent
    /// The turn produced nothing for longer than the stall timeout and was
    /// cancelled (`FAIL-024`). Retryable: the request never completed, so
    /// nothing was accepted and resending is safe.
    case timedOut
}

/// Watches a turn for silence.
///
/// Counts progress rather than timestamps it, so the check is "did anything
/// happen while I slept" — which needs no clock and cannot drift.
private actor StallWatch {
    private var ticks = 0
    private var isFinished = false
    private var stalled = false

    func tick() { ticks += 1 }
    func finish() { isFinished = true }
    func didStall() -> Bool { stalled }

    func waitForStall(timeout: Duration) async -> Bool {
        while !isFinished {
            let before = ticks
            do { try await Task.sleep(for: timeout) } catch { return false }
            if isFinished { return false }
            if ticks == before {
                stalled = true
                return true
            }
        }
        return false
    }
}
