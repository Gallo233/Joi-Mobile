@_spi(CharacterPackageInstaller) import CompanionCore
import CryptoKit
import Foundation
import XCTest
import ZIPFoundation
@testable import CharacterRuntime

final class CharacterPackageInstallerTests: XCTestCase {
    func testCanonicalPreviewDoesNotInstallThenInstallReloadActivateAndRemove() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let archive = fixture.file("fixture.joi-character", storedZip([
            .file("manifest.json", canonicalStaticManifest()),
            .file("portrait.png", validPNG),
        ]))
        let store = fixture.directory("store")
        let installer = CharacterPackageInstaller(root: store)

        let preview = try await installer.preview(.joiCharacterArchive(archive))
        XCTAssertNil(preview.legacyReceipt)
        XCTAssertEqual(preview.manifest.characterID, "fixture.joi")
        let beforeInstall = await installer.list()
        XCTAssertTrue(beforeInstall.isEmpty)

        let installed = try await installer.install(.joiCharacterArchive(archive))
        XCTAssertNil(installed.disposition)
        let firstHandle = try await installer.prepareActivation(installed.installationID)
        let firstRegistered = await installer.isRegistered(firstHandle)
        XCTAssertTrue(firstRegistered)
        let secondHandle = try await installer.prepareActivation(installed.installationID)
        let oldRegistered = await installer.isRegistered(firstHandle)
        let newRegistered = await installer.isRegistered(secondHandle)
        XCTAssertTrue(oldRegistered)
        XCTAssertTrue(newRegistered)
        XCTAssertNotEqual(firstHandle.validationGeneration, secondHandle.validationGeneration)
        XCTAssertEqual(firstHandle.receiptDigest, secondHandle.receiptDigest)

