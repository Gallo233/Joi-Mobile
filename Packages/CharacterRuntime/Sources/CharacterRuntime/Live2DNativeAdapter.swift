import CompanionCore
import Foundation

public enum JMLive2DModel3InspectionError: Error, Equatable, Sendable {
    case invalidEntryPath
    case malformedJSON
    case missingMoc
    case missingTexture
    case undeclaredReference(String)
}

public struct JMLive2DModel3Inspection: Equatable, Sendable {
    public let mocPath: String
    public let texturePaths: [String]
    public let motionGroups: [String: [String]]
    public let expressionPaths: [String]
    public let physicsPath: String?
    public let posePath: String?
    public let eyeBlinkParameterIDs: [String]
    public let lipSyncParameterIDs: [String]

    public var motionPaths: [String] {
        motionGroups.keys.sorted().flatMap { motionGroups[$0] ?? [] }
    }

    public var referencedPaths: [String] {
        [mocPath]
            + texturePaths
            + motionPaths
            + expressionPaths
            + [physicsPath, posePath].compactMap { $0 }
    }

    public init(
        mocPath: String,
        texturePaths: [String],
        motionGroups: [String: [String]],
        expressionPaths: [String],
        physicsPath: String?,
        posePath: String?,
        eyeBlinkParameterIDs: [String],
        lipSyncParameterIDs: [String]
    ) {
        self.mocPath = mocPath
        self.texturePaths = texturePaths
        self.motionGroups = motionGroups
        self.expressionPaths = expressionPaths
        self.physicsPath = physicsPath
        self.posePath = posePath
        self.eyeBlinkParameterIDs = eyeBlinkParameterIDs
        self.lipSyncParameterIDs = lipSyncParameterIDs
    }
}

public struct JMLive2DModel3Inspector: Sendable {
    public init() {}

    public func inspect(
        _ data: Data,
        manifest: CharacterPackageManifestV1
    ) throws -> JMLive2DModel3Inspection {
        guard manifest.entryPath.lowercased().hasSuffix(".model3.json") else {
            throw JMLive2DModel3InspectionError.invalidEntryPath
        }

        let document: JMLive2DModel3Document
        do {
            document = try JSONDecoder().decode(JMLive2DModel3Document.self, from: data)
        } catch {
            throw JMLive2DModel3InspectionError.malformedJSON
        }

        guard let mocPath = nonempty(document.fileReferences.moc) else {
            throw JMLive2DModel3InspectionError.missingMoc
        }
        let texturePaths = (document.fileReferences.textures ?? []).compactMap(nonempty)
        guard !texturePaths.isEmpty else {
            throw JMLive2DModel3InspectionError.missingTexture
        }

        var motionGroups: [String: [String]] = [:]
        for group in (document.fileReferences.motions ?? [:]).keys.sorted() {
            let paths = (document.fileReferences.motions?[group] ?? []).compactMap { nonempty($0.file) }
            if !paths.isEmpty {
                motionGroups[group] = paths
            }
        }
        let expressionPaths = (document.fileReferences.expressions ?? []).compactMap { nonempty($0.file) }
        let physicsPath = nonempty(document.fileReferences.physics)
        let posePath = nonempty(document.fileReferences.pose)
        let eyeBlinkIDs = parameterIDs(named: "EyeBlink", in: document.groups ?? [])
        let lipSyncIDs = parameterIDs(named: "LipSync", in: document.groups ?? [])

        let inspection = JMLive2DModel3Inspection(
            mocPath: mocPath,
            texturePaths: texturePaths,
            motionGroups: motionGroups,
            expressionPaths: expressionPaths,
            physicsPath: physicsPath,
            posePath: posePath,
            eyeBlinkParameterIDs: eyeBlinkIDs,
            lipSyncParameterIDs: lipSyncIDs
        )

        let declaredPaths = Set(manifest.assets.map(\.path))
        for path in [manifest.entryPath] + inspection.referencedPaths where !declaredPaths.contains(path) {
            throw JMLive2DModel3InspectionError.undeclaredReference(path)
        }
        return inspection
    }

