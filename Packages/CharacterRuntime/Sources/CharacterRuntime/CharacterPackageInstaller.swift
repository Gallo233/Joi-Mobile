@_spi(CharacterPackageInstaller) import CompanionCore
import Foundation

public struct LegacyManifestReceiptV1: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let legacySourceID: String
    public let mappedLocale: String?
    public let warnings: [String]
    public let creatorName: String?
    public let sourceType: String?
    public let sourceURL: String?
    public let updateURL: String?
    public let provenanceFormat: String?
    public let archiveSHA256: String?
    public let declaredLicense: String?

    public init(
        schemaVersion: Int = 1,
        legacySourceID: String,
        mappedLocale: String?,
        warnings: [String],
        creatorName: String? = nil,
        sourceType: String? = nil,
        sourceURL: String? = nil,
        updateURL: String? = nil,
        provenanceFormat: String? = nil,
        archiveSHA256: String? = nil,
        declaredLicense: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.legacySourceID = legacySourceID
        self.mappedLocale = mappedLocale
        self.warnings = warnings
        self.creatorName = creatorName
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.updateURL = updateURL
        self.provenanceFormat = provenanceFormat
        self.archiveSHA256 = archiveSHA256
        self.declaredLicense = declaredLicense
    }
}

public enum CharacterPackageImportPhase: String, Codable, Sendable {
    case copySource, preflight, extract, validate, seal, install, activation, removal, recovery
}

public enum CharacterPackageDisposition: String, Codable, Sendable {
    case rejected, quarantined, rolledBack
}

public enum CharacterPackageImportCode: String, Codable, Sendable {
    case malformedArchive
    case unsafeArchive
    case unsupportedArchive
    case unsupportedArchiveProfile
    case invalidManifest
    case unsupportedLegacy
    case hashMismatch
    case invalidRenderer
    case sourceChanged
    case rightsUnverified
    case staleHandle
    case inUse
    case recoveryRequired
    case installFailed
    case notFound
}

/// Deliberately contains no path, payload, underlying error or localized text.
public struct CharacterPackageImportFailure: Error, Equatable, Sendable {
    public let code: CharacterPackageImportCode
    public let phase: CharacterPackageImportPhase
    public let disposition: CharacterPackageDisposition
    public let recoveryKey: String?

    public init(
        _ code: CharacterPackageImportCode,
        _ phase: CharacterPackageImportPhase,
        _ disposition: CharacterPackageDisposition = .rejected,
        recoveryKey: String? = nil
    ) {
        self.code = code
        self.phase = phase
        self.disposition = disposition
        self.recoveryKey = recoveryKey
    }
}

public enum CharacterPackageImportRequest: Sendable {
    case joiCharacterArchive(URL)
    case rawVRM(URL)
    case live2DArchive(URL)
}

public struct CharacterPackagePreview: Equatable, Sendable {
    public let manifest: CharacterPackageManifestV1
    public let contentID: CharacterContentID
    public let legacyReceipt: LegacyManifestReceiptV1?
    public let warnings: [String]

    public init(
        manifest: CharacterPackageManifestV1,
        contentID: CharacterContentID,
        legacyReceipt: LegacyManifestReceiptV1?,
        warnings: [String]
    ) {
        self.manifest = manifest
        self.contentID = contentID
        self.legacyReceipt = legacyReceipt
        self.warnings = warnings
    }
}

public struct CharacterPackageInstallResult: Equatable, Sendable {
    public let installationID: CharacterInstallationID
    public let contentID: CharacterContentID
    public let manifest: CharacterPackageManifestV1
    public let warnings: [String]
    public let disposition: CharacterPackageDisposition?

    public init(
        installationID: CharacterInstallationID,
        contentID: CharacterContentID,
        manifest: CharacterPackageManifestV1,
        warnings: [String],
        disposition: CharacterPackageDisposition?
    ) {
        self.installationID = installationID
        self.contentID = contentID
        self.manifest = manifest
        self.warnings = warnings
        self.disposition = disposition
    }
}

public struct CharacterPackageCatalogEntry: Codable, Equatable, Sendable {
    public let installationID: CharacterInstallationID
    public let contentID: CharacterContentID
    public let characterID: String
    public let displayName: String
    public let renderer: CharacterRendererKind
    public let available: Bool
    public let activationAllowed: Bool

    public init(
        installationID: CharacterInstallationID,
        contentID: CharacterContentID,
        characterID: String,
        displayName: String,
        renderer: CharacterRendererKind,
        available: Bool,
        activationAllowed: Bool
    ) {
        self.installationID = installationID
        self.contentID = contentID
        self.characterID = characterID
        self.displayName = displayName
        self.renderer = renderer
        self.available = available
        self.activationAllowed = activationAllowed
    }
}

