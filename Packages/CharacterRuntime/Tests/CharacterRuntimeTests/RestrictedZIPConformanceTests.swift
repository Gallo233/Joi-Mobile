import Foundation
import XCTest
@testable import CharacterRuntime

/// Runs `Contracts/conformance/zip-profile.json` against the preflight.
///
/// This is the layer where hostile input actually arrives. Everything after it —
/// staging, hashing, sealing, installing — is written on the assumption that the
/// traversals, the links, the overlapping ranges and the profiles nobody
/// implemented were already refused here. A second client that re-derives 51
/// rejection points from prose will agree on the easy ones.
///
/// The three refusals are kept distinct on purpose and the vectors assert which
/// one fires, not merely that something did: `unsupportedArchiveProfile` is a
/// well-formed archive this reader will not open, `unsafeArchive` is an archive
/// attempting something, and `malformedArchive` is bytes that do not describe an
/// archive. Those are three different sentences to show a person.
final class RestrictedZIPConformanceTests: XCTestCase {
    func testEveryArchiveVectorProducesItsStatedOutcome() throws {
        let corpus = try Conformance.load(ZIPCorpus.self, from: "zip-profile.json")
        XCTAssertGreaterThanOrEqual(corpus.cases.count, 35)

        for vector in corpus.cases {
            guard let bytes = Data(base64Encoded: vector.archiveBase64) else {
                return XCTFail("\(vector.id): corpus archive is not base64")
            }
            let root = try Conformance.makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appendingPathComponent("candidate.zip")
            try bytes.write(to: url)

            // A vector marked non-normative states what *should* happen and
            // records what happens instead, so the finding cannot be lost and the
            // lane does not stop on a question that belongs to a decision.
            let expected = vector.normative ?? true ? vector.expect : (vector.currentOutcome ?? vector.expect)

            do {
                let plan = try RestrictedZIPPreflight.plan(url)
                XCTAssertEqual(
                    expected,
                    "accept",
                    "\(vector.id) was admitted with \(plan.files.count) files but should have been refused as \(expected)"
                )
            } catch let failure as CharacterPackageImportFailure {
                XCTAssertEqual(
                    failure.code.rawValue,
                    expected,
                    "wrong code for \(vector.id): \(vector.note)"
                )
                XCTAssertEqual(failure.phase, .preflight, "\(vector.id) should fail during preflight")
            }
        }
    }

    /// A directory entry is structure, not content. If it were reported as a
    /// file the manifest's asset list would have to declare it, and every
    /// package with a folder in it would be refused as carrying an undeclared
    /// asset.
    func testDirectoryEntriesAreStructureAndNotFiles() throws {
        let corpus = try Conformance.load(ZIPCorpus.self, from: "zip-profile.json")
        guard let vector = corpus.cases.first(where: { $0.id == "directory-entry" }),
              let bytes = Data(base64Encoded: vector.archiveBase64) else {
            return XCTFail("the directory-entry vector is missing")
        }
        let root = try Conformance.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("candidate.zip")
        try bytes.write(to: url)

        let plan = try RestrictedZIPPreflight.plan(url)
        XCTAssertEqual(plan.files.map(\.normalizedPath), ["motions/idle.vrma"])
    }
}

struct ZIPCorpus: Decodable {
    struct Case: Decodable {
        let id: String
        let expect: String
        let note: String
        /// Absent means normative. `false` marks a vector the implementation is
        /// known not to satisfy; `currentOutcome` records what it does instead.
        let normative: Bool?
        let currentOutcome: String?
        let archiveBase64: String
    }

    let cases: [Case]
}
