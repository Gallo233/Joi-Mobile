import CompanionCore
import Foundation

public actor ChatSessionController {
    private let gateway: any ChatGateway
    private let receiptStore: JourneyUseReceiptStore
    private var currentRequestID: String?
    private var currentTask: Task<[CompanionEventV1], Error>?

    public init(
        gateway: any ChatGateway,
        receiptStore: JourneyUseReceiptStore = JourneyUseReceiptStore()
    ) {
        self.gateway = gateway
        self.receiptStore = receiptStore
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
        let task = Task { [gateway] in
            var events: [CompanionEventV1] = []
            for try await event in gateway.stream(request) {
                try Task.checkCancellation()
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
}
