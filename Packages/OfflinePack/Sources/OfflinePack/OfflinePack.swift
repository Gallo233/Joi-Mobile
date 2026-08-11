import CompanionCore
import Foundation

public enum OfflinePackError: Error, Equatable, Sendable {
    case unsupportedSchema
    case missingRights
    case missingRoute
    case expired
}

public struct OfflinePackVerifier: Sendable {
    public init() {}

    public func verify(_ manifest: TravelPackManifestV1, now: Date = Date()) throws {
        guard manifest.schema == "joi.travel-pack.v1" else {
            throw OfflinePackError.unsupportedSchema
        }
        guard !manifest.routePath.isEmpty else {
            throw OfflinePackError.missingRoute
        }
        guard !manifest.rights.isEmpty else {
            throw OfflinePackError.missingRights
        }
        if let expiresAt = manifest.expiresAt, expiresAt <= now {
            throw OfflinePackError.expired
        }
    }
}
