import CompanionCore
import CryptoKit
import Foundation
import OfflinePack
import XCTest
@testable import JoiMobile

/// `G2-J4C` at the App boundary.
///
/// `TravelPackInstallerTests` covers verification and refusal. These cover what
/// the App does with the result: that a verified pack becomes the walk, that a
/// refused one changes nothing, and that the route cannot be swapped out from
/// under a walk in progress.
@MainActor
final class TravelPackImportTests: XCTestCase {
    /// The installed pack is durable, while route progress and location are not.
    func testTheLastVerifiedPackReturnsAfterRelaunchWithoutStartingLocation() async throws {
        let fixture = try AppPackFixture()
        defer { fixture.cleanup() }
        let defaults = Self.emptyDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let first = AppModel(
            packInstaller: TravelPackInstaller(root: fixture.store),
            defaults: defaults
        )
        await first.importTravelPack(at: fixture.candidate)
        let imported = try XCTUnwrap(first.installedPack, first.packImportMessage ?? "no message")

        let relaunched = AppModel(
            packInstaller: TravelPackInstaller(root: fixture.store),
            defaults: defaults
        )
        await relaunched.restoreActiveTravelPack()

        XCTAssertEqual(relaunched.installedPack?.packID, imported.packID)
        XCTAssertEqual(relaunched.installedPack?.version, imported.version)
        XCTAssertEqual(relaunched.walk.title, imported.title)
        XCTAssertFalse(relaunched.isWalking)
        XCTAssertNil(relaunched.walkSession)
        XCTAssertNil(relaunched.walkLocation.latest)
        XCTAssertNil(relaunched.packImportMessage, "a successful restore is not a new import")
    }

    /// The saved pointer cannot bless bytes changed after installation.
    func testATamperedSavedPackFallsBackOnceAndClearsItsPointer() async throws {
        let fixture = try AppPackFixture()
        defer { fixture.cleanup() }
        let defaults = Self.emptyDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let first = AppModel(
            packInstaller: TravelPackInstaller(root: fixture.store),
            defaults: defaults
        )
        await first.importTravelPack(at: fixture.candidate)
        let installed = try XCTUnwrap(first.installedPack)
        try Data("changed after install".utf8).write(
            to: installed.rootURL.appendingPathComponent("notes.txt")
        )

        let relaunched = AppModel(
            packInstaller: TravelPackInstaller(root: fixture.store),
            defaults: defaults
        )
        let sampleTitle = relaunched.walk.title
        await relaunched.restoreActiveTravelPack()

        XCTAssertNil(relaunched.installedPack)
        XCTAssertEqual(relaunched.walk.title, sampleTitle)
        XCTAssertTrue(relaunched.packImportMessage?.contains("已不可用") == true)
        XCTAssertNil(defaults.data(forKey: AppModel.activeTravelPackKey))
        XCTAssertFalse(relaunched.isWalking)

        relaunched.acknowledgePackMessage()
        await relaunched.restoreActiveTravelPack()
        XCTAssertNil(relaunched.packImportMessage, "a cleared pointer does not fail every launch")
    }

    /// A verified pack becomes the walk, and the surface stops calling itself a
    /// sample.
    func testAVerifiedPackBecomesTheWalk() async throws {
        let fixture = try AppPackFixture()
        defer { fixture.cleanup() }
        let model = AppModel()
        XCTAssertNil(model.installedPack, "the bundled sample is not a pack")
        let sampleTitle = model.walk.title

        await model.importTravelPack(at: fixture.candidate)

        let installed = try XCTUnwrap(model.installedPack, model.packImportMessage ?? "no message")
        XCTAssertEqual(installed.packID, "pack.app.test")
        XCTAssertNotEqual(model.walk.title, sampleTitle, "the walk is the pack's tour now")
        XCTAssertEqual(model.walk.narrative.stops.count, 2)
        XCTAssertFalse(installed.rights.isEmpty)
    }

    /// The pack's story is the one that gets walked, including its sources.
    func testThePacksOwnStoryIsWhatTheWalkTells() async throws {
        let fixture = try AppPackFixture()
        defer { fixture.cleanup() }
        let model = AppModel()
        await model.importTravelPack(at: fixture.candidate)
        XCTAssertNotNil(model.installedPack, model.packImportMessage ?? "no message")

        model.startWalk()
        let session = try XCTUnwrap(model.walkSession)
        let end = try XCTUnwrap(model.walk.route.coordinates.last)
        model.advanceWalk(
            with: LocationObservation(coordinate: end, horizontalAccuracyMeters: 5, observedAt: Date()),
            session: session
        )

        XCTAssertTrue(model.narrativeState.isComplete)
        let recap = model.walkRecap
        XCTAssertEqual(recap.count, 2)
        XCTAssertEqual(recap.filter(\.isFact).count, 1, "the pack's sourced stop is a fact")
    }

