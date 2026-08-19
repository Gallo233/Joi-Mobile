import CompanionCore
import Foundation
import Network
import XCTest
@testable import JoiMobile

/// `G2-J5G` — the app notices it is offline instead of finding out by failing.
///
/// `G2-J5C` bounded a turn by silence, which is what catches a connection that
/// dies mid-stream. It does nothing for the case the device already knows about:
/// with no interface at all, the old path cleared the draft, spent the journey
/// attachment, opened a request that could not leave, and waited out the stall
/// timeout before saying anything. Every part of that was avoidable.
@MainActor
final class ReachabilityTests: XCTestCase {

    // MARK: - The precondition, without a network interface

    /// A cold launch must not look offline. `NWPathMonitor` delivers its first
    /// path asynchronously, and refusing during that window would break the
    /// first send of every launch.
    func testAnUnaskedNetworkNeverRefusesASend() {
        XCTAssertTrue(SendPrecondition.mayAttemptTurn(.unknown))
    }

    /// The asymmetry: only the negative report is acted on.
    func testOnlyACertainAbsenceRefuses() {
        XCTAssertTrue(SendPrecondition.mayAttemptTurn(.interfaceAvailable))
        XCTAssertFalse(SendPrecondition.mayAttemptTurn(.unreachable))
    }

    /// An interface that exists is not a promise that Joi's backend answers, so
    /// nothing here may be read as one. The stall timeout stays the only thing
    /// that can prove a live-looking connection is dead.
    func testAnAvailableInterfaceIsNotAPromise() {
        let model = Self.freshModel(reachability: .interfaceAvailable)
        XCTAssertTrue(
            SendPrecondition.mayAttemptTurn(model.networkMonitor.reachability),
            "an available interface permits the attempt and guarantees nothing about it"
        )
    }

    // MARK: - Reading a path

    func testAPathReportBecomesReachability() {
        let monitor = NetworkMonitor(monitor: nil)
        XCTAssertEqual(monitor.reachability, .unknown, "an inert monitor has not looked")

        monitor.apply(status: .satisfied, expensive: false, constrained: false)
        XCTAssertEqual(monitor.reachability, .interfaceAvailable)

        monitor.apply(status: .unsatisfied, expensive: false, constrained: false)
        XCTAssertEqual(monitor.reachability, .unreachable)

        // Nothing can be sent until a connection is brought up, so this is read
        // as unreachable rather than as "probably fine".
        monitor.apply(status: .requiresConnection, expensive: false, constrained: false)
        XCTAssertEqual(monitor.reachability, .unreachable)
    }

    /// Cellular and Low Data Mode are recorded and deliberately not acted on: a
    /// chat turn is something the user just asked for, not discretionary work.
    func testAnExpensiveOrConstrainedPathStillSends() {
        let monitor = NetworkMonitor(monitor: nil)
        monitor.apply(status: .satisfied, expensive: true, constrained: true)

        XCTAssertTrue(monitor.isExpensive)
        XCTAssertTrue(monitor.isConstrained)
        XCTAssertTrue(
            SendPrecondition.mayAttemptTurn(monitor.reachability),
            "refusing on cellular would be a data-saving promise this product never made"
        )
    }

    // MARK: - What an offline send costs

    /// The point of the slice: the turn is never opened.
    func testAnOfflineSendNeverReachesTheGateway() async {
        let gateway = CountingGateway()
        let model = Self.freshModel(gateway: gateway, reachability: .unreachable)
        model.chatDraft = "现在几点"

        model.sendChatMessage()

        XCTAssertEqual(gateway.calls, 0, "a request that cannot leave must not be opened")
    }

    /// It costs a tap, not the sentence — the same rule the expired-attachment
    /// guard follows immediately above it.
    func testAnOfflineSendKeepsTheDraft() {
        let model = Self.freshModel(reachability: .unreachable)
        model.chatDraft = "现在几点"

        model.sendChatMessage()

        XCTAssertEqual(model.chatDraft, "现在几点", "the user's sentence survives")
    }

