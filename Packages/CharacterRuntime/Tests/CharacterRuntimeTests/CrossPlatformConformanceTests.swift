import CompanionCore
import Foundation
import XCTest
@testable import CharacterRuntime

/// Runs `Contracts/conformance/` against the shipping iOS implementation.
///
/// These vectors are the written form of semantics that until now existed only
/// as Swift source: what the strict scanner accepts, which envelope a manifest
/// belongs to, which stable code each refusal produces, and how a package's
/// content identity is computed byte for byte. A second client has to reproduce
/// all of it exactly, and prose is not a specification a test can fail against.
///
/// The vectors were written from the rule rather than recorded from this
/// implementation, so a disagreement here is a real finding in one of the two —
/// which is the point.
final class CrossPlatformConformanceTests: XCTestCase {
    // MARK: - Content identity

    func testContentIdentityMatchesEveryVector() throws {
        let corpus = try Conformance.load(ContentIDCorpus.self, from: "content-id.json")
        XCTAssertGreaterThanOrEqual(corpus.cases.count, 8)

        for vector in corpus.cases {
            let root = try Conformance.makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            for file in vector.files {
                let url = root.appendingPathComponent(file.path)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                guard let bytes = Data(base64Encoded: file.base64) else {
                    return XCTFail("\(vector.id): corpus payload is not base64")
                }
                try bytes.write(to: url)
            }

            let measured = try CharacterTreeVerifier.contentID(at: root)
            guard vector.normative ?? true else {
                // A recorded, decided-upon divergence rather than a silent one.
                // If this stops diverging the vector should become normative, so
                // the assertion runs in that direction too.
                XCTAssertNotEqual(
                    measured.rawValue,
                    vector.contentID,
                    "\(vector.id) now agrees with the rule; promote it by removing it from PENDING"
                )
                continue
            }
            XCTAssertEqual(
                measured.rawValue,
                vector.contentID,
                "content identity diverged for \(vector.id): \(vector.note)"
            )
        }
    }

    // MARK: - Strict JSON

    func testStrictJSONScannerMatchesEveryVector() throws {
        let corpus = try Conformance.load(DocumentCorpus.self, from: "strict-json.json")
        XCTAssertGreaterThanOrEqual(corpus.cases.count, 30)

        for vector in corpus.cases {
            let data = Data(vector.document.utf8)
            if vector.expect == "accept" {
                XCTAssertNoThrow(
                    try StrictJSON.object(data),
                    "\(vector.id) should be accepted: \(vector.note ?? "")"
                )
                continue
            }
            do {
                _ = try StrictJSON.object(data)
                XCTFail("\(vector.id) should have been refused as \(vector.expect)")
            } catch let failure as CharacterPackageImportFailure {
                XCTAssertEqual(failure.code.rawValue, vector.expect, "wrong code for \(vector.id)")
            }
        }
    }

    // MARK: - Manifest admission

    func testManifestAdmissionMatchesEveryVector() throws {
        let corpus = try Conformance.load(DocumentCorpus.self, from: "manifest-validation.json")
        XCTAssertGreaterThanOrEqual(corpus.cases.count, 30)

        for vector in corpus.cases {
            let root = try Conformance.makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            try Data(vector.document.utf8).write(to: root.appendingPathComponent("manifest.json"))

            do {
                let decoded = try CharacterManifestValidator.decodeAndAdapt(at: root)
                XCTAssertEqual(
                    vector.expect,
                    "accept",
                    "\(vector.id) was admitted but should have been refused as \(vector.expect)"
                )
                XCTAssertEqual(decoded.manifest.schema, "joi.character.v1", vector.id)
            } catch let failure as CharacterPackageImportFailure {
                // A case that reached the filesystem reports a read-path code
                // instead of the expected one, which is exactly the failure this
                // assertion should produce: no vector here may depend on assets.
                XCTAssertEqual(
                    failure.code.rawValue,
                    vector.expect,
                    "wrong code for \(vector.id): \(vector.note ?? "")"
                )
            }
        }
    }

    // MARK: - The declared asset list (DEC-028)

    /// The one boundary `manifest-validation.json` states in prose instead of
    /// carrying as a vector: 2000 declared assets is a quarter of a megabyte of
    /// filler, and a corpus case that large would be read by nobody. The numbers
    /// therefore live here and in the Kotlin twin, and the corpus `notes` point
    /// at both.
    ///
    /// The rule: the declared asset list is bounded by the contract's file count,
    /// not by the forbidden-content walk's generic array guard.
    func testDeclaredAssetListIsBoundedByTheContractAndNotByTheGenericArrayGuard() throws {
        XCTAssertEqual(CharacterPackageLimits.maximumFileCount, 2_000, "the contract's number moved")
        let maximum = CharacterPackageLimits.maximumFileCount
        for count in [1, 300, 301, maximum] {
            XCTAssertNil(
                try admissionFailure(manifest(assetCount: count)),
                "\(count) declared assets should be admitted"
            )
        }
        XCTAssertEqual(
            try admissionFailure(manifest(assetCount: maximum + 1)),
            .invalidManifest,
            "one past the contract's file count is the refusal"
        )
    }