    /// `FAIL-026` — a refused pack changes nothing, and says why in a way that
    /// distinguishes it from missing content.
    func testARefusedPackLeavesTheWalkAlone() async throws {
        let fixture = try AppPackFixture()
        defer { fixture.cleanup() }
        try Data("tampered".utf8).write(to: fixture.candidate.appendingPathComponent("notes.txt"))
        let model = AppModel()
        let before = model.walk.title

        await model.importTravelPack(at: fixture.candidate)

        XCTAssertNil(model.installedPack)
        XCTAssertEqual(model.walk.title, before, "a refused pack does not touch the current route")
        let message = try XCTUnwrap(model.packImportMessage)
        XCTAssertTrue(message.contains("没有通过校验"), message)
    }

    /// `FAIL-025` — missing content reads differently from invalid content,
    /// because one is worth fetching again and the other is not.
    func testMissingContentAndInvalidContentReadDifferently() async throws {
        let fixture = try AppPackFixture()
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(at: fixture.candidate.appendingPathComponent("route.json"))
        let model = AppModel()

        await model.importTravelPack(at: fixture.candidate)

        let message = try XCTUnwrap(model.packImportMessage)
        XCTAssertTrue(message.contains("缺少"), message)
        XCTAssertNotEqual(message, AppModel.packFailureMessage(OfflinePackError.hashMismatch("x")))
    }

    /// The route cannot be swapped under a walk in progress: its progress, its
    /// journey snapshot and its story would all be invalidated at once.
    func testAPackCannotBeImportedDuringAWalk() async throws {
        let fixture = try AppPackFixture()
        defer { fixture.cleanup() }
        let model = AppModel()
        model.startWalk()
        let before = model.walk.title

        await model.importTravelPack(at: fixture.candidate)

        XCTAssertNil(model.installedPack)
        XCTAssertEqual(model.walk.title, before)
        XCTAssertEqual(model.packImportMessage, "步行进行中，先结束再导入路线包。")
    }

    /// The store may hold several verified tours. Listing does not activate
    /// one, while choosing an exact identity re-verifies and remembers it.
    func testAnInstalledRouteCanBeSelectedAndReturnsAfterRelaunch() async throws {
        let fixture = try AppPackFixture()
        defer { fixture.cleanup() }
        let defaults = Self.emptyDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let model = AppModel(
            packInstaller: TravelPackInstaller(root: fixture.store),
            defaults: defaults
        )
        await model.importTravelPack(at: fixture.candidate)
        let other = try makeAlternativeCandidate(in: fixture)
        await model.importTravelPack(at: other)

        await model.refreshInstalledTravelPacks()
        XCTAssertEqual(model.installedTravelPacks.map(\.packID), ["pack.app.other", "pack.app.test"])

        let selected = await model.selectInstalledTravelPack(
            packID: "pack.app.test",
            version: "1.0.0"
        )
        XCTAssertTrue(selected, model.packImportMessage ?? "selection failed without a message")
        XCTAssertEqual(model.installedPack?.packID, "pack.app.test")
        XCTAssertEqual(model.walk.title, "导入的测试路线")

        let relaunched = AppModel(
            packInstaller: TravelPackInstaller(root: fixture.store),
            defaults: defaults
        )
        await relaunched.restoreActiveTravelPack()
        XCTAssertEqual(relaunched.installedPack?.packID, "pack.app.test")
        XCTAssertEqual(relaunched.walk.title, "导入的测试路线")
    }