        let reloaded = CharacterPackageInstaller(root: store)
        let entries = await reloaded.list()
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].available)
        let reloadedHandle = try await reloaded.prepareActivation(installed.installationID)
        XCTAssertEqual(reloadedHandle.contentID, installed.contentID)
        try await reloaded.validateActivation(reloadedHandle)
        await reloaded.releaseActivation(reloadedHandle)
        try await reloaded.remove(installed.installationID)
        let afterRemoval = await reloaded.list()
        XCTAssertTrue(afterRemoval.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: assetRoot(store, installed.contentID).path))
    }

    func testRawVRMWrapsCanonicalAndRemainsRightsQuarantined() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = fixture.file("avatar.vrm", minimalVRM())
        let installer = CharacterPackageInstaller(root: fixture.directory("store"))

        let preview = try await installer.preview(.rawVRM(source))
        XCTAssertEqual(preview.manifest.renderer, .vrm)
        XCTAssertEqual(preview.manifest.entryPath, "model.vrm")
        XCTAssertEqual(preview.warnings, ["rights_unverified"])
        let installed = try await installer.install(.rawVRM(source))
        XCTAssertEqual(installed.disposition, .quarantined)
        await XCTAssertThrowsPackageFailure(.rightsUnverified) {
            _ = try await installer.prepareActivation(installed.installationID)
        }
    }

    func testDeflatedCanonicalArchiveUsesTheApprovedStreamingLane() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let archiveURL = fixture.root.appendingPathComponent("deflated.joi-character")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        for (path, body) in [
            ("manifest.json", canonicalStaticManifest()),
            ("portrait.png", validPNG),
        ] {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(body.count),
                compressionMethod: .deflate
            ) { position, size in
                let start = Int(position)
                let end = min(body.count, start + size)
                return start < end ? body.subdata(in: start..<end) : Data()
            }
        }

        let installed = try await CharacterPackageInstaller(root: fixture.directory("store"))
            .install(.joiCharacterArchive(archiveURL))
        XCTAssertNil(installed.disposition)
        XCTAssertEqual(installed.manifest.characterID, "fixture.joi")
    }

    func testLive2DArchiveDiscoversOneModelAndRejectsUnrelatedMembers() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let good = fixture.file("hiyori.zip", live2DArchive())
        let installer = CharacterPackageInstaller(root: fixture.directory("store"))

        let preview = try await installer.preview(.live2DArchive(good))
        XCTAssertEqual(preview.manifest.renderer, .live2d)
        XCTAssertEqual(preview.manifest.entryPath, "hiyori.model3.json")
        XCTAssertEqual(Set(preview.manifest.assets.map(\.path)), ["hiyori.model3.json", "hiyori.moc3", "texture.png", "idle.motion3.json"])
        let installed = try await installer.install(.live2DArchive(good))
        XCTAssertEqual(installed.disposition, .quarantined)
        await XCTAssertThrowsPackageFailure(.rightsUnverified) {
            _ = try await installer.prepareActivation(installed.installationID)
        }

        let bad = fixture.file("unrelated.zip", live2DArchive(extra: [.file("model/notes.txt", Data("no".utf8))]))
        await XCTAssertThrowsPackageFailure(.unsafeArchive) {
            _ = try await installer.preview(.live2DArchive(bad))
        }
        let outsideWrapper = fixture.file("outside-wrapper.zip", live2DArchive(extra: [.file("notes.txt", Data("no".utf8))]))
        await XCTAssertThrowsPackageFailure(.unsafeArchive) {
            _ = try await installer.preview(.live2DArchive(outsideWrapper))
        }
    }

    func testLegacyIsDigestIdentifiedMapsZhAndDeduplicatesContent() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let legacy = legacyManifest()
        let archive = fixture.file("legacy.joi-character", storedZip([
            .file("manifest.json", legacy), .file("portrait.png", validPNG),
        ]))
        let installer = CharacterPackageInstaller(root: fixture.directory("store"))

        let preview = try await installer.preview(.joiCharacterArchive(archive))
        XCTAssertEqual(preview.manifest.locales, ["zh-Hans"])
        XCTAssertEqual(preview.legacyReceipt?.legacySourceID.count, 64)
        XCTAssertTrue(preview.manifest.packageID.hasPrefix("legacy."))
        XCTAssertEqual(preview.warnings, ["legacy_locale_zh_mapped_to_zh_Hans", "rights_unverified"])
        let one = try await installer.install(.joiCharacterArchive(archive))
        let two = try await installer.install(.joiCharacterArchive(archive))
        XCTAssertEqual(one.disposition, .quarantined)
        XCTAssertEqual(two.disposition, .quarantined)
        await XCTAssertThrowsPackageFailure(.rightsUnverified) {
            _ = try await installer.prepareActivation(one.installationID)
        }
        XCTAssertEqual(one.contentID, two.contentID)
        XCTAssertNotEqual(one.installationID, two.installationID)
        let installedEntries = await installer.list()
        XCTAssertEqual(installedEntries.count, 2)
    }

    func testCurrentDesktopManifestShapeImportsButDropsStateCapabilitiesAndWeights() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Contracts/fixtures/desktop-character-manifest-v1.json")
        let desktopManifest = try Data(contentsOf: manifestURL)
        let archive = fixture.file("desktop-current.joi-character", storedZip([
            .file("manifest.json", desktopManifest), .file("portrait.png", validPNG),
        ]))

        let preview = try await CharacterPackageInstaller(root: fixture.directory("store"))
            .preview(.joiCharacterArchive(archive))
        XCTAssertEqual(preview.manifest.renderer, .static)
        XCTAssertEqual(preview.manifest.locales, ["zh-Hans"])
        XCTAssertEqual(preview.legacyReceipt?.schemaVersion, 1)
        XCTAssertEqual(preview.legacyReceipt?.creatorName, "Joi Mobile self-authored fixture")
        XCTAssertEqual(preview.legacyReceipt?.sourceType, "desktop-export")
        XCTAssertEqual(preview.legacyReceipt?.sourceURL, "https://example.invalid/characters/fixture")
        XCTAssertEqual(preview.legacyReceipt?.provenanceFormat, "joi-character-desktop-v1")
        XCTAssertEqual(preview.legacyReceipt?.declaredLicense, "Self-authored test fixture")
        let receipt = try XCTUnwrap(preview.legacyReceipt)
        let encodedReceipt = String(decoding: try JSONEncoder().encode(receipt), as: UTF8.self)
        XCTAssertFalse(encodedReceipt.contains("approved_skills"))
        XCTAssertFalse(encodedReceipt.contains("weights.ckpt"))
        XCTAssertFalse(encodedReceipt.contains("desktop-user-state"))
        let localPathMarker = ["/Us", "ers/example/private"].joined()
        XCTAssertFalse(encodedReceipt.contains(localPathMarker))
        XCTAssertTrue(preview.warnings.contains("rights_unverified"))
    }

    func testManifestDiscriminatorRejectsBothNeitherUnknownAndDuplicateKeys() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.directory("store"))
        let bothObject: [String: Any] = [
            "schema": "joi.character.v1", "packageID": "x", "characterID": "x", "version": "1", "displayName": "x",
            "renderer": "static", "entryPath": "portrait.png", "portraitPath": "portrait.png", "locales": ["zh-Hans"],
            "assets": [], "provenance": ["author": "x", "license": "x"], "id": "x", "identity": ["name": "x"], "appearance": ["model_type": "static", "portrait": "portrait.png"],
        ]
        let neither = json(["schema": "joi.character.v1", "displayName": "x"])
        var unknownObject = canonicalStaticObject()
        unknownObject["permissions"] = ["location": true]
        let duplicate = Data("{\"schema\":\"joi.character.v1\",\"schema\":\"joi.character.v1\"}".utf8)
        for (index, manifest) in [json(bothObject), neither, json(unknownObject), duplicate].enumerated() {
            let archive = fixture.file("manifest-\(index).joi-character", storedZip([
                .file("manifest.json", manifest), .file("portrait.png", validPNG),
            ]))
            await XCTAssertThrowsPackageFailure(.invalidManifest) {
                _ = try await installer.preview(.joiCharacterArchive(archive))
            }
        }
    }

    func testCanonicalRejectsLocalOrAbsoluteProvenanceSources() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.directory("store"))
        for (index, source) in [
            "file:///private/character",
            "/private/character",
            "~/character",
            "http://example.invalid/character",
        ].enumerated() {
            var object = canonicalStaticObject()
            object["provenance"] = ["author": "Test", "license": "Self-authored", "source": source]
            let archive = fixture.file("local-source-\(index).joi-character", storedZip([
                .file("manifest.json", json(object)), .file("portrait.png", validPNG),
            ]))
            await XCTAssertThrowsPackageFailure(.invalidManifest) {
                _ = try await installer.preview(.joiCharacterArchive(archive))
            }
        }
    }

    func testLive2DReferencedJSONCannotSmuggleStateOrSecurityKeys() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.directory("store"))
        for (index, key) in ["api_key", "memory", "permissions"].enumerated() {
            let archive = fixture.file("active-json-\(index).zip", live2DArchive(
                motion: json(["Version": 3, "Meta": [:], "Curves": [], key: "smuggled"])
            ))
            await XCTAssertThrowsPackageFailure(.invalidManifest) {
                _ = try await installer.preview(.live2DArchive(archive))
            }
        }
    }

    func testLegacyRejectsForbiddenStateAndExtraPayload() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.directory("store"))
        var forbidden = legacyObject()
        forbidden["persona"] = ["memory": "must never enter package state"]
        let stateArchive = fixture.file("state.joi-character", storedZip([
            .file("manifest.json", json(forbidden)), .file("portrait.png", validPNG),
        ]))
        await XCTAssertThrowsPackageFailure(.unsupportedLegacy) {
            _ = try await installer.preview(.joiCharacterArchive(stateArchive))
        }
        let extraArchive = fixture.file("extra.joi-character", storedZip([
            .file("manifest.json", legacyManifest()), .file("portrait.png", validPNG), .file("notes.txt", Data("no".utf8)),
        ]))
        await XCTAssertThrowsPackageFailure(.unsupportedLegacy) {
            _ = try await installer.preview(.joiCharacterArchive(extraArchive))
        }
    }

    func testPathPolicyRejectsBackslashNULDotAndUnicodeCaseCollisions() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.directory("store"))
        let badSets: [[ZipEntry]] = [
            [.file("manifest.json", canonicalStaticManifest()), .file("folder\\portrait.png", validPNG)],
            [.file("manifest.json", canonicalStaticManifest()), .file("bad\0name.png", validPNG)],
            [.file("manifest.json", canonicalStaticManifest()), .file("./portrait.png", validPNG)],
            [.file("manifest.json", canonicalStaticManifest()), .file("é.png", validPNG), .file("e\u{301}.png", validPNG)],
            [.file("manifest.json", canonicalStaticManifest()), .file("A.png", validPNG), .file("a.png", validPNG)],
        ]
        for (index, entries) in badSets.enumerated() {
            let archive = fixture.file("path-\(index).joi-character", storedZip(entries))
            await XCTAssertThrowsPackageFailure(.unsafeArchive) {
                _ = try await installer.preview(.joiCharacterArchive(archive))
            }
        }
    }

    func testRestrictedZIPRejectsFlagsMethodAttributesExtrasAndNestedMagic() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.directory("store"))
        let manifest = ZipEntry.file("manifest.json", canonicalStaticManifest())
        let attacks: [[ZipEntry]] = [
            [manifest, .file("portrait.png", validPNG, flags: 0x0001)],
            [manifest, .file("portrait.png", validPNG, flags: 0x0008)],
            [manifest, .file("portrait.png", validPNG, method: 99)],
            [manifest, .file("portrait.png", validPNG, madeBy: UInt16(3 << 8) | 20, external: UInt32(0o100755) << 16)],
            [manifest, .file("portrait.png", validPNG, madeBy: UInt16(3 << 8) | 20, external: UInt32(0o120777) << 16)],
            [manifest, .file("portrait.png", validPNG, extra: Data([0x34, 0x12, 0x00, 0x00]))],
            [manifest, .file("portrait.png", Data([0x50, 0x4b, 0x03, 0x04]) + validPNG)],
        ]
        for (index, entries) in attacks.enumerated() {
            let archive = fixture.file("zip-\(index).joi-character", storedZip(entries))
            do {
                _ = try await installer.preview(.joiCharacterArchive(archive))
                XCTFail("attack \(index) was accepted")
            } catch let failure as CharacterPackageImportFailure {
                XCTAssertTrue([.unsafeArchive, .unsupportedArchiveProfile].contains(failure.code))
                XCTAssertTrue([.preflight, .extract].contains(failure.phase))
            } catch {
                XCTFail("unexpected error \(error)")
            }
        }
    }

    func testRestrictedZIPRejectsCRCSizeHeaderMismatchAndOverlap() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.directory("store"))
        let base = storedZip([.file("manifest.json", canonicalStaticManifest()), .file("portrait.png", validPNG)])
        var localCRC = base
        localCRC[14] ^= 0xff
        var centralSize = base
        let firstCentral = findSignature(0x0201_4b50, in: centralSize, from: 0)!
        centralSize[firstCentral + 24] ^= 0x01
        var corruptBody = base
        let nameLength = Int(readU16(corruptBody, 26))
        corruptBody[30 + nameLength] ^= 0xff
        var overlap = base
        let centralOne = findSignature(0x0201_4b50, in: overlap, from: 0)!
        let centralTwo = findSignature(0x0201_4b50, in: overlap, from: centralOne + 4)!
        writeU32(0, into: &overlap, at: centralTwo + 42)
        for (index, bytes) in [localCRC, centralSize, corruptBody, overlap].enumerated() {
            let archive = fixture.file("mismatch-\(index).joi-character", bytes)
            do {
                _ = try await installer.preview(.joiCharacterArchive(archive))
                XCTFail("mismatch \(index) was accepted")
            } catch let failure as CharacterPackageImportFailure {
                XCTAssertTrue([.malformedArchive, .unsafeArchive].contains(failure.code))
            }
        }
    }

    func testDeterministicSeededZIPHeaderMutationCorpusFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.directory("store"))
        let base = storedZip([.file("manifest.json", canonicalStaticManifest()), .file("portrait.png", validPNG)])
        let central = try XCTUnwrap(findSignature(0x0201_4b50, in: base, from: 0))
        let end = try XCTUnwrap(findSignature(0x0605_4b50, in: base, from: central))
        let sensitive = [0, 1, 2, 3, 6, 8, 14, 18, 22, 26, central, central + 1, central + 2, central + 3, central + 8, central + 10, central + 16, central + 20, central + 24, central + 28, central + 42, end, end + 4, end + 8, end + 10, end + 12, end + 16]
        var seed: UInt64 = 0x4a_4f_49_4d_4f_42_49_4c
        for iteration in 0..<32 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let offset = sensitive[Int(seed % UInt64(sensitive.count))]
            var mutated = base
            mutated[offset] ^= UInt8(truncatingIfNeeded: seed >> 32) | 1
            let archive = fixture.file("seeded-\(iteration).joi-character", mutated)
            do {
                _ = try await installer.preview(.joiCharacterArchive(archive))
                XCTFail("seeded mutation \(iteration) was accepted")
            } catch let failure as CharacterPackageImportFailure {
                XCTAssertTrue([.malformedArchive, .unsafeArchive, .unsupportedArchiveProfile, .invalidManifest].contains(failure.code))
            }
        }
    }

    func testPolicyBoundariesDoNotOverflow() throws {
        XCTAssertEqual(CharacterPackageLimits.maximumFileBytes, 128 * 1_024 * 1_024)
        XCTAssertEqual(try RestrictedZIPPolicy.adding(10, 20, limit: 30), 30)
        XCTAssertThrowsError(try RestrictedZIPPolicy.adding(30, 1, limit: 30))
        XCTAssertThrowsError(try RestrictedZIPPolicy.adding(UInt64.max, 1, limit: UInt64.max))
        XCTAssertEqual(try RestrictedZIPPolicy.normalizedPath("模型/角色.vrm"), "模型/角色.vrm")
        XCTAssertThrowsError(try RestrictedZIPPolicy.normalizedPath("C:/avatar.vrm"))
    }

    func testArchiveFileExpandedCountAndRatioExactBoundariesAndPlusOne() throws {
        let mib = UInt64(1_024 * 1_024)
        let ratioSafeCompressed = (512 * mib + 19) / 20
        XCTAssertNoThrow(try RestrictedZIPPolicy.validateLimits(
            archiveBytes: 128 * mib, fileBytes: 128 * mib, expandedBytes: 512 * mib,
            fileCount: 2_000, compressedBytes: ratioSafeCompressed
        ))
        for mutation in 0..<4 {
            XCTAssertThrowsError(try RestrictedZIPPolicy.validateLimits(
                archiveBytes: 128 * mib + (mutation == 0 ? 1 : 0),
                fileBytes: 128 * mib + (mutation == 1 ? 1 : 0),
                expandedBytes: 512 * mib + (mutation == 2 ? 1 : 0),
                fileCount: 2_000 + (mutation == 3 ? 1 : 0),
                compressedBytes: ratioSafeCompressed
            ))
        }
        XCTAssertNoThrow(try RestrictedZIPPolicy.validateLimits(
            archiveBytes: 1_000, fileBytes: 20_000, expandedBytes: 20_000, fileCount: 1, compressedBytes: 1_000
        ))
        XCTAssertThrowsError(try RestrictedZIPPolicy.validateLimits(
            archiveBytes: 1_000, fileBytes: 20_001, expandedBytes: 20_001, fileCount: 1, compressedBytes: 1_000
        ))
    }

    func testArchiveSizeGateUsesSparseExactAndPlusOneFiles() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        for (suffix, size, expected) in [
            ("exact", CharacterPackageLimits.maximumArchiveBytes, CharacterPackageImportCode.malformedArchive),
            ("plus-one", CharacterPackageLimits.maximumArchiveBytes + 1, CharacterPackageImportCode.unsafeArchive),
        ] {
            let url = fixture.root.appendingPathComponent("sparse-\(suffix).zip")
            let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
            XCTAssertGreaterThanOrEqual(fd, 0)
            XCTAssertEqual(Darwin.ftruncate(fd, off_t(size)), 0)
            Darwin.close(fd)
            XCTAssertThrowsError(try RestrictedZIPPreflight.plan(url)) { error in
                XCTAssertEqual((error as? CharacterPackageImportFailure)?.code, expected)
            }
        }
    }

    func testSourceMutationIsRejectedAndUnsafeBytesAreDeleted() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let padding = Data(repeating: 0x41, count: 80_000)
        let source = fixture.file("mutable.joi-character", storedZip([
            .file("manifest.json", canonicalStaticManifest()), .file("portrait.png", validPNG), .file("padding.bin", padding),
        ]))
        let store = fixture.directory("store")
        let observer = SourceMutationObserver(source: source)
        let installer = CharacterPackageInstaller(root: store, sourceCopyObserver: { count in observer.mutateOnce(after: count) })
        await XCTAssertThrowsPackageFailure(.sourceChanged) {
            _ = try await installer.install(.joiCharacterArchive(source))
        }
        XCTAssertEqual(children(store.appendingPathComponent("Characters/Staging")).count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.appendingPathComponent("Characters/quarantine").path))
        XCTAssertEqual(children(store.appendingPathComponent("Characters/Assets/v1/sha256")).count, 0)
    }

    func testSourceSymlinkAndHardlinkAreRejectedBeforeCopy() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = fixture.file("source.joi-character", storedZip([
            .file("manifest.json", canonicalStaticManifest()), .file("portrait.png", validPNG),
        ]))
        let symbolic = fixture.root.appendingPathComponent("symbolic.joi-character")
        try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: source)
        let hard = fixture.root.appendingPathComponent("hard.joi-character")
        try FileManager.default.linkItem(at: source, to: hard)
        let installer = CharacterPackageInstaller(root: fixture.directory("store"))
        for input in [symbolic, hard] {
            await XCTAssertThrowsPackageFailure(.unsafeArchive) {
                _ = try await installer.preview(.joiCharacterArchive(input))
            }
        }
    }

    func testCancellationRollsBackOperationPayload() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = fixture.file("fixture.joi-character", storedZip([
            .file("manifest.json", canonicalStaticManifest()), .file("portrait.png", validPNG),
        ]))
        let store = fixture.directory("store")
        let installer = CharacterPackageInstaller(root: store)
        let task = Task {
            try await installer.install(.joiCharacterArchive(source))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("expected cancellation") }
        catch is CancellationError {}
        XCTAssertEqual(children(store.appendingPathComponent("Characters/Staging")).count, 0)
        let entries = await installer.list()
        XCTAssertTrue(entries.isEmpty)
    }

    func testCancellationAfterSealRollsBackNewContentBeforeCatalogCommit() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = fixture.file("fixture.joi-character", storedZip([
            .file("manifest.json", canonicalStaticManifest()), .file("portrait.png", validPNG),
        ]))
        let store = fixture.directory("store")
        let installer = CharacterPackageInstaller(root: store, phaseObserver: { phase in
            if phase == .seal { withUnsafeCurrentTask { $0?.cancel() } }
        })
        do {
            _ = try await installer.install(.joiCharacterArchive(source))
            XCTFail("expected cancellation")
        } catch is CancellationError {}
        let afterCancel = await installer.list()
        XCTAssertTrue(afterCancel.isEmpty)
        let catalog = children(store.appendingPathComponent("Characters/Catalog/v1")).filter { $0.pathExtension == "json" }
        let prefixes = children(store.appendingPathComponent("Characters/Assets/v1/sha256"))
        XCTAssertTrue(catalog.isEmpty)
        XCTAssertTrue(prefixes.allSatisfy { children($0).isEmpty })
    }

    func testCancellationAfterCatalogCommitReturnsDurableSuccess() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = fixture.file("fixture.joi-character", storedZip([
            .file("manifest.json", canonicalStaticManifest()), .file("portrait.png", validPNG),
        ]))
        let store = fixture.directory("store")
        let installer = CharacterPackageInstaller(root: store, phaseObserver: { phase in
            if phase == .install { withUnsafeCurrentTask { $0?.cancel() } }
        })
        let installTask = Task { try await installer.install(.joiCharacterArchive(source)) }
        let installed = try await installTask.value
        let liveEntries = await installer.list()
        let reloadedEntries = await CharacterPackageInstaller(root: store).list()
        XCTAssertEqual(liveEntries.map(\.installationID), [installed.installationID])
        XCTAssertEqual(reloadedEntries.map(\.installationID), [installed.installationID])
    }

    func testPostInstallMutationMakesCatalogUnavailableAndInvalidatesHandle() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let archive = fixture.file("fixture.joi-character", storedZip([
            .file("manifest.json", canonicalStaticManifest()), .file("portrait.png", validPNG),
        ]))
        let store = fixture.directory("store")
        let installer = CharacterPackageInstaller(root: store)
        let result = try await installer.install(.joiCharacterArchive(archive))
        let handle = try await installer.prepareActivation(result.installationID)
        let portrait = assetRoot(store, result.contentID).appendingPathComponent("portrait.png")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: portrait.path)
        try Data(repeating: 0, count: validPNG.count).write(to: portrait)

        await XCTAssertThrowsPackageFailure(.hashMismatch) {
            _ = try await installer.prepareActivation(result.installationID)
        }
        let stillRegistered = await installer.isRegistered(handle)
        let unavailableEntries = await installer.list()
        XCTAssertFalse(stillRegistered)
        XCTAssertFalse(unavailableEntries.first?.available ?? true)
        let reloaded = CharacterPackageInstaller(root: store)
        let reloadedEntries = await reloaded.list()
        XCTAssertFalse(reloadedEntries.first?.available ?? true)
    }

    func testPostInstallRootReplacementFailsEvenWhenBytesMatch() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let archive = fixture.file("fixture.joi-character", storedZip([
            .file("manifest.json", canonicalStaticManifest()), .file("portrait.png", validPNG),
        ]))
        let store = fixture.directory("store")
        let installer = CharacterPackageInstaller(root: store)
        let result = try await installer.install(.joiCharacterArchive(archive))
        let original = assetRoot(store, result.contentID)
        let replacement = original.deletingLastPathComponent().appendingPathComponent("replacement")
        try FileManager.default.copyItem(at: original, to: replacement)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: original.path)
        let old = original.deletingLastPathComponent().appendingPathComponent("old")
        try FileManager.default.moveItem(at: original, to: old)
        try FileManager.default.moveItem(at: replacement, to: original)
        await XCTAssertThrowsPackageFailure(.hashMismatch) {
            _ = try await installer.prepareActivation(result.installationID)
        }
    }

    func testStartupRemovesAbandonedStagingTrashAndOrphanAssets() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.directory("store")
        let abandoned = store.appendingPathComponent("Characters/Staging/abandoned", isDirectory: true)
        let trash = store.appendingPathComponent("Characters/Trash/dead", isDirectory: true)
        let orphan = store.appendingPathComponent("Characters/Assets/v1/sha256/aa/" + String(repeating: "a", count: 64), isDirectory: true)
        for directory in [abandoned, trash, orphan] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: directory.appendingPathComponent("payload"))
        }
        _ = CharacterPackageInstaller(root: store)
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trash.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testZIP64AndMultidiskUseStableUnsupportedProfileCode() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.directory("store"))
        let base = storedZip([.file("manifest.json", canonicalStaticManifest()), .file("portrait.png", validPNG)])
        var zip64 = base
        zip64.append(contentsOf: [0x50, 0x4b, 0x06, 0x06])
        var multidisk = base
        let end = findSignature(0x0605_4b50, in: multidisk, from: 0)!
        writeU16(1, into: &multidisk, at: end + 4)
        for (index, bytes) in [zip64, multidisk].enumerated() {
            let source = fixture.file("profile-\(index).joi-character", bytes)
            await XCTAssertThrowsPackageFailure(.unsupportedArchiveProfile) {
                _ = try await installer.preview(.joiCharacterArchive(source))
            }
        }
    }

    func testRemovalOfDeduplicatedInstallRetainsContentUntilLastReference() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let archive = fixture.file("fixture.joi-character", storedZip([
            .file("manifest.json", canonicalStaticManifest()), .file("portrait.png", validPNG),
        ]))
        let store = fixture.directory("store")
        let installer = CharacterPackageInstaller(root: store)
        let one = try await installer.install(.joiCharacterArchive(archive))
        let two = try await installer.install(.joiCharacterArchive(archive))
        try await installer.remove(one.installationID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetRoot(store, one.contentID).path))
        let handle = try await installer.prepareActivation(two.installationID)
        await installer.releaseActivation(handle)
        try await installer.remove(two.installationID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: assetRoot(store, one.contentID).path))
    }

    func testConcurrentActivationLeasesBlockRemovalUntilEachLeaseReleases() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let archive = fixture.file("fixture.joi-character", storedZip([
            .file("manifest.json", canonicalStaticManifest()), .file("portrait.png", validPNG),
        ]))
        let installer = CharacterPackageInstaller(root: fixture.directory("store"))
        let installed = try await installer.install(.joiCharacterArchive(archive))
        let first = try await installer.prepareActivation(installed.installationID)
        let second = try await installer.prepareActivation(installed.installationID)
        try await installer.validateActivation(first)
        try await installer.validateActivation(second)
        await installer.releaseActivation(first)
        await XCTAssertThrowsPackageFailure(.staleHandle) { try await installer.validateActivation(first) }
        await XCTAssertThrowsPackageFailure(.inUse) { try await installer.remove(installed.installationID) }
        try await installer.validateActivation(second)
        await installer.releaseActivation(second)
        await XCTAssertThrowsPackageFailure(.staleHandle) { try await installer.validateActivation(second) }
        try await installer.remove(installed.installationID)
    }

    func testMutationDetectedAtPreCASValidationRevokesEveryLeaseAndAllowsRemoval() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let archive = fixture.file("fixture.joi-character", storedZip([
            .file("manifest.json", canonicalStaticManifest()), .file("portrait.png", validPNG),
        ]))
        let store = fixture.directory("store")
        let installer = CharacterPackageInstaller(root: store)
        let installed = try await installer.install(.joiCharacterArchive(archive))
        let first = try await installer.prepareActivation(installed.installationID)
        let second = try await installer.prepareActivation(installed.installationID)
        let portrait = assetRoot(store, installed.contentID).appendingPathComponent("portrait.png")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: portrait.path)
        try Data(repeating: 0, count: validPNG.count).write(to: portrait)

        await XCTAssertThrowsPackageFailure(.hashMismatch) { try await installer.validateActivation(first) }
        let firstRegistered = await installer.isRegistered(first)
        let secondRegistered = await installer.isRegistered(second)
        XCTAssertFalse(firstRegistered)
        XCTAssertFalse(secondRegistered)
        await XCTAssertThrowsPackageFailure(.staleHandle) { try await installer.validateActivation(second) }
        let entries = await installer.list()
        XCTAssertFalse(entries.first?.available ?? true)
        try await installer.remove(installed.installationID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: assetRoot(store, installed.contentID).path))
    }

    func testDeletionJournalFaultsReturnStableRecoveryKeyAndRetry() async throws {
        for point in [CharacterDeletionFaultPoint.afterJournal, .afterAssetMove, .afterCatalogRemoval, .beforeTrashDeletion] {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let archive = fixture.file("fixture.joi-character", storedZip([
                .file("manifest.json", canonicalStaticManifest()), .file("portrait.png", validPNG),
            ]))
            let store = fixture.directory("store")
            let installer = CharacterPackageInstaller(root: store, deletionFaultInjector: { $0 == point })
            let installed = try await installer.install(.joiCharacterArchive(archive))
            var recoveryKey: String?
            do {
                try await installer.remove(installed.installationID)
                XCTFail("expected recoveryRequired at \(point)")
            } catch let failure as CharacterPackageImportFailure {
                XCTAssertEqual(failure.code, .recoveryRequired)
                recoveryKey = failure.recoveryKey
                XCTAssertNotNil(recoveryKey)
            }
            try await installer.remove(installed.installationID)
            XCTAssertFalse(FileManager.default.fileExists(atPath: assetRoot(store, installed.contentID).path))
            if let recoveryKey {
                XCTAssertFalse(FileManager.default.fileExists(atPath: store.appendingPathComponent("Characters/Catalog/v1/Deletions/\(recoveryKey).json").path))
            }
        }
    }

    func testStartupCompletesPendingDeletionJournalAfterCrashPhase() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let archive = fixture.file("fixture.joi-character", storedZip([
            .file("manifest.json", canonicalStaticManifest()), .file("portrait.png", validPNG),
        ]))
        let store = fixture.directory("store")
        let faulting = CharacterPackageInstaller(root: store, deletionFaultInjector: { $0 == .afterAssetMove })
        let installed = try await faulting.install(.joiCharacterArchive(archive))
        await XCTAssertThrowsPackageFailure(.recoveryRequired) { try await faulting.remove(installed.installationID) }

        let recovered = CharacterPackageInstaller(root: store)
        let recoveredEntries = await recovered.list()
        XCTAssertTrue(recoveredEntries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: assetRoot(store, installed.contentID).path))
        XCTAssertTrue(children(store.appendingPathComponent("Characters/Trash")).isEmpty)
        XCTAssertTrue(children(store.appendingPathComponent("Characters/Catalog/v1/Deletions")).isEmpty)
    }

    func testPrivateRawVRMImporterWhenConfigured() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[CharacterFixtureEnvironment.vrmFileURL] else {
            throw XCTSkip("Set the private VRM fixture environment to run this installer gate")
        }
        let source = URL(fileURLWithPath: path)
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let preview = try await CharacterPackageInstaller(root: fixture.directory("store")).preview(.rawVRM(source))
        XCTAssertEqual(preview.manifest.renderer, .vrm)
        XCTAssertEqual(preview.manifest.entryPath, "model.vrm")
        XCTAssertEqual(preview.warnings, ["rights_unverified"])
    }

    func testPrivateLive2DImporterWhenConfigured() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[CharacterFixtureEnvironment.live2DEntryURL] else {
            throw XCTSkip("Set the private Live2D fixture environment to run this installer gate")
        }
        let entry = URL(fileURLWithPath: path)
        let sourceRoot = entry.deletingLastPathComponent()
        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { throw CharacterPackageImportFailure(.notFound, .preflight) }
        var entries: [ZipEntry] = []
        while let file = enumerator.nextObject() as? URL {
            guard (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
            let relative = String(file.path.dropFirst(sourceRoot.path.count + 1))
            entries.append(.file("model/" + relative, try Data(contentsOf: file)))
        }
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let archive = fixture.file("private-live2d.zip", storedZip(entries.sorted { $0.name < $1.name }))
        let store = fixture.directory("store")
        let installer = CharacterPackageInstaller(root: store)
        let preview = try await installer.preview(.live2DArchive(archive))
        XCTAssertEqual(preview.manifest.renderer, .live2d)
        XCTAssertEqual(preview.manifest.assets.count, entries.count)
        XCTAssertTrue(preview.manifest.assets.contains { $0.path.hasSuffix(".cdi3.json") })

        // The stage renders from the installer-issued entry path, so a real
        // import must name the model3 graph and that file must be readable
        // inside the sealed tree. Without this the render link is unproven.
        let installed = try await installer.install(.live2DArchive(archive))
        XCTAssertEqual(installed.manifest.renderer, .live2d)
        XCTAssertTrue(
            installed.manifest.entryPath.hasSuffix(".model3.json"),
            "entry must be the model3 graph, got \(installed.manifest.entryPath)"
        )
        // A bare Live2D ZIP carries no provenance, so it stays quarantined and
        // cannot be activated or yield a content root. This is the J1B rule, not
        // a defect: the render link is only reachable for rights-cleared
        // packages, and confirming rights is G5 work.
        XCTAssertEqual(installed.disposition, .quarantined)
        await XCTAssertThrowsPackageFailure(.rightsUnverified) {
            _ = try await installer.prepareActivation(installed.installationID)
        }
    }

    /// The render link itself, proven on a rights-cleared canonical Live2D
    /// package: activation yields a root whose entry is the model3 graph and
    /// whose declared assets all resolve inside the sealed tree.
    func testActivationYieldsAReadableLive2DEntryForRightsClearedPackages() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let moc = Data([0x4D, 0x4F, 0x43, 0x33] + Array(repeating: 0, count: 64))
        let model3 = try JSONSerialization.data(withJSONObject: [
            "Version": 3,
            "FileReferences": ["Moc": "hiyori.moc3", "Textures": ["texture_00.png"]],
        ], options: [.sortedKeys])
        let archive = fixture.file("cleared.joi-character", storedZip([
            .file("manifest.json", canonicalLive2DManifest(
                entryPath: "hiyori.model3.json",
                assets: [
                    ("hiyori.model3.json", "application/json", model3),
                    ("hiyori.moc3", "application/vnd.live2d.moc3", moc),
                    ("texture_00.png", "image/png", validPNG),
                ]
            )),
            .file("hiyori.model3.json", model3),
            .file("hiyori.moc3", moc),
            .file("texture_00.png", validPNG),
        ]))
        let store = fixture.directory("store")
        let installer = CharacterPackageInstaller(root: store)
        let installed = try await installer.install(.joiCharacterArchive(archive))
        XCTAssertNil(installed.disposition, "a rights-cleared package is not quarantined")

        let handle = try await installer.prepareActivation(installed.installationID)
        let access = try await installer.contentAccess(for: handle)
        XCTAssertEqual(access.renderer, .live2d)
        XCTAssertEqual(access.entryPath, "hiyori.model3.json")
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: access.entryURL.path))
        for asset in installed.manifest.assets {
            XCTAssertTrue(
                FileManager.default.isReadableFile(
                    atPath: access.root.appendingPathComponent(asset.path).path
                ),
                "declared asset unreadable: \(asset.path)"
            )
        }
        await installer.releaseActivation(handle)
    }
}

