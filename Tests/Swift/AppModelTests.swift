import XCTest
@testable import JoiMobile

@MainActor
final class AppModelTests: XCTestCase {
    func testChatMapSwitchPreservesSessionIdentity() async {
        let model = AppModel()
        let before = await model.companionSession.current()
        model.select(.map)
        model.select(.chat)
        let after = await model.companionSession.current()

        XCTAssertEqual(before.characterID, after.characterID)
        XCTAssertEqual(before.threadID, after.threadID)
        XCTAssertEqual(model.selectedSurface, .chat)
    }
}
