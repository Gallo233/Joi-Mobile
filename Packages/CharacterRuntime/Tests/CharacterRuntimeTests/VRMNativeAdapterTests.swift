@_spi(CharacterPackageInstaller) import CompanionCore
import Foundation
import XCTest
@testable import CharacterRuntime

final class VRMNativeAdapterTests: XCTestCase {
    func testInspectorDistinguishesVRM0AndReportsLegacyCapabilities() throws {
        let metadata: [String: Any] = [
            "asset": ["version": "2.0"],
            "extensions": [
                "VRM": [
                    "humanoid": ["humanBones": []],
                    "firstPerson": ["lookAtTypeName": "Bone"],
                    "secondaryAnimation": ["boneGroups": []],
                    "blendShapeMaster": [
                        "blendShapeGroups": [["presetName": "a"]]
                    ],
                    "materialProperties": [["shader": "VRM/MToon"]],
                ]
            ],
        ]

        let report = try VRMNativeMetadataInspector().inspect(jsonData(metadata))

        XCTAssertEqual(report.format, .vrm0)
        XCTAssertTrue(report.humanoid)
        XCTAssertTrue(report.mtoon)
        XCTAssertTrue(report.expressions)
        XCTAssertTrue(report.lookAt)
        XCTAssertTrue(report.springBone)
        XCTAssertEqual(report.lipSync, .vrm0VowelBlendShapes)
    }

    func testInspectorReadsVRM1CapabilityMetadataFromGLB() throws {
        let metadata: [String: Any] = [
            "asset": ["version": "2.0"],
            "extensionsUsed": [
                "VRMC_vrm", "VRMC_materials_mtoon", "VRMC_node_constraint", "VRMC_springBone",
            ],
            "extensions": [
                "VRMC_vrm": [
                    "humanoid": ["humanBones": [:]],
                    "lookAt": ["type": "bone"],
                    "expressions": ["preset": ["aa": ["isBinary": false]]],
                ],
                "VRMC_springBone": ["springs": []],
            ],
            "materials": [["extensions": ["VRMC_materials_mtoon": [:]]]],
            "animations": [["name": "idle"]],
        ]

        let report = try VRMNativeMetadataInspector().inspect(glbData(metadata))

        XCTAssertEqual(report.format, .vrm1)
        XCTAssertEqual(
            report.characterCapabilities,
            CharacterCapabilities(
                motion: true,
                expression: true,
                physics: true,
                pose: true,
                lookAt: true,
                constraints: true,
                springBone: true,
                animation: true,
                lipSync: true
            )
        )
        XCTAssertEqual(report.lipSync, .vrm1PhonemeExpressions)
    }

    func testInspectorDistinguishesVRMA() throws {
        let metadata: [String: Any] = [
            "asset": ["version": "2.0"],
            "extensionsUsed": ["VRMC_vrm_animation"],
            "extensions": [
                "VRMC_vrm_animation": ["humanoid": ["humanBones": [:]]]
            ],
        ]

        let report = try VRMNativeMetadataInspector().inspect(glbData(metadata))

        XCTAssertEqual(report.format, .vrma)
        XCTAssertTrue(report.humanoid)
        XCTAssertTrue(report.animation)
        XCTAssertFalse(report.expressions)
    }

    func testAdapterAllowsOnlyDeclaredTierBOmission() async {
        let report = VRMNativeCapabilityReport(
            format: .vrm1,
            humanoid: true,
            mtoon: true,
            expressions: true,
            lookAt: true,
            constraints: true,
            springBone: true,
            animation: false,
            lipSync: .vrm1PhonemeExpressions
        )
        let bridge = FakeVRMNativeBridge(behavior: .succeed(report, omissions: ["VRMA"]))
        let adapter = VRMNativeAdapter(bridge: bridge)
        let generation = RendererGeneration()

        let result = await adapter.load(package(portrait: "portrait.png"), generation: generation)

        XCTAssertEqual(
            result,
            .degradedAnimated(
                capabilities: report.characterCapabilities,
                omissions: ["VRMA"],
                generation: generation
            )
        )
    }

    func testMissingRequiredMToonFallsBackAndReleases() async {
        let report = VRMNativeCapabilityReport(
            format: .vrm1,
            humanoid: true,
            mtoon: false,
            expressions: true,
            lookAt: true,
            constraints: true,
            springBone: true,
            animation: false,
            lipSync: .vrm1PhonemeExpressions
        )
        let bridge = FakeVRMNativeBridge(behavior: .succeed(report, omissions: ["MToon"]))
        let adapter = VRMNativeAdapter(bridge: bridge)
        let generation = RendererGeneration()

        let result = await adapter.load(package(portrait: "portrait.png"), generation: generation)
        let releaseCount = await bridge.releaseCount(for: generation)

        XCTAssertEqual(result, .packagePortrait(reason: .unsupportedCapability))
        XCTAssertEqual(releaseCount, 1)
    }

    func testDeclaredBridgeFailureUsesPortraitThenBundledFallback() async {
        let portraitBridge = FakeVRMNativeBridge(behavior: .fail(.runtimeUnavailable))
        let portraitAdapter = VRMNativeAdapter(bridge: portraitBridge)
        let portraitResult = await portraitAdapter.load(
            package(portrait: "portrait.png"),
            generation: RendererGeneration()
        )
        XCTAssertEqual(portraitResult, .packagePortrait(reason: .runtimeUnavailable))

        let bundledBridge = FakeVRMNativeBridge(behavior: .fail(.portraitDecodeFailed))
        let bundledAdapter = VRMNativeAdapter(bridge: bundledBridge)
        let bundledResult = await bundledAdapter.load(
            package(portrait: "portrait.png"),
            generation: RendererGeneration()
        )
        XCTAssertEqual(bundledResult, .bundledStaticJoi(reason: .portraitDecodeFailed))
    }

