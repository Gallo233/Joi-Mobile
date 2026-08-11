import CompanionCore
import XCTest
@testable import OfflinePack

final class OfflinePackVerifierTests: XCTestCase {
    func testRequiresRightsBeforeActivation() {
        let manifest = TravelPackManifestV1(
            packID: "pack",
            routeID: "route",
            version: "1.0.0",
            locales: ["en"],
            routePath: "route.json",
            files: [],
            sourceRevisionIDs: [],
            rights: [],
            createdAt: Date()
        )
        XCTAssertThrowsError(try OfflinePackVerifier().verify(manifest))
    }
}
