import CompanionCore
import SwiftUI

/// The answer whose sources are open for reading.
struct InspectedSources: Equatable, Identifiable {
    let eventID: String
    let support: ClaimSupport

    var id: String { eventID }
}

/// What stands behind an answer (`G2-J3C`).
///
/// PRD §8.1 keeps four questions apart — what is this, who says it, does this
/// source support this claim, and which version and when — and forbids
/// collapsing them into one probability. This view is where that rule becomes
/// visible: every source shows all four, and there is no combined score
/// anywhere, because there is no such number to show.
struct SourceListView: View {
    let inspected: InspectedSources
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                switch inspected.support {
                case .unsourced:
                    // Unreachable: an unsourced answer offers no control to open
                    // this. Handled rather than force-unwrapped.
                    Text("这条回答没有附带来源。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                case let .supported(eligible, withheld):
                    Section(String(localized: "支持这条说法的来源")) {
                        ForEach(eligible, id: \.claimID) { SourceRow(source: $0) }
                    }
                    if !withheld.isEmpty {
                        withheldSection(withheld)
                    }

                case let .withheld(withheld):
                    Section {
                        // The important case. The answer arrived with citations
                        // and not one of them may stand, which the reader has to
                        // be told rather than shown an empty list.
                        Label(
                            String(localized: "这条说法目前没有可用来源支持。"),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                    }
                    withheldSection(withheld)
                }
            }
            .navigationTitle(String(localized: "来源"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成"), action: onClose)
                }
            }
        }
    }

    private func withheldSection(_ withheld: [WithheldSource]) -> some View {
        Section {
            ForEach(withheld, id: \.source.claimID) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Label(Self.reason(item.reason), systemImage: "xmark.octagon")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                    SourceRow(source: item.source)
                }
            }
        } header: {
            Text("不能用来支持这条说法")
        } footer: {
            // Kept visible on purpose: "the source for this was withdrawn" is
            // information about the claim, not clutter to filter away.
            Text("这些来源仍然列出，因为它们被撤回或不支持该说法本身就是需要知道的事。")
        }
    }

    private static func reason(_ reason: SourceIneligibility) -> String {
        switch reason {
        case .withdrawn: String(localized: "出版方已撤回该版本")
        case .retracted: String(localized: "该说法已被撤销")
        case .evidenceDoesNotSupportTheClaim: String(localized: "证据不足以支持这条说法")
        }
    }
}

private struct SourceRow: View {
    let source: SourceProjectionV1

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(source.title)
                .font(.callout.weight(.medium))
            Text(source.publisher)
                .font(.caption)
                .foregroundStyle(.secondary)

            // The four values, side by side and never merged.
            HStack(spacing: 6) {
                Chip(label: Self.authority(source.authority), tint: .indigo)
                Chip(
                    label: String(localized: "证据支持 \(Int((source.claimSupportConfidence * 100).rounded()))%"),
                    tint: .teal
                )
                if let identity = source.identityConfidence {
                    Chip(
                        label: String(localized: "地点识别 \(Int((identity * 100).rounded()))%"),
                        tint: .blue
                    )
                }
            }

            Text("版本 \(source.revision) · 获取于 \(source.retrievedAt.formatted(date: .numeric, time: .omitted))")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if source.isConflicted {
                Label(String(localized: "与其他来源存在冲突"), systemImage: "arrow.triangle.branch")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if source.hasCorrectionNote {
                Label(String(localized: "有更正或更正待审"), systemImage: "pencil.and.outline")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            // Rights travel with the source: G5 is a release gate and hiding
            // attribution here would make it unauditable.
            Text("权利：\(source.rights)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(source.locator)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
    }

    private static func authority(_ authority: String) -> String {
        switch authority {
        case "primary": String(localized: "一手来源")
        case "official": String(localized: "官方")
        case "institutional": String(localized: "机构")
        case "secondary": String(localized: "二手来源")
        case "community": String(localized: "社区")
        default: String(localized: "未标注")
        }
    }
}

private struct Chip: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}
