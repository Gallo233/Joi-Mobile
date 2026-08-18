import CompanionCore
import Foundation

public enum OfflinePackError: Error, Equatable, Sendable {
    case unsupportedSchema
    case missingRights
    case missingRoute
    case expired
    /// A tour with nothing to stop at. Distinct from `missingRoute`: the line
    /// exists, the story does not.
    case noStops
    /// A declared stop does not project onto the route it belongs to. A tour
    /// missing one of its stops is a broken pack, not a shorter tour.
    case stopOffRoute(String)
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
