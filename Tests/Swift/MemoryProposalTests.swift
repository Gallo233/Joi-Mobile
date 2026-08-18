import CompanionCore
import Foundation
import XCTest
@testable import JoiMobile

/// `G2-J2D` — durable memory, and the decision in front of it.
///
/// `MemoryRecordV1`, `MemoryProposalV1`, `MemoryCategory`, `MemoryProvenance`
/// and the `MemoryRepository` protocol have been frozen contracts since G1 with
/// no implementation behind any of them, and `memoryEligibility` has travelled
/// from the backend through `CompanionEventV1` into `TranscriptEntry` this whole
/// time without a single reader. `JM-P0-005`'s rule — that nothing
/// model-generated becomes durable silently — was therefore a sentence with
/// nothing enforcing it. These are what enforce it.
@MainActor
final class MemoryProposalTests: XCTestCase {
    // MARK: - The eligibility gate

    /// `J2D-01` — eligibility is the backend's answer and the app obeys it. A
    /// line marked `.none` cannot be proposed at all.
    func testAnIneligibleLineCannotBeProposed() async throws {
        let model = AppModel(memoryStore: InMemoryStore())
        let ineligible = Self.entry(text: "随口一句", eligibility: .none)
        XCTAssertFalse(model.canRemember(ineligible))

        await model.proposeMemory(from: ineligible)
        XCTAssertNil(model.memoryProposal, "an ineligible line must not open a proposal")
    }

    func testAnEligibleLineCanBeProposed() async throws {
        let model = AppModel(memoryStore: InMemoryStore())
        let eligible = Self.entry(text: "我喜欢清晨的江边", eligibility: .proposalAllowed)
        XCTAssertTrue(model.canRemember(eligible))

        await model.proposeMemory(from: eligible)
        let proposal = try XCTUnwrap(model.memoryProposal)
        XCTAssertEqual(proposal.proposal.state, .proposed)
        XCTAssertEqual(model.memoryDraft, "我喜欢清晨的江边", "the sheet opens on the line's own words")
    }

    // MARK: - Nothing durable without a decision

    /// `J2D-02` — the whole point. Opening a proposal writes nothing; only
    /// accepting does.
    func testProposingWritesNothingUntilItIsAccepted() async throws {
        let store = InMemoryStore()
        let model = AppModel(memoryStore: store)
        await model.proposeMemory(from: Self.entry(text: "我住在虹口", eligibility: .proposalAllowed))

        let writes1 = await store.saveCount
        XCTAssertEqual(writes1, 0, "a proposal on screen is not a record on disk")
        await model.refreshMemories()
        XCTAssertTrue(model.memories.isEmpty)

        let state = await model.acceptMemoryProposal()
        XCTAssertEqual(state, .accepted)
        let writes2 = await store.saveCount
        XCTAssertEqual(writes2, 1)
        XCTAssertEqual(model.memories.count, 1)
        XCTAssertNil(model.memoryProposal, "an accepted proposal is finished")
    }

    /// `J2D-03` — the stored sentence is the user's. An edited acceptance says so
    /// rather than being recorded as though the model's wording was approved.
    func testEditingBeforeAcceptingStoresTheUsersOwnWording() async throws {
        let store = InMemoryStore()
        let model = AppModel(memoryStore: store)
        await model.proposeMemory(from: Self.entry(text: "你似乎喜欢江边", eligibility: .proposalAllowed))

        model.memoryDraft = "我喜欢江边散步"
        model.memoryCategory = .preference
        let state = await model.acceptMemoryProposal()

        XCTAssertEqual(state, .editedAndAccepted)
        let stored = await store.records
        let saved = try XCTUnwrap(stored.first)
        XCTAssertEqual(saved.value, "我喜欢江边散步")
        XCTAssertEqual(saved.category, .preference)
        XCTAssertEqual(saved.provenance, .userApprovedProposal)
        XCTAssertFalse(saved.reason.isEmpty, "a durable item records why it exists")
    }

