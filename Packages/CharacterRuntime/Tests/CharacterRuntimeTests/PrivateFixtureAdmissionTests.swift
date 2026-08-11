import CompanionCore
import Foundation
import XCTest
@testable import CharacterRuntime

final class PrivateFixtureAdmissionTests: XCTestCase {
    func testSyntheticLive2DAdmissionVerifiesTreeAndReportsCompatibility() throws {
        let fixture = try makeLive2DFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let computed = try CharacterFixtureAdmitter().admitLive2D(
            entryURL: fixture.entry,
            policy: CharacterFixtureAdmissionPolicy(
                fingerprint: .computeOnly,
                expectedFileCount: fixture.fileCount
            ),
            disclosure: syntheticDisclosure
        )
        XCTAssertFalse(computed.compatibility.hashVerified)

        let verified = try CharacterFixtureAdmitter().admitLive2D(
            entryURL: fixture.entry,
            policy: CharacterFixtureAdmissionPolicy(
                fingerprint: .requireSHA256(computed.compatibility.contentSHA256),
                expectedFileCount: fixture.fileCount
            ),
            disclosure: syntheticDisclosure
        )

        XCTAssertTrue(verified.compatibility.hashVerified)
        XCTAssertEqual(verified.compatibility.format, .live2D)
        XCTAssertNil(verified.compatibility.fallback)
        XCTAssertTrue(verified.compatibility.runtimeVerificationRequired)
        XCTAssertTrue(verified.compatibility.capabilities.motion)
        XCTAssertTrue(verified.compatibility.capabilities.expression)
        XCTAssertTrue(verified.compatibility.capabilities.physics)
        XCTAssertTrue(verified.compatibility.capabilities.pose)
        XCTAssertTrue(verified.compatibility.capabilities.lipSync)
        XCTAssertEqual(verified.compatibility.sourceStatus, .syntheticTest)
    }

    func testLive2DAdmissionRejectsTraversalReference() throws {
        let fixture = try makeLive2DFixture(mocPath: "../outside.moc3")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertThrowsError(
            try CharacterFixtureAdmitter().admitLive2D(
                entryURL: fixture.entry,
                policy: CharacterFixtureAdmissionPolicy(fingerprint: .computeOnly),
                disclosure: syntheticDisclosure
            )
        ) { error in
            XCTAssertEqual(error as? CharacterFixtureAdmissionError, .pathEscape("../outside.moc3"))
        }
    }

