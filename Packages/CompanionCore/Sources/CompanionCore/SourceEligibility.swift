import Foundation

/// Why a source may not be shown as supporting a claim.
///
/// `G2-J3C`. These are refusals, not scores: a withdrawn source is not a weak
/// source, and collapsing the two would be exactly the arithmetic PRD §8.1
/// forbids.
public enum SourceIneligibility: String, Codable, Equatable, Sendable {
    /// The publisher withdrew the revision. TDD §10: a withdrawal invalidates
    /// the narration it supported.
    case withdrawn
    /// The claim itself was retracted, whatever the source's standing.
    case retracted
    /// The source exists and stands, but does not, on balance, support this
    /// particular claim.
    case evidenceDoesNotSupportTheClaim
}

/// A source that was carried but may not be shown as support, and why.
public struct WithheldSource: Equatable, Sendable {
    public let source: SourceProjectionV1
    public let reason: SourceIneligibility

    public init(source: SourceProjectionV1, reason: SourceIneligibility) {
        self.source = source
        self.reason = reason
    }
}

/// What an answer's sources permit it to claim.
public enum ClaimSupport: Equatable, Sendable {
    /// The answer carried no sources. An ordinary conversational reply, which is
    /// not a factual claim and must not be dressed as one.
    case unsourced
    /// At least one source may support it. `withheld` is still carried, because
    /// "two of the three sources for this were retracted" is information, not
    /// noise to be filtered away.
    case supported(eligible: [SourceProjectionV1], withheld: [WithheldSource])
    /// It carried sources and not one of them may support it. This is a
    /// different state from carrying none, and showing it as the same would let
    /// a retracted claim read as ordinary conversation.
    case withheld([WithheldSource])
}

/// The rule deciding whether a source may stand behind a claim.
///
/// It lives in `CompanionCore` rather than in a view because it is a property of
/// the contract, not of a screen: a second client has to reach the same verdict
/// from the same event, and a rule written inside a SwiftUI file cannot be run
/// anywhere else.
public enum SourceEligibility {
    /// The point below which a source's own evidence does not, on balance,
    /// support the claim it is attached to.
    ///
    /// A product judgement rather than a derived constant, and deliberately the
    /// only place in this rule where a number becomes a decision. It applies to
    /// `claimSupportConfidence` alone: identity confidence answers "what is
    /// this?", authority answers "who says it?", and neither is mixed in here.
    /// PRD §8.1 requires those to stay separate values, so nothing in this file
    /// ever adds or averages them.
    public static let claimSupportFloor = 0.5

    public static func ineligibility(of source: SourceProjectionV1) -> SourceIneligibility? {
        if source.withdrawn { return .withdrawn }
        if source.correctionStatus == SourceCorrectionStatus.retracted { return .retracted }
        if source.claimSupportConfidence < claimSupportFloor { return .evidenceDoesNotSupportTheClaim }
        return nil
    }

    public static func support(for sources: [SourceProjectionV1]) -> ClaimSupport {
        guard !sources.isEmpty else { return .unsourced }
        var eligible: [SourceProjectionV1] = []
        var withheld: [WithheldSource] = []
        for source in sources {
            if let reason = ineligibility(of: source) {
                withheld.append(WithheldSource(source: source, reason: reason))
            } else {
                eligible.append(source)
            }
        }
        if eligible.isEmpty { return .withheld(withheld) }
        return .supported(eligible: eligible, withheld: withheld)
    }
}

/// The `conflictStatus` values the schema allows.
public enum SourceConflictStatus {
    public static let none = "none"
    public static let disputed = "disputed"
    public static let unresolved = "unresolved"
    public static let resolved = "resolved"
}

/// The `correctionStatus` values the schema allows.
public enum SourceCorrectionStatus {
    public static let current = "current"
    public static let corrected = "corrected"
    public static let retracted = "retracted"
    public static let pendingReview = "pendingReview"
}

public extension SourceProjectionV1 {
    /// A conflict is preserved and explained, never resolved away by hiding it.
    var isConflicted: Bool {
        conflictStatus == SourceConflictStatus.disputed
            || conflictStatus == SourceConflictStatus.unresolved
    }

    /// A correction that has been applied, or one still being reviewed, both
    /// change what the reader should make of the claim.
    var hasCorrectionNote: Bool {
        correctionStatus == SourceCorrectionStatus.corrected
            || correctionStatus == SourceCorrectionStatus.pendingReview
    }
}