private final class SourceMutationObserver: @unchecked Sendable {
    private let lock = NSLock()
    private let source: URL
    private var mutated = false

    init(source: URL) { self.source = source }

    func mutateOnce(after count: Int) {
        guard count >= 64 * 1024 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !mutated else { return }
        mutated = true
        if let handle = try? FileHandle(forWritingTo: source) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data([0]))
            try? handle.close()
        }
    }
}

private struct Fixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func file(_ name: String, _ data: Data) -> URL {
        let url = root.appendingPathComponent(name)
        try! data.write(to: url)
        return url
    }

    func directory(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }
    func cleanup() {
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            var directories = [root]
            while let item = enumerator.nextObject() as? URL {
                if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    directories.append(item)
                } else {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: item.path)
                }
            }
            for directory in directories.reversed() {
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            }
        }
        try? FileManager.default.removeItem(at: root)
    }
}

private struct ZipEntry {
    let name: String
    let body: Data
    var flags: UInt16 = 0
    var method: UInt16 = 0
    var madeBy: UInt16 = 20
    var external: UInt32 = 0
    var extra = Data()

    static func file(
        _ name: String,
        _ body: Data,
        flags: UInt16 = 0,
        method: UInt16 = 0,
        madeBy: UInt16 = 20,
        external: UInt32 = 0,
        extra: Data = Data()
    ) -> ZipEntry {
        .init(name: name, body: body, flags: flags, method: method, madeBy: madeBy, external: external, extra: extra)
    }
}

