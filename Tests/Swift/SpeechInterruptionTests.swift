import CompanionCore
import XCTest
@testable import JoiMobile

/// `G2-J5F` — `FAIL-007`, the state nothing observed.
///
/// `SpeechCancellationReason.interrupted` has been in the frozen contract since
/// G1 and nothing produced it. The consequence was worse than a truncated line:
/// `AVAudioPlayer` pauses on interruption *without* calling
/// `audioPlayerDidFinishPlaying`, so `isSpeaking` stayed true for the rest of
/// the app's life, and `beginVoiceInput` refuses the microphone while the
/// character is speaking. One phone call left push-to-talk dead.
@MainActor
final class SpeechInterruptionTests: XCTestCase {

    // MARK: - The policy, without audio hardware

    func testAnInterruptionEndsTheLine() {
        XCTAssertEqual(
            SpeechInterruptionPolicy.decide(.interruptionBegan, isSpeaking: true),
            .endLine(.interrupted)
        )
    }

    /// The rule worth stating: PRD §7 requires current-state validation before
    /// resume, and by the time the interruption ends there is nothing left to
    /// validate. The line was ended when it began, and the request, character or
    /// walk it belonged to may all have moved on.
    func testTheSystemsResumeHintIsNotObeyed() {
        for suggests in [true, false] {
            XCTAssertEqual(
                SpeechInterruptionPolicy.decide(
                    .interruptionEnded(systemSuggestsResume: suggests),
                    isSpeaking: true
                ),
                .ignore,
                "a line is never resumed, whatever the system suggests"
            )
        }
    }

    /// Unplugging headphones must not continue the character's voice out of the
    /// speaker; plugging something in is not a reason to stop talking.
    func testLosingTheOutputDeviceEndsTheLineAndOtherRouteChangesDoNot() {
        XCTAssertEqual(
            SpeechInterruptionPolicy.decide(.routeChanged(outputDeviceLost: true), isSpeaking: true),
            .endLine(.interrupted)
        )
        XCTAssertEqual(
            SpeechInterruptionPolicy.decide(.routeChanged(outputDeviceLost: false), isSpeaking: true),
            .ignore
        )
    }

    func testLeavingTheForegroundEndsTheLineAndComingBackDoesNotResumeIt() {
        XCTAssertEqual(
            SpeechInterruptionPolicy.decide(.leftForeground, isSpeaking: true),
            .endLine(.interrupted)
        )
        XCTAssertEqual(
            SpeechInterruptionPolicy.decide(.enteredForeground, isSpeaking: true),
            .ignore
        )
    }

    /// Every event is inert with no line in the air, so an idle app does not
    /// cancel a cue that does not exist.
    func testNothingHappensWhenNothingIsBeingSaid() {
        let events: [SpeechInterruptionEvent] = [
            .interruptionBegan,
            .interruptionEnded(systemSuggestsResume: true),
            .routeChanged(outputDeviceLost: true),
            .leftForeground,
            .enteredForeground,
        ]
        for event in events {
            XCTAssertEqual(
                SpeechInterruptionPolicy.decide(event, isSpeaking: false),
                .ignore,
                "\(event) acted on an idle app"
            )
        }
    }

    // MARK: - The defect it exists to prevent

    /// The whole point: after an interruption the microphone must be openable
    /// again. This is the state that used to stick.
    func testAnInterruptedLineDoesNotLeaveTheCharacterSpeakingForever() async {
        let model = AppModel()
        let generation = await model.speakCompanionLine("こんばんは")
        XCTAssertNotNil(generation, "the coordinator accepted the line")

        model.speechPlayer.handle(.interruptionBegan)

        XCTAssertFalse(
            model.speechPlayer.isSpeaking,
            "an interrupted line must not leave the player believing it is talking"
        )
    }

    /// The owner is told, not only the player: `SpeechCoordinator` may not go on
    /// reporting a line nobody is saying.
    func testAnInterruptionRetiresTheCue() async {
        let model = AppModel()
        _ = await model.speakCompanionLine("こんばんは")
        let during = await model.speechCoordinator.currentCue()
        XCTAssertNotNil(during, "a line is in the air before the interruption")

        await model.speechWasInterrupted()

        let after = await model.speechCoordinator.currentCue()
        XCTAssertNil(after, "the coordinator must not report a line nobody is saying")
    }

    /// An interruption is not a reason to lose accepted words. `JM-P0-007`:
    /// interruption never commits *or discards* accepted transcript.
    func testAnInterruptionLeavesTheTranscriptAlone() async {
        let model = AppModel(chatGateway: MockChatGateway())
        await model.runChatTurn(text: "你好")
        let before = model.chatTranscript.map(\.eventID)
        XCTAssertFalse(before.isEmpty, "there is a transcript to protect")

        model.speechPlayer.handle(.interruptionBegan)
        await model.speechWasInterrupted()

        XCTAssertEqual(model.chatTranscript.map(\.eventID), before)
    }

    /// A completion arriving for the interrupted generation is refused, so a
    /// late callback cannot revive a line the system already took.
    func testALateCompletionForAnInterruptedLineIsRefused() async {
        let model = AppModel()
        let generation = await model.speakCompanionLine("こんばんは")
        guard let generation else { return XCTFail("no generation") }

        await model.speechWasInterrupted()

        let accepts = await model.speechCoordinator.acceptsCompletion(for: generation)
        XCTAssertFalse(accepts, "the interrupted generation is no longer current")
    }
}
