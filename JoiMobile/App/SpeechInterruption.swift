import CompanionCore
import Foundation

/// Something the system did to the audio the character was speaking.
///
/// Named as facts rather than as `AVAudioSession` constants so the policy below
/// can be tested without audio hardware, the way `MouthOpening` was extracted in
/// `G2-J2B` for the same reason. `SpeechPlayer` translates the real
/// notifications into these.
enum SpeechInterruptionEvent: Equatable, Sendable {
    /// An interruption began: a call, Siri, an alarm, another app taking the
    /// session.
    case interruptionBegan
    /// The interruption ended. `systemSuggestsResume` carries
    /// `AVAudioSession.InterruptionOptions.shouldResume`, which this product
    /// deliberately does not obey — see `decide`.
    case interruptionEnded(systemSuggestsResume: Bool)
    /// The output route changed. `outputDeviceLost` is `.oldDeviceUnavailable`:
    /// headphones unplugged, Bluetooth walked away.
    case routeChanged(outputDeviceLost: Bool)
    /// The app left the foreground. There is no background-audio entitlement, so
    /// the system is stopping this audio whether the app agrees or not.
    case leftForeground
    /// The app came back to the foreground.
    case enteredForeground
}

/// What the speech owner must do about it.
enum SpeechInterruptionOutcome: Equatable, Sendable {
    /// End the line now, and tell the coordinator why. Nothing resumes it.
    case endLine(SpeechCancellationReason)
    /// Nothing to do.
    case ignore
}

/// `FAIL-007` — what an interrupted line does.
///
/// Before this, nothing in the product observed an audio interruption at all,
/// and the consequence was worse than a truncated line. `AVAudioPlayer` pauses
/// on interruption without calling `audioPlayerDidFinishPlaying`, so
/// `SpeechPlayer.isSpeaking` stayed `true` for the rest of the app's life — and
/// `beginVoiceInput` refuses to open the microphone while the character is
/// speaking. One phone call during one line left push-to-talk dead until the
/// character spoke again. `SpeechCancellationReason.interrupted` has existed in
/// the frozen contract since G1 with nothing producing it.
enum SpeechInterruptionPolicy {

    /// - Parameter isSpeaking: whether a line is actually in the air. Every event
    ///   is inert without one, so a route change while the app is idle is not an
    ///   occasion to cancel a cue that does not exist.
    static func decide(_ event: SpeechInterruptionEvent, isSpeaking: Bool) -> SpeechInterruptionOutcome {
        guard isSpeaking else { return .ignore }

        switch event {
        case .interruptionBegan:
            return .endLine(.interrupted)

        case .interruptionEnded:
            // Never resumed, whatever the system suggests. PRD §7 requires
            // current-state validation before resume, and by this point there is
            // nothing left to validate: the line was ended when the interruption
            // began, and the state it belonged to — the request, the character,
            // the walk — may all have moved on. The transcript still carries the
            // words, so the cost of not resuming is a line the user can read
            // rather than one they must hear.
            return .ignore

        case .routeChanged(let outputDeviceLost):
            // Unplugging headphones must not continue the character's voice out
            // of the speaker. Any other route change — plugging *in*, switching
            // to a better device — is not a reason to stop talking.
            return outputDeviceLost ? .endLine(.interrupted) : .ignore

        case .leftForeground:
            // The audio is stopping regardless; this is the state following the
            // fact rather than causing it.
            return .endLine(.interrupted)

        case .enteredForeground:
            return .ignore
        }
    }
}