private func storedZip(_ entries: [ZipEntry]) -> Data {
    var output = Data()
    var central = Data()
    var offset: UInt32 = 0
    for entry in entries {
        let name = Data(entry.name.utf8)
        let crc = crc32(entry.body)
        let size = UInt32(entry.body.count)
        output.u32(0x0403_4b50); output.u16(20); output.u16(entry.flags); output.u16(entry.method)
        output.u16(0); output.u16(0); output.u32(crc); output.u32(size); output.u32(size)
        output.u16(UInt16(name.count)); output.u16(UInt16(entry.extra.count)); output.append(name); output.append(entry.extra); output.append(entry.body)
        central.u32(0x0201_4b50); central.u16(entry.madeBy); central.u16(20); central.u16(entry.flags); central.u16(entry.method)
        central.u16(0); central.u16(0); central.u32(crc); central.u32(size); central.u32(size)
        central.u16(UInt16(name.count)); central.u16(UInt16(entry.extra.count)); central.u16(0); central.u16(0); central.u16(0)
        central.u32(entry.external); central.u32(offset); central.append(name); central.append(entry.extra)
        offset += UInt32(30 + name.count + entry.extra.count + entry.body.count)
    }
    let centralOffset = offset
    output.append(central)
    output.u32(0x0605_4b50); output.u16(0); output.u16(0); output.u16(UInt16(entries.count)); output.u16(UInt16(entries.count))
    output.u32(UInt32(central.count)); output.u32(centralOffset); output.u16(0)
    return output
}

