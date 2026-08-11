import CompanionCore
import Foundation

// Every public type in this file is deliberately prefixed with `VRMNative`.
// The package contract remains CharacterRenderer; a future VRMKit dependency must
// stay private to the bridge below rather than leaking into CompanionCore.

public enum VRMNativeFormat: String, Equatable, Sendable {
    case gltf2
    case vrm0
    case vrm1
    case vrma
}

public enum VRMNativeLipSyncExpectation: String, Equatable, Sendable {
    case unavailable
    case vrm0VowelBlendShapes
    case vrm1PhonemeExpressions
}

public struct VRMNativeCapabilityReport: Equatable, Sendable {
    public let format: VRMNativeFormat
    public let humanoid: Bool
    public let mtoon: Bool
    public let expressions: Bool
    public let lookAt: Bool
    public let constraints: Bool
    public let springBone: Bool
    public let animation: Bool
    public let lipSync: VRMNativeLipSyncExpectation

    public init(
        format: VRMNativeFormat,
        humanoid: Bool,
        mtoon: Bool,
        expressions: Bool,
        lookAt: Bool,
        constraints: Bool,
        springBone: Bool,
        animation: Bool,
        lipSync: VRMNativeLipSyncExpectation
    ) {
        self.format = format
        self.humanoid = humanoid
        self.mtoon = mtoon
        self.expressions = expressions
        self.lookAt = lookAt
        self.constraints = constraints
        self.springBone = springBone
        self.animation = animation
        self.lipSync = lipSync
    }

    public var characterCapabilities: CharacterCapabilities {
        CharacterCapabilities(
            motion: animation,
            expression: expressions,
            physics: springBone,
            pose: humanoid,
            lookAt: lookAt,
            constraints: constraints,
            springBone: springBone,
            animation: animation,
            lipSync: lipSync != .unavailable
        )
    }
}

public enum VRMNativeMetadataError: Error, Equatable, Sendable {
    case unsupportedContainer
    case malformedGLB
    case missingJSONChunk
    case invalidJSON
}

public struct VRMNativeMetadataInspector: Sendable {
    private static let glbMagic: UInt32 = 0x4654_6C67
    private static let jsonChunkType: UInt32 = 0x4E4F_534A

    public init() {}

    public func inspect(_ data: Data) throws -> VRMNativeCapabilityReport {
        let jsonData = try Self.jsonPayload(from: data)
        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw VRMNativeMetadataError.invalidJSON
        }

        let rootExtensions = root["extensions"] as? [String: Any] ?? [:]
        let used = Set((root["extensionsUsed"] as? [String] ?? []) + rootExtensions.keys)
        let vrm0 = rootExtensions["VRM"] as? [String: Any]
        let vrm1 = rootExtensions["VRMC_vrm"] as? [String: Any]
        let vrma = rootExtensions["VRMC_vrm_animation"] as? [String: Any]

        let format: VRMNativeFormat
        if vrm1 != nil || used.contains("VRMC_vrm") {
            format = .vrm1
        } else if vrm0 != nil || used.contains("VRM") {
            format = .vrm0
        } else if vrma != nil || used.contains("VRMC_vrm_animation") {
            format = .vrma
        } else {
            format = .gltf2
        }

        let vrm0Groups = ((vrm0?["blendShapeMaster"] as? [String: Any])?["blendShapeGroups"] as? [[String: Any]]) ?? []
        let vrm1Expressions = vrm1?["expressions"] as? [String: Any]
        let vrm1Presets = vrm1Expressions?["preset"] as? [String: Any] ?? [:]
        let vrm0Presets = Set(vrm0Groups.compactMap { ($0["presetName"] as? String)?.lowercased() })
        let vrm1Phonemes: Set<String> = ["aa", "ih", "ou", "ee", "oh"]

        let lipSync: VRMNativeLipSyncExpectation
        if !vrm1Phonemes.isDisjoint(with: Set(vrm1Presets.keys.map { $0.lowercased() })) {
            lipSync = .vrm1PhonemeExpressions
        } else if !Set(["a", "i", "u", "e", "o"]).isDisjoint(with: vrm0Presets) {
            lipSync = .vrm0VowelBlendShapes
        } else {
            lipSync = .unavailable
        }