    func testLive2DAdmissionRejectsSymlink() throws {
        let fixture = try makeLive2DFixture()
        let external = fixture.root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: fixture.root)
            try? FileManager.default.removeItem(at: external)
        }
        try Data("outside".utf8).write(to: external)
        let linked = fixture.root.appendingPathComponent("linked.png")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: external)

        XCTAssertThrowsError(
            try CharacterFixtureAdmitter().admitLive2D(
                entryURL: fixture.entry,
                policy: CharacterFixtureAdmissionPolicy(fingerprint: .computeOnly),
                disclosure: syntheticDisclosure
            )
        ) { error in
            XCTAssertEqual(error as? CharacterFixtureAdmissionError, .symlink("linked.png"))
        }
    }

    func testAdmissionRejectsSizeAndHashMismatch() throws {
        let file = try makeVRMFixture()
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertThrowsError(
            try CharacterFixtureAdmitter().admitVRM(
                fileURL: file,
                policy: CharacterFixtureAdmissionPolicy(fingerprint: .computeOnly, maximumBytes: 1),
                disclosure: syntheticDisclosure
            )
        ) { error in
            XCTAssertEqual(error as? CharacterFixtureAdmissionError, .contentTooLarge(maximum: 1))
        }

        XCTAssertThrowsError(
            try CharacterFixtureAdmitter().admitVRM(
                fileURL: file,
                policy: CharacterFixtureAdmissionPolicy(fingerprint: .requireSHA256(String(repeating: "0", count: 64))),
                disclosure: syntheticDisclosure
            )
        ) { error in
            guard case .sha256Mismatch = error as? CharacterFixtureAdmissionError else {
                return XCTFail("Expected sha256Mismatch, got \(error)")
            }
        }
    }

    func testSyntheticVRMAdmissionReusesMetadataInspector() throws {
        let file = try makeVRMFixture()
        defer { try? FileManager.default.removeItem(at: file) }

        let computed = try CharacterFixtureAdmitter().admitVRM(
            fileURL: file,
            policy: CharacterFixtureAdmissionPolicy(fingerprint: .computeOnly, expectedFileCount: 1),
            disclosure: syntheticDisclosure
        )
        let verified = try CharacterFixtureAdmitter().admitVRM(
            fileURL: file,
            policy: CharacterFixtureAdmissionPolicy(
                fingerprint: .requireSHA256(computed.compatibility.contentSHA256),
                expectedFileCount: 1
            ),
            disclosure: syntheticDisclosure
        )

        XCTAssertEqual(verified.compatibility.format, .vrm0)
        XCTAssertTrue(verified.compatibility.hashVerified)
        XCTAssertNil(verified.compatibility.fallback)
        XCTAssertTrue(verified.compatibility.capabilities.expression)
        XCTAssertTrue(verified.compatibility.capabilities.lookAt)
        XCTAssertTrue(verified.compatibility.capabilities.springBone)
        XCTAssertTrue(verified.compatibility.capabilities.lipSync)
        XCTAssertTrue(verified.compatibility.omissions.contains("vrma:undeclared"))
    }

    func testVRMAdmissionRejectsJSONDisguisedWithVRMExtension() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("joi-disguised-\(UUID().uuidString).vrm")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(#"{"asset":{"version":"2.0"}}"#.utf8).write(to: file)

        XCTAssertThrowsError(
            try CharacterFixtureAdmitter().admitVRM(
                fileURL: file,
                policy: CharacterFixtureAdmissionPolicy(fingerprint: .computeOnly),
                disclosure: syntheticDisclosure
            )
        ) { error in
            XCTAssertEqual(
                error as? CharacterFixtureAdmissionError,
                .contentTypeMismatch(file.lastPathComponent)
            )
        }
    }

    func testEnvironmentRequiresAbsolutePath() {
        XCTAssertThrowsError(
            try CharacterFixtureEnvironment.fileURL(
                for: CharacterFixtureEnvironment.vrmFileURL,
                environment: [CharacterFixtureEnvironment.vrmFileURL: "relative/avatar.vrm"]
            )
        ) { error in
            XCTAssertEqual(
                error as? CharacterFixtureAdmissionError,
                .relativeEnvironmentPath(CharacterFixtureEnvironment.vrmFileURL)
            )
        }
    }

    func testPrivateLive2DFixtureWhenConfigured() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let entryURL = try CharacterFixtureEnvironment.fileURL(
            for: CharacterFixtureEnvironment.live2DEntryURL,
            environment: environment
        ) else {
            throw XCTSkip("Set \(CharacterFixtureEnvironment.live2DEntryURL) to run the private Live2D fixture gate")
        }
        let expectedSHA = try XCTUnwrap(environment[CharacterFixtureEnvironment.live2DTreeSHA256])
        let expectedFileCount = try XCTUnwrap(
            environment[CharacterFixtureEnvironment.live2DFileCount].flatMap(Int.init)
        )

        let fixture = try CharacterFixtureAdmitter().admitLive2D(
            entryURL: entryURL,
            policy: CharacterFixtureAdmissionPolicy(
                fingerprint: .requireSHA256(expectedSHA),
                expectedFileCount: expectedFileCount
            ),
            disclosure: privateFixtureDisclosure
        )

        XCTAssertEqual(fixture.compatibility.format, .live2D)
        XCTAssertTrue(fixture.compatibility.hashVerified)
        XCTAssertNil(fixture.compatibility.fallback)
        XCTAssertEqual(fixture.compatibility.rightsStatus, .privateTestingOnly)
        XCTAssertTrue(fixture.compatibility.capabilities.motion)
        XCTAssertTrue(fixture.compatibility.capabilities.physics)
        XCTAssertTrue(fixture.compatibility.capabilities.pose)
        XCTAssertTrue(fixture.compatibility.capabilities.lipSync)
    }

    func testPrivateVRMFixtureWhenConfigured() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let fileURL = try CharacterFixtureEnvironment.fileURL(
            for: CharacterFixtureEnvironment.vrmFileURL,
            environment: environment
        ) else {
            throw XCTSkip("Set \(CharacterFixtureEnvironment.vrmFileURL) to run the private VRM fixture gate")
        }
        let expectedSHA = try XCTUnwrap(environment[CharacterFixtureEnvironment.vrmSHA256])

        let fixture = try CharacterFixtureAdmitter().admitVRM(
            fileURL: fileURL,
            policy: CharacterFixtureAdmissionPolicy(
                fingerprint: .requireSHA256(expectedSHA),
                expectedFileCount: 1
            ),
            disclosure: privateFixtureDisclosure
        )

        XCTAssertEqual(fixture.compatibility.format, .vrm0)
        XCTAssertTrue(fixture.compatibility.hashVerified)
        XCTAssertNil(fixture.compatibility.fallback)
        XCTAssertEqual(fixture.compatibility.rightsStatus, .privateTestingOnly)
        XCTAssertTrue(fixture.compatibility.capabilities.humanoidEquivalent)
        XCTAssertTrue(fixture.compatibility.capabilities.expression)
        XCTAssertTrue(fixture.compatibility.capabilities.lookAt)
        XCTAssertTrue(fixture.compatibility.capabilities.springBone)
        XCTAssertTrue(fixture.compatibility.capabilities.lipSync)
    }

    private var syntheticDisclosure: CharacterFixtureDisclosure {
        CharacterFixtureDisclosure(
            sourceStatus: .syntheticTest,
            rightsStatus: .verifiedRedistributable,
            sourceReference: "https://example.invalid/self-authored-fixture",
            rightsNotice: "Self-authored synthetic test data"
        )
    }

    private var privateFixtureDisclosure: CharacterFixtureDisclosure {
        CharacterFixtureDisclosure(
            sourceStatus: .environmentProvided,
            rightsStatus: .privateTestingOnly,
            rightsNotice: "Local compatibility testing only; never package or distribute"
        )
    }

    private func makeLive2DFixture(
        mocPath: String = "model.moc3"
    ) throws -> (root: URL, entry: URL, fileCount: Int) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("joi-live2d-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let entry = root.appendingPathComponent("model.model3.json")
        let model: [String: Any] = [
            "Version": 3,
            "FileReferences": [
                "Moc": mocPath,
                "Textures": ["texture.png"],
                "Motions": ["Idle": [["File": "idle.motion3.json"]]],
                "Expressions": [["Name": "smile", "File": "smile.exp3.json"]],
                "Physics": "model.physics3.json",
                "Pose": "model.pose3.json",
            ],
            "Groups": [
                ["Target": "Parameter", "Name": "EyeBlink", "Ids": ["ParamEyeLOpen", "ParamEyeROpen"]],
                ["Target": "Parameter", "Name": "LipSync", "Ids": ["ParamMouthOpenY"]],
            ],
        ]
        try JSONSerialization.data(withJSONObject: model, options: [.sortedKeys]).write(to: entry)
        let assets = [
            "model.moc3", "texture.png", "idle.motion3.json", "smile.exp3.json",
            "model.physics3.json", "model.pose3.json",
        ]
        for asset in assets {
            try Data("fixture:\(asset)".utf8).write(to: root.appendingPathComponent(asset))
        }
        return (root, entry, assets.count + 1)
    }

    private func makeVRMFixture() throws -> URL {
        let metadata: [String: Any] = [
            "asset": ["version": "2.0"],
            "extensionsUsed": ["VRM"],
            "extensions": [
                "VRM": [
                    "humanoid": ["humanBones": []],
                    "firstPerson": ["lookAtTypeName": "Bone"],
                    "secondaryAnimation": ["boneGroups": []],
                    "blendShapeMaster": ["blendShapeGroups": [["presetName": "a"]]],
                    "materialProperties": [["shader": "VRM/MToon"]],
                ],
            ],
        ]
        var json = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        while !json.count.isMultiple(of: 4) { json.append(0x20) }
        var data = Data()
        appendUInt32LE(0x4654_6C67, to: &data)
        appendUInt32LE(2, to: &data)
        appendUInt32LE(UInt32(20 + json.count), to: &data)
        appendUInt32LE(UInt32(json.count), to: &data)
        appendUInt32LE(0x4E4F_534A, to: &data)
        data.append(json)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("joi-vrm-\(UUID().uuidString).vrm")
        try data.write(to: url)
        return url
    }

    private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }
}

private extension CharacterCapabilities {
    var humanoidEquivalent: Bool { pose }
}
