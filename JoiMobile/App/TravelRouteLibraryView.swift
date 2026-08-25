import OfflinePack
import SwiftUI
import UniformTypeIdentifiers

/// The secondary route picker for Map (`G2-J5O`).
///
/// Inventory rows are not trusted route content. `AppModel` reopens and verifies
/// the exact sealed pack only after a deliberate tap, before changing the walk.
struct TravelRouteLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    @State private var isImportingPack = false
    @State private var selectionInFlight: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.installedPack == nil {
                        RouteLibraryRow(
                            title: CachedWalk.sample.title,
                            detail: String(localized: "内置体验内容 · 不是已下载路线"),
                            footnote: String(localized: "用于体验步行流程，不代表已校验的文化内容或发布权利。"),
                            isCurrent: true,
                            isBusy: selectionInFlight == "sample"
                        )
                    } else {
                        Button {
                            selectSample()
                        } label: {
                            RouteLibraryRow(
                                title: CachedWalk.sample.title,
                                detail: String(localized: "内置体验内容 · 不是已下载路线"),
                                footnote: String(localized: "用于体验步行流程，不代表已校验的文化内容或发布权利。"),
                                isCurrent: false,
                                isBusy: selectionInFlight == "sample"
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(selectionInFlight != nil)
                    }
                } header: {
                    Text("示例路线")
                }

                Section {
                    if model.installedTravelPacks.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("还没有已安装路线")
                                .font(.subheadline.weight(.semibold))
                            Text("可以从“文件”选择一个路线包文件夹；导入前会校验内容、哈希与权利声明。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(model.installedTravelPacks, id: \.selectionID) { pack in
                            installedRow(pack)
                        }
                    }
                } header: {
                    Text("已安装路线")
                } footer: {
                    Text("列表只说明路线包存在于本机。每次选择都会重新校验；Apple 地图搜索结果不会自动成为 Joi 文化路线。")
                }

                if let message = model.packImportMessage {
                    Section {
                        HStack(alignment: .firstTextBaseline) {
                            Text(message)
                                .font(.footnote)
                            Spacer(minLength: 8)
                            Button {
                                model.acknowledgePackMessage()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "关闭提示"))
                        }
                    }
                }

                Section {
                    Button {
                        isImportingPack = true
                    } label: {
                        Label(String(localized: "导入路线包"), systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(selectionInFlight != nil)
                }
            }
            .navigationTitle(String(localized: "文化路线"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
            .task {
                await model.refreshInstalledTravelPacks()
            }
            .fileImporter(
                isPresented: $isImportingPack,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                guard case let .success(urls) = result, let url = urls.first else { return }
                Task {
                    await model.importTravelPack(at: url)
                    await model.refreshInstalledTravelPacks()
                }
            }
        }
    }

    @ViewBuilder
    private func installedRow(_ pack: InstalledTravelPackSummary) -> some View {
        let isCurrent = model.installedPack?.packID == pack.packID
            && model.installedPack?.version == pack.version
        let title = pack.title ?? String(localized: "无法读取路线标题")
        let sourceCount = pack.sourceRevisionIDs.count
        if isCurrent || pack.title == nil {
            RouteLibraryRow(
                title: title,
                detail: String(localized: "版本 \(pack.version) · \(sourceCount) 个资料版本"),
                footnote: pack.title == nil
                    ? String(localized: "内容无法读取，不能选择；重新获取有效路线包后再导入。")
                    : String(localized: "权利声明：\(pack.rights)"),
                isCurrent: isCurrent,
                isBusy: selectionInFlight == pack.selectionID,
                hasError: pack.title == nil
            )
        } else {
            Button {
                select(pack)
            } label: {
                RouteLibraryRow(
                    title: title,
                    detail: String(localized: "版本 \(pack.version) · \(sourceCount) 个资料版本"),
                    footnote: String(localized: "权利声明：\(pack.rights)"),
                    isCurrent: false,
                    isBusy: selectionInFlight == pack.selectionID
                )
            }
            .buttonStyle(.plain)
            .disabled(selectionInFlight != nil)
        }
    }

    private func select(_ pack: InstalledTravelPackSummary) {
        selectionInFlight = pack.selectionID
        Task {
            let changed = await model.selectInstalledTravelPack(
                packID: pack.packID,
                version: pack.version
            )
            selectionInFlight = nil
            if changed { dismiss() }
        }
    }

    private func selectSample() {
        selectionInFlight = "sample"
        Task {
            let changed = await model.selectBundledSampleWalk()
            selectionInFlight = nil
            if changed { dismiss() }
        }
    }
}

private struct RouteLibraryRow: View {
    let title: String
    let detail: String
    let footnote: String
    let isCurrent: Bool
    let isBusy: Bool
    var hasError = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hasError ? "exclamationmark.triangle.fill" : "map.fill")
                .font(.title3)
                .foregroundStyle(hasError ? Color.orange : Color.teal)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)
            if isBusy {
                ProgressView()
            } else if isCurrent {
                Label(String(localized: "当前"), systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.teal)
                    .accessibilityLabel(String(localized: "当前路线"))
            } else if !hasError {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

private extension InstalledTravelPackSummary {
    var selectionID: String { "\(packID)#\(version)" }
}