    /// `J2D-04` — declining writes nothing and leaves the conversation alone.
    func testRejectingWritesNothingAndLeavesTheTranscriptAlone() async throws {
        let store = InMemoryStore()
        let model = AppModel(memoryStore: store)
        let before = await model.companionSession.current()
        await model.proposeMemory(from: Self.entry(text: "别记这句", eligibility: .proposalAllowed))

        model.rejectMemoryProposal()

        XCTAssertNil(model.memoryProposal)
        let writes3 = await store.saveCount
        XCTAssertEqual(writes3, 0)
        let after = await model.companionSession.current()
        XCTAssertEqual(before, after, "deciding not to remember changes nothing about the session")
    }

    /// A proposal left open too long stops being acceptable, so a sheet from
    /// yesterday cannot write today.
    func testAnExpiredProposalIsNotWritten() async throws {
        let store = InMemoryStore()
        let model = AppModel(memoryStore: store)
        let opened = Date()
        await model.proposeMemory(from: Self.entry(text: "过期的想法", eligibility: .proposalAllowed), now: opened)

        let state = await model.acceptMemoryProposal(
            now: opened.addingTimeInterval(MemoryProposal.lifetime + 1)
        )
        XCTAssertEqual(state, .expired)
        let writes4 = await store.saveCount
        XCTAssertEqual(writes4, 0)
        XCTAssertNil(model.memoryProposal)
    }

    /// Whitespace is not a memory. Accepting an emptied draft writes nothing and
    /// leaves the proposal open rather than storing a blank record.
    func testAnEmptiedDraftIsNotAMemory() async throws {
        let store = InMemoryStore()
        let model = AppModel(memoryStore: store)
        await model.proposeMemory(from: Self.entry(text: "有内容", eligibility: .proposalAllowed))

        model.memoryDraft = "   \n  "
        let state = await model.acceptMemoryProposal()

        XCTAssertNil(state)
        let writes5 = await store.saveCount
        XCTAssertEqual(writes5, 0)
        XCTAssertNotNil(model.memoryProposal, "the decision is still open")
    }

    // MARK: - What a record may be

    /// `J2D-05` — precise location is never promoted by talking about it. The
    /// category is not offerable, and the contract refuses it even if it were.
    func testLocationCategoriesAreUnreachableFromAConversationProposal() async throws {
        XCTAssertFalse(MemoryProposal.selectableCategories.contains(.preciseLocation))
        XCTAssertFalse(MemoryProposal.selectableCategories.contains(.protectedNeverSync))

        let store = InMemoryStore()
        let model = AppModel(memoryStore: store)
        await model.proposeMemory(from: Self.entry(text: "我在外滩", eligibility: .proposalAllowed))

        // Force the category past the picker; the write must still refuse.
        model.memoryCategory = .preciseLocation
        let state = await model.acceptMemoryProposal()
        XCTAssertNil(state)
        let writes6 = await store.saveCount
        XCTAssertEqual(writes6, 0, "a location record cannot come from a chat proposal")
    }

    /// The contract's own floor, restated where a reader will meet it: a
    /// location record is never sync-eligible, whatever the caller asks for.
    func testALocationRecordIsNeverSyncEligible() {
        let record = MemoryRecordV1(
            recordID: "record-1",
            characterID: "joi.starter",
            category: .preciseLocation,
            classification: .sensitiveLocation,
            value: "31.230, 121.474",
            provenance: .userEntered,
            reason: "测试",
            createdAt: Date(),
            updatedAt: Date(),
            syncEligible: true
        )
        XCTAssertFalse(record.syncEligible)
    }

    /// `J2D-06` — nothing written here may leave the device: sync is opt-in per
    /// category and no such consent exists yet.
    func testNothingWrittenByThisSliceIsSyncEligible() async throws {
        let store = InMemoryStore()
        let model = AppModel(memoryStore: store)
        await model.proposeMemory(from: Self.entry(text: "记住我怕高", eligibility: .proposalAllowed))
        await model.acceptMemoryProposal()

        let stored = await store.records
        let saved = try XCTUnwrap(stored.first)
        XCTAssertFalse(saved.syncEligible)
    }

    // MARK: - The store

