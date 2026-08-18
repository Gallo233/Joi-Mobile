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

    // `FAIL-025 offlinePackMissing`: content the pack promised is not there.
    // Recoverable by fetching the pack again.
    case missingFile(String)

    // `FAIL-026 offlinePackInvalid`: the pack is present and wrong. Not a
    // redownload problem — a pack you should not trust.
    case invalidManifest
    case invalidContent
    case hashMismatch(String)
    /// Content the pack ships but never declared. A hash list proves what it
    /// covers and says nothing about what it does not (DEC-020's rule, applied
    /// to tours).
    case undeclaredFile(String)
    /// A path that could reach outside the pack, or an entry that is not a
    /// regular file.
    case unsupportedEntry(String)
    case tooManyFiles
    case packTooLarge
    /// Sealing the verified pack into the store did not produce the pack that
    /// was verified.
    case activationFailed

    /// `FAIL-029 storageInsufficient`: the device cannot hold this pack.
    ///
    /// Carries both numbers because the state's whole requirement is to show
    /// required against available — "not enough space" without them tells the
    /// user nothing they can act on.
    case storageInsufficient(requiredBytes: Int, availableBytes: Int)
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
