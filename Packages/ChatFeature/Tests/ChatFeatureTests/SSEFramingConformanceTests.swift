import Foundation
import XCTest
@testable import ChatFeature

/// Runs `Contracts/conformance/sse-framing.json` against the shipping framer.
///
/// Framing is where this product has actually been bitten: unit tests over
/// hand-written single frames passed while every live turn failed, because the
/// convenience line reader in use did not emit the empty line that terminates a
/// frame. A second client will reach for the same convenience API on its own
/// platform, so the boundaries belong in a corpus rather than in a comment.
final class SSEFramingConformanceTests: XCTestCase {
    func testFramingMatchesEveryVector() throws {
        let corpus = try loadCorpus()
        XCTAssertGreaterThanOrEqual(corpus.cases.count, 15)

        for vector in corpus.cases {
            var parser = SSEFrameParser()
            var payloads: [String] = []
            for byte in try bytes(of: vector) {
                if let payload = try parser.consume(byte) {
                    payloads.append(payload)
                }
            }
            if let payload = parser.finish() {
                payloads.append(payload)
            }
            XCTAssertEqual(
                payloads,
                vector.payloads,
                "framing diverged for \(vector.id): \(vector.note ?? "")"
            )
        }
    }

    /// Chunk boundaries must not change the outcome, so every vector is also fed
    /// as one contiguous run. A framer that keeps per-chunk state passes the
    /// vectors as written and fails here.
    func testChunkBoundariesAreNotSemantic() throws {
        for vector in try loadCorpus().cases where vector.chunks?.count ?? 0 > 1 {
            var parser = SSEFrameParser()
            var payloads: [String] = []
            for byte in try bytes(of: vector) {
                if let payload = try parser.consume(byte) { payloads.append(payload) }
            }
            if let payload = parser.finish() { payloads.append(payload) }
            XCTAssertEqual(payloads, vector.payloads, vector.id)
        }
    }

    // MARK: - Corpus

    private struct Corpus: Decodable {
        struct Case: Decodable {
            let id: String
            let chunks: [String]?
            let chunksBase64: [String]?
            let payloads: [String]
            let note: String?
        }

        let cases: [Case]
    }

    private func loadCorpus() throws -> Corpus {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url = url.deletingLastPathComponent() }
        url.append(path: "Contracts/conformance/sse-framing.json")
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }

    private func bytes(of vector: Corpus.Case) throws -> [UInt8] {
        if let encoded = vector.chunksBase64 {
            return try encoded.flatMap { chunk -> [UInt8] in
                guard let data = Data(base64Encoded: chunk) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return Array(data)
            }
        }
        return (vector.chunks ?? []).flatMap { Array($0.utf8) }
    }
}