    private func parameterIDs(
        named name: String,
        in groups: [JMLive2DModel3ParameterGroup]
    ) -> [String] {
        groups
            .filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            .flatMap(\.ids)
            .compactMap(nonempty)
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

public protocol JMLive2DPackageAssetSource: Sendable {
    func model3Data(for package: ValidatedCharacterPackageHandle) async throws -> Data
    func portraitDecodes(for package: ValidatedCharacterPackageHandle) async -> Bool
}

public enum JMLive2DBridgeBackend: String, Sendable {
    case cubismNativeMetal
}

public enum JMLive2DBridgeError: Error, Equatable, Sendable {
    case runtimeUnavailable
    case unsupportedCapability
    case loadCancelled
    case staleGeneration
    case resourceFailure
}

public struct JMLive2DBridgeLoadReport: Equatable, Sendable {
    public let loadedTextureCount: Int
    public let motion: Bool
    public let expression: Bool
    public let physics: Bool
    public let pose: Bool
    public let gaze: Bool
    public let lipSync: Bool
    public let metal: Bool

    public init(
        loadedTextureCount: Int,
        motion: Bool,
        expression: Bool,
        physics: Bool,
        pose: Bool,
        gaze: Bool,
        lipSync: Bool,
        metal: Bool
    ) {
        self.loadedTextureCount = loadedTextureCount
        self.motion = motion
        self.expression = expression
        self.physics = physics
        self.pose = pose
        self.gaze = gaze
        self.lipSync = lipSync
        self.metal = metal
    }
}

/// Asset-free boundary for a future Cubism Native + Metal implementation.
///
/// A conforming bridge must invalidate a generation when `stop` or `release`
/// arrives during `load`, and must not publish or retain resources afterward.
/// Vendor SDK and Metal resource types stay behind this actor boundary.
public protocol JMLive2DNativeMetalBridge: Actor {
    nonisolated var backend: JMLive2DBridgeBackend { get }
    func load(
        package: ValidatedCharacterPackageHandle,
        inspection: JMLive2DModel3Inspection,
        generation: RendererGeneration
    ) async throws -> JMLive2DBridgeLoadReport
    func apply(_ state: CharacterPresentationState, generation: RendererGeneration) async
    func stop(generation: RendererGeneration) async
    func release(generation: RendererGeneration) async
}

public actor JMLive2DUnavailableNativeMetalBridge: JMLive2DNativeMetalBridge {
    public nonisolated let backend: JMLive2DBridgeBackend = .cubismNativeMetal

    public init() {}

    public func load(
        package _: ValidatedCharacterPackageHandle,
        inspection _: JMLive2DModel3Inspection,
        generation _: RendererGeneration
    ) async throws -> JMLive2DBridgeLoadReport {
        throw JMLive2DBridgeError.runtimeUnavailable
    }

    public func apply(_ state: CharacterPresentationState, generation: RendererGeneration) async {
        _ = (state, generation)
    }

    public func stop(generation: RendererGeneration) async {
        _ = generation
    }

    public func release(generation: RendererGeneration) async {
        _ = generation
    }
}

public actor JMLive2DNativeAdapter: CharacterRenderer {
    public nonisolated let kind: CharacterRendererKind = .live2d

    private let assetSource: any JMLive2DPackageAssetSource
    private let bridge: any JMLive2DNativeMetalBridge
    private let inspector: JMLive2DModel3Inspector
    private var currentGeneration: RendererGeneration?
    private var nativeGenerations = Set<RendererGeneration>()
    private var stoppedGenerations = Set<RendererGeneration>()
    private var releasedGenerations = Set<RendererGeneration>()

    public init(
        assetSource: any JMLive2DPackageAssetSource,
        bridge: any JMLive2DNativeMetalBridge = JMLive2DUnavailableNativeMetalBridge(),
        inspector: JMLive2DModel3Inspector = JMLive2DModel3Inspector()
    ) {
        self.assetSource = assetSource
        self.bridge = bridge
        self.inspector = inspector
    }

    public func load(
        _ package: ValidatedCharacterPackageHandle,
        generation: RendererGeneration
    ) async -> CharacterLoadResult {
        if let previous = currentGeneration, previous != generation {
            await stopBridgeOnce(generation: previous)
            await releaseBridgeOnce(generation: previous)
        }
        guard !releasedGenerations.contains(generation) else {
            return await fallback(for: package, reason: .cancelled)
        }
        currentGeneration = generation

        guard package.manifest.renderer == .live2d else {
            await releaseBridgeOnce(generation: generation)
            return await fallback(for: package, reason: .unsupportedCapability)
        }

        let inspection: JMLive2DModel3Inspection
        do {
            let data = try await assetSource.model3Data(for: package)
            guard currentGeneration == generation, !Task.isCancelled else {
                await stopBridgeOnce(generation: generation)
                await releaseBridgeOnce(generation: generation)
                return await fallback(for: package, reason: .cancelled)
            }
            inspection = try inspector.inspect(data, manifest: package.manifest)
        } catch is JMLive2DModel3InspectionError {
            await releaseBridgeOnce(generation: generation)
            return await fallback(for: package, reason: .unsupportedCapability)
        } catch {
            await releaseBridgeOnce(generation: generation)
            return await fallback(for: package, reason: .resourceFailure)
        }

        guard !inspection.lipSyncParameterIDs.isEmpty else {
            await releaseBridgeOnce(generation: generation)
            return await fallback(for: package, reason: .unsupportedCapability)
        }

        do {
            let report = try await bridge.load(
                package: package,
                inspection: inspection,
                generation: generation
            )
            guard currentGeneration == generation, !Task.isCancelled else {
                await stopBridgeOnce(generation: generation)
                await releaseBridgeOnce(generation: generation)
                return await fallback(for: package, reason: .cancelled)
            }
            guard bridgeReportSupportsDeclaredModel(report, inspection: inspection) else {
                await stopBridgeOnce(generation: generation)
                await releaseBridgeOnce(generation: generation)
                return await fallback(for: package, reason: .unsupportedCapability)
            }

            nativeGenerations.insert(generation)
            let capabilities = CharacterCapabilities(
                motion: !inspection.motionPaths.isEmpty,
                expression: !inspection.expressionPaths.isEmpty,
                physics: inspection.physicsPath != nil,
                pose: inspection.posePath != nil,
                lookAt: report.gaze,
                animation: !inspection.motionPaths.isEmpty,
                lipSync: report.lipSync
            )
            let omissions = undeclaredOptionalOmissions(in: inspection)
            if omissions.isEmpty {
                return .animated(capabilities: capabilities, generation: generation)
            }
            return .degradedAnimated(
                capabilities: capabilities,
                omissions: omissions,
                generation: generation
            )
        } catch let error as JMLive2DBridgeError {
            await stopBridgeOnce(generation: generation)
            await releaseBridgeOnce(generation: generation)
            return await fallback(for: package, reason: fallbackReason(for: error))
        } catch {
            await stopBridgeOnce(generation: generation)
            await releaseBridgeOnce(generation: generation)
            return await fallback(for: package, reason: .resourceFailure)
        }
    }

    public func apply(
        _ state: CharacterPresentationState,
        generation: RendererGeneration
    ) async {
        guard currentGeneration == generation,
              nativeGenerations.contains(generation),
              !releasedGenerations.contains(generation) else {
            return
        }
        await bridge.apply(state, generation: generation)
    }

    public func stop(generation: RendererGeneration) async {
        await stopBridgeOnce(generation: generation)
        nativeGenerations.remove(generation)
    }

    public func release(generation: RendererGeneration) async {
        await stopBridgeOnce(generation: generation)
        await releaseBridgeOnce(generation: generation)
        if currentGeneration == generation {
            currentGeneration = nil
        }
    }

    private func bridgeReportSupportsDeclaredModel(
        _ report: JMLive2DBridgeLoadReport,
        inspection: JMLive2DModel3Inspection
    ) -> Bool {
        guard report.metal,
              report.loadedTextureCount == inspection.texturePaths.count,
              report.gaze,
              report.lipSync else {
            return false
        }
        if !inspection.motionPaths.isEmpty, !report.motion { return false }
        if !inspection.expressionPaths.isEmpty, !report.expression { return false }
        if inspection.physicsPath != nil, !report.physics { return false }
        if inspection.posePath != nil, !report.pose { return false }
        return true
    }

    private func undeclaredOptionalOmissions(
        in inspection: JMLive2DModel3Inspection
    ) -> [String] {
        var omissions: [String] = []
        if inspection.motionPaths.isEmpty { omissions.append("motion:undeclared") }
        if inspection.expressionPaths.isEmpty { omissions.append("expression:undeclared") }
        if inspection.physicsPath == nil { omissions.append("physics:undeclared") }
        if inspection.posePath == nil { omissions.append("pose:undeclared") }
        return omissions
    }

    private func fallbackReason(for error: JMLive2DBridgeError) -> CharacterFallbackReason {
        switch error {
        case .runtimeUnavailable:
            .runtimeUnavailable
        case .unsupportedCapability:
            .unsupportedCapability
        case .loadCancelled, .staleGeneration:
            .cancelled
        case .resourceFailure:
            .resourceFailure
        }
    }

    private func fallback(
        for package: ValidatedCharacterPackageHandle,
        reason: CharacterFallbackReason
    ) async -> CharacterLoadResult {
        guard package.manifest.portraitPath != nil else {
            return .bundledStaticJoi(reason: .portraitMissing)
        }
        guard await assetSource.portraitDecodes(for: package) else {
            return .bundledStaticJoi(reason: .portraitDecodeFailed)
        }
        return .packagePortrait(reason: reason)
    }

    private func stopBridgeOnce(generation: RendererGeneration) async {
        guard stoppedGenerations.insert(generation).inserted else { return }
        await bridge.stop(generation: generation)
    }

    private func releaseBridgeOnce(generation: RendererGeneration) async {
        guard releasedGenerations.insert(generation).inserted else { return }
        nativeGenerations.remove(generation)
        await bridge.release(generation: generation)
    }
}

private struct JMLive2DModel3Document: Decodable {
    let fileReferences: JMLive2DModel3FileReferences
    let groups: [JMLive2DModel3ParameterGroup]?

    enum CodingKeys: String, CodingKey {
        case fileReferences = "FileReferences"
        case groups = "Groups"
    }
}

private struct JMLive2DModel3FileReferences: Decodable {
    let moc: String?
    let textures: [String]?
    let motions: [String: [JMLive2DModel3Motion]]?
    let expressions: [JMLive2DModel3Expression]?
    let physics: String?
    let pose: String?

    enum CodingKeys: String, CodingKey {
        case moc = "Moc"
        case textures = "Textures"
        case motions = "Motions"
        case expressions = "Expressions"
        case physics = "Physics"
        case pose = "Pose"
    }
}

private struct JMLive2DModel3Motion: Decodable {
    let file: String?

    enum CodingKeys: String, CodingKey {
        case file = "File"
    }
}

private struct JMLive2DModel3Expression: Decodable {
    let file: String?

    enum CodingKeys: String, CodingKey {
        case file = "File"
    }
}

private struct JMLive2DModel3ParameterGroup: Decodable {
    let name: String
    let ids: [String]

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case ids = "Ids"
    }
}
