import CompanionCore
import XCTest
@testable import ChatFeature

final class SSEChatGatewayTests: XCTestCase {
    func testOnlyLoopbackMayUsePlainHTTP() throws {
        XCTAssertNoThrow(try ChatBackendEndpoint(baseURL: URL(string: "http://127.0.0.1:8787")!))
        XCTAssertNoThrow(try ChatBackendEndpoint(baseURL: URL(string: "http://localhost:8787")!))
        XCTAssertNoThrow(try ChatBackendEndpoint(baseURL: URL(string: "https://api.example.com")!))

        for insecure in ["http://api.example.com", "http://192.168.1.10:8787", "ws://127.0.0.1"] {
            XCTAssertThrowsError(try ChatBackendEndpoint(baseURL: URL(string: insecure)!)) { error in
                XCTAssertEqual(error as? ChatTransportError, .insecureEndpoint)
            }
        }
    }

    func testChatStreamPathMatchesTheVersionedContract() {
        XCTAssertEqual(
            ChatBackendEndpoint.localMock(port: 9000).chatStreamURL.absoluteString,
            "http://127.0.0.1:9000/v1/chat/streams"
        )
    }

    func testRetryabilityIsExplicitPerTransportCode() {
        XCTAssertTrue(ChatTransportError.rateLimited.isRetryable)
        XCTAssertTrue(ChatTransportError.serverUnavailable.isRetryable)
        XCTAssertFalse(ChatTransportError.unauthorized.isRetryable)
        XCTAssertFalse(ChatTransportError.invalidRequest.isRetryable)
        XCTAssertFalse(ChatTransportError.malformedStream.isRetryable)
        XCTAssertFalse(ChatTransportError.insecureEndpoint.isRetryable)
    }

    func testDecodesTheMockBackendFrameShape() throws {
        let frame = """
        {"schema":"joi.companion-event.v1","eventID":"r1-done","requestID":"r1","threadID":"t1",
        "sessionID":"s1","characterID":"c1","timestamp":"2026-08-11T00:00:00Z","phase":"done",
        "contentState":"acceptedFinal","displayText":"这是来自官方代理边界的本地模拟回复。",
        "voiceLine":"这是本地模拟回复。","memoryEligibility":"proposalAllowed","sources":[],"errorCode":null}
        """
        let event = try SSEChatGateway.decodeFrame(frame)
        XCTAssertEqual(event.eventID, "r1-done")
        XCTAssertEqual(event.contentState, .acceptedFinal)
        XCTAssertEqual(event.memoryEligibility, .proposalAllowed)
    }

    func testMalformedFrameThrowsAStableTransportCode() {
        XCTAssertThrowsError(try SSEChatGateway.decodeFrame("{ not json")) { error in
            XCTAssertEqual(error as? ChatTransportError, .malformedStream)
        }
    }

    /// Regression: `AsyncSequence.lines` drops empty lines, so using it merged
    /// consecutive events into one invalid payload. Blank lines are the frame
    /// delimiter and must survive parsing.
    func testBlankLineDelimitsFramesSoConsecutiveEventsStaySeparate() throws {
        let stream = """
        id: r1-received
        event: companion
        data: {"a":1}

        id: r1-done
        event: companion
        data: {"a":2}

        """
        XCTAssertEqual(try Self.frames(of: stream), ["{\"a\":1}", "{\"a\":2}"])
    }

    func testCRLFDelimitersAndMultiLineDataAreHandled() throws {
        let crlf = "event: companion\r\ndata: {\"a\":1}\r\n\r\n"
        XCTAssertEqual(try Self.frames(of: crlf), ["{\"a\":1}"])

        let multiline = "data: {\"a\":\ndata: 1}\n\n"
        XCTAssertEqual(try Self.frames(of: multiline), ["{\"a\":\n1}"])
    }

    func testStreamEndingWithoutBlankLineStillDeliversItsFinalFrame() throws {
        XCTAssertEqual(try Self.frames(of: "data: {\"a\":1}\n"), ["{\"a\":1}"])
        XCTAssertEqual(try Self.frames(of: "data: {\"a\":1}"), ["{\"a\":1}"])
    }

    func testCommentAndUnknownFieldsProduceNoFrame() throws {
        XCTAssertEqual(try Self.frames(of: ": keep-alive\n\nretry: 100\n\n"), [])
    }

    func testOverlongLineFailsClosedInsteadOfBufferingWithoutBound() {
        var parser = SSEFrameParser()
        XCTAssertThrowsError(
            try (0...SSEFrameParser.maximumLineBytes).forEach { _ in
                _ = try parser.consume(UInt8(ascii: "x"))
            }
        ) { error in
            XCTAssertEqual(error as? ChatTransportError, .malformedStream)
        }
    }

    func testSSEFieldPrefixDroppingKeepsPayloadExactly() {
        XCTAssertEqual(SSEFrameParser.fieldValue("data: {\"a\":1}", prefix: "data:"), "{\"a\":1}")
        XCTAssertEqual(SSEFrameParser.fieldValue("data:{\"a\":1}", prefix: "data:"), "{\"a\":1}")
        XCTAssertNil(SSEFrameParser.fieldValue("event: companion", prefix: "data:"))
        // Only one leading space is structural; further spaces belong to the payload.
        XCTAssertEqual(SSEFrameParser.fieldValue("data:  x", prefix: "data:"), " x")
    }

    /// Drives the parser exactly as the gateway does: one byte at a time.
    private static func frames(of stream: String) throws -> [String] {
        var parser = SSEFrameParser()
        var payloads: [String] = []
        for byte in Array(stream.utf8) {
            if let payload = try parser.consume(byte) { payloads.append(payload) }
        }
        if let payload = parser.finish() { payloads.append(payload) }
        return payloads
    }
}