    /// `J2D-07` — memory is durable. A second store over the same file sees what
    /// the first wrote, which is the difference between remembering and holding
    /// something until the process ends.
    func testMemorySurvivesANewStoreOverTheSameFile() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }

        let first = MemoryStore(fileURL: fixture.fileURL)
        try await first.save(Self.record(id: "record-1", value: "我怕高"), authorizationDigest: nil)

        let second = MemoryStore(fileURL: fixture.fileURL)
        let reloaded = try await second.list(characterID: "joi.starter")
        XCTAssertEqual(reloaded.map(\.value), ["我怕高"])
    }

    /// `J2D-07` — deletion is durable too, and a reload cannot bring it back.
    func testDeletionIsDurable() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }

        let store = MemoryStore(fileURL: fixture.fileURL)
        try await store.save(Self.record(id: "record-1", value: "一"), authorizationDigest: nil)
        try await store.save(Self.record(id: "record-2", value: "二"), authorizationDigest: nil)
        try await store.delete(recordID: "record-1")

        let reloaded = try await MemoryStore(fileURL: fixture.fileURL).list(characterID: "joi.starter")
        XCTAssertEqual(reloaded.map(\.recordID), ["record-2"])
    }

    /// Deleting something that is not there is an error rather than a silent
    /// success, so a UI cannot report a deletion that did not happen.
    func testDeletingAnAbsentRecordFails() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let store = MemoryStore(fileURL: fixture.fileURL)

        do {
            try await store.delete(recordID: "never-existed")
            XCTFail("deleting nothing must not report success")
        } catch let error as MemoryStoreError {
            XCTAssertEqual(error, .notFound)
        }
    }

    /// `J2D-08` — memory belongs to a relationship. A second character does not
    /// read what was said to the first.
    func testMemoryIsScopedToItsCharacter() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let store = MemoryStore(fileURL: fixture.fileURL)

        try await store.save(Self.record(id: "a", value: "对甲说的"), authorizationDigest: nil)
        try await store.save(
            Self.record(id: "b", value: "对乙说的", characterID: "other.character"),
            authorizationDigest: nil
        )

        let mine = try await store.list(characterID: "joi.starter")
        XCTAssertEqual(mine.map(\.value), ["对甲说的"])
    }

    /// The store refuses a record whose stored authorisation disagrees with the
    /// one presented, so the two cannot drift apart unnoticed.
    func testAMismatchedAuthorizationIsRefused() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let store = MemoryStore(fileURL: fixture.fileURL)

        do {
            try await store.save(Self.record(id: "a", value: "x"), authorizationDigest: "a-different-digest")
            XCTFail("a record must not be saved under an authorisation it does not carry")
        } catch let error as MemoryStoreError {
            XCTAssertEqual(error, .authorizationMismatch)
        }
    }

    // MARK: - Helpers

    private static func entry(text: String, eligibility: MemoryEligibility) -> TranscriptEntry {
        TranscriptEntry(
            eventID: UUID().uuidString,
            requestID: "request-1",
            author: .companion,
            text: text,
            timestamp: Date(),
            memoryEligibility: eligibility
        )
    }

    private static func record(
        id: String,
        value: String,
        characterID: String = "joi.starter"
    ) -> MemoryRecordV1 {
        MemoryRecordV1(
            recordID: id,
            characterID: characterID,
            category: .relationship,
            classification: .standard,
            value: value,
            provenance: .userApprovedProposal,
            reason: "测试",
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

/// A store that keeps records in memory and counts writes, so a test can assert
/// that nothing was written without going near the filesystem.
private actor InMemoryStore: MemoryRepository {
    private(set) var records: [MemoryRecordV1] = []
    private(set) var saveCount = 0

    func list(characterID: String) async throws -> [MemoryRecordV1] {
        records.filter { $0.characterID == characterID }
    }

    func save(_ record: MemoryRecordV1, authorizationDigest _: String?) async throws {
        saveCount += 1
        records.append(record)
    }

    func delete(recordID: String) async throws {
        records.removeAll { $0.recordID == recordID }
    }
}

private struct StoreFixture {
    let root: URL
    let fileURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appendingPathComponent("memory.v1.json")
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