private let validPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!

private func canonicalStaticObject() -> [String: Any] {
    [
        "schema": "joi.character.v1", "packageID": "fixture.static", "characterID": "fixture.joi", "version": "1.0.0",
        "displayName": "Fixture", "renderer": "static", "entryPath": "portrait.png", "portraitPath": "portrait.png", "locales": ["zh-Hans"],
        "assets": [["path": "portrait.png", "mediaType": "image/png", "sha256": sha(validPNG)]],
        "provenance": ["author": "Test", "license": "Self-authored test fixture"],
    ]
}

private func canonicalStaticManifest() -> Data { json(canonicalStaticObject()) }

/// A canonical Live2D manifest with declared provenance, so the package is
/// rights-cleared and may be activated rather than quarantined.
private func canonicalLive2DManifest(
    entryPath: String,
    assets: [(String, String, Data)]
) -> Data {
    json([
        "schema": "joi.character.v1", "packageID": "fixture.live2d", "characterID": "fixture.hiyori",
        "version": "1.0.0", "displayName": "Fixture Live2D", "renderer": "live2d",
        "entryPath": entryPath, "locales": ["zh-Hans"],
        "assets": assets.map { ["path": $0.0, "mediaType": $0.1, "sha256": sha($0.2)] },
        "provenance": ["author": "Test", "license": "Self-authored test fixture"],
    ])
}