    /// An inventory row is not authority. If bytes changed after listing, the
    /// exact restore fails and the route already on screen stays byte-for-byte.
    func testATamperedListedRouteCannotReplaceTheCurrentRoute() async throws {
        let fixture = try AppPackFixture()
        defer { fixture.cleanup() }
        let model = AppModel(packInstaller: TravelPackInstaller(root: fixture.store))
        await model.importTravelPack(at: fixture.candidate)
        let first = try XCTUnwrap(model.installedPack)
        let other = try makeAlternativeCandidate(in: fixture)
        await model.importTravelPack(at: other)
        let beforeID = try XCTUnwrap(model.installedPack?.packID)
        let beforeRoute = model.walk.route

        try Data("changed after listing".utf8).write(
            to: first.rootURL.appendingPathComponent("notes.txt")
        )
        await model.refreshInstalledTravelPacks()
        XCTAssertTrue(model.installedTravelPacks.contains { $0.packID == first.packID })

        let selected = await model.selectInstalledTravelPack(
            packID: first.packID,
            version: first.version
        )
        XCTAssertFalse(selected)
        XCTAssertEqual(model.installedPack?.packID, beforeID)
        XCTAssertEqual(model.walk.route, beforeRoute)
        XCTAssertTrue(model.packImportMessage?.contains("没有通过校验") == true)
    }

    /// Returning to the explicitly labelled sample leaves downloads installed,
    /// but clears the active pointer so a relaunch cannot silently switch back.
    func testTheBundledSampleCanBeSelectedAndClearsTheActivePointer() async throws {
        let fixture = try AppPackFixture()
        defer { fixture.cleanup() }
        let defaults = Self.emptyDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let model = AppModel(
            packInstaller: TravelPackInstaller(root: fixture.store),
            defaults: defaults
        )
        await model.importTravelPack(at: fixture.candidate)

        let selected = await model.selectBundledSampleWalk()
        XCTAssertTrue(selected)
        XCTAssertNil(model.installedPack)
        XCTAssertEqual(model.walk.route.routeID, CachedWalk.sample.route.routeID)
        XCTAssertNil(defaults.data(forKey: AppModel.activeTravelPackKey))
        await model.refreshInstalledTravelPacks()
        XCTAssertEqual(model.installedTravelPacks.count, 1, "selection does not delete the installed pack")

        let relaunched = AppModel(
            packInstaller: TravelPackInstaller(root: fixture.store),
            defaults: defaults
        )
        await relaunched.restoreActiveTravelPack()
        XCTAssertNil(relaunched.installedPack)
        XCTAssertEqual(relaunched.walk.route.routeID, CachedWalk.sample.route.routeID)
        XCTAssertNil(relaunched.packImportMessage)
    }

    /// Route selection has the same task boundary as import: never swap the
    /// progress engine or narrative underneath an active journey.
    func testAnInstalledRouteCannotBeSelectedDuringAWalk() async throws {
        let fixture = try AppPackFixture()
        defer { fixture.cleanup() }
        let model = AppModel(packInstaller: TravelPackInstaller(root: fixture.store))
        await model.importTravelPack(at: fixture.candidate)
        let other = try makeAlternativeCandidate(in: fixture)
        await model.importTravelPack(at: other)
        let before = try XCTUnwrap(model.installedPack?.packID)
        model.startWalk()

        let selected = await model.selectInstalledTravelPack(
            packID: "pack.app.test",
            version: "1.0.0"
        )

        XCTAssertFalse(selected)
        XCTAssertEqual(model.installedPack?.packID, before)
        XCTAssertEqual(model.packImportMessage, "步行进行中，先结束再切换文化路线。")
        model.stopWalk()
    }

    /// `FAIL-029` — a space refusal names both numbers, because "not enough
    /// space" alone tells the user nothing they can act on.
    func testAStorageRefusalNamesRequiredAndAvailable() {
        let message = AppModel.packFailureMessage(
            OfflinePackError.storageInsufficient(
                requiredBytes: 12 * 1_024 * 1_024,
                availableBytes: 3 * 1_024 * 1_024
            )
        )
        XCTAssertTrue(message.contains("12"), message)
        XCTAssertTrue(message.contains("3"), message)
        XCTAssertTrue(message.contains("当前路线没有变化"), message)
    }

    /// Rounded up, so a refusal never claims to need zero megabytes.
    func testASmallRequirementStillReadsAsAtLeastOneMegabyte() {
        XCTAssertEqual(AppModel.megabytes(1), 1)
        XCTAssertEqual(AppModel.megabytes(0), 0)
        XCTAssertEqual(AppModel.megabytes(1_024 * 1_024), 1)
        XCTAssertEqual(AppModel.megabytes(1_024 * 1_024 + 1), 2)
    }