        let materials = root["materials"] as? [[String: Any]] ?? []
        let hasMToonMaterial = materials.contains { material in
            let extensions = material["extensions"] as? [String: Any] ?? [:]
            return extensions["VRMC_materials_mtoon"] != nil
        }
        let vrm0MaterialProperties = vrm0?["materialProperties"] as? [[String: Any]] ?? []
        let hasVRM0MToon = vrm0MaterialProperties.contains {
            (($0["shader"] as? String) ?? "").localizedCaseInsensitiveContains("MToon")
        }
        let hasAnimations = !(root["animations"] as? [Any] ?? []).isEmpty

        return VRMNativeCapabilityReport(
            format: format,
            humanoid: vrm0?["humanoid"] != nil || vrm1?["humanoid"] != nil || vrma?["humanoid"] != nil,
            mtoon: used.contains("VRMC_materials_mtoon") || hasMToonMaterial || hasVRM0MToon,
            expressions: !vrm0Groups.isEmpty || vrm1Expressions != nil,
            lookAt: vrm1?["lookAt"] != nil || vrm0?["firstPerson"] != nil,
            constraints: used.contains("VRMC_node_constraint"),
            springBone: used.contains("VRMC_springBone") || vrm0?["secondaryAnimation"] != nil,
            animation: hasAnimations || vrma != nil || used.contains("VRMC_vrm_animation"),
            lipSync: lipSync
        )
    }

    private static func jsonPayload(from data: Data) throws -> Data {
        guard data.count >= 4 else { throw VRMNativeMetadataError.unsupportedContainer }
        if readUInt32LE(data, at: 0) != glbMagic {
            guard data.first == Character("{").asciiValue else {
                throw VRMNativeMetadataError.unsupportedContainer
            }
            return data
        }

        guard data.count >= 20,
              readUInt32LE(data, at: 4) == 2,
              let declaredLength = readUInt32LE(data, at: 8),
              Int(declaredLength) <= data.count,
              let chunkLength = readUInt32LE(data, at: 12),
              readUInt32LE(data, at: 16) == jsonChunkType else {
            throw VRMNativeMetadataError.malformedGLB
        }
        let start = 20
        let end = start + Int(chunkLength)
        guard end <= Int(declaredLength), end <= data.count else {
            throw VRMNativeMetadataError.missingJSONChunk
        }
        var payload = data.subdata(in: start..<end)
        while let last = payload.last, last == 0 || last == 0x20 {
            payload.removeLast()
        }
        return payload
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}

enum VRMNativeBridgeFailure: Error, Equatable, Sendable {
    case runtimeUnavailable
    case unsupportedMetadata
    case resourceFailure
    case portraitDecodeFailed
}

struct VRMNativeBridgeLoad: Equatable, Sendable {
    let report: VRMNativeCapabilityReport
    let omissions: [String]
}

/// Native seam for RealityKit/Metal. A future VRMKit implementation belongs
/// behind this internal protocol and cannot become a public package dependency.
protocol VRMNativeRealityKitMetalBridging: Actor {
    func load(
        _ package: ValidatedCharacterPackageHandle,
        generation: RendererGeneration
    ) async throws -> VRMNativeBridgeLoad
    func apply(_ state: CharacterPresentationState, generation: RendererGeneration) async
    func stop(generation: RendererGeneration) async
    func release(generation: RendererGeneration) async
}

private actor VRMNativeUnavailableRealityKitMetalBridge: VRMNativeRealityKitMetalBridging {
    func load(
        _ package: ValidatedCharacterPackageHandle,
        generation: RendererGeneration
    ) async throws -> VRMNativeBridgeLoad {
        _ = package
        _ = generation
        throw VRMNativeBridgeFailure.runtimeUnavailable
    }

    func apply(_ state: CharacterPresentationState, generation: RendererGeneration) async {}
    func stop(generation: RendererGeneration) async {}
    func release(generation: RendererGeneration) async {}
}

