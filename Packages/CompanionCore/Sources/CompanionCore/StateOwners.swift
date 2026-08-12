import Foundation

public struct CompanionSessionSnapshot: Codable, Equatable, Sendable {
    public let selection: CharacterSelection
    public let threadID: String
    public let sessionID: String
    public let acceptedEventIDs: [String]

    public var characterID: String { selection.characterID }
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
            acceptedEventIDs: snapshot.acceptedEventIDs
        )
        return true
    }

    public func accept(eventID: String) {
        guard !snapshot.acceptedEventIDs.contains(eventID) else { return }
        snapshot = CompanionSessionSnapshot(
            selection: snapshot.selection,
            threadID: snapshot.threadID,
            sessionID: snapshot.sessionID,
            acceptedEventIDs: snapshot.acceptedEventIDs + [eventID]
        )
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
