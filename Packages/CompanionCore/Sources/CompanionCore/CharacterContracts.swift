import Foundation

public enum CharacterRendererKind: String, Codable, Sendable, CaseIterable {
    case `static`
    case live2d
    case vrm
}

public struct CharacterAssetV1: Codable, Equatable, Sendable {
    public let path: String
    public let mediaType: String
    public let sha256: String

    public init(path: String, mediaType: String, sha256: String) {
        self.path = path
        self.mediaType = mediaType
        self.sha256 = sha256
    }
}

public struct CharacterProvenanceV1: Codable, Equatable, Sendable {
    public let author: String
    public let license: String
    public let source: String?

    public init(author: String, license: String, source: String? = nil) {
        self.author = author
        self.license = license
        self.source = source
    }
}

public struct CharacterPackageManifestV1: Codable, Equatable, Sendable {
    public let schema: String
    public let packageID: String
    public let characterID: String
    public let version: String
    public let displayName: String
    public let renderer: CharacterRendererKind
    public let entryPath: String
    public let portraitPath: String?
    public let locales: [String]
    public let assets: [CharacterAssetV1]
    public let provenance: CharacterProvenanceV1

    public init(
        schema: String = "joi.character.v1",
        packageID: String,
        characterID: String,
        version: String,
        displayName: String,
        renderer: CharacterRendererKind,
        entryPath: String,
        portraitPath: String? = nil,
        locales: [String],
        assets: [CharacterAssetV1],
        provenance: CharacterProvenanceV1
    ) {
        self.schema = schema
        self.packageID = packageID
        self.characterID = characterID
        self.version = version
        self.displayName = displayName
        self.renderer = renderer
        self.entryPath = entryPath
        self.portraitPath = portraitPath
        self.locales = locales
        self.assets = assets
        self.provenance = provenance
    }
}

public struct CharacterPackageValidationReceiptV1: Codable, Equatable, Sendable {
    public let manifestSHA256: String
    public let expandedBytes: Int
    public let fileCount: Int
    public let validatedAt: Date

    public init(manifestSHA256: String, expandedBytes: Int, fileCount: Int, validatedAt: Date) {
        self.manifestSHA256 = manifestSHA256
        self.expandedBytes = expandedBytes
        self.fileCount = fileCount
        self.validatedAt = validatedAt
    }
}

public struct ValidatedCharacterPackageHandle: Equatable, Sendable {
    public let installationID: String
    public let immutableRootID: String
    public let manifest: CharacterPackageManifestV1
    public let receipt: CharacterPackageValidationReceiptV1

    public init(
        installationID: String,
        immutableRootID: String,
        manifest: CharacterPackageManifestV1,
        receipt: CharacterPackageValidationReceiptV1
    ) {
        self.installationID = installationID
        self.immutableRootID = immutableRootID
        self.manifest = manifest
        self.receipt = receipt
    }
}

public struct CharacterCapabilities: Codable, Equatable, Sendable {
    public var motion: Bool
    public var expression: Bool
    public var physics: Bool
    public var pose: Bool
    public var lookAt: Bool
    public var constraints: Bool
    public var springBone: Bool
    public var animation: Bool
    public var lipSync: Bool

    public init(
        motion: Bool = false,
        expression: Bool = false,
        physics: Bool = false,
        pose: Bool = false,
        lookAt: Bool = false,
        constraints: Bool = false,
        springBone: Bool = false,
        animation: Bool = false,
        lipSync: Bool = false
    ) {
        self.motion = motion
        self.expression = expression
        self.physics = physics
        self.pose = pose
        self.lookAt = lookAt
        self.constraints = constraints
        self.springBone = springBone
        self.animation = animation
        self.lipSync = lipSync
    }
}

public struct RendererGeneration: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum CharacterPresentationState: Equatable, Sendable {
    case idle
    case listening(level: Double)
    case thinking
    case speaking(level: Double)
    case navigating
    case failed
}

public enum CharacterFallbackReason: String, Codable, Equatable, Sendable {
    case runtimeUnavailable
    case unsupportedCapability
    case cancelled
    case resourceFailure
    case portraitMissing
    case portraitDecodeFailed
}

public enum CharacterLoadResult: Equatable, Sendable {
    case animated(capabilities: CharacterCapabilities, generation: RendererGeneration)
    case degradedAnimated(capabilities: CharacterCapabilities, omissions: [String], generation: RendererGeneration)
    case packagePortrait(reason: CharacterFallbackReason)
    case bundledStaticJoi(reason: CharacterFallbackReason)
}

public enum CharacterActivationResult: Equatable, Sendable {
    case loaded(CharacterLoadResult)
    case rejectedImport(code: String)
}

public protocol CharacterRenderer: Actor {
    nonisolated var kind: CharacterRendererKind { get }
    func load(
        _ package: ValidatedCharacterPackageHandle,
        generation: RendererGeneration
    ) async -> CharacterLoadResult
    func apply(_ state: CharacterPresentationState, generation: RendererGeneration) async
    func stop(generation: RendererGeneration) async
    func release(generation: RendererGeneration) async
}
