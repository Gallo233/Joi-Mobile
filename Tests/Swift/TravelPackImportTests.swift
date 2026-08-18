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

    /// Every refusal maps to copy that says the route is unchanged, so no
    /// failure can read as a partial import.
    func testEveryRefusalSaysTheRouteIsUnchanged() {
        let errors: [OfflinePackError] = [
            .missingFile("route.json"), .expired, .missingRights, .hashMismatch("x"),
            .undeclaredFile("x"), .invalidManifest, .unsupportedSchema, .activationFailed,
        ]
        for error in errors {
            XCTAssertTrue(
                AppModel.packFailureMessage(error).contains("当前路线没有变化"),
                "\(error) must promise the route is untouched"
            )
        }
    }
}

/// A valid pack on disk for the App-level path.
private struct AppPackFixture {
    let root: URL
    let candidate: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
