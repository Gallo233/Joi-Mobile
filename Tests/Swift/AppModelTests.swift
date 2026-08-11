import XCTest
@testable import JoiMobile

@MainActor
final class AppModelTests: XCTestCase {
    func testChatMapSwitchPreservesSessionIdentity() async {
        let model = AppModel()
        let before = await model.companionSession.current()
        let beforeJourney = await model.journeyContext.current()
        model.select(.map)
        model.select(.chat)
        let after = await model.companionSession.current()
        let afterJourney = await model.journeyContext.current()

        XCTAssertEqual(before.characterID, after.characterID)
        XCTAssertEqual(before.threadID, after.threadID)
        XCTAssertEqual(beforeJourney, afterJourney)
        XCTAssertEqual(model.selectedSurface, .chat)
    }

    func testSuccessfulCharacterPreviewDoesNotChangeSessionIdentity() async throws {
        let model = AppModel()
        let before = await model.companionSession.current()
        let beforeJourney = await model.journeyContext.current()
        let fixtureURL = try makeVRM0MetadataFixture()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        await model.previewCharacter(at: fixtureURL)

        let after = await model.companionSession.current()
        let afterJourney = await model.journeyContext.current()
        XCTAssertEqual(before.characterID, after.characterID)
        XCTAssertEqual(before.threadID, after.threadID)
        XCTAssertEqual(before.sessionID, after.sessionID)
        XCTAssertEqual(beforeJourney, afterJourney)
        guard case let .ready(preview) = model.characterPreviewState else {
            return XCTFail("Expected admitted preview")
        }
        XCTAssertEqual(preview.format, "VRM 0.x")
        XCTAssertEqual(preview.fileName, fixtureURL.lastPathComponent)
        XCTAssertNotNil(preview.fingerprint)
        XCTAssertTrue(preview.rights.contains("待确认"))
    }

    func testFailedCharacterPreviewDoesNotChangeSessionIdentity() async throws {
        let model = AppModel()
        let before = await model.companionSession.current()
        let beforeJourney = await model.journeyContext.current()
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try Data("not-a-character".utf8).write(to: fixtureURL)
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        await model.previewCharacter(at: fixtureURL)

        let after = await model.companionSession.current()
        let afterJourney = await model.journeyContext.current()
        XCTAssertEqual(before.characterID, after.characterID)
        XCTAssertEqual(before.threadID, after.threadID)
        XCTAssertEqual(before.sessionID, after.sessionID)
        XCTAssertEqual(beforeJourney, afterJourney)
        guard case .failed = model.characterPreviewState else {
            return XCTFail("Expected failed preview")
        }
    }

    private func makeVRM0MetadataFixture() throws -> URL {
        let fixture: [String: Any] = [
            "asset": ["version": "2.0"],
            "extensionsUsed": ["VRM"],
            "extensions": [
                "VRM": [
                    "humanoid": ["humanBones": []],
                    "firstPerson": [:],
                    "materialProperties": [["shader": "VRM/MToon"]],
                    "blendShapeMaster": [
                        "blendShapeGroups": [["presetName": "a"]],
                    ],
                ],
            ],
        ]
        var json = try JSONSerialization.data(withJSONObject: fixture, options: [.sortedKeys])
        while !json.count.isMultiple(of: 4) { json.append(0x20) }
        var data = Data()
        appendUInt32LE(0x4654_6C67, to: &data)
        appendUInt32LE(2, to: &data)
        appendUInt32LE(UInt32(20 + json.count), to: &data)
        appendUInt32LE(UInt32(json.count), to: &data)
        appendUInt32LE(0x4E4F_534A, to: &data)
        data.append(json)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("vrm")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }
}
