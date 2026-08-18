import CompanionCore
import XCTest
@testable import JoiMobile

/// `G2-J2B` rows 08–10. `SpeechCoordinator` is named a unique state owner by
/// both AGENTS.md and TDD §3.1, and it was fully implemented and tested — but
/// the app constructed one and then spoke around it, so nothing in the product
/// ever asked who was allowed to talk. These are the rules that make it the
/// owner in fact rather than on paper.
@MainActor
final class SpeechCoordinationTests: XCTestCase {
    /// `J2B-08` — a spoken line is a cue the coordinator accepted, and the
    /// coordinator can answer what the character is currently saying.
    func testSpeakingALineRegistersItWithTheCoordinator() async throws {
        let model = AppModel()
        let before = await model.speechCoordinator.currentCue()
        XCTAssertNil(before, "nothing is being said before a turn")

        let generation = await model.speakCompanionLine("こんばんは")
        XCTAssertNotNil(generation, "an accepted line must be accepted by the coordinator")

        let current = await model.speechCoordinator.currentCue()
        let cue = try XCTUnwrap(current)
        XCTAssertEqual(cue.text, "こんばんは")
        XCTAssertEqual(cue.priority, .conversation)
        // The cue carries the session it belongs to, so a line from a previous
        // character or session is identifiable rather than anonymous.
        let session = await model.companionSession.current()
        XCTAssertEqual(cue.sessionID, session.sessionID)
        XCTAssertEqual(cue.characterID, session.selection.characterID)
    }

    /// `J2B-09` — a newer line supersedes an older one through the coordinator,
    /// and the older generation stops being accepted. Stopping the player is not
    /// the same thing: the decision has to be visible before any fetch starts.
    func testNewerLinePreemptsTheOlderGenerationThroughTheCoordinator() async throws {
        let model = AppModel()
        let firstGeneration = await model.speakCompanionLine("さきの行")
        let first = try XCTUnwrap(firstGeneration)
        let secondGeneration = await model.speakCompanionLine("あとの行")
        let second = try XCTUnwrap(secondGeneration)
        XCTAssertNotEqual(first, second)

        let firstStillCurrent = await model.speechCoordinator.acceptsCompletion(for: first)
        let secondIsCurrent = await model.speechCoordinator.acceptsCompletion(for: second)
        XCTAssertFalse(firstStillCurrent, "the superseded line must not be accepted any more")
        XCTAssertTrue(secondIsCurrent, "the newest line is the current one")

        let current = await model.speechCoordinator.currentCue()
        let cue = try XCTUnwrap(current)
        XCTAssertEqual(cue.text, "あとの行")
    }

    /// `J2B-10` — a user stop cancels through the coordinator, so a line that
    /// finishes after the stop is refused instead of being treated as current.
    func testUserStopCancelsThroughTheCoordinatorSoLateCompletionIsRefused() async throws {
        let model = AppModel()
        let started = await model.speakCompanionLine("止められる行")
        let generation = try XCTUnwrap(started)
        let held = await model.speechCoordinator.acceptsCompletion(for: generation)
        XCTAssertTrue(held, "the line holds the voice before the stop")

        model.stopChatTurn()
        // `stopChatTurn` cancels on a detached task; wait for the owner to settle.
        var cleared = false
        for _ in 0..<200 {
            let cue = await model.speechCoordinator.currentCue()
            if cue == nil {
                cleared = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(cleared, "stopping the turn must clear the speech owner")

        let accepted = await model.speechCoordinator.acceptsCompletion(for: generation)
        XCTAssertFalse(accepted, "a line completing after the stop is not the current one")
    }

    /// DEC-021's silence rule, at the coordination boundary: a turn with no
    /// `voiceLine` must not register a cue at all, rather than register an empty
    /// one and let something downstream decide.
    func testALineWithNothingToSayNeverClaimsTheVoice() async throws {
        let model = AppModel()
        let blank = await model.speakCompanionLine("   ")
        XCTAssertNil(blank)
        let cue = await model.speechCoordinator.currentCue()
        XCTAssertNil(cue, "whitespace is not a line and must not claim the voice")
    }
}