private func legacyObject() -> [String: Any] {
    [
        "schema": "joi.character.v1", "id": "old-joi", "version": "1.0.0", "locale": "zh",
        "identity": ["name": "旧角色"], "appearance": ["model_type": "static", "portrait": "portrait.png"],
    ]
}

private func legacyManifest() -> Data { json(legacyObject()) }

private func live2DArchive(
    extra: [ZipEntry] = [],
    motion: Data = json(["Version": 3, "Meta": [:], "Curves": []])
) -> Data {
    let model: [String: Any] = [
        "Version": 3,
        "FileReferences": [
            "Moc": "hiyori.moc3", "Textures": ["texture.png"],
            "Motions": ["Idle": [["File": "idle.motion3.json"]]],
        ],
    ]
    return storedZip([
        .file("model/hiyori.model3.json", json(model)),
        .file("model/hiyori.moc3", Data("MOC3".utf8) + Data(repeating: 0, count: 8)),
        .file("model/texture.png", validPNG),
        .file("model/idle.motion3.json", motion),
    ] + extra)
}

private func minimalVRM() -> Data {
    var jsonData = json([
        "asset": ["version": "2.0"],
        "extensionsUsed": ["VRMC_vrm"],
        "extensions": ["VRMC_vrm": ["humanoid": ["humanBones": [:]], "expressions": ["preset": [:]]]],
    ])
    while !jsonData.count.isMultiple(of: 4) { jsonData.append(0x20) }
    var result = Data()
    result.u32(0x4654_6c67); result.u32(2); result.u32(UInt32(20 + jsonData.count)); result.u32(UInt32(jsonData.count)); result.u32(0x4e4f_534a); result.append(jsonData)
    return result
}