    /// `FAIL-024`: keep cached and accepted state. A refusal is not a reason to
    /// lose the conversation.
    func testAnOfflineSendLeavesTheTranscriptAlone() async {
        let model = Self.freshModel(gateway: MockChatGateway(), reachability: .interfaceAvailable)
        await model.runChatTurn(text: "你好")
        let before = model.chatTranscript.map(\.eventID)
        XCTAssertFalse(before.isEmpty)

        model.networkMonitor.apply(status: .unsatisfied, expensive: false, constrained: false)
        model.chatDraft = "还在吗"
        model.sendChatMessage()

        XCTAssertEqual(model.chatTranscript.map(\.eventID), before)
    }

    /// PRD §7 asks this state to show online retry versus cached mode, so the
    /// refusal has to be retryable and has to name what still works.
    func testTheRefusalIsRetryableAndNamesWhatStillWorks() {
        let model = Self.freshModel(reachability: .unreachable)
        model.chatDraft = "现在几点"
        model.sendChatMessage()

        guard case let .failed(message, retryable) = model.chatTurnState else {
            return XCTFail("an offline send must report a named state, got \(model.chatTurnState)")
        }
        XCTAssertTrue(retryable, "the network coming back is exactly what a retry is for")
        XCTAssertTrue(message.contains("缓存"), "the cached walk is what works with no network: \(message)")
        XCTAssertTrue(message.contains("输入框"), "the user needs to know the sentence was kept: \(message)")
    }

    /// A turn that could not leave may not consume the one-turn location
    /// approval; that receipt buys exactly one request.
    func testAnOfflineSendDoesNotSpendAJourneyAttachment() {
        let model = Self.freshModel(reachability: .unreachable)
        model.chatDraft = "这里是哪"
        let before = model.pendingJourneyAttachment

        model.sendChatMessage()

        XCTAssertEqual(model.pendingJourneyAttachment, before, "the approval is untouched")
    }

    /// The network coming back needs no ceremony: the next send just goes.
    func testTheNextSendGoesOnceTheNetworkReturns() async {
        let gateway = CountingGateway()
        let model = Self.freshModel(gateway: gateway, reachability: .unreachable)
        model.chatDraft = "现在几点"
        model.sendChatMessage()
        XCTAssertEqual(gateway.calls, 0)

        model.networkMonitor.apply(status: .satisfied, expensive: false, constrained: false)
        await model.runChatTurn(text: model.chatDraft)

        XCTAssertEqual(gateway.calls, 1)
    }

    // MARK: - The ambient state

    /// Visible before the user taps anything, which is the half `FAIL-024` was
    /// missing: the app could only report the network by failing at it.
    func testChatShowsCachedModeWhileIdleAndOffline() {
        let model = Self.freshModel(reachability: .unreachable)
        XCTAssertTrue(model.isShowingCachedMode)
    }

    func testCachedModeIsNotShownWhileTheNetworkIsThere() {
        XCTAssertFalse(Self.freshModel(reachability: .interfaceAvailable).isShowingCachedMode)
        XCTAssertFalse(
            Self.freshModel(reachability: .unknown).isShowingCachedMode,
            "a cold launch is not offline"
        )
    }

    /// It steps aside as soon as something more specific is on screen: the
    /// refusal already says the sentence was kept and a retry is worth making.
    func testCachedModeStepsAsideForAMessageThatSaysMore() {
        let model = Self.freshModel(reachability: .unreachable)
        model.chatDraft = "现在几点"
        model.sendChatMessage()

        XCTAssertFalse(
            model.isShowingCachedMode,
            "the failure banner says strictly more than the ambient strip does"
        )
    }

    // MARK: - Helpers

    private static func freshModel(
        gateway: (any ChatGateway)? = nil,
        reachability: NetworkReachability
    ) -> AppModel {
        let monitor = NetworkMonitor(monitor: nil)
        switch reachability {
        case .unknown: break
        case .interfaceAvailable: monitor.apply(status: .satisfied, expensive: false, constrained: false)
        case .unreachable: monitor.apply(status: .unsatisfied, expensive: false, constrained: false)
        }
        let suite = "joi.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppModel(chatGateway: gateway, networkMonitor: monitor, defaults: defaults)
    }
}

/// Counts the requests that were actually opened.
///
/// `MockChatGateway` cannot answer the question this suite asks — "was a turn
/// spent" — because it has nothing to count with.
private final class CountingGateway: ChatGateway, @unchecked Sendable {
    /// Read and written only from the main actor in these tests.
    private(set) nonisolated(unsafe) var calls = 0

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<CompanionEventV1, Error> {
        calls += 1
        return MockChatGateway().stream(request)
    }
}