/// Read access to one installed character's sealed content, issued by the
/// installer only after it has revalidated the lease and the tree.
///
/// A renderer has to read real files, so some root must reach it. Handing it out
/// is therefore deliberate rather than an oversight: what the boundary actually
/// buys is that this value cannot be constructed by a consumer, is refused for a
/// stale, removed or mutated installation, and names the entry file from the
/// verified manifest instead of letting a caller guess a path.
public struct CharacterContentAccess: Equatable, Sendable {
    public let installationID: CharacterInstallationID
    public let contentID: CharacterContentID
    public let renderer: CharacterRendererKind
    /// Absolute root of the sealed, read-only content tree.
    public let root: URL
    /// Manifest-declared entry file, relative to `root`.
    public let entryPath: String
    /// Manifest-declared motions, already checked to name declared `.vrma`
    /// assets inside this tree. A renderer plays these and nothing else, so it
    /// can never be pointed at an arbitrary file (DEC-024).
    public let motions: [CharacterMotionV1]
    public let displayName: String

    @_spi(CharacterPackageInstaller)
    public init(
        installationID: CharacterInstallationID,
        contentID: CharacterContentID,
        renderer: CharacterRendererKind,
        root: URL,
        entryPath: String,
        motions: [CharacterMotionV1] = [],
        displayName: String
    ) {
        self.installationID = installationID
        self.contentID = contentID
        self.renderer = renderer
        self.root = root
        self.entryPath = entryPath
        self.motions = motions
        self.displayName = displayName
    }

    /// Absolute URL of the entry file.
    public var entryURL: URL {
        root.appendingPathComponent(entryPath)
    }

    /// Absolute URL of one declared motion's clip, or nil when the character
    /// declares no such motion.
    public func animationURL(forMotion motion: String) -> URL? {
        motions.first { $0.motion == motion }.map { root.appendingPathComponent($0.animation) }
    }
}

