import CompanionCore
import SwiftUI

/// The proposal sheet (`G2-J2D`).
///
/// It exists so that `JM-P0-005`'s "no model-generated proposal becomes durable
/// silently" has a place where the user actually decides. Everything the record
/// will carry — the wording, the category, the reason and the fact that it stays
/// on this device — is on screen before anything is written.
struct MemoryProposalSheet: View {
    @Bindable var model: AppModel
    let proposal: MemoryProposal

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "要记住的内容"), text: $model.memoryDraft, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("记住什么")
                } footer: {
                    // The wording is editable, and saying so matters: what gets
                    // stored is the user's sentence, not the model's.
                    Text("你可以修改这段文字，保存的是你确认后的内容。")
                }

                Section(String(localized: "归到哪一类")) {
                    Picker(String(localized: "归到哪一类"), selection: $model.memoryCategory) {
                        ForEach(MemoryProposal.selectableCategories, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    LabeledContent(String(localized: "来源"), value: proposal.proposal.reason)
                    LabeledContent(String(localized: "保存位置"), value: String(localized: "仅这台设备"))
                } footer: {
                    Text("这条记忆只属于当前角色，不会随角色包导出，也不会上传。")
                }
            }
            .navigationTitle(String(localized: "记住这句话"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "不记")) { model.rejectMemoryProposal() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "记住")) {
                        Task { await model.acceptMemoryProposal() }
                    }
                    .disabled(model.memoryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

/// What the current character remembers, and the way to remove any of it.
struct MemoryListView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.memories.isEmpty {
                    ContentUnavailableView(
                        String(localized: "还没有记住任何内容"),
                        systemImage: "bookmark",
                        description: Text("在聊天记录里选择一句话，确认后它才会保存到这里。")
                    )
                } else {
                    List {
                        ForEach(model.memories, id: \.recordID) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.value)
                                    .font(.callout)
                                HStack(spacing: 8) {
                                    Text(record.category.displayName)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.thinMaterial, in: Capsule())
                                    Text(record.reason)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                            .swipeActions {
                                Button(String(localized: "删除"), role: .destructive) {
                                    Task { await model.deleteMemory(record.recordID) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "记忆"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { model.dismissMemoryList() }
                }
            }
        }
    }
}
