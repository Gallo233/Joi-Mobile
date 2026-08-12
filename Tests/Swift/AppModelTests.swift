import CharacterRuntime
import CompanionCore
import CryptoKit
import Foundation
import XCTest
@testable import JoiMobile

@MainActor
final class AppModelTests: XCTestCase {
    func testThreeImportInputsMapWithoutChangingSession() async {
        let model = AppModel()
        let before = await model.companionSession.current()
        let inputs = [
            ("character.joi-character", "joi"),
            ("character.vrm", "vrm"),
            ("live2d.zip", "live2d"),
        ]
        for (name, expected) in inputs {
            let url = URL(fileURLWithPath: "/tmp/" + name)
            guard let request = AppModel.importRequest(for: url) else { return XCTFail("Expected import request") }
            switch (request, expected) {
            case (.joiCharacterArchive, "joi"), (.rawVRM, "vrm"), (.live2DArchive, "live2d"): break
            default: XCTFail("Wrong import mapping")
            }
        }
        let after = await model.companionSession.current()
        XCTAssertEqual(before, after)
    }

    func testUnsupportedPreviewPreservesSelectionThreadSessionAndJourney() async {
        let model = AppModel()
        let before = await model.companionSession.current()
        let journey = await model.journeyContext.current()
        await model.previewCharacter(at: URL(fileURLWithPath: "/tmp/not-a-character.txt"))
        let after = await model.companionSession.current()
        let afterJourney = await model.journeyContext.current()
        XCTAssertEqual(before, after)
        XCTAssertEqual(journey, afterJourney)
        guard case .failed = model.characterLibraryState else { return XCTFail("Expected failure") }
    }

    func testCancelledOperationRejectsLateStateWrite() async {
        let model = AppModel()
        model.startPreview(at: URL(fileURLWithPath: "/tmp/not-a-character.txt"))
        model.cancelCharacterImport()
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(model.characterLibraryState, .cancelled)
    }

    func testChatMapProjectionUsesTheSessionSelectionProjection() async {
        let model = AppModel()
        let before = await model.companionSession.current()
        XCTAssertEqual(model.currentCharacterName, before.selection.displayName)
        model.select(.map)
        XCTAssertEqual(model.currentCharacterName, before.selection.displayName)
        model.select(.chat)
        XCTAssertEqual(model.currentCharacterName, before.selection.displayName)
    }

    func testCanonicalPackagePreviewInstallAndActivationPreserveSessionAndJourney() async throws {
        let fixture = try AppCharacterFixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.store)
        let model = AppModel(installer: installer)
        await model.companionSession.accept(eventID: "event-1")
        let route = AcceptedNavigationRoute(
            routeID: "route-1",
            coordinates: [GeoCoordinate(latitude: 31.23, longitude: 121.47)],
            cached: true
        )
        await model.journeyContext.begin(route: route, session: NavigationSessionID())
        let before = await model.companionSession.current()
        let journeyBefore = await model.journeyContext.current()

        await model.previewCharacter(at: fixture.archive)
        guard case .preview = model.characterLibraryState else {
            return XCTFail("Expected safe preview")
        }
        let afterPreview = await model.companionSession.current()
        XCTAssertEqual(afterPreview, before)

        model.startInstall()
        guard let installed = try await waitForInstalledState(model) else {
            return XCTFail("Expected durable installed state")
        }
        let afterInstall = await model.companionSession.current()
        XCTAssertEqual(afterInstall, before)

