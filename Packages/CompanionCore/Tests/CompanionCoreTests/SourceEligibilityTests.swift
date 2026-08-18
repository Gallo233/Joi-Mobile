import XCTest
@testable import CompanionCore

/// `G2-J3C` — which sources may stand behind a claim.
///
/// `SourceProjectionV1` has been part of `CompanionEventV1` since G1, is a
/// required field in the JSON schema, is parsed by the SSE gateway and is
/// mirrored in the Kotlin core — and no code on either platform had ever read
/// one. `JM-P0-013`'s rules therefore had nothing enforcing them.
final class SourceEligibilityTests: XCTestCase {
    /// `J3C-01` — a withdrawn revision invalidates the narration it supported,
    /// however confident it claims to be.
    func testAWithdrawnSourceCanNeverSupportAClaim() {
        let source = Self.source(claimSupport: 0.99, withdrawn: true)
        XCTAssertEqual(SourceEligibility.ineligibility(of: source), .withdrawn)

        guard case let .withheld(withheld) = SourceEligibility.support(for: [source]) else {
            return XCTFail("a withdrawn source cannot leave a claim supported")
        }
        XCTAssertEqual(withheld.map(\.reason), [.withdrawn])
    }

    /// `J3C-01` — a retracted claim is refused even when its source stands.
    func testARetractedClaimIsRefused() {
        let source = Self.source(claimSupport: 0.99, correction: SourceCorrectionStatus.retracted)
        XCTAssertEqual(SourceEligibility.ineligibility(of: source), .retracted)
    }

    /// `J3C-01` — evidence that does not, on balance, support the claim is not
    /// shown as if it did.
    func testEvidenceBelowTheFloorDoesNotSupportTheClaim() {
        let weak = Self.source(claimSupport: SourceEligibility.claimSupportFloor - 0.01)
        XCTAssertEqual(SourceEligibility.ineligibility(of: weak), .evidenceDoesNotSupportTheClaim)

        let atFloor = Self.source(claimSupport: SourceEligibility.claimSupportFloor)
        XCTAssertNil(SourceEligibility.ineligibility(of: atFloor), "the floor itself is admitted")
    }

    /// `J3C-02` — the floor applies to evidence support alone. A source whose
    /// identity confidence is low, or whose authority is weak, is still support:
    /// those answer different questions and PRD §8.1 forbids collapsing them.
    func testLowIdentityConfidenceAndWeakAuthorityDoNotRemoveSupport() {
        let uncertainIdentity = Self.source(claimSupport: 0.9, identityConfidence: 0.05)
        XCTAssertNil(
            SourceEligibility.ineligibility(of: uncertainIdentity),
            "identity confidence answers a different question from evidence support"
        )

        let weakAuthority = Self.source(claimSupport: 0.9, authority: "community")
        XCTAssertNil(
            SourceEligibility.ineligibility(of: weakAuthority),
            "authority is shown, not silently converted into support"
        )
    }

    /// `J3C-03` — a conflict is preserved and explained rather than resolved by
    /// dropping the source.
    func testAConflictedSourceStillSupportsAndIsMarked() {
        let disputed = Self.source(claimSupport: 0.8, conflict: SourceConflictStatus.disputed)
        XCTAssertTrue(disputed.isConflicted)
        XCTAssertNil(SourceEligibility.ineligibility(of: disputed), "a conflict is shown, not hidden")

        let unresolved = Self.source(claimSupport: 0.8, conflict: SourceConflictStatus.unresolved)
        XCTAssertTrue(unresolved.isConflicted)

        let settled = Self.source(claimSupport: 0.8, conflict: SourceConflictStatus.resolved)
        XCTAssertFalse(settled.isConflicted)
    }

    /// A pending or applied correction is a note on the claim, not a refusal.
    func testCorrectionsAreNotedRatherThanRefused() {
        let pending = Self.source(claimSupport: 0.8, correction: SourceCorrectionStatus.pendingReview)
        XCTAssertTrue(pending.hasCorrectionNote)
        XCTAssertNil(SourceEligibility.ineligibility(of: pending))

        let corrected = Self.source(claimSupport: 0.8, correction: SourceCorrectionStatus.corrected)
        XCTAssertTrue(corrected.hasCorrectionNote)
        XCTAssertNil(SourceEligibility.ineligibility(of: corrected))

        XCTAssertFalse(Self.source(claimSupport: 0.8).hasCorrectionNote)
    }

    /// `J3C-04` — carrying no sources and carrying only refused ones are
    /// different states. Merging them would let a retracted claim read as
    /// ordinary conversation.
    func testCarryingNoSourcesIsNotTheSameAsCarryingOnlyRefusedOnes() {
        XCTAssertEqual(SourceEligibility.support(for: []), .unsourced)

        let refused = SourceEligibility.support(for: [Self.source(claimSupport: 0.9, withdrawn: true)])
        XCTAssertNotEqual(refused, .unsourced)
        guard case .withheld = refused else {
            return XCTFail("sources that all fail must produce a withheld state")
        }
    }

    /// A partly-supported answer keeps both halves: the sources that stand, and
    /// the ones that were refused with the reason.
    func testAPartlySupportedAnswerKeepsBothTheStandingAndTheRefused() {
        let good = Self.source(claimID: "claim.ok", claimSupport: 0.9)
        let gone = Self.source(claimID: "claim.gone", claimSupport: 0.9, withdrawn: true)
        let weak = Self.source(claimID: "claim.weak", claimSupport: 0.1)

        guard case let .supported(eligible, withheld) = SourceEligibility.support(for: [good, gone, weak]) else {
            return XCTFail("one standing source leaves the claim supported")
        }
        XCTAssertEqual(eligible.map(\.claimID), ["claim.ok"])
        XCTAssertEqual(withheld.map(\.source.claimID), ["claim.gone", "claim.weak"])
        XCTAssertEqual(withheld.map(\.reason), [.withdrawn, .evidenceDoesNotSupportTheClaim])
    }

    /// Withdrawal outranks a weak score, so the reason a reader is given is the
    /// most serious true one rather than whichever check ran first.
    func testWithdrawalIsReportedAheadOfAWeakScore() {
        let both = Self.source(claimSupport: 0.1, withdrawn: true)
        XCTAssertEqual(SourceEligibility.ineligibility(of: both), .withdrawn)
    }

    // MARK: - Helpers

    private static func source(
        claimID: String = "claim.1",
        claimSupport: Double,
        identityConfidence: Double? = 0.9,
        authority: String = "institutional",
        conflict: String = SourceConflictStatus.none,
        correction: String = SourceCorrectionStatus.current,
        withdrawn: Bool = false
    ) -> SourceProjectionV1 {
        SourceProjectionV1(
            placeID: "place.1",
            claimID: claimID,
            identityConfidence: identityConfidence,
            claimSupportConfidence: claimSupport,
            publisher: "测试出版方",
            title: "测试条目",
            locator: "fixture://sources/test",
            authority: authority,
            revision: "2026-08-18",
            retrievedAt: Date(timeIntervalSince1970: 0),
            conflictStatus: conflict,
            correctionStatus: correction,
            rights: "Repository-authored contract fixture",
            withdrawn: withdrawn
        )
    }
}
