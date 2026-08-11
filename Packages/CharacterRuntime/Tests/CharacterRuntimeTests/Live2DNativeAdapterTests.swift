import CompanionCore
import Foundation
import XCTest
@testable import CharacterRuntime

final class Live2DNativeAdapterTests: XCTestCase {
    func testModel3InspectorCollectsMultiTextureAndDeclaredCapabilities() throws {
        let inspection = try JMLive2DModel3Inspector().inspect(
            fullModel3Data,
            manifest: manifest()
        )

        XCTAssertEqual(inspection.mocPath, "model/joi.moc3")
        XCTAssertEqual(inspection.texturePaths, ["model/texture_00.png", "model/texture_01.png"])
        XCTAssertEqual(inspection.motionGroups["Idle"], ["motions/idle.motion3.json"])
        XCTAssertEqual(inspection.motionGroups["Tap"], ["motions/tap.motion3.json"])
        XCTAssertEqual(inspection.expressionPaths, ["expressions/smile.exp3.json"])
        XCTAssertEqual(inspection.physicsPath, "model/joi.physics3.json")
        XCTAssertEqual(inspection.posePath, "model/joi.pose3.json")
        XCTAssertEqual(inspection.eyeBlinkParameterIDs, ["ParamEyeLOpen", "ParamEyeROpen"])
        XCTAssertEqual(inspection.lipSyncParameterIDs, ["ParamMouthOpenY"])
    }

    func testAdapterReportsAnimatedCapabilitiesIncludingGazeAndLipSync() async {
        let source = JMLive2DTestAssetSource(data: fullModel3Data, portraitDecodes: true)
        let bridge = JMLive2DTestBridge(report: .full)
        let adapter = JMLive2DNativeAdapter(assetSource: source, bridge: bridge)
        let generation = RendererGeneration()

        let result = await adapter.load(handle(), generation: generation)

        XCTAssertEqual(
            result,
            .animated(
                capabilities: CharacterCapabilities(
                    motion: true,
                    expression: true,
                    physics: true,
                    pose: true,
                    lookAt: true,
                    animation: true,
                    lipSync: true
                ),
                generation: generation
            )
        )

        await adapter.apply(.speaking(level: 0.75), generation: generation)
        let applied = await bridge.appliedStates(for: generation)
        XCTAssertEqual(applied, [.speaking(level: 0.75)])
    }

    func testNewGenerationCancelsStaleLoadAndSuppressesStaleApply() async {
        let source = JMLive2DTestAssetSource(data: fullModel3Data, portraitDecodes: true)
        let firstGeneration = RendererGeneration()
        let secondGeneration = RendererGeneration()
        let bridge = JMLive2DTestBridge(
            report: .full,
            suspendedGenerations: [firstGeneration]
        )
        let adapter = JMLive2DNativeAdapter(assetSource: source, bridge: bridge)
        let package = handle()

        let firstLoad = Task {
            await adapter.load(package, generation: firstGeneration)
        }
        await bridge.waitUntilSuspended(firstGeneration)

        let secondResult = await adapter.load(package, generation: secondGeneration)
        await bridge.resume(firstGeneration)
        let firstResult = await firstLoad.value

        XCTAssertEqual(
            secondResult,
            .animated(capabilities: .jmlive2dFull, generation: secondGeneration)
        )
        XCTAssertEqual(firstResult, .packagePortrait(reason: .cancelled))

        await adapter.apply(.speaking(level: 1), generation: firstGeneration)
        await adapter.apply(.speaking(level: 0.5), generation: secondGeneration)
        let staleApplied = await bridge.appliedStates(for: firstGeneration)
        let currentApplied = await bridge.appliedStates(for: secondGeneration)
        let firstStops = await bridge.stopCount(for: firstGeneration)
        let firstReleases = await bridge.releaseCount(for: firstGeneration)

        XCTAssertTrue(staleApplied.isEmpty)
        XCTAssertEqual(currentApplied, [.speaking(level: 0.5)])
        XCTAssertEqual(firstStops, 1)
        XCTAssertEqual(firstReleases, 1)
    }

