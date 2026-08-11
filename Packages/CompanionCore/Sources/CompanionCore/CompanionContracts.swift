import Foundation

public enum CompanionPublicPhase: String, Codable, Sendable, CaseIterable {
    case idle
    case received
    case understanding
    case thinking
    case acting
    case waiting
    case paused
    case done
    case failed
}

public enum CompanionContentState: String, Codable, Sendable {
    case partial
    case acceptedInput
    case streamingDraft
    case acceptedFinal
    case cancelled
    case failed
}

public enum MemoryEligibility: String, Codable, Sendable {
    case none
    case proposalAllowed
}

public struct SourceProjectionV1: Codable, Equatable, Sendable {
    public let placeID: String?
    public let claimID: String
    public let identityConfidence: Double?
    public let claimSupportConfidence: Double
    public let publisher: String
    public let title: String
    public let locator: String
    public let authority: String
    public let revision: String
    public let retrievedAt: Date
    public let conflictStatus: String
    public let correctionStatus: String
    public let rights: String
    public let withdrawn: Bool

    public init(
        placeID: String? = nil,
        claimID: String,
        identityConfidence: Double? = nil,
        claimSupportConfidence: Double,
        publisher: String,
        title: String,
        locator: String,
        authority: String,
        revision: String,
        retrievedAt: Date,
        conflictStatus: String,
        correctionStatus: String,
        rights: String,
        withdrawn: Bool
    ) {
        self.placeID = placeID
        self.claimID = claimID
        self.identityConfidence = identityConfidence
        self.claimSupportConfidence = claimSupportConfidence
        self.publisher = publisher
        self.title = title
        self.locator = locator
        self.authority = authority
        self.revision = revision
        self.retrievedAt = retrievedAt
        self.conflictStatus = conflictStatus
        self.correctionStatus = correctionStatus
        self.rights = rights
        self.withdrawn = withdrawn
    }
}

public struct CompanionEventV1: Codable, Equatable, Sendable {
    public let schema: String
    public let eventID: String
    public let requestID: String
    public let threadID: String
    public let sessionID: String
    public let characterID: String
    public let timestamp: Date
    public let phase: CompanionPublicPhase
    public let contentState: CompanionContentState
    public let displayText: String?
    public let voiceLine: String?
    public let memoryEligibility: MemoryEligibility
    public let sources: [SourceProjectionV1]
    public let errorCode: String?

    public init(
        schema: String = "joi.companion-event.v1",
        eventID: String,
        requestID: String,
        threadID: String,
        sessionID: String,
        characterID: String,
        timestamp: Date = Date(),
        phase: CompanionPublicPhase,
        contentState: CompanionContentState,
        displayText: String? = nil,
        voiceLine: String? = nil,
        memoryEligibility: MemoryEligibility = .none,
        sources: [SourceProjectionV1] = [],
        errorCode: String? = nil
    ) {
        self.schema = schema
        self.eventID = eventID
        self.requestID = requestID
        self.threadID = threadID
        self.sessionID = sessionID
        self.characterID = characterID
        self.timestamp = timestamp
        self.phase = phase
        self.contentState = contentState
        self.displayText = displayText
        self.voiceLine = voiceLine
        self.memoryEligibility = memoryEligibility
        self.sources = sources
        self.errorCode = errorCode
    }
}
