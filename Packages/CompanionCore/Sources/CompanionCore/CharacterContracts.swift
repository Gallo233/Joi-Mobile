import Foundation

public struct CharacterInstallationID: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct CharacterContentID: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct CharacterSelection: Codable, Equatable, Sendable {
    public let characterID: String
    public let displayName: String
    public let installationID: CharacterInstallationID?
    public let contentID: CharacterContentID?

    public init(
        characterID: String,
        displayName: String,
        installationID: CharacterInstallationID? = nil,
        contentID: CharacterContentID? = nil
    ) {
        self.characterID = characterID
        self.displayName = displayName
        self.installationID = installationID
        self.contentID = contentID
    }
}

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

/// One semantic motion a character can be asked to play, and the animation
/// clip that performs it.
///
/// A `.vrm` file carries a rig and no animation at all, so a VRM character's
/// idle, greeting and dance clips are separate `.vrma` assets. This mapping is
/// what lets the product ask for `greet` without knowing a file name, and it is
/// also the renderer graph that decides which animation files may enter runtime
/// content — see DEC-024. Only a `vrm` package may declare motions.
public struct CharacterMotionV1: Codable, Equatable, Sendable {
    /// Semantic name the product triggers: `idle`, `greet`, `happy`, …
    public let motion: String
    /// Package-relative path of a `.vrma` asset that is also declared in `assets`.
    public let animation: String
    /// Whether the clip plays continuously. Absent means it plays once.
    public let loop: Bool?

    public init(motion: String, animation: String, loop: Bool? = nil) {
        self.motion = motion
        self.animation = animation
        self.loop = loop
    }

    public var loops: Bool { loop ?? false }

    /// The motion a character holds between events. Named here because both the
    /// session (deciding what a tap plays) and the renderer (deciding what to
    /// return to) need the same answer.
    public static let idleName = "idle"
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
    /// Optional so every package that predates DEC-024 keeps decoding, and so an
    /// absent table is encoded as an absent key rather than an empty array.
    /// Read it through ``declaredMotions``.
    public let motions: [CharacterMotionV1]?
    public let assets: [CharacterAssetV1]
    public let provenance: CharacterProvenanceV1

    public var declaredMotions: [CharacterMotionV1] { motions ?? [] }

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
        motions: [CharacterMotionV1]? = nil,
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
        self.motions = motions
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
    public let installationID: CharacterInstallationID
    public let contentID: CharacterContentID
    public let rootCapabilityID: UUID
    public let validationGeneration: UUID
    public let receiptDigest: String
    public let manifest: CharacterPackageManifestV1
    public let receipt: CharacterPackageValidationReceiptV1

    @_spi(CharacterPackageInstaller)
    public init(
        installationID: CharacterInstallationID,
        contentID: CharacterContentID,
        rootCapabilityID: UUID,
        validationGeneration: UUID,
        receiptDigest: String,
        manifest: CharacterPackageManifestV1,
        receipt: CharacterPackageValidationReceiptV1
    ) {
        self.installationID = installationID
        self.contentID = contentID
        self.rootCapabilityID = rootCapabilityID
        self.validationGeneration = validationGeneration
        self.receiptDigest = receiptDigest
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
