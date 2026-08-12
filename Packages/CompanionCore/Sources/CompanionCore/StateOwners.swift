import Foundation

public enum TranscriptAuthor: String, Codable, Equatable, Sendable {
    case user
    case companion
}

/// One accepted transcript line. Only `acceptedInput` and `acceptedFinal`
/// events may become an entry, and each `eventID` appends exactly once.
public struct TranscriptEntry: Codable, Equatable, Sendable {
    public let eventID: String
    public let requestID: String
    public let author: TranscriptAuthor
    public let text: String
    public let timestamp: Date
    public let memoryEligibility: MemoryEligibility

    public init(
        eventID: String,
        requestID: String,
        author: TranscriptAuthor,
        text: String,
        timestamp: Date,
        memoryEligibility: MemoryEligibility = .none
    ) {
        self.eventID = eventID
        self.requestID = requestID
        self.author = author
        self.text = text
        self.timestamp = timestamp
        self.memoryEligibility = memoryEligibility
    }
}

public struct CompanionSessionSnapshot: Codable, Equatable, Sendable {
    public let selection: CharacterSelection
    public let threadID: String
    public let sessionID: String
    public let acceptedEventIDs: [String]
    public let transcript: [TranscriptEntry]

    public var characterID: String { selection.characterID }

    public init(
        selection: CharacterSelection,
        threadID: String,
        sessionID: String,
        acceptedEventIDs: [String],
        transcript: [TranscriptEntry] = []
    ) {
        self.selection = selection
        self.threadID = threadID
        self.sessionID = sessionID
        self.acceptedEventIDs = acceptedEventIDs
        self.transcript = transcript
    }
}

public actor CompanionSessionStore {
    private var snapshot: CompanionSessionSnapshot

    public init(
        characterID: String,
        displayName: String = "Joi",
        threadID: String,
        sessionID: String
    ) {
        snapshot = CompanionSessionSnapshot(
            selection: CharacterSelection(
                characterID: characterID,
                displayName: displayName
            ),
            threadID: threadID,
            sessionID: sessionID,
            acceptedEventIDs: []
        )
    }

    public func current() -> CompanionSessionSnapshot {
        snapshot
    }

    @discardableResult
    public func activate(
        selection: CharacterSelection,
        expecting expected: CharacterSelection
    ) -> Bool {
        guard !Task.isCancelled else { return false }
        guard snapshot.selection == expected else { return false }
        snapshot = CompanionSessionSnapshot(
            selection: selection,
            threadID: snapshot.threadID,
            sessionID: snapshot.sessionID,
            acceptedEventIDs: snapshot.acceptedEventIDs,
            transcript: snapshot.transcript
        )
        return true
    }

    public func accept(eventID: String) {
        guard !snapshot.acceptedEventIDs.contains(eventID) else { return }
        snapshot = CompanionSessionSnapshot(
            selection: snapshot.selection,
            threadID: snapshot.threadID,
            sessionID: snapshot.sessionID,
            acceptedEventIDs: snapshot.acceptedEventIDs + [eventID],
            transcript: snapshot.transcript
        )
    }

    /// Appends an accepted transcript line exactly once. Returns false when the
    /// event was already accepted or when it does not belong to this session's
    /// thread — a late or foreign event must never extend the transcript.
    @discardableResult
    public func appendAccepted(_ entry: TranscriptEntry, threadID: String) -> Bool {
        guard threadID == snapshot.threadID else { return false }
        guard !snapshot.acceptedEventIDs.contains(entry.eventID) else { return false }
        snapshot = CompanionSessionSnapshot(
            selection: snapshot.selection,
            threadID: snapshot.threadID,
            sessionID: snapshot.sessionID,
            acceptedEventIDs: snapshot.acceptedEventIDs + [entry.eventID],
            transcript: snapshot.transcript + [entry]
        )
        return true
    }
}

public actor JourneyContextStore {
    private var snapshot: JourneyContextSnapshot = .empty
    private var activeNavigationSession: NavigationSessionID?

    public init() {}

    public func current() -> JourneyContextSnapshot {
        snapshot
    }

    public func begin(route: AcceptedNavigationRoute, session: NavigationSessionID) {
        activeNavigationSession = session
        snapshot = JourneyContextSnapshot(
            journeyID: session.rawValue.uuidString,
            routeID: route.routeID,
            routeProgress: 0,
            consentScope: "ephemeral"
        )
    }

    @discardableResult
    public func reduce(_ observation: NavigationObservation) -> Bool {
        guard observation.sessionID == activeNavigationSession else { return false }
        snapshot = JourneyContextSnapshot(
            journeyID: snapshot.journeyID,
            placeID: snapshot.placeID,
            routeID: snapshot.routeID,
            stopID: snapshot.stopID,
            coordinate: observation.nearestCoordinate,
            routeProgress: min(max(observation.candidateProgress, 0), 1),
            sourceRevisionIDs: snapshot.sourceRevisionIDs,
            consentScope: "ephemeral"
        )
        return true
    }

    public func clear() {
        activeNavigationSession = nil
        snapshot = .empty
    }
}
