import CompanionCore
import Foundation

/// What a single event is allowed to do to visible state, per TDD 3.4.
/// Draft text is a replaceable projection; only accepted events may append.
public enum ChatTurnEffect: Equatable, Sendable {
    /// Editable/replaceable projection only. Never appended, never spoken as final.
    case draft(String?)
    /// Append exactly once to the accepted transcript.
    case append(TranscriptEntry)
    /// Diagnostic status only. Never appended, never memory eligible.
    case diagnostic(phase: CompanionPublicPhase, errorCode: String?)
    /// A phase change with no content effect.
    case status(CompanionPublicPhase)
}

// An unrecognized `contentState` needs no case here: `CompanionContentState` is
// a closed enum, so an unknown wire value fails to decode and the event is
// rejected before reaching this reducer. That is stricter than ignoring it, and
// is what "unknown values do not become accepted or memory eligible" requires.

/// Pure reducer from a validated event to its permitted effect. Identity
/// filtering (request/thread/session/character) already happened in
/// `ChatSessionController`; this decides acceptance only.
public struct ChatTurnProjection: Sendable {
    public init() {}

    public func effect(of event: CompanionEventV1) -> ChatTurnEffect {
        switch event.contentState {
        case .partial, .streamingDraft:
            return .draft(event.displayText)
        case .acceptedInput:
            return append(event, author: .user)
        case .acceptedFinal:
            return append(event, author: .companion)
        case .cancelled, .failed:
            return .diagnostic(phase: event.phase, errorCode: event.errorCode)
        }
    }

    private func append(_ event: CompanionEventV1, author: TranscriptAuthor) -> ChatTurnEffect {
        // An accepted event with no text carries no line to show; treat it as a
        // phase change rather than appending an empty transcript entry.
        guard let text = event.displayText, !text.isEmpty else {
            return .status(event.phase)
        }
        return .append(
            TranscriptEntry(
                eventID: event.eventID,
                requestID: event.requestID,
                author: author,
                text: text,
                timestamp: event.timestamp,
                memoryEligibility: event.memoryEligibility
            )
        )
    }
}