        model.startActivation(installed)
        let activated = try await waitUntil { model.currentCharacterName == "测试角色" }
        XCTAssertTrue(activated)
        let after = await model.companionSession.current()
        XCTAssertEqual(after.selection.installationID, installed.installationID)
        XCTAssertEqual(after.threadID, before.threadID)
        XCTAssertEqual(after.sessionID, before.sessionID)
        XCTAssertEqual(after.acceptedEventIDs, before.acceptedEventIDs)
        let journeyAfter = await model.journeyContext.current()
        XCTAssertEqual(journeyAfter, journeyBefore)
        XCTAssertEqual(model.currentCharacterName, after.selection.displayName)
        do {
            try await installer.remove(installed.installationID)
            XCTFail("Current activation lease must veto direct removal")
        } catch let failure as CharacterPackageImportFailure {
            XCTAssertEqual(failure.code, .inUse)
        }
    }

    func testActivationPublishesInstallerIssuedContentAccessForTheStage() async throws {
        let fixture = try AppCharacterFixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.store)
        let model = AppModel(installer: installer)
        XCTAssertNil(model.stageContent, "nothing is activated at launch")

        await model.previewCharacter(at: fixture.archive)
        model.startInstall()
        guard let installed = try await waitForInstalledState(model) else {
            return XCTFail("Expected durable installed state")
        }
        model.startActivation(installed)
        let published = try await waitUntil { model.stageContent != nil }
        XCTAssertTrue(published)

        let access = try XCTUnwrap(model.stageContent)
        // The stage must draw the character the session actually holds.
        let session = await model.companionSession.current()
        XCTAssertEqual(access.installationID, session.selection.installationID)
        XCTAssertEqual(access.contentID, session.selection.contentID)
        XCTAssertEqual(access.displayName, model.currentCharacterName)
        // Entry path comes from the verified manifest, not from a guess, and the
        // file it names must actually be readable inside the sealed tree.
        XCTAssertEqual(access.entryPath, "portrait.png")
        XCTAssertEqual(access.renderer, .static)
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: access.entryURL.path))
    }

    func testContentAccessIsRefusedForAStaleHandleAndClearedOnRemoval() async throws {
        let fixture = try AppCharacterFixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.store)
        let model = AppModel(installer: installer)
        await model.previewCharacter(at: fixture.archive)
        model.startInstall()
        guard let installed = try await waitForInstalledState(model) else {
            return XCTFail("Expected durable installed state")
        }

        // A handle whose lease was released must not still yield a content root.
        let handle = try await installer.prepareActivation(installed.installationID)
        await installer.releaseActivation(handle)
        do {
            _ = try await installer.contentAccess(for: handle)
            XCTFail("A released handle must not yield content access")
        } catch let failure as CharacterPackageImportFailure {
            XCTAssertEqual(failure.code, .staleHandle)
        }

        model.startActivation(installed)
        let published = try await waitUntil { model.stageContent != nil }
        XCTAssertTrue(published)
        // Switching away then removing must leave no stage content behind.
        model.startRemoval(
            CharacterPackageCatalogEntry(
                installationID: installed.installationID,
                contentID: installed.contentID,
                characterID: installed.manifest.characterID,
                displayName: installed.manifest.displayName,
                renderer: installed.manifest.renderer,
                available: true,
                activationAllowed: true
            )
        )
        // Removal of the active character is refused, so the stage keeps drawing.
        _ = try await waitUntil { if case .failed = model.characterLibraryState { true } else { false } }
        XCTAssertNotNil(model.stageContent)
    }

    func testActiveRemovalIsBlockedAndInactiveDuplicateCanBeRemoved() async throws {
        let fixture = try AppCharacterFixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.store)
        let model = AppModel(installer: installer)

        await model.previewCharacter(at: fixture.archive)
        model.startInstall()
        guard let first = try await waitForInstalledState(model) else { return XCTFail("Expected install") }
        model.startActivation(first)
        let activated = try await waitUntil { model.sessionSelection.installationID == first.installationID }
        XCTAssertTrue(activated)

        await model.previewCharacter(at: fixture.archive)
        model.startInstall()
        guard let second = try await waitForInstalledState(model), second.installationID != first.installationID else {
            return XCTFail("Expected a second installation")
        }
        await model.refreshInstalledCharacters()
        guard let active = model.installedCharacters.first(where: { $0.installationID == first.installationID }),
              let inactive = model.installedCharacters.first(where: { $0.installationID == second.installationID }) else {
            return XCTFail("Expected catalog entries")
        }

        model.startRemoval(active)
        let activeBlocked = try await waitUntil {
            if case .failed = model.characterLibraryState { return true }
            return false
        }
        XCTAssertTrue(activeBlocked)
        model.startRemoval(inactive)
        let removed = try await waitUntil {
            !model.installedCharacters.contains(where: { $0.installationID == inactive.installationID })
        }
        XCTAssertTrue(removed)
        XCTAssertEqual(model.sessionSelection.installationID, first.installationID)
    }

    func testFreshStoreSelectionBlocksRemovalDespiteStaleUIProjection() async throws {
        let fixture = try AppCharacterFixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.store)
        let model = AppModel(installer: installer)
        let first = try await install(fixture.archive, into: model)
        model.startActivation(first)
        let firstActivated = try await waitUntil {
            model.sessionSelection.installationID == first.installationID
        }
        XCTAssertTrue(firstActivated)
        let second = try await install(fixture.archive, into: model)

        let snapshot = await model.companionSession.current()
        let externallySelected = CharacterSelection(
            characterID: second.manifest.characterID,
            displayName: second.manifest.displayName,
            installationID: second.installationID,
            contentID: second.contentID
        )
        let externallyActivated = await model.companionSession.activate(selection: externallySelected, expecting: snapshot.selection)
        XCTAssertTrue(externallyActivated)
        XCTAssertEqual(model.sessionSelection.installationID, first.installationID) // deliberately stale UI projection
        await model.refreshInstalledCharacters()
        let entry = try XCTUnwrap(model.installedCharacters.first { $0.installationID == second.installationID })
        model.startRemoval(entry)
        let blocked = try await waitUntil {
            if case .failed = model.characterLibraryState { return true }
            return false
        }
        XCTAssertTrue(blocked)
        await model.refreshInstalledCharacters()
        XCTAssertNotNil(model.installedCharacters.first { $0.installationID == second.installationID })
    }

    func testSwitchReleasesPreviousLeaseSoOldInstallationCanBeRemoved() async throws {
        let fixture = try AppCharacterFixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.store)
        let model = AppModel(installer: installer)
        let first = try await install(fixture.archive, into: model)
        model.startActivation(first)
        let firstActivated = try await waitUntil {
            model.sessionSelection.installationID == first.installationID
        }
        XCTAssertTrue(firstActivated)
        let second = try await install(fixture.archive, into: model)
        model.startActivation(second)
        let secondActivated = try await waitUntil {
            model.sessionSelection.installationID == second.installationID
        }
        XCTAssertTrue(secondActivated)
        try await installer.remove(first.installationID)
        let entries = await installer.list()
        XCTAssertFalse(entries.contains { $0.installationID == first.installationID })
    }

    func testCancellationDuringRendererLoadReleasesLeaseWithoutSessionCommit() async throws {
        let fixture = try AppCharacterFixture()
        defer { fixture.cleanup() }
        let installer = CharacterPackageInstaller(root: fixture.store)
        let renderer = BlockingCharacterRenderer()
        let model = AppModel(installer: installer, renderer: renderer)
        let installed = try await install(fixture.archive, into: model)
        let before = await model.companionSession.current()

        model.startActivation(installed)
        await renderer.waitUntilLoadStarts()
        model.cancelCharacterImport()
        await renderer.finishLoad()
        var released = false
        for _ in 0..<300 {
            if await renderer.releaseCount() == 1 {
                released = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(released)
        let after = await model.companionSession.current()
        XCTAssertEqual(after, before)
        try await installer.remove(installed.installationID)
        let remaining = await installer.list()
        XCTAssertTrue(remaining.isEmpty)
    }

    private func install(_ archive: URL, into model: AppModel) async throws -> CharacterPackageInstallResult {
        await model.previewCharacter(at: archive)
        model.startInstall()
        let result = try await waitForInstalledState(model)
        return try XCTUnwrap(result)
    }

    private func waitForInstalledState(_ model: AppModel) async throws -> CharacterPackageInstallResult? {
        let reached = try await waitUntil {
            if case .installed = model.characterLibraryState { return true }
            if case .failed = model.characterLibraryState { return true }
            return false
        }
        guard reached, case let .installed(result) = model.characterLibraryState else { return nil }
        return result
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws -> Bool {
        for _ in 0..<300 {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private actor BlockingCharacterRenderer: CharacterRenderer {
    nonisolated let kind: CharacterRendererKind = .static
    private var loadStarted = false
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var releases = 0

    func load(
        _ package: ValidatedCharacterPackageHandle,
        generation: RendererGeneration
    ) async -> CharacterLoadResult {
        _ = generation
        loadStarted = true
        let waiters = loadWaiters
        loadWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            loadContinuation = continuation
        }
        return package.manifest.portraitPath == nil
            ? .bundledStaticJoi(reason: .portraitMissing)
            : .packagePortrait(reason: .runtimeUnavailable)
    }

    func waitUntilLoadStarts() async {
        if loadStarted { return }
        await withCheckedContinuation { continuation in
            loadWaiters.append(continuation)
        }
    }

    func finishLoad() {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func releaseCount() -> Int { releases }

    func apply(_ state: CharacterPresentationState, generation: RendererGeneration) async {
        _ = state
        _ = generation
    }

    func stop(generation: RendererGeneration) async { _ = generation }

    func release(generation: RendererGeneration) async {
        _ = generation
        releases += 1
    }
}

private struct AppCharacterFixture {
    let root: URL
    let store: URL
    let archive: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = root.appendingPathComponent("store", isDirectory: true)
        archive = root.appendingPathComponent("fixture.joi-character")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let hash = SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
        let manifest = try JSONSerialization.data(withJSONObject: [
            "schema": "joi.character.v1",
            "packageID": "fixture.app.static",
            "characterID": "fixture.app.character",
            "version": "1.0.0",
            "displayName": "测试角色",
            "renderer": "static",
            "entryPath": "portrait.png",
            "portraitPath": "portrait.png",
            "locales": ["zh-Hans"],
            "assets": [["path": "portrait.png", "mediaType": "image/png", "sha256": hash]],
            "provenance": ["author": "Joi Mobile test", "license": "Self-authored test fixture"],
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        try makeStoredZIP([("manifest.json", manifest), ("portrait.png", image)]).write(to: archive)
    }

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

private func makeStoredZIP(_ entries: [(String, Data)]) -> Data {
    var output = Data()
    var central = Data()
    var offset: UInt32 = 0
    for (path, body) in entries {
        let name = Data(path.utf8)
        let crc = appCRC32(body)
        let size = UInt32(body.count)
        output.appU32(0x0403_4b50); output.appU16(20); output.appU16(0); output.appU16(0)
        output.appU16(0); output.appU16(0); output.appU32(crc); output.appU32(size); output.appU32(size)
        output.appU16(UInt16(name.count)); output.appU16(0); output.append(name); output.append(body)
        central.appU32(0x0201_4b50); central.appU16(20); central.appU16(20); central.appU16(0); central.appU16(0)
        central.appU16(0); central.appU16(0); central.appU32(crc); central.appU32(size); central.appU32(size)
        central.appU16(UInt16(name.count)); central.appU16(0); central.appU16(0); central.appU16(0); central.appU16(0)
        central.appU32(0); central.appU32(offset); central.append(name)
        offset += UInt32(30 + name.count + body.count)
    }
    output.append(central)
    output.appU32(0x0605_4b50); output.appU16(0); output.appU16(0)
    output.appU16(UInt16(entries.count)); output.appU16(UInt16(entries.count))
    output.appU32(UInt32(central.count)); output.appU32(offset); output.appU16(0)
    return output
}

private func appCRC32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffff_ffff
    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb8_8320 : crc >> 1 }
    }
    return crc ^ 0xffff_ffff
}

private extension Data {
    mutating func appU16(_ value: UInt16) {
        append(UInt8(value & 0xff)); append(UInt8(value >> 8))
    }

    mutating func appU32(_ value: UInt32) {
        appU16(UInt16(value & 0xffff)); appU16(UInt16(value >> 16))
    }
}
