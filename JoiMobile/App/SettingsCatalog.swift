import CompanionCore
import Foundation

/// The eight groups PRD §6.4 names, in the order it names them.
///
/// Kept as a closed enum rather than as sections written inline in a view, so
/// that "Settings has every group the product promised" is a property a test can
/// check instead of a thing someone remembers to look at.
enum SettingsGroup: String, CaseIterable, Identifiable, Sendable {
    case characterAndVoice
    case languageAndAppearance
    case memory
    case travelAndDownloads
    case accountAndSync
    case privacyAndData
    case accessibility
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .characterAndVoice: String(localized: "角色与语音")
        case .languageAndAppearance: String(localized: "语言与外观")
        case .memory: String(localized: "记忆")
        case .travelAndDownloads: String(localized: "出行与下载")
        case .accountAndSync: String(localized: "账户与同步")
        case .privacyAndData: String(localized: "隐私与数据")
        case .accessibility: String(localized: "无障碍")
        case .diagnostics: String(localized: "诊断")
        }
    }
}

/// Where a Settings row can go. Deliberately tiny: a destination may only be
/// named here once something real is behind it, so the type itself is the list
/// of what Settings can honestly open.
enum SettingsDestination: Equatable, Sendable {
    case characterLibrary
    case memoryList
}

/// One row of Settings.
///
/// `destination == nil` is the case this type exists for. Most of what PRD §6.4
/// asks Settings to group is not built yet, and the tempting shape — a switch
/// per row, wired to nothing — would be a screen full of controls that lie. A
/// row with no destination renders as a statement instead: it names the group,
/// says plainly what is and is not there, and cannot be toggled.
struct SettingsRow: Identifiable, Equatable, Sendable {
    let group: SettingsGroup
    let title: String
    /// What is true about this row today, in the user's words.
    let detail: String
    /// `nil` when tapping does nothing, because nothing is there to open.
    let destination: SettingsDestination?
    /// A fact this build can print — its version, which runtimes it compiled.
    /// Kept apart from `detail` so a measured value is never mistaken for
    /// explanatory copy, and vice versa.
    let value: String?

    var id: String { "\(group.rawValue).\(title)" }

    init(
        _ group: SettingsGroup,
        title: String,
        detail: String,
        destination: SettingsDestination? = nil,
        value: String? = nil
    ) {
        self.group = group
        self.title = title
        self.detail = detail
        self.destination = destination
        self.value = value
    }
}

/// The facts Settings reports about the running build.
///
/// Passed in rather than read from `Bundle` and the compile-time flags at the
/// point of use, so every row is reachable from a test on any rung of the spec
/// ladder — including the combinations this workstation cannot build.
struct SettingsBuildFacts: Equatable, Sendable {
    let version: String
    let build: String
    let admitsLive2D: Bool
    let admitsVRM: Bool
    /// The renderer the activated character actually uses, or `nil` when no
    /// character is activated.
    let activeRenderer: CharacterRendererKind?

    static var current: SettingsBuildFacts {
        let info = Bundle.main.infoDictionary
        return SettingsBuildFacts(
            version: info?["CFBundleShortVersionString"] as? String ?? "—",
            build: info?["CFBundleVersion"] as? String ?? "—",
            admitsLive2D: StageRuntimeAdmission.live2d,
            admitsVRM: StageRuntimeAdmission.vrm,
            activeRenderer: nil
        )
    }

    func withActiveRenderer(_ renderer: CharacterRendererKind?) -> SettingsBuildFacts {
        SettingsBuildFacts(
            version: version,
            build: build,
            admitsLive2D: admitsLive2D,
            admitsVRM: admitsVRM,
            activeRenderer: renderer
        )
    }

    /// Which native runtimes this binary compiled in, said in one line.
    ///
    /// This is the row that would have ended today's third debugging cycle in
    /// five seconds. A default-spec build draws the static silhouette correctly
    /// and looks exactly like a broken model, and until now nothing anywhere in
    /// the app could be asked which runtimes it had.
    var runtimeSummary: String {
        let admitted = [
            admitsLive2D ? "Live2D" : nil,
            admitsVRM ? "VRM" : nil,
        ].compactMap(\.self)
        return admitted.isEmpty ? String(localized: "均未编译（静态回退）") : admitted.joined(separator: " · ")
    }

    var activeRendererSummary: String {
        guard let activeRenderer else { return String(localized: "未激活角色") }
        switch activeRenderer {
        case .static: return String(localized: "静态")
        case .live2d: return "Live2D"
        case .vrm: return "VRM"
        }
    }
}

/// Every Settings row, built from what this build actually is.
///
/// Pure and total: it takes the facts and returns the rows, so the honesty rules
/// — every PRD group present, nothing claiming a capability that does not exist,
/// no diagnostic carrying a forbidden category — are checkable without a screen.
enum SettingsCatalog {

    static func rows(facts: SettingsBuildFacts) -> [SettingsRow] {
        characterAndVoice + languageAndAppearance + memory + travelAndDownloads
            + accountAndSync + privacyAndData + accessibility + diagnostics(facts: facts)
    }

