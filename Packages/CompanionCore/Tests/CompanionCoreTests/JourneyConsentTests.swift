import XCTest
@testable import CompanionCore

final class JourneyConsentTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAttachmentRequiresReceipt() {
        XCTAssertThrowsError(
            try request(attachment: snapshot(), receipt: nil)
        ) { error in
            XCTAssertEqual(error as? ChatRequestValidationError, .missingJourneyReceipt)
        }
    }

    func testReceiptRejectsMismatchedDigestAndIdentity() {
        let context = snapshot()
        XCTAssertThrowsError(
            try request(attachment: context, receipt: receipt(for: context, digest: "wrong"))
        ) { error in
            XCTAssertEqual(error as? ChatRequestValidationError, .digestMismatch)
        }

        XCTAssertThrowsError(
            try request(
                attachment: context,
                receipt: receipt(for: context, requestID: "another-request")
            )
        ) { error in
            XCTAssertEqual(error as? ChatRequestValidationError, .identityMismatch)
        }
    }

    func testReceiptRejectsExpiredAndRevokedUse() {
        let context = snapshot()
        XCTAssertThrowsError(
            try request(
                attachment: context,
                receipt: receipt(for: context, expiresAt: now)
            )
        ) { error in
            XCTAssertEqual(error as? ChatRequestValidationError, .expired)
        }

        XCTAssertThrowsError(
            try request(
                attachment: context,
                receipt: receipt(for: context, revoked: true)
            )
        ) { error in
            XCTAssertEqual(error as? ChatRequestValidationError, .revoked)
        }
    }

    func testReceiptIsConsumedOnlyOnce() async throws {
        let context = snapshot()
        let authorized = try request(
            attachment: context,
            receipt: receipt(for: context)
        )
        let store = JourneyUseReceiptStore()

        try await store.consume(for: authorized, at: now)
        do {
            try await store.consume(for: authorized, at: now)
            XCTFail("Expected one-use receipt rejection")
        } catch {
            XCTAssertEqual(error as? ChatRequestValidationError, .receiptAlreadyUsed)
        }
    }

    private func snapshot() -> JourneyContextSnapshot {
        JourneyContextSnapshot(
            journeyID: "journey",
            placeID: "place",
            routeID: "route",
            coordinate: GeoCoordinate(latitude: 31.2304, longitude: 121.4737),
            horizontalAccuracyMeters: 8,
            observedAt: now,
            routeProgress: 0.5,
            identityConfidence: 0.9,
            sourceRevisionIDs: ["source-v1"],
            consentScope: "chatOneTurn"
        )
    }

    private func receipt(
        for context: JourneyContextSnapshot,
        digest: String? = nil,
        requestID: String = "request",
        expiresAt: Date? = nil,
        revoked: Bool = false
    ) -> JourneyUseReceiptV1 {
        JourneyUseReceiptV1(
            receiptID: "receipt",
            purpose: .chatOneTurn,
            userAction: "map-context-share-button",
            payloadDigest: digest ?? context.payloadDigest(),
            precision: "place",
            threadID: "thread",
            requestID: requestID,
            issuedAt: now.addingTimeInterval(-10),
            expiresAt: expiresAt ?? now.addingTimeInterval(60),
            revoked: revoked
        )
    }

    private func request(
        attachment: JourneyContextSnapshot?,
        receipt: JourneyUseReceiptV1?
    ) throws -> ChatRequest {
        try ChatRequest(
            requestID: "request",
            threadID: "thread",
            sessionID: "session",
            characterID: "joi",
            text: "你好",
            displayLocale: "zh-Hans",
            voiceLocale: "zh-Hans",
            journeyAttachment: attachment,
            journeyReceipt: receipt,
            validationDate: now
        )
    }
}
