import CharacterRuntime
import CompanionCore
import CryptoKit
import Foundation
import OfflinePack
import XCTest
@testable import JoiMobile

/// `G2-J5I` — the local half of `JM-P0-023`.
///
/// PRD §6.4 has required an export that "distinguishes packages, conversations,
/// memory, travel history and account data" since G0, and TDD §4.1 has named
/// `DataExportRequestV1/ResultV1` for just as long. Nothing existed behind
/// either: Settings said 导出尚未实现, `MemoryRepository` was missing the
/// `export` its own contract line lists, and `FAIL-029` recorded that export did
/// not exist at all.
///
/// Two properties carry most of this suite. An export must be able to say that a
/// category is *absent from the product* rather than *empty for this user*, and
/// an export must not claim to have produced a file it cannot read back.
@MainActor
final class DataExportTests: XCTestCase {

    // MARK: - What a document says

    /// Every category PRD §6.4 names, exactly once, whatever the device holds.
    func testEveryCategoryAppearsExactlyOnce() {
        let document = Self.document()
        XCTAssertEqual(document.sections.map(\.category), DataCategory.allCases)
        XCTAssertEqual(Set(document.sections.map(\.category)).count, DataCategory.allCases.count)
    }

    /// The distinction the coverage type exists for.
    ///
    /// An empty array under `account` would read as "you have no account data",
    /// a claim about the user. The truth is "this build has no accounts", a
    /// claim about the app. An export that cannot tell those apart misinforms
    /// the person it was made for.
    func testAnAbsentFeatureIsNotReportedAsEmptyUserData() throws {
        let document = Self.document()

        let account = try XCTUnwrap(document.sections.first { $0.category == .account })
        guard case let .unavailable(reason) = account.coverage else {
            return XCTFail("account is unavailable in this build, not empty: \(account.coverage)")
        }
        XCTAssertFalse(reason.isEmpty, "an unavailable category has to say why")

        let travel = try XCTUnwrap(document.sections.first { $0.category == .travelHistory })
        guard case .unavailable = travel.coverage else {
            return XCTFail("nothing records where the walk went: \(travel.coverage)")
        }

        // And the other direction: a feature that exists and holds nothing.
        let memory = try XCTUnwrap(document.sections.first { $0.category == .memory })
        XCTAssertEqual(memory.coverage, .empty)
        XCTAssertNotEqual(memory.coverage, account.coverage)
    }

    /// Export is the whole store, not the current relationship.
    ///
    /// `list(characterID:)` cannot answer this: the caller would have to already
    /// know every character that ever existed, and a record whose character was
    /// removed — memory deliberately outlives its character, DEC-002 — would be
    /// invisible to an export while still sitting on disk.
    func testMemoryCoversEveryCharacterIncludingRemovedOnes() throws {
        let document = Self.document(memory: [
            Self.record(id: "m1", characterID: "joi.starter"),
            Self.record(id: "m2", characterID: "character.since.removed"),
        ])

        let memory = try XCTUnwrap(document.sections.first { $0.category == .memory })
        XCTAssertEqual(memory.coverage, .complete(itemCount: 2))
        XCTAssertEqual(memory.memory?.map(\.recordID), ["m1", "m2"])
    }

    /// Conversations are always partial, including when the list is empty.
    ///
    /// Nothing keeps a conversation after the app closes, so an empty list here
    /// means "nothing was said in this session" and never "you have no history".
    /// Reporting it as `empty` would let the second reading stand.
    func testConversationsSayThatEarlierOnesWereNeverKept() throws {
        for conversation in [[], [Self.line("你好"), Self.line("你好呀")]] {
            let document = Self.document(conversation: conversation)
            let section = try XCTUnwrap(document.sections.first { $0.category == .conversations })
            guard case let .partial(count, missing) = section.coverage else {
                return XCTFail("an open conversation is never the whole story: \(section.coverage)")
            }
            XCTAssertEqual(count, conversation.count)
            XCTAssertFalse(missing.isEmpty, "it has to say what is not in it")
            XCTAssertTrue(section.statement.contains("从未被保存"), section.statement)
        }
    }