    func testCancellationReturnsFallbackAndReleasesExactlyOnce() async {
        let bridge = FakeVRMNativeBridge(behavior: .wait)
        let adapter = VRMNativeAdapter(bridge: bridge)
        let generation = RendererGeneration()
        let testPackage = package(portrait: "portrait.png")
        let loadTask = Task {
            await adapter.load(testPackage, generation: generation)
        }

        await bridge.waitUntilLoadStarts()
        loadTask.cancel()
        let result = await loadTask.value
        await adapter.release(generation: generation)
        await adapter.release(generation: generation)
        let releaseCount = await bridge.releaseCount(for: generation)

        XCTAssertEqual(result, .packagePortrait(reason: .cancelled))
        XCTAssertEqual(releaseCount, 1)
    }

    func testStaleGenerationCommandsAreIgnoredAndCurrentReleaseIsIdempotent() async {
        let report = VRMNativeCapabilityReport(
            format: .vrm1,
            humanoid: true,
            mtoon: true,
            expressions: true,
            lookAt: true,
            constraints: false,
            springBone: true,
            animation: false,
            lipSync: .vrm1PhonemeExpressions
        )
        let bridge = FakeVRMNativeBridge(behavior: .succeed(report, omissions: []))
        let adapter = VRMNativeAdapter(bridge: bridge)
        let stale = RendererGeneration()
        let current = RendererGeneration()

        _ = await adapter.load(package(portrait: nil), generation: stale)
        _ = await adapter.load(package(portrait: nil), generation: current)
        await adapter.apply(.speaking(level: 0.8), generation: stale)
        await adapter.apply(.speaking(level: 0.4), generation: current)
        await adapter.stop(generation: stale)
        await adapter.release(generation: current)
        await adapter.release(generation: current)
        let applications = await bridge.appliedGenerations()
        let stops = await bridge.stoppedGenerations()
        let staleReleaseCount = await bridge.releaseCount(for: stale)
        let releaseCount = await bridge.releaseCount(for: current)

        XCTAssertEqual(applications, [current])
        XCTAssertEqual(stops, [])
        XCTAssertEqual(staleReleaseCount, 1)
        XCTAssertEqual(releaseCount, 1)
    }

    private func package(portrait: String?) -> ValidatedCharacterPackageHandle {
        ValidatedCharacterPackageHandle(
            installationID: "test-installation",
            immutableRootID: "test-root",
            manifest: CharacterPackageManifestV1(
                packageID: "test.vrm",
                characterID: "joi",
                version: "1.0.0",
                displayName: "Test VRM",
                renderer: .vrm,
                entryPath: "avatar.vrm",
                portraitPath: portrait,
                locales: ["en"],
                assets: [CharacterAssetV1(path: "avatar.vrm", mediaType: "model/gltf-binary", sha256: "test")],
                provenance: CharacterProvenanceV1(author: "Test", license: "Self-authored test fixture")
            ),
            receipt: CharacterPackageValidationReceiptV1(
                manifestSHA256: "test",
                expandedBytes: 100,
                fileCount: 1,
                validatedAt: Date(timeIntervalSince1970: 0)
            )
        )
    }

    private func jsonData(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func glbData(_ object: [String: Any]) -> Data {
        var json = jsonData(object)
        while json.count.isMultiple(of: 4) == false {
            json.append(0x20)
        }

        var result = Data()
        appendUInt32LE(0x4654_6C67, to: &result)
        appendUInt32LE(2, to: &result)
        appendUInt32LE(UInt32(20 + json.count), to: &result)
        appendUInt32LE(UInt32(json.count), to: &result)
        appendUInt32LE(0x4E4F_534A, to: &result)
        result.append(json)
        return result
    }

    private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }
}

private actor FakeVRMNativeBridge: VRMNativeRealityKitMetalBridging {
    enum Behavior: Sendable {
        case succeed(VRMNativeCapabilityReport, omissions: [String])
        case fail(VRMNativeBridgeFailure)
        case wait
    }

    private let behavior: Behavior
    private var didStartLoad = false
    private var loadStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var applications: [RendererGeneration] = []
    private var stops: [RendererGeneration] = []
    private var releases: [RendererGeneration: Int] = [:]

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func load(
        _ package: ValidatedCharacterPackageHandle,
        generation: RendererGeneration
    ) async throws -> VRMNativeBridgeLoad {
        _ = package
        _ = generation
        didStartLoad = true
        let waiters = loadStartWaiters
        loadStartWaiters.removeAll()
        waiters.forEach { $0.resume() }

        switch behavior {
        case .succeed(let report, let omissions):
            return VRMNativeBridgeLoad(report: report, omissions: omissions)
        case .fail(let failure):
            throw failure
        case .wait:
            try await Task.sleep(for: .seconds(30))
            throw VRMNativeBridgeFailure.runtimeUnavailable
        }
    }

    func apply(_ state: CharacterPresentationState, generation: RendererGeneration) async {
        _ = state
        applications.append(generation)
    }

    func stop(generation: RendererGeneration) async {
        stops.append(generation)
    }

    func release(generation: RendererGeneration) async {
        releases[generation, default: 0] += 1
    }

    func waitUntilLoadStarts() async {
        if didStartLoad { return }
        await withCheckedContinuation { continuation in
            loadStartWaiters.append(continuation)
        }
    }

    func releaseCount(for generation: RendererGeneration) -> Int {
        releases[generation, default: 0]
    }

    func appliedGenerations() -> [RendererGeneration] {
        applications
    }

    func stoppedGenerations() -> [RendererGeneration] {
        stops
    }
}
