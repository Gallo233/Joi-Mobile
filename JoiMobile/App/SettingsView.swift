import SwiftUI

/// Settings (`G2-J5E`).
///
/// `JM-P0-018` names eight groups, and this build has something real behind
/// three of them. The screen shows all eight anyway, because the alternative
/// shapes are both worse: hiding the empty groups makes the product look like it
/// decided against them, and drawing a switch per group makes it look like they
/// work. A group with nothing behind it is listed and says what is missing.
///
/// This is also where the profile affordance finally goes. It has been drawn on
/// the Chat header since G1 with an empty action — the last dead control on a
/// primary surface, after `G2-J2C` took the microphone.
struct SettingsView: View {
    @Bindable var model: AppModel

    private var rows: [SettingsRow] {
        SettingsCatalog.rows(facts: model.settingsBuildFacts)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(SettingsGroup.allCases) { group in
                    let groupRows = rows.filter { $0.group == group }
                    if !groupRows.isEmpty {
                        Section(group.title) {
                            ForEach(groupRows) { row in
                                SettingsRowView(row: row) { destination in
                                    model.openFromSettings(destination)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { model.dismissSettings() }
                }
            }
        }
    }
}

/// One row, drawn as a control only when it is one.
private struct SettingsRowView: View {
    let row: SettingsRow
    let onOpen: (SettingsDestination) -> Void

    var body: some View {
        if let destination = row.destination {
            Button { onOpen(destination) } label: {
                HStack {
                    content
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            // Not a Button, not disabled-looking: a statement. A disabled row
            // would read as "this is switched off", which is a different and
            // untrue claim from "this does not exist yet".
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                if let value = row.value {
                    Spacer(minLength: 12)
                    Text(value)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            Text(row.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