    private static var characterAndVoice: [SettingsRow] {
        [
            SettingsRow(
                .characterAndVoice,
                title: String(localized: "角色库"),
                detail: String(localized: "导入、切换或删除本机角色。"),
                destination: .characterLibrary
            ),
            SettingsRow(
                .characterAndVoice,
                title: String(localized: "语音"),
                detail: String(localized: "角色使用角色包自带的语音，暂不能更换或调节。")
            ),
        ]
    }

    private static var languageAndAppearance: [SettingsRow] {
        [
            SettingsRow(
                .languageAndAppearance,
                title: String(localized: "界面语言"),
                // PRD §3.2 reserves the entry point without claiming the
                // languages: the copy contract is editable `zh-Hans`, and one
                // language is not a language setting.
                detail: String(localized: "这一版只有简体中文，其他语言尚未实现。"),
                value: String(localized: "简体中文")
            ),
            SettingsRow(
                .languageAndAppearance,
                title: String(localized: "外观"),
                detail: String(localized: "跟随系统的浅色与深色，没有单独设置。")
            ),
        ]
    }

    private static var memory: [SettingsRow] {
        [
            SettingsRow(
                .memory,
                title: String(localized: "这个角色记住的内容"),
                detail: String(localized: "逐条查看、改写或删除；记忆只属于当前角色，也只在这台设备上。"),
                destination: .memoryList
            )
        ]
    }

    private static var travelAndDownloads: [SettingsRow] {
        [
            SettingsRow(
                .travelAndDownloads,
                title: String(localized: "旅行包"),
                // Import is real (`G2-J4C`) and lives on Map; downloading is not
                // implemented at all, and saying only the first half would read
                // as if the second existed somewhere.
                detail: String(localized: "在「地图」里导入本机旅行包。应用内下载尚未实现。")
            )
        ]
    }

    private static var accountAndSync: [SettingsRow] {
        [
            SettingsRow(
                .accountAndSync,
                title: String(localized: "账户"),
                detail: String(localized: "没有账户，也无处登录：这一版完全在本机运行。")
            ),
            SettingsRow(
                .accountAndSync,
                title: String(localized: "分类同步"),
                detail: String(localized: "按分类同步尚未实现，没有任何内容为了同步离开这台设备。")
            ),
        ]
    }

    private static var privacyAndData: [SettingsRow] {
        [
            SettingsRow(
                .privacyAndData,
                title: String(localized: "数据存放"),
                detail: String(localized: "对话、记忆与角色包都留在这台设备上。"),
                value: String(localized: "仅本机")
            ),
            SettingsRow(
                .privacyAndData,
                title: String(localized: "会发出去的内容"),
                // Precise, because the easy sentence here would be false: a
                // journey attachment does send location, after an explicit
                // per-turn approval and coarsened to a ~111 m grid (`G2-J3B`).
                detail: String(localized: "只有对话与语音请求会经官方代理边界发出。位置仅在你为某一次对话明确附带时随那一次请求发出，且已粗化到约 111 米网格；照片与记忆内容不会发出。")
            ),
            SettingsRow(
                .privacyAndData,
                title: String(localized: "删除"),
                detail: String(localized: "记忆可以逐条删除，角色可以在角色库里删除。"),
                destination: .memoryList
            ),
            SettingsRow(
                .privacyAndData,
                title: String(localized: "导出"),
                detail: String(localized: "导出尚未实现。")
            ),
        ]
    }

    private static var accessibility: [SettingsRow] {
        [
            SettingsRow(
                .accessibility,
                title: String(localized: "无障碍"),
                // `JM-P0-021` keeps the hooks and defers the validation, so this
                // says which half is done rather than implying both.
                detail: String(localized: "语义标签、系统字体样式与减弱动态效果的接线已经在位；完整的 VoiceOver、动态字体与长文本验证仍是后续工作。")
            )
        ]
    }

    private static func diagnostics(facts: SettingsBuildFacts) -> [SettingsRow] {
        [
            SettingsRow(
                .diagnostics,
                title: String(localized: "版本"),
                detail: String(localized: "应用版本与构建号。"),
                value: "\(facts.version) (\(facts.build))"
            ),
            SettingsRow(
                .diagnostics,
                title: String(localized: "原生角色运行时"),
                detail: String(localized: "这个构建编译进了哪些原生运行时。未编译时，角色舞台会正确地显示剪影。"),
                value: facts.runtimeSummary
            ),
            SettingsRow(
                .diagnostics,
                title: String(localized: "当前角色渲染方式"),
                detail: String(localized: "当前激活角色实际使用的渲染方式。"),
                value: facts.activeRendererSummary
            ),
            SettingsRow(
                .diagnostics,
                title: String(localized: "诊断范围"),
                // PRD §6.4's own rule, stated on the screen it constrains.
                detail: String(localized: "诊断只包含以上内容，不含凭据、原始提示词、精确位置、照片或记忆内容。")
            ),
        ]
    }
}
