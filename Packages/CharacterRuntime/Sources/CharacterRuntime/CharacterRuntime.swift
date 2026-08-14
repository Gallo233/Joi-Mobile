import CompanionCore
import Foundation

public enum CharacterPackageLimits {
    public static let maximumArchiveBytes = 128 * 1_024 * 1_024
    public static let maximumFileBytes = 128 * 1_024 * 1_024
    public static let maximumExpandedBytes = 512 * 1_024 * 1_024
    public static let maximumFileCount = 2_000
    public static let maximumExpansionRatio = 20
    /// Declared motions per package. Matches the contract schema's `maxItems`.
    public static let maximumMotionCount = 64
    /// The manifest document itself. Sized so `maximumFileCount` declared assets
    /// fit at any path length a real package uses, because a byte bound that bit
    /// first would cap the declared asset count at a number the contract never
    /// states — and would report it as `unsafeArchive` (DEC-028).
    public static let maximumManifestBytes = 1_024 * 1_024
}

public enum CharacterPackageValidationError: Error, Equatable, Sendable {
    case invalidSize
    case unsupportedSchema
    case tooManyFiles
    case archiveTooLarge
    case expandedContentTooLarge
    case expansionRatioExceeded
    case unsafePath(String)
    case duplicatePath(String)
    case executable(String)
    case undeclaredAsset(String)
}

public struct CharacterPackageCandidate: Sendable {
    public let archiveBytes: Int
    public let expandedBytes: Int
    public let paths: [String]
    public let executablePaths: Set<String>
    public let manifest: CharacterPackageManifestV1

    public init(
        archiveBytes: Int,
        expandedBytes: Int,
        paths: [String],
        executablePaths: Set<String> = [],
        manifest: CharacterPackageManifestV1
    ) {
        self.archiveBytes = archiveBytes
        self.expandedBytes = expandedBytes
        self.paths = paths
        self.executablePaths = executablePaths
        self.manifest = manifest
    }
}

public struct CharacterPackageValidator: Sendable {
    public init() {}

    public func validate(_ candidate: CharacterPackageCandidate) throws {
        guard candidate.archiveBytes >= 0, candidate.expandedBytes >= 0 else {
            throw CharacterPackageValidationError.invalidSize
        }
        guard candidate.manifest.schema == "joi.character.v1" else {
            throw CharacterPackageValidationError.unsupportedSchema
        }
        guard candidate.archiveBytes <= CharacterPackageLimits.maximumArchiveBytes else {
            throw CharacterPackageValidationError.archiveTooLarge
        }
        guard candidate.expandedBytes <= CharacterPackageLimits.maximumExpandedBytes else {
            throw CharacterPackageValidationError.expandedContentTooLarge
        }
        guard candidate.paths.count <= CharacterPackageLimits.maximumFileCount else {
            throw CharacterPackageValidationError.tooManyFiles
        }
        let effectiveArchiveBytes = max(candidate.archiveBytes, 1)
        let maximumExpandedBytes = effectiveArchiveBytes * CharacterPackageLimits.maximumExpansionRatio
        guard candidate.expandedBytes <= maximumExpandedBytes else {
            throw CharacterPackageValidationError.expansionRatioExceeded
        }

        var normalizedPaths = Set<String>()
        for path in candidate.paths {
            let normalized = path.precomposedStringWithCanonicalMapping.lowercased()
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
                throw CharacterPackageValidationError.unsafePath(path)
            }
            guard normalizedPaths.insert(normalized).inserted else {
                throw CharacterPackageValidationError.duplicatePath(path)
            }
            guard !candidate.executablePaths.contains(path) else {
                throw CharacterPackageValidationError.executable(path)
            }
        }

        let declared = Set(candidate.manifest.assets.map(\.path))
        for path in candidate.paths where path != "manifest.json" {
            guard declared.contains(path) else {
                throw CharacterPackageValidationError.undeclaredAsset(path)
            }
        }
    }
}

public actor StaticCharacterRenderer: CharacterRenderer {
    public nonisolated let kind: CharacterRendererKind = .static
    private var currentGeneration: RendererGeneration?

    public init() {}

    public func load(
        _ package: ValidatedCharacterPackageHandle,
        generation: RendererGeneration
    ) async -> CharacterLoadResult {
        currentGeneration = generation
        return package.manifest.portraitPath == nil
            ? .bundledStaticJoi(reason: .portraitMissing)
            : .packagePortrait(reason: .runtimeUnavailable)
    }

    public func apply(_ state: CharacterPresentationState, generation: RendererGeneration) async {
        guard generation == currentGeneration else { return }
        _ = state
    }

    public func stop(generation: RendererGeneration) async {
        guard generation == currentGeneration else { return }
    }

    public func release(generation: RendererGeneration) async {
        guard generation == currentGeneration else { return }
        currentGeneration = nil
    }
}
