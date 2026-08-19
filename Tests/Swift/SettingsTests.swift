import CompanionCore
import Foundation
import XCTest
@testable import JoiMobile

/// `G2-J5E` — Settings, and the last dead control on a primary surface.
///
/// `JM-P0-018` names eight groups and this build has something real behind three
/// of them, so the interesting property is not that Settings works: it is that
/// Settings does not lie. A screen of switches wired to nothing would satisfy
/// "Settings exists" and be worse than the empty button it replaced.
@MainActor
final class SettingsTests: XCTestCase {

    private static let facts = SettingsBuildFacts(
        version: "0.1.0",
        build: "1",
        admitsLive2D: true,
        admitsVRM: true,
        activeRenderer: .live2d
    )

    // MARK: - Every group the PRD names

    func testEveryGroupInThePRDIsPresentAndInOrder() {
        let rows = SettingsCatalog.rows(facts: Self.facts)
        var seen: [SettingsGroup] = []
        for row in rows where seen.last != row.group {
            seen.append(row.group)
        }
        XCTAssertEqual(seen, SettingsGroup.allCases, "PRD §6.4 names these eight, in this order")
        XCTAssertEqual(Set(seen).count, seen.count, "a group may not be split across the screen")
    }

    func testEveryRowSaysSomething() {
        for row in SettingsCatalog.rows(facts: Self.facts) {
            XCTAssertFalse(row.title.isEmpty, "\(row.id) has no title")
            XCTAssertFalse(row.detail.isEmpty, "\(row.id) explains nothing, which is the failure mode")
        }
    }

    // MARK: - Honesty

    /// The rule the type exists to enforce: a row may only be tappable when
    /// something real is behind it.
    func testOnlyGroupsWithSomethingBehindThemAreOpenable() {
        let openable = Set(
            SettingsCatalog.rows(facts: Self.facts)
                .filter { $0.destination != nil }
                .map(\.group)
        )
        XCTAssertEqual(openable, [.characterAndVoice, .memory, .privacyAndData])

        for group in [SettingsGroup.languageAndAppearance, .travelAndDownloads, .accountAndSync, .accessibility] {
            let rows = SettingsCatalog.rows(facts: Self.facts).filter { $0.group == group }
            XCTAssertFalse(rows.isEmpty, "\(group) is listed even though it is not built")
            XCTAssertTrue(
                rows.allSatisfy { $0.destination == nil },
                "\(group) has nothing to open and must not look like it does"
            )
        }
    }

    /// A group with nothing behind it has to name what is missing, or listing it
    /// is worse than hiding it.
    func testAnUnbuiltGroupNamesWhatIsMissing() {
        let rows = SettingsCatalog.rows(facts: Self.facts)
        for group in [SettingsGroup.travelAndDownloads, .accountAndSync] {
            let detail = rows.filter { $0.group == group }.map(\.detail).joined()
            XCTAssertTrue(
                detail.contains("尚未实现"),
                "\(group) does not say that it is unimplemented: \(detail)"
            )
        }
    }

    // MARK: - Diagnostics

    /// The row that would have ended today's third debugging cycle in five
    /// seconds, across every rung of the ladder including ones this workstation
    /// cannot build.
    func testDiagnosticsReportWhichRuntimesTheBuildCompiled() {
        func summary(live2d: Bool, vrm: Bool) -> String {
            SettingsBuildFacts(
                version: "0.1.0", build: "1",
                admitsLive2D: live2d, admitsVRM: vrm, activeRenderer: nil
            ).runtimeSummary
        }

        XCTAssertEqual(summary(live2d: true, vrm: true), "Live2D · VRM")
        XCTAssertEqual(summary(live2d: true, vrm: false), "Live2D")
        XCTAssertEqual(summary(live2d: false, vrm: true), "VRM")
        // The default-spec build: the one that renders a correct silhouette and
        // looks exactly like a broken model.
        XCTAssertTrue(summary(live2d: false, vrm: false).contains("均未编译"))
    }

    func testDiagnosticsDistinguishNoActiveCharacterFromAStaticOne() {
        let none = Self.facts.withActiveRenderer(nil).activeRendererSummary
        let still = Self.facts.withActiveRenderer(.static).activeRendererSummary
        XCTAssertNotEqual(none, still, "an absent character and a static one are different facts")
        XCTAssertEqual(Self.facts.withActiveRenderer(.vrm).activeRendererSummary, "VRM")
    }

    /// PRD §6.4: diagnostics never reveal credentials, raw prompts, precise
    /// location, photos or memory values. Checked against a model that actually
    /// holds a conversation, so this is not a claim about an empty object.
    func testDiagnosticsCarryNothingFromTheConversationOrMemory() async {
        let model = Self.freshModel(gateway: MockChatGateway())
        await model.restoreActiveCharacter()
        await model.runChatTurn(text: "我住在建国路 88 号")

        let printed = SettingsCatalog.rows(facts: model.settingsBuildFacts)
            .map { "\($0.title)\($0.detail)\($0.value ?? "")" }
            .joined()

        XCTAssertFalse(printed.contains("建国路"), "a diagnostic may not echo what was said")
        for transcript in model.chatTranscript {
            XCTAssertFalse(printed.contains(transcript.text), "a diagnostic may not echo the transcript")
        }
        for forbidden in ["Bearer", "sk-", "api_key", "Authorization"] {
            XCTAssertFalse(printed.contains(forbidden), "a diagnostic may not carry a credential shape")
        }
    }

    /// The diagnostics section is closed: adding a field to it is a decision,
    /// not a side effect of touching the catalog.
    func testDiagnosticsAreExactlyTheFourDeclaredFacts() {
        let diagnostics = SettingsCatalog.rows(facts: Self.facts).filter { $0.group == .diagnostics }
        XCTAssertEqual(diagnostics.count, 4)
        XCTAssertEqual(diagnostics.compactMap(\.value).count, 3, "the fourth row states the rule itself")
        XCTAssertTrue(diagnostics.contains { $0.value == "0.1.0 (1)" })
    }

    // MARK: - The control is no longer dead

    func testTheProfileControlOpensSettings() {
        let model = Self.freshModel()
        XCTAssertFalse(model.isSettingsPresented)
        model.presentSettings()
        XCTAssertTrue(model.isSettingsPresented)
        model.dismissSettings()
        XCTAssertFalse(model.isSettingsPresented)
    }

    /// Settings closes before its destination opens, so a user is never two
    /// dismissals deep in sheets.
    func testFollowingARowClosesSettingsAndOpensTheDestination() {
        let model = Self.freshModel()

        model.presentSettings()
        model.openFromSettings(.characterLibrary)
        XCTAssertFalse(model.isSettingsPresented)
        XCTAssertTrue(model.isCharacterLibraryPresented)

        model.dismissCharacterLibrary()
        model.presentSettings()
        model.openFromSettings(.memoryList)
        XCTAssertFalse(model.isSettingsPresented)
    }

    /// Settings is secondary by `JM-P0-001`: opening it changes no session state
    /// and adds no primary surface.
    func testOpeningSettingsChangesNothingAboutTheSession() async {
        let model = Self.freshModel(gateway: MockChatGateway())
        await model.restoreActiveCharacter()
        await model.runChatTurn(text: "你好")

        let surface = model.selectedSurface
        let transcript = model.chatTranscript.map(\.eventID)
        let character = model.currentCharacterName

        model.presentSettings()

        XCTAssertEqual(model.selectedSurface, surface)
        XCTAssertEqual(model.chatTranscript.map(\.eventID), transcript)
        XCTAssertEqual(model.currentCharacterName, character)
    }

    // MARK: - Helpers

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
