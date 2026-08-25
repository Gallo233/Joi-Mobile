import CompanionCore
import SwiftUI

extension DataCategory {
    /// PRD §6.4's five categories, in the user's words.
    var displayName: String {
        switch self {
        case .packages: String(localized: "已安装内容")
        case .conversations: String(localized: "对话")
        case .memory: String(localized: "记忆")
        case .travelHistory: String(localized: "行程历史")
        case .account: String(localized: "账户")
        }
    }
}

/// Local data export (`G2-J5I`).
///
/// The screen says what will be in the file before it makes one, because the
/// two things a person needs to decide with are what an export contains and
/// what it does not — and afterwards, holding a file, they can no longer tell.
struct DataExportView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(DataCategory.allCases) { category in
                        LabeledContent(category.displayName) {
                            Text(Self.plan(category))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text("导出会包含什么")
                } footer: {
                    Text("导出的是一个可读的 JSON 文件，只在你选择保存或分享后才离开这台设备。角色包的模型与动作文件不在其中：它们的使用权利属于作者，你导入时用的原始文件仍在你手里。")
                }

                switch model.dataExportState {
                case .idle:
                    Section {
                        Button(String(localized: "生成导出文件")) {
                            Task { await model.produceDataExport() }
                        }
                    }
                case .working:
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在整理这台设备上的数据…")
                                .foregroundStyle(.secondary)
                        }
                    }
                case let .ready(export):
                    readySection(export)
                case let .failed(message):
                    Section {
                        Text(message)
                            .font(.callout)
                        Button(String(localized: "再试一次")) {
                            Task { await model.produceDataExport() }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "导出"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { model.dismissDataExport() }
                }
            }
        }
    }

    @ViewBuilder
    private func readySection(_ export: DataExport) -> some View {
        Section {
            ForEach(export.result.categories, id: \.category) { entry in
                LabeledContent(entry.category.displayName) {
                    Text(Self.summary(entry.coverage))
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Text("这份文件里的内容")
        }

        Section {
            LabeledContent(String(localized: "文件"), value: export.fileName)
            LabeledContent(
                String(localized: "大小"),
                value: String(localized: "\(AppModel.kilobytes(export.result.byteCount)) KB")
            )
            // The digest of the file as it was read back, not of the bytes that
            // were handed to the writer. It is here so the person holding the
            // file can check that the copy they keep is the one this app made.
            LabeledContent(String(localized: "校验值"), value: String(export.result.sha256.prefix(16)))
                .font(.footnote.monospaced())
            ShareLink(item: export.fileURL) {
                Text("保存或分享这个文件")
            }
            Button(String(localized: "重新生成")) {
                Task { await model.produceDataExport() }
            }
        } footer: {
            Text("这台设备上只保留最近一次导出；再次生成会覆盖上一份。")
        }
    }

    /// What a category will contribute, said before the file exists.
    private static func plan(_ category: DataCategory) -> String {
        switch category {
        case .packages: String(localized: "清单，不含资源文件")
        case .conversations: String(localized: "当前这一段")
        case .memory: String(localized: "全部，含所有角色")
        case .travelHistory: String(localized: "这一版不记录")
        case .account: String(localized: "这一版没有账户")
        }
    }

    /// What a category actually contributed.
    ///
    /// `empty` and `unavailable` render differently on purpose: "没有内容" is a
    /// fact about the user's data, and "这一版不记录" is a fact about the app.
    private static func summary(_ coverage: DataExportCoverage) -> String {
        switch coverage {
        case let .complete(count):
            String(localized: "已全部导出 · \(count) 条")
        case .empty:
            String(localized: "没有内容")
        case let .partial(count, missing):
            String(localized: "已导出 \(count) 条 · 不含 \(missing)")
        case let .unavailable(reason):
            reason
        }
    }
}
