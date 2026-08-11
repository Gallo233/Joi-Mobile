import CompanionCore
import XCTest
@testable import CharacterRuntime

final class CharacterPackageValidatorTests: XCTestCase {
    func testRejectsTraversalAndPreservesContractBoundary() {
        let candidate = CharacterPackageCandidate(
            archiveBytes: 100,
            expandedBytes: 200,
            paths: ["manifest.json", "../escape"],
            manifest: manifest(assets: [CharacterAssetV1(path: "../escape", mediaType: "application/octet-stream", sha256: "hash")])
        )

        XCTAssertThrowsError(try CharacterPackageValidator().validate(candidate)) { error in
            XCTAssertEqual(error as? CharacterPackageValidationError, .unsafePath("../escape"))
        }
    }

    func testRejectsCaseCollidingEntries() {
        let candidate = CharacterPackageCandidate(
            archiveBytes: 100,
            expandedBytes: 200,
            paths: ["manifest.json", "Textures/A.png", "textures/a.png"],
            manifest: manifest(assets: [
                CharacterAssetV1(path: "Textures/A.png", mediaType: "image/png", sha256: "a"),
                CharacterAssetV1(path: "textures/a.png", mediaType: "image/png", sha256: "b"),
            ])
        )

        XCTAssertThrowsError(try CharacterPackageValidator().validate(candidate))
    }

    private func manifest(assets: [CharacterAssetV1]) -> CharacterPackageManifestV1 {
        CharacterPackageManifestV1(
            packageID: "package",
            characterID: "joi",
            version: "1.0.0",
            displayName: "Joi",
            renderer: .live2d,
            entryPath: "model.model3.json",
            locales: ["en"],
            assets: assets,
            provenance: CharacterProvenanceV1(author: "Test", license: "Test-only")
        )
    }
}