    func testRuntimeFailureFallsBackFromPortraitToBundledStatic() async {
        let portraitSource = JMLive2DTestAssetSource(data: fullModel3Data, portraitDecodes: true)
        let portraitBridge = JMLive2DTestBridge(report: .full, failure: .runtimeUnavailable)
        let portraitAdapter = JMLive2DNativeAdapter(assetSource: portraitSource, bridge: portraitBridge)

        let portraitResult = await portraitAdapter.load(handle(), generation: RendererGeneration())
        XCTAssertEqual(portraitResult, .packagePortrait(reason: .runtimeUnavailable))

        let staticSource = JMLive2DTestAssetSource(data: fullModel3Data, portraitDecodes: false)
        let staticBridge = JMLive2DTestBridge(report: .full, failure: .runtimeUnavailable)
        let staticAdapter = JMLive2DNativeAdapter(assetSource: staticSource, bridge: staticBridge)

        let staticResult = await staticAdapter.load(handle(), generation: RendererGeneration())
        XCTAssertEqual(staticResult, .bundledStaticJoi(reason: .portraitDecodeFailed))
    }

    func testReleaseIsExactlyOnceAcrossRepeatedCycles() async {
        let source = JMLive2DTestAssetSource(data: fullModel3Data, portraitDecodes: true)
        let bridge = JMLive2DTestBridge(report: .full)
        let adapter = JMLive2DNativeAdapter(assetSource: source, bridge: bridge)
        var generations: [RendererGeneration] = []

        for _ in 0..<50 {
            let generation = RendererGeneration()
            generations.append(generation)
            let result = await adapter.load(handle(), generation: generation)
            XCTAssertEqual(result, .animated(capabilities: .jmlive2dFull, generation: generation))
            await adapter.release(generation: generation)
            await adapter.release(generation: generation)
        }

        let totalReleases = await bridge.totalReleaseCount()
        let totalStops = await bridge.totalStopCount()
        XCTAssertEqual(totalReleases, generations.count)
        XCTAssertEqual(totalStops, generations.count)
        for generation in generations {
            let releaseCount = await bridge.releaseCount(for: generation)
            XCTAssertEqual(releaseCount, 1)
        }
    }

    func testUndeclaredModelReferenceFallsBackWithoutBridgeLoad() async {
        let assets = manifestAssets().filter { $0.path != "model/texture_01.png" }
        let source = JMLive2DTestAssetSource(data: fullModel3Data, portraitDecodes: true)
        let bridge = JMLive2DTestBridge(report: .full)
        let adapter = JMLive2DNativeAdapter(assetSource: source, bridge: bridge)
        let generation = RendererGeneration()

        let result = await adapter.load(
            handle(manifest: manifest(assets: assets)),
            generation: generation
        )

        XCTAssertEqual(result, .packagePortrait(reason: .unsupportedCapability))
        let loadCount = await bridge.totalLoadCount()
        XCTAssertEqual(loadCount, 0)
    }