/// Filesystem-backed installer. Content roots reach a renderer only through
/// `contentAccess(for:)`, which revalidates first.
public actor CharacterPackageInstaller {
    private let root: URL
    private let paths: CharacterStorePaths
    private var records: [CharacterInstallationID: StoredCharacterRecord]
    private var activationLeases: [CharacterInstallationID: [UUID: CharacterActivationLease]] = [:]
    private let sourceCopyObserver: (@Sendable (Int) -> Void)?
    private let phaseObserver: (@Sendable (CharacterPackageImportPhase) -> Void)?
    private let deletionFaultInjector: (@Sendable (CharacterDeletionFaultPoint) -> Bool)?

    public init(root: URL) {
        let standardized = root.standardizedFileURL
        self.root = standardized
        self.paths = CharacterStorePaths(root: standardized)
        self.sourceCopyObserver = nil
        self.phaseObserver = nil
        self.deletionFaultInjector = nil
        self.records = CharacterStoreRecovery.bootstrap(paths: CharacterStorePaths(root: standardized))
    }

    init(
        root: URL,
        sourceCopyObserver: (@Sendable (Int) -> Void)? = nil,
        phaseObserver: (@Sendable (CharacterPackageImportPhase) -> Void)? = nil,
        deletionFaultInjector: (@Sendable (CharacterDeletionFaultPoint) -> Bool)? = nil
    ) {
        let standardized = root.standardizedFileURL
        self.root = standardized
        self.paths = CharacterStorePaths(root: standardized)
        self.sourceCopyObserver = sourceCopyObserver
        self.phaseObserver = phaseObserver
        self.deletionFaultInjector = deletionFaultInjector
        self.records = CharacterStoreRecovery.bootstrap(paths: CharacterStorePaths(root: standardized))
    }

    public func preview(_ request: CharacterPackageImportRequest) async throws -> CharacterPackagePreview {
        let operation: URL
        do { operation = try paths.makeOperationRoot() }
        catch { throw CharacterPackageImportFailure(.installFailed, .recovery, .rolledBack) }
        defer { paths.removeOperationRoot(operation) }
        do {
            let materialized = try await materialize(request, operation: operation)
            try Task.checkCancellation()
            let contentID = try CharacterTreeVerifier.contentID(at: materialized.packageRoot)
            return CharacterPackagePreview(
                manifest: materialized.manifest,
                contentID: contentID,
                legacyReceipt: materialized.legacyReceipt,
                warnings: materialized.warnings
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as CharacterPackageImportFailure {
            throw failure
        } catch {
            throw CharacterPackageImportFailure(.installFailed, .validate, .rolledBack)
        }
    }

    public func install(_ request: CharacterPackageImportRequest) async throws -> CharacterPackageInstallResult {
        let operation: URL
        do { operation = try paths.makeOperationRoot() }
        catch { throw CharacterPackageImportFailure(.installFailed, .recovery, .rolledBack) }
        defer { paths.removeOperationRoot(operation) }
        var newlySealedContent: CharacterContentID?
        do {
            let materialized = try await materialize(request, operation: operation)
            try Task.checkCancellation()
            let sealed = try CharacterContentStore.seal(
                materialized,
                operation: operation,
                paths: paths
            )
            if sealed.newlyCreated { newlySealedContent = sealed.contentID }
            phaseObserver?(.seal)
            try Task.checkCancellation()

            let installationID = CharacterInstallationID(rawValue: UUID().uuidString.lowercased())
            let record = StoredCharacterRecord(
                schemaVersion: 1,
                installationID: installationID,
                contentID: sealed.contentID,
                manifest: sealed.manifest,
                receipt: sealed.receipt,
                rootIdentity: sealed.rootIdentity,
                legacyReceipt: materialized.legacyReceipt,
                warnings: materialized.warnings,
                activationAllowed: materialized.activationAllowed,
                available: true
            )
            try CharacterContentStore.persist(record, paths: paths)
            records[installationID] = record
            newlySealedContent = nil
            phaseObserver?(.install)
            // Cancellation after the atomic catalog commit is success: callers
            // receive the durable installation instead of a false rollback.
            return CharacterPackageInstallResult(
                installationID: installationID,
                contentID: sealed.contentID,
                manifest: sealed.manifest,
                warnings: materialized.warnings,
                disposition: materialized.activationAllowed ? nil : .quarantined
            )
        } catch is CancellationError {
            if let newlySealedContent {
                try? CharacterContentStore.trashUnreferencedContent(newlySealedContent, paths: paths)
            }
            throw CancellationError()
        } catch let failure as CharacterPackageImportFailure {
            if let newlySealedContent {
                try? CharacterContentStore.trashUnreferencedContent(newlySealedContent, paths: paths)
            }
            throw failure
        } catch {
            if let newlySealedContent {
                try? CharacterContentStore.trashUnreferencedContent(newlySealedContent, paths: paths)
            }
            throw CharacterPackageImportFailure(.installFailed, .install, .rolledBack)
        }
    }

    public func list() -> [CharacterPackageCatalogEntry] {
        records.values.map { record in
            CharacterPackageCatalogEntry(
                installationID: record.installationID,
                contentID: record.contentID,
                characterID: record.manifest.characterID,
                displayName: record.manifest.displayName,
                renderer: record.manifest.renderer,
                available: record.available,
                activationAllowed: record.activationAllowed
            )
        }.sorted {
            if $0.displayName == $1.displayName {
                return $0.installationID.rawValue < $1.installationID.rawValue
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    public func prepareActivation(
        _ installationID: CharacterInstallationID
    ) throws -> ValidatedCharacterPackageHandle {
        guard var record = records[installationID] else {
            throw CharacterPackageImportFailure(.notFound, .activation)
        }
        guard record.activationAllowed else {
            throw CharacterPackageImportFailure(.rightsUnverified, .activation, .quarantined)
        }
        do {
            let verification = try CharacterTreeVerifier.verify(record: record, paths: paths)
            let generation = UUID()
            let capability = UUID()
            let lease = CharacterActivationLease(
                installationID: installationID,
                generation: generation,
                rootCapabilityID: capability,
                contentID: record.contentID
            )
            activationLeases[installationID, default: [:]][generation] = lease
            record.available = true
            records[installationID] = record
            return ValidatedCharacterPackageHandle(
                installationID: installationID,
                contentID: record.contentID,
                rootCapabilityID: capability,
                validationGeneration: generation,
                receiptDigest: CharacterDigests.validationReceiptDigest(verification.receipt),
                manifest: verification.manifest,
                receipt: verification.receipt
            )
        } catch let failure as CharacterPackageImportFailure {
            quarantineMutatedInstallation(record)
            throw failure
        } catch {
            quarantineMutatedInstallation(record)
            throw CharacterPackageImportFailure(.hashMismatch, .activation)
        }
    }

    public func remove(_ installationID: CharacterInstallationID) throws {
        if activationLeases[installationID]?.isEmpty == false {
            throw CharacterPackageImportFailure(.inUse, .removal)
        }
        if try CharacterContentStore.retryPendingRemoval(installationID, paths: paths) {
            records.removeValue(forKey: installationID)
            return
        }
        if let record = records[installationID] {
            let isLastReference = !records.values.contains {
                $0.installationID != installationID && $0.contentID == record.contentID
            }
            do {
                if isLastReference {
                    try CharacterContentStore.removeLastReference(
                        record,
                        paths: paths,
                        faultInjector: deletionFaultInjector
                    )
                } else {
                    try CharacterContentStore.removeCatalog(record, paths: paths)
                }
                records.removeValue(forKey: installationID)
            } catch let failure as CharacterPackageImportFailure {
                throw failure
            } catch {
                throw CharacterPackageImportFailure(.recoveryRequired, .removal, recoveryKey: installationID.rawValue)
            }
            return
        }
        throw CharacterPackageImportFailure(.notFound, .removal)
    }

    func isRegistered(_ handle: ValidatedCharacterPackageHandle) -> Bool {
        activationLeases[handle.installationID]?[handle.validationGeneration]?.matches(handle) == true
    }

    public func validateActivation(_ handle: ValidatedCharacterPackageHandle) throws {
        guard activationLeases[handle.installationID]?[handle.validationGeneration]?.matches(handle) == true,
              let record = records[handle.installationID],
              record.contentID == handle.contentID else {
            throw CharacterPackageImportFailure(.staleHandle, .activation)
        }
        let verification: CharacterTreeVerification
        do {
            verification = try CharacterTreeVerifier.verify(record: record, paths: paths)
        } catch let failure as CharacterPackageImportFailure {
            quarantineMutatedInstallation(record)
            throw failure
        } catch {
            quarantineMutatedInstallation(record)
            throw CharacterPackageImportFailure(.hashMismatch, .activation)
        }
        guard verification.manifest == handle.manifest else {
            removeActivationLease(handle)
            throw CharacterPackageImportFailure(.staleHandle, .activation)
        }
    }

    /// A tree that fails revalidation is untrustworthy for every outstanding
    /// lease, not only the caller's: leaving a lease registered would keep the
    /// catalog entry undeletable behind `inUse` and let a mutated handle stay
    /// registered after the mutation was detected.
    private func quarantineMutatedInstallation(_ record: StoredCharacterRecord) {
        var updated = record
        updated.available = false
        records[updated.installationID] = updated
        try? CharacterContentStore.persist(updated, paths: paths)
        activationLeases.removeValue(forKey: updated.installationID)
    }

    /// Issues read access for a live handle. This revalidates exactly as
    /// `validateActivation` does, so a stale, removed or mutated installation
    /// cannot yield a root, and the entry path comes from the verified manifest.
    public func contentAccess(
        for handle: ValidatedCharacterPackageHandle
    ) throws -> CharacterContentAccess {
        try validateActivation(handle)
        guard let record = records[handle.installationID] else {
            throw CharacterPackageImportFailure(.notFound, .activation)
        }
        guard record.activationAllowed else {
            throw CharacterPackageImportFailure(.rightsUnverified, .activation, .quarantined)
        }
        let root = try paths.assetRoot(record.contentID)
        return CharacterContentAccess(
            installationID: handle.installationID,
            contentID: record.contentID,
            renderer: record.manifest.renderer,
            root: root,
            entryPath: record.manifest.entryPath,
            motions: record.manifest.declaredMotions,
            displayName: record.manifest.displayName
        )
    }

    public func releaseActivation(_ handle: ValidatedCharacterPackageHandle) {
        removeActivationLease(handle)
    }

    private func removeActivationLease(_ handle: ValidatedCharacterPackageHandle) {
        guard activationLeases[handle.installationID]?[handle.validationGeneration]?.matches(handle) == true else {
            return
        }
        activationLeases[handle.installationID]?.removeValue(forKey: handle.validationGeneration)
        if activationLeases[handle.installationID]?.isEmpty == true {
            activationLeases.removeValue(forKey: handle.installationID)
        }
    }

    private func materialize(
        _ request: CharacterPackageImportRequest,
        operation: URL
    ) async throws -> MaterializedCharacterPackage {
        try Task.checkCancellation()
        let source = operation.appendingPathComponent("source", isDirectory: true)
        let sourceFile = source.appendingPathComponent("input")
        try CharacterSecureFilesystem.makePrivateDirectory(source)
        let inputURL: URL
        switch request {
        case let .joiCharacterArchive(url), let .rawVRM(url), let .live2DArchive(url):
            inputURL = url
        }
        try await CharacterSecureFilesystem.copyUntrustedSource(
            inputURL,
            to: sourceFile,
            observer: sourceCopyObserver
        )
        try Task.checkCancellation()

        switch request {
        case .rawVRM:
            return try await CharacterPackageMaterializer.rawVRM(from: sourceFile, operation: operation)
        case .live2DArchive:
            return try await CharacterPackageMaterializer.live2DArchive(from: sourceFile, operation: operation)
        case .joiCharacterArchive:
            return try await CharacterPackageMaterializer.joiArchive(from: sourceFile, operation: operation)
        }
    }
}
