import Foundation

public enum MemoryCategory: String, Codable, Hashable, Sendable, CaseIterable {
    case profile
    case preference
    case relationship
    case travelRecap
    case preciseLocation
    case protectedNeverSync
}

public enum MemoryDataClassification: String, Codable, Sendable {
    case standard
    case sensitiveLocation
    case protectedNeverSync
}

public enum MemoryProvenance: String, Codable, Sendable {
    case userEntered
    case userApprovedProposal
    case importedWithConsent
}

public struct MemoryRecordV1: Codable, Equatable, Sendable {
    public let recordID: String
    public let characterID: String
    public let threadID: String?
    public let category: MemoryCategory
    public let classification: MemoryDataClassification
    public let value: String
    public let provenance: MemoryProvenance
    public let reason: String
    public let precision: String?
    public let authorizationDigest: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let syncEligible: Bool

    public init(
        recordID: String,
        characterID: String,
        threadID: String? = nil,
        category: MemoryCategory,
        classification: MemoryDataClassification,
        value: String,
        provenance: MemoryProvenance,
        reason: String,
        precision: String? = nil,
        authorizationDigest: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        syncEligible: Bool = false
    ) {
        self.recordID = recordID
        self.characterID = characterID
        self.threadID = threadID
        self.category = category
        self.classification = classification
        self.value = value
        self.provenance = provenance
        self.reason = reason
        self.precision = precision
        self.authorizationDigest = authorizationDigest
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncEligible = category == .preciseLocation ? false : syncEligible
    }
}

public enum MemoryProposalState: String, Codable, Sendable {
    case proposed
    case accepted
    case editedAndAccepted
    case rejected
    case expired
}

public struct MemoryProposalV1: Codable, Equatable, Sendable {
    public let proposalID: String
    public let category: MemoryCategory
    public let value: String
    public let reason: String
    public let state: MemoryProposalState
    public let expiresAt: Date

    public init(
        proposalID: String,
        category: MemoryCategory,
        value: String,
        reason: String,
        state: MemoryProposalState,
        expiresAt: Date
    ) {
        self.proposalID = proposalID
        self.category = category
        self.value = value
        self.reason = reason
        self.state = state
        self.expiresAt = expiresAt
    }
}

public enum JourneyUsePurpose: String, Codable, Sendable {
    case chatOneTurn
}

public struct JourneyUseReceiptV1: Codable, Equatable, Sendable {
    public let receiptID: String
    public let purpose: JourneyUsePurpose
    public let userAction: String
    public let payloadDigest: String
    public let precision: String
    public let threadID: String
    public let requestID: String
    public let issuedAt: Date
    public let expiresAt: Date
    public let revoked: Bool

    public init(
        receiptID: String,
        purpose: JourneyUsePurpose,
        userAction: String,
        payloadDigest: String,
        precision: String,
        threadID: String,
        requestID: String,
        issuedAt: Date,
        expiresAt: Date,
        revoked: Bool
    ) {
        self.receiptID = receiptID
        self.purpose = purpose
        self.userAction = userAction
        self.payloadDigest = payloadDigest
        self.precision = precision
        self.threadID = threadID
        self.requestID = requestID
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.revoked = revoked
    }
}

public struct LocationMemoryAuthorizationV1: Codable, Equatable, Sendable {
    public let authorizationID: String
    public let payloadDigest: String
    public let precision: String
    public let retention: String
    public let issuedAt: Date

    public init(
        authorizationID: String,
        payloadDigest: String,
        precision: String,
        retention: String,
        issuedAt: Date
    ) {
        self.authorizationID = authorizationID
        self.payloadDigest = payloadDigest
        self.precision = precision
        self.retention = retention
        self.issuedAt = issuedAt
    }
}

public struct LocationSyncAuthorizationV1: Codable, Equatable, Sendable {
    public let authorizationID: String
    public let recordRevisionDigest: String
    public let precision: String
    public let remoteRetention: String
    public let accountID: String
    public let issuedAt: Date

    public init(
        authorizationID: String,
        recordRevisionDigest: String,
        precision: String,
        remoteRetention: String,
        accountID: String,
        issuedAt: Date
    ) {
        self.authorizationID = authorizationID
        self.recordRevisionDigest = recordRevisionDigest
        self.precision = precision
        self.remoteRetention = remoteRetention
        self.accountID = accountID
        self.issuedAt = issuedAt
    }
}

public enum SyncOperation: String, Codable, Sendable {
    case upsert
    case tombstone
}

public struct MemorySyncRecordV1: Codable, Equatable, Sendable {
    public let recordID: String
    public let category: MemoryCategory
    public let characterID: String
    public let encryptedPayload: String?
    public let revision: Int
    public let deviceID: String
    public let operation: SyncOperation
    public let updatedAt: Date

    public init(
        recordID: String,
        category: MemoryCategory,
        characterID: String,
        encryptedPayload: String?,
        revision: Int,
        deviceID: String,
        operation: SyncOperation,
        updatedAt: Date
    ) {
        self.recordID = recordID
        self.category = category
        self.characterID = characterID
        self.encryptedPayload = encryptedPayload
        self.revision = revision
        self.deviceID = deviceID
        self.operation = operation
        self.updatedAt = updatedAt
    }
}

public struct CharacterPackageSyncRecordV1: Codable, Equatable, Sendable {
    public let packageID: String
    public let contentID: String
    public let encryptedAssetReference: String?
    public let revision: Int
    public let deviceID: String
    public let operation: SyncOperation
    public let updatedAt: Date

    public init(
        packageID: String,
        contentID: String,
        encryptedAssetReference: String?,
        revision: Int,
        deviceID: String,
        operation: SyncOperation,
        updatedAt: Date
    ) {
        self.packageID = packageID
        self.contentID = contentID
        self.encryptedAssetReference = encryptedAssetReference
        self.revision = revision
        self.deviceID = deviceID
        self.operation = operation
        self.updatedAt = updatedAt
    }
}

public protocol MemoryRepository: Sendable {
    func list(characterID: String) async throws -> [MemoryRecordV1]
    func save(_ record: MemoryRecordV1, authorizationDigest: String?) async throws
    func delete(recordID: String) async throws
}
