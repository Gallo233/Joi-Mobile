import SwiftUI
import UniformTypeIdentifiers

struct CharacterLibraryView: View {
    @Bindable var model: AppModel
    @State private var isImporterPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section("本机导入") {
                    Button { isImporterPresented = true } label: {
                        Label("选择本机角色文件", systemImage: "square.and.arrow.down")
                    }
                    Text("支持 .joi-character、.vrm 与 Live2D ZIP。角色资产只在本机处理，不会上传。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                stateSection
                installedSection
            }
            .navigationTitle("角色库")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { model.dismissCharacterLibrary() } } }
        }
        .task { await model.refreshInstalledCharacters() }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: allowedContentTypes, allowsMultipleSelection: false) { result in
            switch result {
            case let .success(urls): if let url = urls.first { model.startPreview(at: url) }
            case .failure: model.characterLibraryState = .failed(message: String(localized: "未能打开所选文件，当前角色和会话未发生变化。"))
            }
        }
    }

    @ViewBuilder private var stateSection: some View {
        switch model.characterLibraryState {
        case .idle: EmptyView()
        case let .previewing(name), let .installing(name):
            Section("安全导入") { ProgressView(); Text(name).lineLimit(1); Button("取消") { model.cancelCharacterImport() } }
        case let .preview(candidate):
            Section("安全预览") {
                LabeledContent("名称", value: candidate.receipt.manifest.displayName)
                LabeledContent("格式", value: candidate.receipt.manifest.renderer.rawValue)
                LabeledContent("来源", value: candidate.receipt.manifest.provenance.author)
                LabeledContent("权利状态", value: candidate.receipt.manifest.provenance.license)
                Text("兼容性和权利信息仅供核对，不代表原生运行时或发布权利已验证。").font(.footnote).foregroundStyle(.secondary)
                Button("安装到本机") { model.startInstall() }
                Button("取消", role: .cancel) { model.cancelCharacterImport() }
            }
        case let .installed(result):
            if result.disposition == .quarantined {
                Section("已安装，权利待确认") {
                    Text("角色资产已安全保存到本机隔离区；确认权利前不能设为当前角色。")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("已安装，尚未切换") {
                    Text(model.fallbackLabel(for: result)).foregroundStyle(.secondary)
                    Button("设为当前角色") { model.startActivation(result) }
                }
            }
        case .activating: Section("切换角色") { ProgressView("正在安全切换角色") }
        case .removing: Section("移除角色") { ProgressView("正在移除本机角色资产") }
        case .cancelled: Section("导入已取消") { Text("当前角色、会话、记忆和行程未发生变化。"); Button("重新选择") { model.resetCharacterImport(); isImporterPresented = true } }
        case let .failed(message): Section("无法导入或切换") { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange); Button("重新选择") { model.resetCharacterImport(); isImporterPresented = true } }
        }
    }

    @ViewBuilder private var installedSection: some View {
        Section("已安装角色") {
            if model.installedCharacters.isEmpty { Text("尚无已安装角色").foregroundStyle(.secondary) }
            ForEach(model.installedCharacters, id: \.installationID) { entry in
                HStack { VStack(alignment: .leading) { Text(entry.displayName); Text(entry.renderer.rawValue).font(.caption).foregroundStyle(.secondary) }; Spacer()
                    if entry.installationID == model.sessionSelection.installationID {
                        Text("当前角色").font(.caption).foregroundStyle(.secondary)
                    } else {
                        if !entry.activationAllowed { Text("权利待确认").font(.caption).foregroundStyle(.secondary) }
                        Button("移除", role: .destructive) { model.startRemoval(entry) }
                    }
                }
            }
            Text("移除只删除此设备上的角色资产，不会删除聊天、记忆或行程。").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var allowedContentTypes: [UTType] { [UTType(filenameExtension: "joi-character") ?? .archive, UTType(filenameExtension: "vrm") ?? .data, .zip] }
}
