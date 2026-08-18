import CompanionCore
import Foundation
import XCTest
@testable import JoiMobile

/// `G2-J3C` — sources reaching the surface that shows them.
///
/// `SourceEligibilityTests` in CompanionCore covers the rule. These cover the
/// part the rule cannot: that an accepted answer's sources actually arrive in
/// the App, that a refused event's do not, and that the control the reader taps
/// appears exactly when there is something behind it.
@MainActor
final class SourceProjectionTests: XCTestCase {
    /// `J3C-06` — a sourced answer carries its sources into the App, and the
    /// verdict shown is `SourceEligibility`'s.
    func testAnAcceptedAnswerCarriesItsSourcesIntoTheApp() async throws {
        let model = AppModel(chatGateway: SourcedGateway(sources: [Self.source()]))
        await model.runChatTurn(text: "外滩是什么时候建的？")

        let answer = try XCTUnwrap(model.chatTranscript.last { $0.author == .companion })
        guard case let .supported(eligible, withheld) = model.claimSupport(for: answer) else {
            return XCTFail("a standing source must leave the answer supported")
        }
        XCTAssertEqual(eligible.map(\.claimID), ["claim.ok"])
        XCTAssertTrue(withheld.isEmpty)
    }

    /// `J3C-04` — an answer that arrived with citations, none of which may
    /// stand, is a different state from one that arrived with none. The reader
    /// is told, rather than shown a reply that looks unsourced.
    func testAnAnswerWhoseSourcesAllFailIsNotTreatedAsUnsourced() async throws {
        let withdrawn = Self.source(claimID: "claim.gone", withdrawn: true)
        let model = AppModel(chatGateway: SourcedGateway(sources: [withdrawn]))
        await model.runChatTurn(text: "这栋楼有多高？")

        let answer = try XCTUnwrap(model.chatTranscript.last { $0.author == .companion })
        let support = model.claimSupport(for: answer)
        XCTAssertNotEqual(support, .unsourced)
        guard case let .withheld(refused) = support else {
            return XCTFail("expected a withheld state, got \(support)")
        }
        XCTAssertEqual(refused.map(\.reason), [.withdrawn])

        // And it is openable, because the reason is the point.
        model.inspectSources(for: answer)
        XCTAssertNotNil(model.inspectedSources)
    }

    /// `J3C-06` — an ordinary conversational reply carries nothing, and offers
    /// nothing to open. The control is absent rather than showing an empty list.
    func testAnUnsourcedAnswerOffersNothingToOpen() async throws {
        let model = AppModel(chatGateway: SourcedGateway(sources: []))
        await model.runChatTurn(text: "今天过得怎么样？")

        let answer = try XCTUnwrap(model.chatTranscript.last { $0.author == .companion })
        XCTAssertEqual(model.claimSupport(for: answer), .unsourced)

        model.inspectSources(for: answer)
        XCTAssertNil(model.inspectedSources, "there is nothing to inspect behind an unsourced line")
    }

    /// A citation belongs to the line it supports. The user's own message is not
    /// a claim and carries nothing.
    func testTheUsersOwnMessageCarriesNoSources() async throws {
        let model = AppModel(chatGateway: SourcedGateway(sources: [Self.source()]))
        await model.runChatTurn(text: "外滩是什么时候建的？")

        let mine = try XCTUnwrap(model.chatTranscript.first { $0.author == .user })
        XCTAssertEqual(model.claimSupport(for: mine), .unsourced)
    }