    /// The exemption is that array and nothing else. Both of these were bounded
    /// at 300 before DEC-028 and must stay bounded at 300 after it, or the fix
    /// has removed a guard rather than corrected it.
    func testEveryOtherArrayKeepsTheGenericBound() throws {
        var manyLocales = manifest(assetCount: 1)
        manyLocales["locales"] = Array(repeating: "zh-Hans", count: 301)
        XCTAssertEqual(try admissionFailure(manyLocales), .invalidManifest, "a 301-element `locales`")

        var nestedInsideAnAsset = manifest(assetCount: 1)
        nestedInsideAnAsset["assets"] = [[
            "path": Array(repeating: "x", count: 301),
            "mediaType": "application/json",
            "sha256": String(repeating: "0", count: 64),
        ]]
        XCTAssertEqual(
            try admissionFailure(nestedInsideAnAsset),
            .invalidManifest,
            "an array nested inside an asset entry is not the declared asset list"
        )

        // Arbitrary JSON carried *as an asset* is walked too, and gets no
        // exemption for happening to have a top-level `assets` key.
        let activeJSON = try JSONSerialization.data(withJSONObject: ["assets": Array(repeating: 0, count: 301)])
        XCTAssertThrowsError(try CharacterManifestValidator.validateActiveJSON(activeJSON)) { error in
            XCTAssertEqual((error as? CharacterPackageImportFailure)?.code, .invalidManifest)
        }
    }

    /// A count bound the document size makes unreachable is not a bound anyone
    /// can use. Before DEC-028 a manifest declaring the contract's own file count
    /// was refused for bytes — and refused as `unsafeArchive`, from the read, which
    /// tells an author their package is dangerous when it is merely long.
    func testTheFullDeclaredAssetCountFitsWithinTheManifestByteBound() throws {
        XCTAssertNil(
            try admissionFailure(manifest(assetCount: CharacterPackageLimits.maximumFileCount, pathLength: 28)),
            "the contract's file count at a realistic Live2D path length"
        )
        // The residual, stated rather than hidden: paths near the schema's
        // 512-character maximum still exhaust the byte bound first, and that
        // refusal comes from the bounded read.
        XCTAssertEqual(
            try admissionFailure(manifest(assetCount: CharacterPackageLimits.maximumFileCount, pathLength: 512)),
            .unsafeArchive,
            "2000 assets at the maximum path length is over a megabyte of manifest"
        )
    }

    // MARK: - Admission helpers

    /// A canonical Live2D manifest declaring `assetCount` assets. Admission never
    /// opens an asset, so the files these name do not have to exist.
    private func manifest(assetCount: Int, pathLength: Int = 12) -> [String: Any] {
        let assets = (0..<assetCount).map { index -> [String: Any] in
            let stem = String(format: "motions/%05d", index)
            return [
                "path": stem + String(repeating: "x", count: max(0, pathLength - stem.count)),
                "mediaType": "application/json",
                "sha256": String(repeating: "0", count: 64),
            ]
        }
        return [
            "schema": "joi.character.v1", "packageID": "fixture.live2d", "characterID": "fixture.live2d",
            "version": "1.0.0", "displayName": "Fixture", "renderer": "live2d",
            "entryPath": "model.model3.json", "locales": ["zh-Hans"], "assets": assets,
            "provenance": ["author": "Joi Mobile fixture", "license": "Repository test metadata only"],
        ]
    }

    /// The code `manifest.json` is refused with, or `nil` if it was admitted.
    private func admissionFailure(_ object: [String: Any]) throws -> CharacterPackageImportCode? {
        let root = try Conformance.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            .write(to: root.appendingPathComponent("manifest.json"))
        do {
            _ = try CharacterManifestValidator.decodeAndAdapt(at: root)
            return nil
        } catch let failure as CharacterPackageImportFailure {
            return failure.code
        }
    }

    /// The stable codes are product surface — they choose the sentence a user
    /// reads — so a vector may not name one that does not exist.
    func testEveryExpectedCodeIsAStableImportCode() throws {
        let corpora = ["strict-json.json", "manifest-validation.json"]
        for name in corpora {
            for vector in try Conformance.load(DocumentCorpus.self, from: name).cases
            where vector.expect != "accept" {
                XCTAssertNotNil(
                    CharacterPackageImportCode(rawValue: vector.expect),
                    "\(name)/\(vector.id) expects unknown code \(vector.expect)"
                )
            }
        }
    }
}

// MARK: - Corpus loading

enum Conformance {
    /// The corpus lives at the repository root, above every package. `#filePath`
    /// is the only anchor that survives both `swift test` and an Xcode test run.
    static func directory() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url = url.deletingLastPathComponent() }
        return url.appendingPathComponent("Contracts/conformance")
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        let url = directory().appendingPathComponent(name)
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("joi-conformance-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

struct ContentIDCorpus: Decodable {
    struct File: Decodable {
        let path: String
        let base64: String
    }

    struct Case: Decodable {
        let id: String
        let note: String
        /// Absent means normative. `false` marks a vector the implementation is
        /// known not to satisfy; see the case's `finding`.
        let normative: Bool?
        let files: [File]
        let contentID: String
    }

    let cases: [Case]
}

struct DocumentCorpus: Decodable {
    struct Case: Decodable {
        let id: String
        let document: String
        let expect: String
        let note: String?
    }

    let cases: [Case]
}