    private var fullModel3Data: Data {
        Data(
            #"""
            {
              "Version": 3,
              "FileReferences": {
                "Moc": "model/joi.moc3",
                "Textures": ["model/texture_00.png", "model/texture_01.png"],
                "Motions": {
                  "Idle": [{"File": "motions/idle.motion3.json"}],
                  "Tap": [{"File": "motions/tap.motion3.json"}]
                },
                "Expressions": [{"Name": "smile", "File": "expressions/smile.exp3.json"}],
                "Physics": "model/joi.physics3.json",
                "Pose": "model/joi.pose3.json"
              },
              "Groups": [
                {"Target": "Parameter", "Name": "EyeBlink", "Ids": ["ParamEyeLOpen", "ParamEyeROpen"]},
                {"Target": "Parameter", "Name": "LipSync", "Ids": ["ParamMouthOpenY"]}
              ]
            }
            """#.utf8
        )
    }

    private func handle(
        manifest: CharacterPackageManifestV1? = nil
    ) -> ValidatedCharacterPackageHandle {
        ValidatedCharacterPackageHandle(
            installationID: "test-installation",
            immutableRootID: "sha256:test-root",
            manifest: manifest ?? self.manifest(),
            receipt: CharacterPackageValidationReceiptV1(
                manifestSHA256: "test-manifest-hash",
                expandedBytes: 4_096,
                fileCount: manifestAssets().count,
                validatedAt: Date(timeIntervalSince1970: 0)
            )
        )
    }

    private func manifest(
        assets: [CharacterAssetV1]? = nil
    ) -> CharacterPackageManifestV1 {
        CharacterPackageManifestV1(
            packageID: "test-live2d-package",
            characterID: "joi",
            version: "1.0.0",
            displayName: "Joi",
            renderer: .live2d,
            entryPath: "model/joi.model3.json",
            portraitPath: "portrait/joi.png",
            locales: ["en"],
            assets: assets ?? manifestAssets(),
            provenance: CharacterProvenanceV1(
                author: "Repository test fixture",
                license: "Self-authored test metadata"
            )
        )
    }

    private func manifestAssets() -> [CharacterAssetV1] {
        [
            "model/joi.model3.json",
            "model/joi.moc3",
            "model/texture_00.png",
            "model/texture_01.png",
            "motions/idle.motion3.json",
            "motions/tap.motion3.json",
            "expressions/smile.exp3.json",
            "model/joi.physics3.json",
            "model/joi.pose3.json",
            "portrait/joi.png",
        ].map {
            CharacterAssetV1(path: $0, mediaType: "application/octet-stream", sha256: "hash:\($0)")
        }
    }
}

private extension CharacterCapabilities {
    static let jmlive2dFull = CharacterCapabilities(
        motion: true,
        expression: true,
        physics: true,
        pose: true,
        lookAt: true,
        animation: true,
        lipSync: true
    )
}

private actor JMLive2DTestAssetSource: JMLive2DPackageAssetSource {
    private let data: Data
    private let portraitCanDecode: Bool

    init(data: Data, portraitDecodes: Bool) {
        self.data = data
        portraitCanDecode = portraitDecodes
    }

    func model3Data(for package: ValidatedCharacterPackageHandle) async throws -> Data {
        _ = package
        return data
    }

    func portraitDecodes(for package: ValidatedCharacterPackageHandle) async -> Bool {
        _ = package
        return portraitCanDecode
    }
}

private actor JMLive2DTestBridge: JMLive2DNativeMetalBridge {
    nonisolated let backend: JMLive2DBridgeBackend = .cubismNativeMetal

    private let report: JMLive2DBridgeLoadReport
    private let failure: JMLive2DBridgeError?
    private let suspendedGenerations: Set<RendererGeneration>
    private var suspendedLoads: [RendererGeneration: CheckedContinuation<Void, Never>] = [:]
    private var loadCounts: [RendererGeneration: Int] = [:]
    private var stopCounts: [RendererGeneration: Int] = [:]
    private var releaseCounts: [RendererGeneration: Int] = [:]
    private var states: [RendererGeneration: [CharacterPresentationState]] = [:]

    init(
        report: JMLive2DBridgeLoadReport,
        failure: JMLive2DBridgeError? = nil,
        suspendedGenerations: Set<RendererGeneration> = []
    ) {
        self.report = report
        self.failure = failure
        self.suspendedGenerations = suspendedGenerations
    }

    func load(
        package: ValidatedCharacterPackageHandle,
        inspection: JMLive2DModel3Inspection,
        generation: RendererGeneration
    ) async throws -> JMLive2DBridgeLoadReport {
        _ = (package, inspection)
        loadCounts[generation, default: 0] += 1
        if suspendedGenerations.contains(generation) {
            await withCheckedContinuation { continuation in
                suspendedLoads[generation] = continuation
            }
        }
        if let failure {
            throw failure
        }
        return report
    }

    func apply(_ state: CharacterPresentationState, generation: RendererGeneration) async {
        states[generation, default: []].append(state)
    }

    func stop(generation: RendererGeneration) async {
        stopCounts[generation, default: 0] += 1
    }

    func release(generation: RendererGeneration) async {
        releaseCounts[generation, default: 0] += 1
    }

    func waitUntilSuspended(_ generation: RendererGeneration) async {
        while suspendedLoads[generation] == nil {
            await Task.yield()
        }
    }

    func resume(_ generation: RendererGeneration) {
        suspendedLoads.removeValue(forKey: generation)?.resume()
    }

    func appliedStates(for generation: RendererGeneration) -> [CharacterPresentationState] {
        states[generation] ?? []
    }

    func stopCount(for generation: RendererGeneration) -> Int {
        stopCounts[generation, default: 0]
    }

    func releaseCount(for generation: RendererGeneration) -> Int {
        releaseCounts[generation, default: 0]
    }

    func totalLoadCount() -> Int {
        loadCounts.values.reduce(0, +)
    }

    func totalStopCount() -> Int {
        stopCounts.values.reduce(0, +)
    }

    func totalReleaseCount() -> Int {
        releaseCounts.values.reduce(0, +)
    }
}

private extension JMLive2DBridgeLoadReport {
    static let full = JMLive2DBridgeLoadReport(
        loadedTextureCount: 2,
        motion: true,
        expression: true,
        physics: true,
        pose: true,
        gaze: true,
        lipSync: true,
        metal: true
    )
}