    /// A package is exported as an inventory, never as its files.
    ///
    /// DEC-010: a hash proves integrity, not authorship or the right to
    /// redistribute. Writing a character's model out under the heading "your
    /// data" would make every export a redistribution the rights quarantine
    /// exists to prevent — and would give the user nothing they do not already
    /// have, since the file they imported is still theirs.
    func testPackagesAreListedWithoutTheirAssets() throws {
        let document = Self.document(characters: [Self.catalogEntry()])
        let section = try XCTUnwrap(document.sections.first { $0.category == .packages })

        guard case let .partial(count, missing) = section.coverage else {
            return XCTFail("an inventory without assets is partial by definition: \(section.coverage)")
        }
        XCTAssertEqual(count, 1)
        XCTAssertFalse(missing.isEmpty)
        XCTAssertEqual(section.characterPackages?.first?.contentID, "sha256:abc")
    }

    /// A pack installed in an earlier session is inventory too.
    ///
    /// The App only holds the active pack, so the export asks the store for its
    /// full inventory. `TravelPackInstallerTests` covers the store's side of
    /// that; this covers that the answer reaches the document.
    func testAnInstalledTravelPackIsListedBesideTheCharacters() throws {
        let document = Self.document(
            characters: [Self.catalogEntry()],
            travelPacks: [
                InstalledTravelPackSummary(
                    packID: "pack.app.test",
                    version: "1.0.0",
                    rights: "Repository-authored test fixture",
                    sourceRevisionIDs: ["fixture://sources/app@2026-08-18"],
                    title: "导入的测试路线"
                )
            ]
        )

        let section = try XCTUnwrap(document.sections.first { $0.category == .packages })
        XCTAssertEqual(section.coverage.itemCount, 2, "one character and one pack")
        XCTAssertEqual(section.travelPacks?.first?.packID, "pack.app.test")
        XCTAssertEqual(section.travelPacks?.first?.title, "导入的测试路线")
    }

    /// Nothing in the file names a place on this device.
    ///
    /// A path is not the user's data, it is the app's; an export carrying one
    /// tells whoever receives the file where the sandbox lives and hands a
    /// support channel something it should never be asked to redact.
    func testTheWrittenFileCarriesNoFilesystemPath() throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        let export = try fixture.writer().write(
            Self.document(memory: [Self.record(id: "m1", characterID: "joi.starter")],
                          characters: [Self.catalogEntry()]),
            request: Self.request()
        )

