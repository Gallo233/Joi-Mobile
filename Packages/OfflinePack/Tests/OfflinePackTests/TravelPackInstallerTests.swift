import CompanionCore
import CryptoKit
import XCTest
@testable import OfflinePack

/// `G2-J4C` — importing a travel pack, and refusing the ones that are wrong.
///
/// `OfflinePackVerifier` checked a manifest's shape and nothing checked its
/// contents, so "a verified pack" meant a well-formed sentence about files
/// nobody had opened. `JM-P0-014` wants integrity, completeness and atomic
/// activation; `FAIL-025` and `FAIL-026` want missing content and invalid
/// content told apart, because one is a redownload and the other is a pack you
/// should not trust.
final class TravelPackInstallerTests: XCTestCase {
    /// The whole point, first: a good pack installs and yields a walkable tour.
    func testAWellFormedPackInstalls() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        let installer = TravelPackInstaller(root: fixture.store)

        let installed = try await installer.install(from: fixture.candidate)

        XCTAssertEqual(installed.packID, "pack.test")
        XCTAssertEqual(installed.version, "1.0.0")
        XCTAssertFalse(installed.rights.isEmpty, "a pack without rights is not installable")
        XCTAssertEqual(installed.stops.count, 2)
        XCTAssertEqual(installed.route.coordinates.count, 5)
        XCTAssertTrue(installed.route.cached, "a pack is cached content by definition")
        // Sealed under its own identity, inside the store.
        XCTAssertTrue(installed.rootURL.path.contains("pack.test@1.0.0"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.rootURL.appendingPathComponent("manifest.json").path))
    }

    /// And the tour it yields is the one the pack described.
    func testTheInstalledTourIsTheOneThePackDescribed() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        let installed = try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)

        let engine = try RouteProgressEngine(
            route: installed.route,
            configuration: RouteProgressConfiguration()
        )
        let narrative = try RouteNarrative(engine: engine, stops: installed.stops)
        XCTAssertEqual(narrative.stops.map(\.stop.stopID), ["pack.stop.start", "pack.stop.end"])

        let recap = narrative.recap(furthestProgress: 1)
        XCTAssertEqual(recap.count, 2)
        XCTAssertEqual(recap.filter(\.isFact).count, 1, "one sourced stop, one reflection")
    }

    /// `G2-J5J`: the pointer saved by the App is only a preference. A later
    /// process has to rebuild the walk from the sealed bytes and their checks.
    func testAnInstalledPackCanBeRestoredByItsExactIdentity() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        _ = try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)

        let restored = try await TravelPackInstaller(root: fixture.store).restore(
            packID: "pack.test",
            version: "1.0.0"
        )

        XCTAssertEqual(restored.title, "测试路线包")
        XCTAssertEqual(restored.stops.count, 2)
        XCTAssertTrue(restored.route.cached)
    }

    /// A pack changed after installation is not restored merely because its
    /// identity still has a directory in the store.
    func testRestoreRechecksTheSealedHashes() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        let installed = try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)
        try Data("tampered after install".utf8).write(
            to: installed.rootURL.appendingPathComponent("route.json")
        )

        await Self.assertThrows(.hashMismatch("route.json")) {
            try await TravelPackInstaller(root: fixture.store).restore(
                packID: "pack.test",
                version: "1.0.0"
            )
        }
    }

    /// Restore also repeats the negative half of integrity: a valid hash list
    /// cannot make an undeclared payload trusted.
    func testRestoreRefusesContentAddedAfterInstallation() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        let installed = try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)
        try Data("not declared".utf8).write(
            to: installed.rootURL.appendingPathComponent("added-after-install.txt")
        )

        await Self.assertThrows(.undeclaredFile("added-after-install.txt")) {
            try await TravelPackInstaller(root: fixture.store).restore(
                packID: "pack.test",
                version: "1.0.0"
            )
        }
    }

    /// Both strings become one directory component. Non-empty is not enough:
    /// traversal in either value would put the sealed tree outside `packs/`.
    func testStoreIdentityCannotContainAPath() async throws {
        for (packID, version) in [("../../escaped", "1.0.0"), ("pack.test", "../escaped")] {
            let fixture = try PackFixture(packID: packID, version: version)
            defer { fixture.cleanup() }

            await Self.assertThrows(.invalidManifest) {
                try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)
            }
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("escaped@1.0.0").path)
            )
        }
    }

    /// A lexical prefix is not a filesystem boundary. `candidate-escape` used
    /// to pass the `hasPrefix(candidate)` check and let an un-hashed route file
    /// supply the walk through a symlink.
    func testASymlinkToASiblingWithTheSamePrefixIsOutsideThePack() async throws {
        let fixture = try PackFixture(routePath: "linked/route.json")
        defer { fixture.cleanup() }
        let sibling = fixture.root.appendingPathComponent("candidate-escape", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: fixture.candidate.appendingPathComponent("route.json"),
            to: sibling.appendingPathComponent("route.json")
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.candidate.appendingPathComponent("linked"),
            withDestinationURL: sibling
        )

        await Self.assertThrows(.unsupportedEntry("linked/route.json")) {
            try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)
        }
    }

    // MARK: - What the store holds

    /// A pack installed in one session is still listed by a later one.
    ///
    /// This is what an export has to ask (`JM-P0-023`). The App's own
    /// `installedPack` is only the active one, so an inventory built from it
    /// would omit other identities the device is holding.
    func testAnInstalledPackIsListedByALaterInstallerOverTheSameStore() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        _ = try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)

        let listed = await TravelPackInstaller(root: fixture.store).installed()

        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.packID, "pack.test")
        XCTAssertEqual(listed.first?.version, "1.0.0")
        XCTAssertEqual(listed.first?.title, "测试路线包")
        XCTAssertFalse(listed.first?.rights.isEmpty ?? true, "rights travel with the inventory")
    }

    /// An empty store lists nothing, and does not fail for want of a directory.
    func testAnEmptyStoreListsNothing() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        let listed = await TravelPackInstaller(root: fixture.store).installed()
        XCTAssertEqual(listed, [])
    }

    /// A pack whose content no longer decodes is still installed, so it is still
    /// listed — without a title, rather than not at all.
    func testAPackWithUnreadableContentIsStillListed() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        let installed = try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)
        try Data("{".utf8).write(to: installed.rootURL.appendingPathComponent("route.json"))

        let listed = await TravelPackInstaller(root: fixture.store).installed()

        XCTAssertEqual(listed.first?.packID, "pack.test")
        XCTAssertNil(listed.first?.title)
    }

    // MARK: - FAIL-025 offlinePackMissing

    func testADeclaredFileThatIsNotThereIsMissingRatherThanInvalid() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(at: fixture.candidate.appendingPathComponent("route.json"))

        await Self.assertThrows(.missingFile("route.json")) {
            try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)
        }
    }

    func testAPackWithNoManifestIsMissingIt() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(at: fixture.candidate.appendingPathComponent("manifest.json"))

        await Self.assertThrows(.missingFile("manifest.json")) {
            try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)
        }
    }

    // MARK: - FAIL-026 offlinePackInvalid

    func testAFileThatDoesNotMatchItsHashIsRefused() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        try Data("tampered".utf8).write(to: fixture.candidate.appendingPathComponent("notes.txt"))

        await Self.assertThrows(.hashMismatch("notes.txt")) {
            try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)
        }
    }

    /// A pack ships what it declares and nothing else. A hash list proves the
    /// content it covers and says nothing about content nobody declared.
    func testUndeclaredContentIsRefused() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        try Data("smuggled".utf8).write(to: fixture.candidate.appendingPathComponent("extra.bin"))

        await Self.assertThrows(.undeclaredFile("extra.bin")) {
            try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)
        }
    }

    func testAPathThatReachesOutsideThePackIsRefused() async throws {
        for path in ["../escape.json", "/etc/passwd", "a\\b.json", "sub/../../out.json"] {
            let fixture = try PackFixture(routePath: path)
            defer { fixture.cleanup() }
            await Self.assertThrowsUnsupportedEntry {
                try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)
            }
        }
    }

    func testAPackWithoutRightsIsRefused() async throws {
        let fixture = try PackFixture(rights: [])
        defer { fixture.cleanup() }
        await Self.assertThrows(.missingRights) {
            try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)
        }
    }

    func testAnExpiredPackIsRefused() async throws {
        let fixture = try PackFixture(expiresAt: Date(timeIntervalSince1970: 1))
        defer { fixture.cleanup() }
        await Self.assertThrows(.expired) {
            try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)
        }
    }

    func testAnUnknownSchemaIsRefused() async throws {
        let fixture = try PackFixture(schema: "joi.travel-pack.v99")
        defer { fixture.cleanup() }
        await Self.assertThrows(.unsupportedSchema) {
            try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)
        }
    }

    func testAMalformedManifestIsRefused() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        try Data("{ not json".utf8).write(to: fixture.candidate.appendingPathComponent("manifest.json"))
        await Self.assertThrows(.invalidManifest) {
            try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)
        }
    }

    /// A stop that is not on its own route is a broken pack, and the refusal
    /// comes from `RouteNarrative` rather than being re-implemented here.
    func testAPackWhoseStopIsNotOnItsRouteIsRefused() async throws {
        let fixture = try PackFixture(strayStop: true)
        defer { fixture.cleanup() }

        do {
            _ = try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)
            XCTFail("a stop off the route must not install")
        } catch let error as OfflinePackError {
            guard case .stopOffRoute = error else {
                return XCTFail("expected stopOffRoute, got \(error)")
            }
        }
    }

    // MARK: - FAIL-029 storageInsufficient

    /// A pack the device cannot hold is refused **through `install`**, before
    /// anything is copied, with both numbers.
    ///
    /// Driven by what the volume reports rather than by filling the disk. The
    /// first version of this test called the space check directly, which left
    /// the call site inside `install` untested — deleting it passed the whole
    /// suite. Going through `install` is the point.
    func testAPackTooLargeForTheDeviceIsRefusedWithBothNumbers() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        let installer = TravelPackInstaller(root: fixture.store, availableBytes: { _ in 4_096 })

        do {
            _ = try await installer.install(from: fixture.candidate)
            XCTFail("a pack larger than the volume must be refused")
        } catch let error as OfflinePackError {
            guard case let .storageInsufficient(required, available) = error else {
                return XCTFail("expected storageInsufficient, got \(error)")
            }
            XCTAssertEqual(available, 4_096)
            XCTAssertGreaterThan(required, available)
            XCTAssertGreaterThanOrEqual(
                required,
                TravelPackInstaller.storageMarginBytes,
                "the requirement includes the pack's own bytes plus the margin"
            )
        }

        // Refused before copying: nothing reached the store.
        let packs = fixture.store.appendingPathComponent("packs", isDirectory: true)
        XCTAssertTrue(
            ((try? FileManager.default.contentsOfDirectory(atPath: packs.path)) ?? []).isEmpty,
            "a space refusal must not leave a pack behind"
        )
    }

    /// A volume with room installs normally, so the check cannot be satisfied by
    /// refusing everything.
    func testAPackThatFitsIsNotRefusedForSpace() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        let installer = TravelPackInstaller(root: fixture.store, availableBytes: { _ in 1 << 40 })
        _ = try await installer.install(from: fixture.candidate)
    }

    /// A volume that declines to report capacity is treated as having room:
    /// refusing an import because the filesystem would not answer would fail
    /// closed on the wrong thing.
    func testAVolumeThatCannotReportCapacityDoesNotBlockTheImport() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        let installer = TravelPackInstaller(root: fixture.store, availableBytes: { _ in nil })
        _ = try await installer.install(from: fixture.candidate)
    }

    /// The check runs before anything is copied, so a completed install leaves
    /// no staging directory behind either.
    func testAnInstallLeavesNoStagingBehind() async throws {
        let fixture = try PackFixture()
        defer { fixture.cleanup() }
        _ = try await TravelPackInstaller(root: fixture.store).install(from: fixture.candidate)

        let staging = fixture.store.appendingPathComponent("staging", isDirectory: true)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []
        XCTAssertTrue(leftovers.isEmpty, "staging must not accumulate: \(leftovers)")
    }

    // MARK: - Nothing is disturbed by a refusal

    /// `FAIL-026`: "keep last valid version". A refused candidate must not touch
    /// the pack already installed.
    func testARefusedPackLeavesTheInstalledOneUntouched() async throws {
        let good = try PackFixture()
        defer { good.cleanup() }
        let installer = TravelPackInstaller(root: good.store)
        let installed = try await installer.install(from: good.candidate)
        let sealedManifest = installed.rootURL.appendingPathComponent("manifest.json")
        let before = try Data(contentsOf: sealedManifest)

        // A second candidate under the same identity, but tampered.
        let bad = try PackFixture(store: good.store)
        defer { bad.cleanup() }
        try Data("tampered".utf8).write(to: bad.candidate.appendingPathComponent("notes.txt"))
        await Self.assertThrows(.hashMismatch("notes.txt")) {
            try await installer.install(from: bad.candidate)
        }

        let after = try Data(contentsOf: sealedManifest)
        XCTAssertEqual(before, after, "the installed pack is untouched by a refused candidate")
    }

    /// Reinstalling the same identity replaces it in place and stays valid,
    /// which is the path a version bump takes.
    func testReinstallingTheSameIdentitySucceedsAndStaysVerified() async throws {
        let first = try PackFixture()
        defer { first.cleanup() }
        let installer = TravelPackInstaller(root: first.store)
        _ = try await installer.install(from: first.candidate)

        let again = try PackFixture(store: first.store)
        defer { again.cleanup() }
        let reinstalled = try await installer.install(from: again.candidate)

        XCTAssertEqual(reinstalled.packID, "pack.test")
        XCTAssertEqual(try Self.sha256OfFile(reinstalled.rootURL.appendingPathComponent("notes.txt")),
                       try Self.sha256OfFile(again.candidate.appendingPathComponent("notes.txt")))
    }

    // MARK: - Helpers

    private static func assertThrows(
        _ expected: OfflinePackError,
        _ work: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await work()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as OfflinePackError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }

    private static func assertThrowsUnsupportedEntry(
        _ work: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await work()
            XCTFail("expected a refused path", file: file, line: line)
        } catch let error as OfflinePackError {
            switch error {
            case .unsupportedEntry, .missingFile: break
            default: XCTFail("expected a path refusal, got \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }

    private static func sha256OfFile(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
}

/// A complete, valid pack on disk, with knobs for the ways one can be wrong.
private struct PackFixture {
    let root: URL
    let store: URL
    let candidate: URL

    init(
        store: URL? = nil,
        schema: String = "joi.travel-pack.v1",
        packID: String = "pack.test",
        version: String = "1.0.0",
        rights: [String] = ["Repository-authored test fixture"],
        expiresAt: Date? = nil,
        routePath: String = "route.json",
        strayStop: Bool = false
    ) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.store = store ?? root.appendingPathComponent("store", isDirectory: true)
        candidate = root.appendingPathComponent("candidate", isDirectory: true)
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)

        let coordinates: [[String: Double]] = [
            ["latitude": 31.2304, "longitude": 121.4737],
            ["latitude": 31.2312, "longitude": 121.4749],
            ["latitude": 31.2325, "longitude": 121.4761],
            ["latitude": 31.2338, "longitude": 121.4770],
            ["latitude": 31.2351, "longitude": 121.4776],
        ]
        let endStop: [String: Any] = strayStop
            ? ["stopID": "pack.stop.end", "name": "不在路线上", "latitude": 999.0, "longitude": 999.0,
               "narration": "……", "sourceRevisionIDs": [], "suggestedDurationSeconds": 60.0]
            : ["stopID": "pack.stop.end", "name": "终点", "latitude": 31.2351, "longitude": 121.4776,
               "narration": "走到这里就完了。", "sourceRevisionIDs": [], "suggestedDurationSeconds": 60.0]

        let content: [String: Any] = [
            "schema": "joi.travel-pack-content.v1",
            "routeID": "pack.route",
            "title": "测试路线包",
            "coordinates": coordinates,
            "stops": [
                ["stopID": "pack.stop.start", "name": "起点", "latitude": 31.2304, "longitude": 121.4737,
                 "narration": "这段堤岸建于二十世纪初。",
                 "sourceRevisionIDs": ["fixture://sources/test@2026-08-18"],
                 "suggestedDurationSeconds": 120.0],
                endStop,
            ],
        ]
        let contentData = try JSONSerialization.data(withJSONObject: content, options: [.sortedKeys])
        let notesData = Data("测试备注".utf8)

        // The route file is written at its real name even when `routePath`
        // points somewhere illegal, so the path check is what refuses it rather
        // than the file simply being absent.
        try contentData.write(to: candidate.appendingPathComponent("route.json"))
        try notesData.write(to: candidate.appendingPathComponent("notes.txt"))

        var manifest: [String: Any] = [
            "schema": schema,
            "packID": packID,
            "routeID": "pack.route",
            "version": version,
            "locales": ["zh-Hans"],
            "routePath": routePath,
            "files": [
                ["path": "route.json", "sha256": Self.hash(contentData), "mediaType": "application/json"],
                ["path": "notes.txt", "sha256": Self.hash(notesData), "mediaType": "text/plain"],
            ],
            "sourceRevisionIDs": ["fixture://sources/test@2026-08-18"],
            "rights": rights,
            "createdAt": "2026-08-18T00:00:00Z",
        ]
        if let expiresAt {
            manifest["expiresAt"] = ISO8601DateFormatter().string(from: expiresAt)
        }
        try JSONSerialization
            .data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: candidate.appendingPathComponent("manifest.json"))
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
