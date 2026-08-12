import CompanionCore
import Foundation

/// Stable, provider-independent transport codes. No provider name, model name,
/// prompt, response body or tool trace may be surfaced through this type.
public enum ChatTransportError: Error, Equatable, Sendable {
    case insecureEndpoint
    case invalidRequest
    case unauthorized
    case rateLimited
    case serverUnavailable
    case malformedStream
    case notStreaming
    case backend(code: String)

    /// Whether a caller may retry the same turn unchanged.
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .serverUnavailable:
            return true
        case .insecureEndpoint, .invalidRequest, .unauthorized, .malformedStream, .notStreaming, .backend:
            return false
        }
    }
}

/// The official proxy boundary. Only loopback may use plain HTTP, and only so a
/// developer can run `Backend/mock_server.py`; every other host must be HTTPS.
public struct ChatBackendEndpoint: Equatable, Sendable {
    public let baseURL: URL

    public init(baseURL: URL) throws {
        let scheme = baseURL.scheme?.lowercased()
        let host = baseURL.host?.lowercased()
        let isLoopback = host == "127.0.0.1" || host == "localhost" || host == "::1"
        guard scheme == "https" || (scheme == "http" && isLoopback) else {
            throw ChatTransportError.insecureEndpoint
        }
        self.baseURL = baseURL
    }

    /// The local contract mock in `Backend/mock_server.py`.
    public static func localMock(port: Int = 8787) -> ChatBackendEndpoint {
        // Safe to force: this literal always satisfies the loopback rule above.
        try! ChatBackendEndpoint(baseURL: URL(string: "http://127.0.0.1:\(port)")!)
    }

    var chatStreamURL: URL {
        baseURL.appendingPathComponent("v1/chat/streams")
    }
}

/// `ChatGateway` over server-sent events. It owns no transcript and no session
/// identity: it emits decoded events and lets `ChatSessionController` filter
/// them against the current request.
public struct SSEChatGateway: ChatGateway {
    private let endpoint: ChatBackendEndpoint
    private let session: URLSession

    public init(endpoint: ChatBackendEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<CompanionEventV1, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ request: ChatRequest,
        into continuation: AsyncThrowingStream<CompanionEventV1, Error>.Continuation
    ) async throws {
        var urlRequest = URLRequest(url: endpoint.chatStreamURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try Self.encoder.encode(request)

        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ChatTransportError.malformedStream
        }
        guard http.statusCode == 200 else {
            throw Self.error(for: http.statusCode)
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard contentType.contains("text/event-stream") else {
            throw ChatTransportError.notStreaming
        }

        var parser = SSEFrameParser()
        for try await byte in bytes {
            try Task.checkCancellation()
            if let payload = try parser.consume(byte) {
                continuation.yield(try Self.decodeFrame(payload))
            }
        }
        // A stream that ends without its blank-line terminator still delivers a
        // complete final frame; anything malformed throws from decodeFrame.
        if let payload = parser.finish() {
            continuation.yield(try Self.decodeFrame(payload))
        }
    }

    static func decodeFrame(_ payload: String) throws -> CompanionEventV1 {
        do {
            return try decoder.decode(CompanionEventV1.self, from: Data(payload.utf8))
        } catch {
            throw ChatTransportError.malformedStream
        }
    }

    private static func error(for statusCode: Int) -> ChatTransportError {
        switch statusCode {
        case 400, 422: return .invalidRequest
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        case 500...599: return .serverUnavailable
        default: return .malformedStream
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
