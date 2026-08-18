import CompanionCore
import Foundation

/// A proposal to remember something, while the user is still deciding.
///
/// `G2-J2D`. `JM-P0-005`'s rule is that no model-generated proposal becomes
/// durable silently, and the mechanism that makes that true is this type: a
/// proposal is a thing that exists, is shown, and has to be accepted before any
/// record is written. Nothing constructs a `MemoryRecordV1` except
/// `acceptedRecord`, and that is only reachable from an accepted proposal.
struct MemoryProposal: Equatable, Sendable, Identifiable {
    var id: String { proposal.proposalID }

    /// How long a pending proposal stands. Long enough to read and think about,
    /// short enough that a sheet left open overnight does not silently write
    /// yesterday's context into a relationship the user has moved on from.
    static let lifetime: TimeInterval = 600

    /// The categories a conversation line may be remembered as.
    ///
    /// `preciseLocation` and `protectedNeverSync` are deliberately absent.
    /// Location does not become long-term memory by being talked about — that is
    /// the implicit promotion TDD §8.3 forbids — and it would need its own
    /// authorisation, with its own precision and retention, which is a different
    /// decision from this one (DEC-032 made the neighbouring one for chat turns).
    static let selectableCategories: [MemoryCategory] = [
        .profile, .preference, .relationship, .travelRecap,
    ]

    /// The frozen contract value describing what is being proposed.
    let proposal: MemoryProposalV1
    /// The accepted transcript line this came from, so a record can be traced
    /// back to the turn that produced it.
    let sourceEventID: String
    let characterID: String
    let threadID: String

    init(
        entry: TranscriptEntry,
        characterID: String,
        threadID: String,
        at now: Date,
        proposalID: String = UUID().uuidString.lowercased()
    ) {
        self.init(
            value: entry.text,
            reason: String(localized: "来自你与角色的一次对话"),
            category: .relationship,
            sourceEventID: entry.eventID,
            characterID: characterID,
            threadID: threadID,
            at: now,
            proposalID: proposalID
        )
    }

    /// The general form. Used directly by the trip recap (`G2-J4B`), where what
    /// is being proposed came from a stop the user walked past rather than from
    /// a line the character said.
    init(
        value: String,
        reason: String,
        category: MemoryCategory,
        sourceEventID: String = "",
        characterID: String,
        threadID: String,
        at now: Date,
        proposalID: String = UUID().uuidString.lowercased()
    ) {
        proposal = MemoryProposalV1(
            proposalID: proposalID,
            category: category,
            value: value,
            reason: reason,
            state: .proposed,
            expiresAt: now.addingTimeInterval(Self.lifetime)
        )
        self.sourceEventID = sourceEventID
        self.characterID = characterID
        self.threadID = threadID
    }

    func isExpired(at date: Date) -> Bool { date >= proposal.expiresAt }

    /// The durable record for an accepted proposal, or `nil` if there is nothing
    /// left to remember after trimming.
    ///
    /// `state` records whether the user changed the wording, because "the user
    /// approved this sentence" and "the user rewrote it and approved that" are
    /// different provenance claims and the record should not flatten them.
    func acceptedRecord(
        value: String,
        category: MemoryCategory,
        at now: Date,
        recordID: String = UUID().uuidString.lowercased()
    ) -> (record: MemoryRecordV1, state: MemoryProposalState)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // A category outside the selectable set cannot be reached from here, so
        // location can never be written by accepting a conversation proposal.
        guard Self.selectableCategories.contains(category) else { return nil }
        let state: MemoryProposalState = trimmed == proposal.value ? .accepted : .editedAndAccepted
        return (
            MemoryRecordV1(
                recordID: recordID,
                characterID: characterID,
                threadID: threadID,
                category: category,
                classification: .standard,
                value: trimmed,
                provenance: .userApprovedProposal,
                reason: proposal.reason,
                createdAt: now,
                updatedAt: now,
                // Sync is opt-in per category and no account or sync surface
                // exists yet, so nothing written here is eligible to leave the
                // device. `JM-P0-019` is what changes that, deliberately and
                // with its own consent.
                syncEligible: false
            ),
            state
        )
    }
}

extension MemoryCategory {
    /// Chinese label for the category picker.
    var displayName: String {
        switch self {
        case .profile: String(localized: "关于我")
        case .preference: String(localized: "我的偏好")
        case .relationship: String(localized: "我们之间")
        case .travelRecap: String(localized: "旅行回顾")
        case .preciseLocation: String(localized: "精确位置")
        case .protectedNeverSync: String(localized: "仅本机保留")
        }
    }
}