private func json(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
}

private func sha(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func assetRoot(_ root: URL, _ contentID: CharacterContentID) -> URL {
    let hex = String(contentID.rawValue.dropFirst("sha256:".count))
    return root.appendingPathComponent("Characters/Assets/v1/sha256/\(hex.prefix(2))/\(hex)", isDirectory: true)
}

private func children(_ url: URL) -> [URL] {
    (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
}

private func findSignature(_ signature: UInt32, in data: Data, from offset: Int) -> Int? {
    var needle = Data(); needle.u32(signature)
    return data.range(of: needle, options: [], in: offset..<data.count)?.lowerBound
}

private func readU16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
}

private func writeU32(_ value: UInt32, into data: inout Data, at offset: Int) {
    data[offset] = UInt8(value & 0xff); data[offset + 1] = UInt8((value >> 8) & 0xff)
    data[offset + 2] = UInt8((value >> 16) & 0xff); data[offset + 3] = UInt8((value >> 24) & 0xff)
}

private func writeU16(_ value: UInt16, into data: inout Data, at offset: Int) {
    data[offset] = UInt8(value & 0xff); data[offset + 1] = UInt8(value >> 8)
}

private extension Data {
    mutating func u16(_ value: UInt16) { append(UInt8(value & 0xff)); append(UInt8(value >> 8)) }
    mutating func u32(_ value: UInt32) { u16(UInt16(value & 0xffff)); u16(UInt16(value >> 16)) }
}

private func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffff_ffff
    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb8_8320 : crc >> 1 }
    }
    return crc ^ 0xffff_ffff
}

private extension XCTestCase {
    func XCTAssertThrowsPackageFailure(
        _ expected: CharacterPackageImportCode,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let failure as CharacterPackageImportFailure {
            XCTAssertEqual(failure.code, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}
