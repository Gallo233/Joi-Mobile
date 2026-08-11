import XCTest
@testable import MapFeature

final class MapExperienceStateTests: XCTestCase {
    func testInitialStateDoesNotClaimOfflineRerouting() {
        let state = MapExperienceState()
        XCTAssertTrue(state.isOffline)
        XCTAssertEqual(state.detail, "已缓存路线预览")
    }
}
