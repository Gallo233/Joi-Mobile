import CompanionCore
import XCTest
@testable import ChatFeature

/// Opt-in lane against a locally running `Backend/mock_server.py`. It is skipped
/// unless `JOI_MOBILE_MOCK_BACKEND_URL` is set, so the public suite stays
/// hermetic while the wire format can still be proven end to end.
///
///     Backend/.venv/bin/python Backend/mock_server.py &
///     JOI_MOBILE_MOCK_BACKEND_URL=http://127.0.0.1:8787 \
///       swift test --package-path Packages/ChatFeature
final class MockBackendIntegrationTests: XCTestCase {
    private func endpoint() throws -> ChatBackendEndpoint {
        guard let raw = ProcessInfo.processInfo.environment["JOI_MOBILE_MOCK_BACKEND_URL"],
              let url = URL(string: raw) else {
            throw XCTSkip("Set JOI_MOBILE_MOCK_BACKEND_URL to run the local mock backend lane")
        }
        return try ChatBackendEndpoint(baseURL: url)
    }

    func testOneTurnYieldsAcceptedInputThenAcceptedFinal() async throws {
        let gateway = SSEChatGateway(endpoint: try endpoint())
        let request = try ChatRequest(
            requestID: "itest-\(UUID().uuidString.lowercased())",
            threadID: "t1",
            sessionID: "s1",
            characterID: "c1",
            text: "你好",
            displayLocale: "zh-Hans",
            voiceLocale: "zh-CN"
        )

        var events: [CompanionEventV1] = []
        for try await event in gateway.stream(request) {
            events.append(event)
        }

        XCTAssertEqual(events.count, 2, "the mock contract returns one received and one done event")
        XCTAssertEqual(events.first?.contentState, .acceptedInput)
        XCTAssertEqual(events.first?.displayText, "你好")
        XCTAssertEqual(events.last?.contentState, .acceptedFinal)
        XCTAssertEqual(events.last?.phase, .done)
        for event in events {
            XCTAssertEqual(event.requestID, request.requestID)
            XCTAssertEqual(event.threadID, request.threadID)
        }
    }

    func testControllerAcceptsTheTurnAndProjectionAppendsBothLines() async throws {
        let gateway = SSEChatGateway(endpoint: try endpoint())
        let controller = ChatSessionController(gateway: gateway)
        let request = try ChatRequest(
            requestID: "itest-\(UUID().uuidString.lowercased())",
            threadID: "t1",
            sessionID: "s1",
            characterID: "c1",
            text: "在吗",
            displayLocale: "zh-Hans",
            voiceLocale: "zh-CN"
        )

        let events = try await controller.send(request)
        let projection = ChatTurnProjection()
        let store = CompanionSessionStore(characterID: "c1", threadID: "t1", sessionID: "s1")
        for event in events {
            if case let .append(entry) = projection.effect(of: event) {
                await store.appendAccepted(entry, threadID: "t1")
            }
        }
        let snapshot = await store.current()
        XCTAssertEqual(snapshot.transcript.map(\.author), [.user, .companion])
        XCTAssertEqual(snapshot.transcript.first?.text, "在吗")
    }
}