public actor VRMNativeAdapter: CharacterRenderer {
    public nonisolated let kind: CharacterRendererKind = .vrm

    private let bridge: any VRMNativeRealityKitMetalBridging
    private var currentGeneration: RendererGeneration?
    private var releasedGenerations: Set<RendererGeneration> = []

    public init() {
        bridge = VRMNativeUnavailableRealityKitMetalBridge()
    }

    init(bridge: any VRMNativeRealityKitMetalBridging) {
        self.bridge = bridge
    }

    public func load(
        _ package: ValidatedCharacterPackageHandle,
        generation: RendererGeneration
    ) async -> CharacterLoadResult {
        guard package.manifest.renderer == .vrm else {
            return fallback(for: package, reason: .unsupportedCapability)
        }

        if let previousGeneration = currentGeneration, previousGeneration != generation {
            await releaseBridgeOnce(previousGeneration)
        }
        currentGeneration = generation
        do {
            let loaded = try await bridge.load(package, generation: generation)
            guard !Task.isCancelled, currentGeneration == generation else {
                await releaseBridgeOnce(generation)
                return fallback(for: package, reason: .cancelled)
            }
            guard let accepted = acceptedResult(for: loaded, generation: generation) else {
                await releaseBridgeOnce(generation)
                return fallback(for: package, reason: .unsupportedCapability)
            }
            return accepted
        } catch is CancellationError {
            await releaseBridgeOnce(generation)
            return fallback(for: package, reason: .cancelled)
        } catch let failure as VRMNativeBridgeFailure {
            await releaseBridgeOnce(generation)
            return fallback(for: package, reason: fallbackReason(for: failure))
        } catch {
            await releaseBridgeOnce(generation)
            return fallback(for: package, reason: .resourceFailure)
        }
    }

    public func apply(_ state: CharacterPresentationState, generation: RendererGeneration) async {
        guard generation == currentGeneration, !releasedGenerations.contains(generation) else { return }
        await bridge.apply(state, generation: generation)
    }

    public func stop(generation: RendererGeneration) async {
        guard generation == currentGeneration, !releasedGenerations.contains(generation) else { return }
        await bridge.stop(generation: generation)
    }

    public func release(generation: RendererGeneration) async {
        await releaseBridgeOnce(generation)
    }

    private func releaseBridgeOnce(_ generation: RendererGeneration) async {
        guard releasedGenerations.insert(generation).inserted else { return }
        await bridge.release(generation: generation)
        if currentGeneration == generation {
            currentGeneration = nil
        }
    }

    private func fallback(
        for package: ValidatedCharacterPackageHandle,
        reason: CharacterFallbackReason
    ) -> CharacterLoadResult {
        if package.manifest.portraitPath != nil, reason != .portraitDecodeFailed {
            return .packagePortrait(reason: reason)
        }
        return .bundledStaticJoi(reason: reason)
    }

    private func fallbackReason(for failure: VRMNativeBridgeFailure) -> CharacterFallbackReason {
        switch failure {
        case .runtimeUnavailable:
            return .runtimeUnavailable
        case .unsupportedMetadata:
            return .unsupportedCapability
        case .resourceFailure:
            return .resourceFailure
        case .portraitDecodeFailed:
            return .portraitDecodeFailed
        }
    }

    private func acceptedResult(
        for loaded: VRMNativeBridgeLoad,
        generation: RendererGeneration
    ) -> CharacterLoadResult? {
        let report = loaded.report
        let normalizedOmissions = Set(
            loaded.omissions.map {
                $0.lowercased().filter { $0.isLetter || $0.isNumber }
            }
        )

        let requiredCorePresent: Bool
        let allowedOmissions: Set<String>
        switch report.format {
        case .vrm0:
            requiredCorePresent = report.humanoid
                && report.mtoon
                && report.expressions
                && report.lookAt
                && report.lipSync == .vrm0VowelBlendShapes
            allowedOmissions = ["constraints", "vrma"]
        case .vrm1:
            requiredCorePresent = report.humanoid
                && report.mtoon
                && report.expressions
                && report.lookAt
                && report.lipSync == .vrm1PhonemeExpressions
            allowedOmissions = ["vrma"]
        case .vrma:
            requiredCorePresent = report.humanoid && report.animation
            allowedOmissions = ["nonessentialmetadata"]
        case .gltf2:
            return nil
        }

        guard requiredCorePresent, normalizedOmissions.isSubset(of: allowedOmissions) else {
            return nil
        }
        let capabilities = report.characterCapabilities
        return loaded.omissions.isEmpty
            ? .animated(capabilities: capabilities, generation: generation)
            : .degradedAnimated(
                capabilities: capabilities,
                omissions: loaded.omissions,
                generation: generation
            )
    }
}
