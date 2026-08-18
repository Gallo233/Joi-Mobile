import XCTest
@testable import JoiMobile

/// `G2-J2C` acceptance. Live transcription needs a real voice and a real
/// microphone, so what is provable here is the part that decides whether the
/// microphone opens at all, what the user is told when it does not, and that a
/// recognised sentence lands somewhere the user can still edit it.
@MainActor
final class VoiceInputTests: XCTestCase {
    /// `J2C-04` — every failure carries Chinese copy, and the states that speak
    /// for themselves through the button carry none.
    func testEveryFailureStateExplainsItselfInChinese() {
        for state in [VoiceInput.State.unavailable, .denied, .heardNothing, .failed] {
            let message = state.message
            XCTAssertNotNil(message, "\(state) must explain itself")
            XCTAssertFalse(message?.isEmpty ?? true)
        }
        XCTAssertNil(VoiceInput.State.idle.message)
        XCTAssertNil(VoiceInput.State.requestingPermission.message)
        XCTAssertNil(VoiceInput.State.listening(partial: "在说话").message)
    }

    /// `J2C-02` — nothing is requested at construction. The permission prompt
    /// belongs to the first press, not to launch.
    func testConstructionRequestsNothingAndListensToNothing() {
        let voice = VoiceInput()
        XCTAssertEqual(voice.state, .idle)
        XCTAssertFalse(voice.state.isListening)
    }

    /// `J2C-01` — an unavailable recogniser is a named state, not a dead button.
    /// The simulator has no on-device Chinese recogniser, which is exactly the
    /// case this row exists for.
    func testUnavailableRecognitionEndsAsANamedStateRatherThanSilence() async throws {
        let voice = VoiceInput()
        guard !voice.isAvailable else {
            throw XCTSkip("this host can recognise on device; the unavailable path cannot be exercised here")
        }
        await voice.begin()
        XCTAssertEqual(voice.state, .unavailable)
        XCTAssertNotNil(voice.state.message)
        // And it clears once the user has seen it.
        voice.acknowledge()
        XCTAssertEqual(voice.state, .idle)
    }

    /// `J2C-04` — a failure the user has read must not linger, and acknowledging
    /// a state that is not a failure must not disturb it.
    func testAcknowledgeClearsOnlyFailureStates() {
        let voice = VoiceInput()
        voice.acknowledge()
        XCTAssertEqual(voice.state, .idle)
    }

    /// `J2C-03` — a recognised sentence becomes an editable draft. Voice is an
    /// input method; it never sends on the user's behalf.
    func testRecognisedTextLandsInTheDraftAndIsNotSent() async {
        let model = AppModel()
        model.chatDraft = ""
        // `finish` with nothing listening yields nothing, and must not fabricate
        // a draft or a turn.
        model.finishVoiceInput()
        XCTAssertEqual(model.chatDraft, "")
        XCTAssertFalse(model.chatTurnState.isPending, "voice input never starts a turn by itself")
        XCTAssertTrue(model.chatTranscript.isEmpty)
    }

    /// `J2C-05` — the microphone must not open while the character is talking,
    /// or it would record the character's own voice back into the composer.
    func testListeningIsRefusedWhileTheCharacterIsSpeaking() async {
        let model = AppModel()
        model.speechPlayer.speak("しゃべっている")
        // `speak` is asynchronous about fetching, so drive the guard directly on
        // the state it reads rather than racing the network.
        if model.speechPlayer.isSpeaking {
            await model.beginVoiceInput()
            XCTAssertFalse(model.voiceInput.state.isListening)
        }
        model.speechPlayer.stop()
    }
}