    /// Every refusal maps to copy that says the route is unchanged, so no
    /// failure can read as a partial import.
    func testEveryRefusalSaysTheRouteIsUnchanged() {
        let errors: [OfflinePackError] = [
            .missingFile("route.json"), .expired, .missingRights, .hashMismatch("x"),
            .undeclaredFile("x"), .invalidManifest, .unsupportedSchema, .activationFailed,
            .storageInsufficient(requiredBytes: 1, availableBytes: 0),
        ]
        for error in errors {
            XCTAssertTrue(
                AppModel.packFailureMessage(error).contains("当前路线没有变化"),
                "\(error) must promise the route is untouched"
            )
        }
    }

    private static func emptyDefaults() -> UserDefaults {
        let suite = "TravelPackImportTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(suite, forKey: "test.suite-name")
        return defaults
    }

    private func defaultsSuite(_ defaults: UserDefaults) -> String {
        defaults.string(forKey: "test.suite-name")!
    }

    private func makeAlternativeCandidate(in fixture: AppPackFixture) throws -> URL {
        let candidate = fixture.root.appendingPathComponent("candidate-other", isDirectory: true)
        try FileManager.default.copyItem(at: fixture.candidate, to: candidate)

        let routeURL = candidate.appendingPathComponent("route.json")
        var route = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: routeURL)) as? [String: Any]
        )
        route["routeID"] = "pack.app.other.route"
        route["title"] = "另一条已安装路线"
        let routeData = try JSONSerialization.data(withJSONObject: route, options: [.sortedKeys])
        try routeData.write(to: routeURL)

        let manifestURL = candidate.appendingPathComponent("manifest.json")
        var manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        manifest["packID"] = "pack.app.other"
        manifest["routeID"] = "pack.app.other.route"
        manifest["version"] = "2.0.0"
        var files = try XCTUnwrap(manifest["files"] as? [[String: Any]])
        let routeIndex = try XCTUnwrap(files.firstIndex { $0["path"] as? String == "route.json" })
        files[routeIndex]["sha256"] = SHA256.hash(data: routeData)
            .map { String(format: "%02x", $0) }
            .joined()
        manifest["files"] = files
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: manifestURL)
        return candidate
    }
}

/// A valid pack on disk for the App-level path.
private struct AppPackFixture {
    let root: URL
    let store: URL
    let candidate: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = root.appendingPathComponent("store", isDirectory: true)
        candidate = root.appendingPathComponent("candidate", isDirectory: true)
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)

        let content: [String: Any] = [
            "schema": "joi.travel-pack-content.v1",
            "routeID": "pack.app.route",
            "title": "导入的测试路线",
            "coordinates": [
                ["latitude": 31.2304, "longitude": 121.4737],
                ["latitude": 31.2325, "longitude": 121.4761],
                ["latitude": 31.2351, "longitude": 121.4776],
            ],
            "stops": [
                ["stopID": "app.stop.start", "name": "起点", "latitude": 31.2304, "longitude": 121.4737,
                 "narration": "这段堤岸建于二十世纪初。",
                 "sourceRevisionIDs": ["fixture://sources/app@2026-08-18"],
                 "suggestedDurationSeconds": 120.0],
                ["stopID": "app.stop.end", "name": "终点", "latitude": 31.2351, "longitude": 121.4776,
                 "narration": "走到这里，江面就宽了。",
                 "sourceRevisionIDs": [], "suggestedDurationSeconds": 60.0],
            ],
        ]
        let contentData = try JSONSerialization.data(withJSONObject: content, options: [.sortedKeys])
        let notesData = Data("备注".utf8)
        try contentData.write(to: candidate.appendingPathComponent("route.json"))
        try notesData.write(to: candidate.appendingPathComponent("notes.txt"))

        let manifest: [String: Any] = [
            "schema": "joi.travel-pack.v1",
            "packID": "pack.app.test",
            "routeID": "pack.app.route",
            "version": "1.0.0",
            "locales": ["zh-Hans"],
            "routePath": "route.json",
            "files": [
                ["path": "route.json", "sha256": Self.hash(contentData), "mediaType": "application/json"],
                ["path": "notes.txt", "sha256": Self.hash(notesData), "mediaType": "text/plain"],
            ],
            "sourceRevisionIDs": ["fixture://sources/app@2026-08-18"],
            "rights": ["Repository-authored test fixture"],
            "createdAt": "2026-08-18T00:00:00Z",
        ]
        try JSONSerialization
            .data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: candidate.appendingPathComponent("manifest.json"))
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