        let text = try String(contentsOf: export.fileURL, encoding: .utf8)
        for forbidden in ["file://", "/Users/", "Application Support", "Assets/v1/sha256", ".vrm", ".moc3"] {
            XCTAssertFalse(text.contains(forbidden), "export leaked \(forbidden)")
        }
        XCTAssertTrue(text.contains("sha256:abc"), "the content identity itself is inventory, and stays")
    }

    // MARK: - Writing it

    /// The result describes the file that landed, measured from the file.
    func testTheResultIsEvidenceAboutTheFileOnDisk() throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }

        let export = try fixture.writer().write(Self.document(), request: Self.request())

        let data = try Data(contentsOf: export.fileURL)
        XCTAssertEqual(export.result.byteCount, data.count)
        XCTAssertEqual(export.result.sha256, Self.digest(data))
        XCTAssertEqual(export.result.categories.map(\.category), DataCategory.allCases)
        XCTAssertTrue(export.fileName.hasPrefix("joi-export-"), export.fileName)
        XCTAssertTrue(export.fileName.hasSuffix(".json"), export.fileName)
    }

    /// `FAIL-029` at the export end: refused before anything is written, with
    /// both numbers, because "not enough space" leaves the user unable to tell
    /// whether to free one file or ten thousand.
    func testAnExportTheDeviceCannotHoldIsRefusedBeforeItStarts() throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }

        XCTAssertThrowsError(
            try fixture.writer(available: 16).write(Self.document(), request: Self.request())
        ) { error in
            guard case let DataExportError.storageInsufficient(required, available) = error else {
                return XCTFail("expected a storage refusal, got \(error)")
            }
            XCTAssertGreaterThan(required, available)
            XCTAssertEqual(available, 16)
        }
        XCTAssertEqual(try fixture.files(), [], "a refusal writes nothing at all")
    }

    /// A failed export must never be the reason the previous one is gone.
    func testARefusedExportLeavesTheEarlierOneInPlace() throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        let first = try fixture.writer().write(Self.document(), request: Self.request())

        XCTAssertThrowsError(
            try fixture.writer(available: 16).write(Self.document(), request: Self.request(seconds: 30))
        )

        XCTAssertEqual(try fixture.files(), [first.fileName])
        XCTAssertEqual(try Data(contentsOf: first.fileURL).count, first.result.byteCount)
    }

    /// A write that cannot be read back is not an export.
    ///
    /// Reporting it as one would hand someone a file they believe holds their
    /// data. The written file is removed rather than left as a half-truth.
    func testAWriteThatDoesNotReadBackIsNotReportedAsAnExport() throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        let writer = DataExportWriter(
            directory: fixture.directory,
            availableBytes: { _ in 1 << 30 },
            writeData: { _, url in try Data("这不是刚才那份文件".utf8).write(to: url, options: .atomic) }
        )

        XCTAssertThrowsError(try writer.write(Self.document(), request: Self.request())) { error in
            XCTAssertEqual(error as? DataExportError, .verificationFailed)
        }
        XCTAssertEqual(try fixture.files(), [], "the unverifiable file is not left behind")
    }

    /// One export at a time: an export is a second copy of everything the user
    /// holds, and letting them accumulate turns a privacy feature into a pile of
    /// duplicates nobody remembers making.
    func testANewExportReplacesThePreviousOne() throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        _ = try fixture.writer().write(Self.document(), request: Self.request())

        let second = try fixture.writer().write(Self.document(), request: Self.request(seconds: 61))

        XCTAssertEqual(try fixture.files(), [second.fileName])
    }

    /// Two exports in the same second land on the same file name, and the
    /// second replaces the first without a moment where neither exists.
    func testRegeneratingWithinTheSameSecondReplacesTheFileInPlace() throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        let first = try fixture.writer().write(Self.document(), request: Self.request())

        let second = try fixture.writer().write(
            Self.document(memory: [Self.record(id: "m1", characterID: "joi.starter")]),
            request: Self.request()
        )

        XCTAssertEqual(second.fileName, first.fileName, "the same second is the same name")
        XCTAssertEqual(try fixture.files(), [second.fileName])
        XCTAssertEqual(try Data(contentsOf: second.fileURL).count, second.result.byteCount)
        XCTAssertEqual(second.result.coverage(of: .memory), .complete(itemCount: 1))
    }

    // MARK: - The app around it

    /// Settings' last unimplemented privacy row now opens something.
    func testSettingsOpensTheExport() throws {
        let rows = SettingsCatalog.rows(facts: Self.facts)
        let row = try XCTUnwrap(rows.first { $0.group == .privacyAndData && $0.title == "导出" })
        XCTAssertEqual(row.destination, .dataExport)
        XCTAssertFalse(row.detail.contains("尚未实现"), row.detail)

        let model = Self.model()
        model.presentSettings()
        model.openFromSettings(.dataExport)
        XCTAssertTrue(model.isDataExportPresented)
        XCTAssertFalse(model.isSettingsPresented, "a destination replaces Settings rather than stacking on it")
    }

    /// End to end through the model: the store's records and the open
    /// conversation reach a file the user can share.
    func testTheModelProducesAFileFromWhatTheDeviceHolds() async throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        let store = InMemoryMemoryStore(records: [Self.record(id: "m1", characterID: "joi.starter")])
        let model = Self.model(fixture: fixture, store: store, gateway: MockChatGateway())
        await model.runChatTurn(text: "你好")
        XCTAssertFalse(model.chatTranscript.isEmpty, "the turn is what the export will carry")

        await model.produceDataExport()

        guard case let .ready(export) = model.dataExportState else {
            return XCTFail("expected a file, got \(model.dataExportState)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.fileURL.path))
        XCTAssertEqual(export.result.coverage(of: .memory), .complete(itemCount: 1))
        XCTAssertEqual(
            export.result.coverage(of: .conversations)?.itemCount,
            model.chatTranscript.count
        )
        guard case .notApplicable = export.result.remote else {
            return XCTFail("nothing here has a server copy to acknowledge")
        }
    }

    /// A refusal names both numbers in kilobytes. Megabytes would round a 300 KB
    /// requirement and 96 KB of free space to the same "1 MB" and explain
    /// nothing.
    func testARefusalTellsTheUserWhatToFreeUp() async throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        let model = Self.model(fixture: fixture, available: 16)

        await model.produceDataExport()

        guard case let .failed(message) = model.dataExportState else {
            return XCTFail("expected a refusal, got \(model.dataExportState)")
        }
        XCTAssertTrue(message.contains("KB"), message)
        XCTAssertTrue(message.contains("空间不足"), message)
        XCTAssertEqual(try fixture.files(), [])
    }

    /// A store that cannot be read produces no export at all.
    ///
    /// The tempting shape — treat an unreadable store as empty — would hand the
    /// user a document that says they have no memories, which is a different
    /// claim from "this could not be read".
    func testAnUnreadableStoreFailsRatherThanExportingNothing() async throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        let model = Self.model(fixture: fixture, store: FailingMemoryStore())

        await model.produceDataExport()

        guard case let .failed(message) = model.dataExportState else {
            return XCTFail("expected a failure, got \(model.dataExportState)")
        }
        XCTAssertTrue(message.contains("无法读取本机数据"), message)
        XCTAssertEqual(try fixture.files(), [])
    }

    // MARK: - Fixtures

    private static let facts = SettingsBuildFacts(
        version: "0.1.0",
        build: "1",
        admitsLive2D: false,
        admitsVRM: false,
        activeRenderer: nil
    )

    private static func document(
        memory: [MemoryRecordV1] = [],
        conversation: [TranscriptEntry] = [],
        characters: [CharacterPackageCatalogEntry] = [],
        travelPacks: [InstalledTravelPackSummary] = []
    ) -> DataExportDocumentV1 {
        DataExportBuilder.document(
            request: request(),
            app: DataExportDocumentV1.AppFacts(version: "0.1.0", build: "1"),
            memory: memory,
            conversation: conversation,
            characters: characters,
            travelPacks: travelPacks
        )
    }

    private static func request(seconds: TimeInterval = 0) -> DataExportRequestV1 {
        DataExportRequestV1(
            requestID: "export.test.\(Int(seconds))",
            requestedAt: Date(timeIntervalSince1970: 1_787_000_000 + seconds)
        )
    }

    private static func record(id: String, characterID: String) -> MemoryRecordV1 {
        MemoryRecordV1(
            recordID: id,
            characterID: characterID,
            category: .relationship,
            classification: .standard,
            value: "喜欢在江边走",
            provenance: .userApprovedProposal,
            reason: "对话中确认",
            createdAt: Date(timeIntervalSince1970: 1_786_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_786_000_000)
        )
    }

    private static func line(_ text: String) -> TranscriptEntry {
        TranscriptEntry(
            eventID: "event.\(text)",
            requestID: "request.1",
            author: .user,
            text: text,
            timestamp: Date(timeIntervalSince1970: 1_786_500_000)
        )
    }

    private static func catalogEntry() -> CharacterPackageCatalogEntry {
        CharacterPackageCatalogEntry(
            installationID: CharacterInstallationID(rawValue: "install.1"),
            contentID: CharacterContentID(rawValue: "sha256:abc"),
            characterID: "joi.starter",
            displayName: "Joi",
            renderer: .vrm,
            available: true,
            activationAllowed: true
        )
    }

    private static func model(
        fixture: ExportFixture? = nil,
        store: (any MemoryRepository)? = nil,
        gateway: (any ChatGateway)? = nil,
        available: Int64 = 1 << 30
    ) -> AppModel {
        let suite = "joi.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppModel(
            installer: CharacterPackageInstaller(
                root: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            chatGateway: gateway,
            // Never the workstation's own store: a suite that read the machine
            // it runs on would pass or fail on what happens to be installed.
            memoryStore: store ?? InMemoryMemoryStore(records: []),
            dataExportWriter: fixture.map { $0.writer(available: available) },
            defaults: defaults
        )
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// A directory that belongs to one test.
private struct ExportFixture {
    let root: URL
    let directory: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        directory = root.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func writer(available: Int64 = 1 << 30) -> DataExportWriter {
        DataExportWriter(directory: directory, availableBytes: { _ in available })
    }

    func files() throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0 != ".DS_Store" }
            .sorted()
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

private actor InMemoryMemoryStore: MemoryRepository {
    private var records: [MemoryRecordV1]

    init(records: [MemoryRecordV1]) { self.records = records }

    func list(characterID: String) async throws -> [MemoryRecordV1] {
        records.filter { $0.characterID == characterID }
    }
    func save(_ record: MemoryRecordV1, authorizationDigest _: String?) async throws {
        records.append(record)
    }
    func delete(recordID: String) async throws { records.removeAll { $0.recordID == recordID } }
    func export() async throws -> [MemoryRecordV1] { records }
}

/// A store whose file is there and unreadable — the case a real `MemoryStore`
/// reaches when its JSON no longer decodes.
private actor FailingMemoryStore: MemoryRepository {
    private struct Unreadable: Error {}

    func list(characterID: String) async throws -> [MemoryRecordV1] { throw Unreadable() }
    func save(_ record: MemoryRecordV1, authorizationDigest _: String?) async throws { throw Unreadable() }
    func delete(recordID: String) async throws { throw Unreadable() }
    func export() async throws -> [MemoryRecordV1] { throw Unreadable() }
}
