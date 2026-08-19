import CompanionCore
import Foundation
import XCTest
@testable import JoiMobile

/// `G2-J5H` — `FAIL-006`, the silence that explained nothing.
///
/// A line that could not be spoken was silent by design, and the design was
/// half right: no substitute voice may ever speak as the character, and the
/// transcript already carries the words. What it left out is that a character
/// which simply stops making sound is indistinguishable from a broken one — and
/// PRD §7.1 asks for something the code did not do at all. "End playback
/// generation" was never done, so a line that never played left
/// `SpeechCoordinator` naming it as what the character was currently saying,
/// indefinitely.
@MainActor
final class SpeechFailureTests: XCTestCase {

    // MARK: - Naming the reason

    /// Three reasons rather than one, because the product can genuinely tell
    /// them apart and they do not have the same remedy.
    func testEveryReasonSaysSomethingDifferentAndKeepsTheTextAlive() {
        let reasons: [SpeechFailure] = [.voiceUnavailable, .audioUndecodable, .routeRefused]
        let messages = reasons.map(\.message)

        XCTAssertEqual(Set(messages).count, reasons.count, "two reasons may not share one sentence")
        for message in messages {
            XCTAssertFalse(message.isEmpty)
            XCTAssertTrue(
                message.contains("文字仍在"),
                "PRD §7 asks for the readable text to be preserved, and the user has to be told it was: \(message)"
            )
        }
    }

    // MARK: - The defect PRD §7.1 names

    /// The half that was missing: ending the playback generation.
    func testALineThatNeverPlayedStopsBeingWhatTheCharacterIsSaying() async {
        let model = AppModel()
        _ = await model.speakCompanionLine("こんばんは")
        let during = await model.speechCoordinator.currentCue()
        XCTAssertNotNil(during, "the coordinator accepted the line")

        model.speechPlayer.fail(.voiceUnavailable)
        await model.speechDidFail()

        let after = await model.speechCoordinator.currentCue()
        XCTAssertNil(after, "a line that was never heard is not being said")
    }

    /// A failure is not an interruption, and the reasons stay apart: one line
    /// was taken away mid-sentence, the other was never heard.
    func testAFailureIsNotReportedAsAnInterruption() {
        XCTAssertNotEqual(SpeechCancellationReason.playbackFailed, .interrupted)
        XCTAssertEqual(SpeechCancellationReason.playbackFailed.rawValue, "playbackFailed")
    }

    /// `FAIL-006`: preserve the visible text. The transcript is written on
    /// acceptance and never depended on audio, and this holds it there.
    func testAFailedVoiceLeavesTheTranscriptAlone() async {
        let model = AppModel(chatGateway: MockChatGateway())
        await model.runChatTurn(text: "你好")
        let before = model.chatTranscript.map(\.eventID)
        XCTAssertFalse(before.isEmpty)

        model.speechPlayer.fail(.voiceUnavailable)
        await model.speechDidFail()

        XCTAssertEqual(model.chatTranscript.map(\.eventID), before)
        XCTAssertNotNil(model.latestCompanionLine, "the words are still on screen")
    }

    // MARK: - What the user is told

    func testTheFailureIsVisibleAndNamesItself() {
        let model = AppModel()
        XCTAssertNil(model.speechFailureMessage, "nothing is owed before anything is tried")

        model.speechPlayer.fail(.routeRefused)
        XCTAssertEqual(model.speechFailureMessage, SpeechFailure.routeRefused.message)
    }

    /// A fresh attempt supersedes the previous verdict: a stale reason must not
    /// outlive the line it was about.
    func testANewLineClearsTheOldReason() {
        let model = AppModel()
        model.speechPlayer.fail(.voiceUnavailable)
        XCTAssertNotNil(model.speechFailureMessage)

        model.speechPlayer.speak("こんばんは")
        XCTAssertNil(model.speechFailureMessage, "a new attempt owes its own verdict, not the last one's")
    }

    /// A line the user stopped owes no explanation.
    func testStoppingClearsTheReasonRatherThanExplainingIt() {
        let model = AppModel()
        model.speechPlayer.fail(.audioUndecodable)
        model.speechPlayer.stop()
        XCTAssertNil(model.speechFailureMessage)
    }

    /// A failed line does not leave the player believing it is talking — the
    /// same stuck state `G2-J5F` fixed for interruptions.
    func testAFailedLineDoesNotLeaveTheCharacterSpeaking() {
        let model = AppModel()
        model.speechPlayer.fail(.voiceUnavailable)
        XCTAssertFalse(model.speechPlayer.isSpeaking)
    }

    // MARK: - Retry is offered, not performed

    /// PRD §7's "retry after route/interruption recovery", kept manual for the
    /// same reason `G2-J5F` never resumes: the product does not decide on its
    /// own that a stale line is still worth hearing.
    func testRetryReplaysTheVoiceLineAndClaimsTheVoiceAgain() async {
        let model = AppModel()
        _ = await model.speakCompanionLine("こんばんは")
        model.speechPlayer.fail(.voiceUnavailable)
        await model.speechDidFail()
        let cleared = await model.speechCoordinator.currentCue()
        XCTAssertNil(cleared)

        await model.retryLastVoiceLine()

        let cue = await model.speechCoordinator.currentCue()
        XCTAssertEqual(cue?.text, "こんばんは", "a retry replays what was meant to be heard")
    }

    /// Nothing to replay is not an error, and must not register an empty cue.
    func testRetryingWithNothingSpokenYetDoesNothing() async {
        let model = AppModel()
        await model.retryLastVoiceLine()
        let cue = await model.speechCoordinator.currentCue()
        XCTAssertNil(cue)
    }
}