    /// Sources are recorded on acceptance, not on arrival. A repeated event is
    /// refused by `CompanionSessionStore`, and its citations must be refused
    /// with it rather than quietly replacing the accepted ones.
    func testARepeatedEventCannotReplaceTheAcceptedLinesSources() async throws {
        let accepted = Self.source(claimID: "claim.accepted")
        let arrivedLate = Self.source(claimID: "claim.late")
        let model = AppModel(chatGateway: RepeatingGateway(first: [accepted], repeated: [arrivedLate]))

        await model.runChatTurn(text: "外滩是什么时候建的？")

        // One line, not two: the duplicate eventID was refused.
        let answers = model.chatTranscript.filter { $0.author == .companion }
        XCTAssertEqual(answers.count, 1)
        guard case let .supported(eligible, _) = model.claimSupport(for: try XCTUnwrap(answers.first)) else {
            return XCTFail("the accepted line keeps its own sources")
        }
        XCTAssertEqual(eligible.map(\.claimID), ["claim.accepted"])
    }

    /// The rule the whole slice exists for, at the App boundary: nothing here
    /// invents a citation. An answer's support comes from the event or not at
    /// all.
    func testNothingFabricatesASourceForAnAnswerThatCarriedNone() async throws {
        let model = AppModel(chatGateway: SourcedGateway(sources: []))
        await model.runChatTurn(text: "随便聊聊")

        for entry in model.chatTranscript {
            guard case .unsourced = model.claimSupport(for: entry) else {
                return XCTFail("a citation appeared for an answer that carried none")
            }
        }
    }

    // MARK: - Helpers

    private static func source(
        claimID: String = "claim.ok",
        withdrawn: Bool = false
    ) -> SourceProjectionV1 {
        SourceProjectionV1(
            placeID: "place.shanghai.bund",
            claimID: claimID,
            identityConfidence: 0.96,
            claimSupportConfidence: 0.91,
            publisher: "Joi Mobile test fixture",
            title: "外滩历史资料测试条目",
            locator: "fixture://sources/bund-history",
            authority: "institutional",
            revision: "2026-08-18",
            retrievedAt: Date(timeIntervalSince1970: 0),
            conflictStatus: SourceConflictStatus.none,
            correctionStatus: SourceCorrectionStatus.current,
            rights: "Repository-authored contract fixture",
            withdrawn: withdrawn
        )
    }
}

/// Answers one turn with a chosen set of sources on the final event, which is
/// the only place the contract carries them.
private struct SourcedGateway: ChatGateway {
    let sources: [SourceProjectionV1]

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<CompanionEventV1, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                CompanionEventV1(
                    eventID: "\(request.requestID)-received",
                    requestID: request.requestID,
                    threadID: request.threadID,
                    sessionID: request.sessionID,
                    characterID: request.characterID,
                    phase: .received,
                    contentState: .acceptedInput,
                    displayText: request.text
                )
            )
            continuation.yield(
                CompanionEventV1(
                    eventID: "\(request.requestID)-done",
                    requestID: request.requestID,
                    threadID: request.threadID,
                    sessionID: request.sessionID,
                    characterID: request.characterID,
                    phase: .done,
                    contentState: .acceptedFinal,
                    displayText: "外滩的建筑群大多建于二十世纪初。",
                    memoryEligibility: .proposalAllowed,
                    sources: sources
                )
            )
            continuation.finish()
        }
    }
}


/// Emits one final event twice under the same `eventID`, carrying different
/// sources each time. `CompanionSessionStore` accepts an event ID once.
private struct RepeatingGateway: ChatGateway {
    let first: [SourceProjectionV1]
    let repeated: [SourceProjectionV1]

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<CompanionEventV1, Error> {
        AsyncThrowingStream { continuation in
            func final(_ sources: [SourceProjectionV1]) -> CompanionEventV1 {
                CompanionEventV1(
                    eventID: "\(request.requestID)-done",
                    requestID: request.requestID,
                    threadID: request.threadID,
                    sessionID: request.sessionID,
                    characterID: request.characterID,
                    phase: .done,
                    contentState: .acceptedFinal,
                    displayText: "外滩的建筑群大多建于二十世纪初。",
                    sources: sources
                )
            }
            continuation.yield(final(first))
            continuation.yield(final(repeated))
            continuation.finish()
        }
    }
}
