import Foundation

public enum ChatRequestValidationError: Error, Equatable, Sendable {
    case missingJourneyReceipt
    case receiptWithoutAttachment
    case wrongPurpose
    case missingUserAction
    case identityMismatch
    case digestMismatch
    case notYetValid
    case expired
    case revoked
    case receiptAlreadyUsed
}

public struct ChatRequest: Codable, Equatable, Sendable {
    public let requestID: String
    public let threadID: String
    public let sessionID: String
    public let characterID: String
    public let text: String
    public let displayLocale: String
    public let voiceLocale: String
    public let journeyAttachment: JourneyContextSnapshot?
    public let journeyReceipt: JourneyUseReceiptV1?

    public init(
        requestID: String,
        threadID: String,
        sessionID: String,
        characterID: String,
        text: String,
        displayLocale: String,
        voiceLocale: String,
        journeyAttachment: JourneyContextSnapshot? = nil,
        journeyReceipt: JourneyUseReceiptV1? = nil,
        validationDate: Date = Date()
    ) throws {
        self.requestID = requestID
        self.threadID = threadID
        self.sessionID = sessionID
        self.characterID = characterID
        self.text = text
        self.displayLocale = displayLocale
        self.voiceLocale = voiceLocale
        self.journeyAttachment = journeyAttachment
        self.journeyReceipt = journeyReceipt
        try validate(at: validationDate)
    }

    public func validate(at date: Date = Date()) throws {
        switch (journeyAttachment, journeyReceipt) {
        case (nil, nil):
            return
        case (.some, nil):
            throw ChatRequestValidationError.missingJourneyReceipt
        case (nil, .some):
            throw ChatRequestValidationError.receiptWithoutAttachment
        case let (.some(attachment), .some(receipt)):
            guard receipt.purpose == .chatOneTurn else {
                throw ChatRequestValidationError.wrongPurpose
            }
            guard !receipt.userAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ChatRequestValidationError.missingUserAction
            }
            guard receipt.threadID == threadID, receipt.requestID == requestID else {
                throw ChatRequestValidationError.identityMismatch
            }
            guard receipt.payloadDigest == attachment.payloadDigest() else {
                throw ChatRequestValidationError.digestMismatch
            }
            guard receipt.issuedAt <= date else {
                throw ChatRequestValidationError.notYetValid
            }
            guard receipt.expiresAt > date else {
                throw ChatRequestValidationError.expired
            }
            guard !receipt.revoked else {
                throw ChatRequestValidationError.revoked
            }
        }
    }
}

public actor JourneyUseReceiptStore {
    private var consumedReceiptIDs: Set<String> = []

    public init() {}

    public func consume(for request: ChatRequest, at date: Date = Date()) throws {
        try request.validate(at: date)
        guard let receipt = request.journeyReceipt else { return }
        guard consumedReceiptIDs.insert(receipt.receiptID).inserted else {
            throw ChatRequestValidationError.receiptAlreadyUsed
        }
    }
}

public protocol ChatGateway: Sendable {
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<CompanionEventV1, Error>
}

public enum SyncEnvelopeV1: Codable, Equatable, Sendable {
    case memory(MemorySyncRecordV1)
    case characterPackage(CharacterPackageSyncRecordV1)
}

public struct SyncCursor: Codable, Equatable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct SyncPage: Codable, Equatable, Sendable {
    public let records: [SyncEnvelopeV1]
    public let cursor: SyncCursor?
    public init(records: [SyncEnvelopeV1], cursor: SyncCursor?) {
        self.records = records
        self.cursor = cursor
    }
}

public protocol SyncGateway: Sendable {
    func push(_ records: [SyncEnvelopeV1], after cursor: SyncCursor?) async throws -> SyncPage
    func pull(after cursor: SyncCursor?) async throws -> SyncPage
}

public enum SpeechPriority: Int, Codable, Sendable, Comparable {
    case preview = 0
    case conversation = 10
    case placeNarration = 20
    case routeManeuver = 30

    public static func < (lhs: SpeechPriority, rhs: SpeechPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct SpeechCue: Codable, Equatable, Sendable {
    public let cueID: String
    public let text: String
    public let displayLocale: String
    public let voiceLocale: String
    public let priority: SpeechPriority
    public let sessionID: String
    public let characterID: String

    public init(
        cueID: String,
        text: String,
        displayLocale: String,
        voiceLocale: String,
        priority: SpeechPriority,
        sessionID: String,
        characterID: String
    ) {
        self.cueID = cueID
        self.text = text
        self.displayLocale = displayLocale
        self.voiceLocale = voiceLocale
        self.priority = priority
        self.sessionID = sessionID
        self.characterID = characterID
    }
}

public struct SpeechGeneration: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public enum SpeechCancellationReason: String, Codable, Sendable {
    case userStopped
    case superseded
    case routePriority
    case characterChanged
    case interrupted
}

public enum SpeechStartResult: Equatable, Sendable {
    case started(SpeechGeneration)
    case preempted(new: SpeechGeneration, cancelled: SpeechGeneration)
    case rejected(active: SpeechGeneration)

    public var acceptedGeneration: SpeechGeneration? {
        switch self {
        case .started(let generation), .preempted(let generation, _):
            generation
        case .rejected:
            nil
        }
    }
}

public actor SpeechCoordinator {
    private var current: (cue: SpeechCue, generation: SpeechGeneration)?

    public init() {}

    public func begin(_ cue: SpeechCue) -> SpeechStartResult {
        if let current, current.cue.priority > cue.priority {
            return .rejected(active: current.generation)
        }
        let generation = SpeechGeneration()
        let replaced = current?.generation
        current = (cue, generation)
        if let replaced {
            return .preempted(new: generation, cancelled: replaced)
        }
        return .started(generation)
    }

    public func cancel(reason _: SpeechCancellationReason) {
        current = nil
    }

    public func acceptsCompletion(for generation: SpeechGeneration) -> Bool {
        current?.generation == generation
    }

    public func currentCue() -> SpeechCue? {
        current?.cue
    }
}
