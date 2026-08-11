import CompanionCore
import XCTest
@testable import SyncClient

final class SyncConsentStoreTests: XCTestCase {
    func testPreciseLocationNeedsSeparateAuthorization() async {
        let store = SyncConsentStore()
        let record = MemoryRecordV1(
            recordID: "record",
            characterID: "joi",
            category: .preciseLocation,
            classification: .sensitiveLocation,
            value: "Place",
            provenance: .userEntered,
            reason: "Saved",
            precision: "place",
            authorizationDigest: "digest",
            createdAt: Date(),
            updatedAt: Date()
        )
        await store.setEnabled(true, category: .preciseLocation)
        let defaultAllowed = await store.mayEnqueue(record)
        XCTAssertFalse(defaultAllowed)

        let authorization = LocationSyncAuthorizationV1(
            authorizationID: "auth",
            recordRevisionDigest: "digest",
            precision: "place",
            remoteRetention: "until-deleted",
            accountID: "account",
            issuedAt: Date()
        )
        let explicitAllowed = await store.mayEnqueuePreciseLocation(record, authorization: authorization)
        XCTAssertTrue(explicitAllowed)
    }
}
