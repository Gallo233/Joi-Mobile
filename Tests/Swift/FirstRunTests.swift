import CompanionCore
import Foundation
import XCTest
@testable import JoiMobile

/// `G2-J5A` — first run is local, and stays that way.
///
/// `JM-P0-002` asks that a new user can choose a character, enter Chat and send
/// text without creating an account or granting microphone, location, camera or
/// photo access. That has been true since G1 by construction and nothing has
/// ever checked it — which is exactly the kind of property that regresses
/// silently, one convenient `requestAuthorization()` at a time.
@MainActor
final class FirstRunTests: XCTestCase {
    /// A launched app asks for nothing.
    func testLaunchingAsksForNoPermission() async {
        let model = Self.freshModel()
        await model.restoreActiveCharacter()

        XCTAssertEqual(
            model.walkLocation.availability,
            .idle,
            "location must not be requested until a walk starts"
        )
        XCTAssertFalse(model.voiceInput.state.isListening, "the microphone must not open at launch")
        XCTAssertFalse(model.isWalking)
    }

    /// A character is visible and a message can be sent — PRD §3.2's own
    /// definition of first run being complete.
    func testANewUserCanSendAMessageWithTheBundledCharacter() async throws {
        let model = Self.freshModel(gateway: MockChatGateway())
        await model.restoreActiveCharacter()

        let session = await model.companionSession.current()
        XCTAssertFalse(session.selection.displayName.isEmpty, "a bundled character is present")
        XCTAssertEqual(model.currentCharacterName, session.selection.displayName)

        await model.runChatTurn(text: "你好")

        XCTAssertFalse(model.chatTranscript.isEmpty, "first run is complete once a message can be sent")
        XCTAssertEqual(model.walkLocation.availability, .idle, "sending a message needs no location")
    }

    // MARK: - The welcome is not a gate

    func testTheWelcomeShowsOnceAndThenNotAgain() {
        let defaults = Self.emptyDefaults()
        XCTAssertTrue(AppModel(defaults: defaults).isWelcomePresented, "a new install is greeted")

        let first = AppModel(defaults: defaults)
        first.completeWelcome()
        XCTAssertFalse(first.isWelcomePresented)

        XCTAssertFalse(
            AppModel(defaults: defaults).isWelcomePresented,
            "a later launch is not greeted again"
        )
    }

    /// The point of it being an overlay: the app underneath already works, so
    /// dismissing is never a precondition for using it.
    func testTheAppIsUsableWithoutDismissingTheWelcome() async throws {
        let model = Self.freshModel(gateway: MockChatGateway())
        XCTAssertTrue(model.isWelcomePresented)

        await model.runChatTurn(text: "先说句话")

        XCTAssertFalse(model.chatTranscript.isEmpty, "the welcome must not stand in the way")
        XCTAssertTrue(model.isWelcomePresented, "and it is still there afterwards")
    }

    /// Reading it is not a requirement, so waving it away is the same call and
    /// is equally permanent.
    func testDismissingWithoutReadingIsRemembered() {
        let defaults = Self.emptyDefaults()
        let model = AppModel(defaults: defaults)
        model.completeWelcome()
        XCTAssertTrue(defaults.bool(forKey: AppModel.welcomeSeenKey))
    }

    // MARK: - Helpers

    /// A model whose stored state is its own, so this suite neither reads nor
    /// writes the state of the workstation it happens to run on.
    private static func freshModel(gateway: (any ChatGateway)? = nil) -> AppModel {
        AppModel(chatGateway: gateway, defaults: emptyDefaults())
    }

    private static func emptyDefaults() -> UserDefaults {
        let suite = "joi.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
