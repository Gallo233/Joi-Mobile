import SwiftUI
import UniformTypeIdentifiers

struct CharacterLibraryView: View {
    @Bindable var model: AppModel
    @State private var isImporterPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("选择本机角色文件", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("文件仅用于本机预览。预览不会切换当前角色、会话或记忆，也不会上传角色资产。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("本机导入")
                }

                previewSection
            }
            .navigationTitle("角色库")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        model.dismissCharacterLibrary()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                Task {
                    await model.previewCharacter(at: url)
                }
            case .failure:
                model.characterPreviewState = .failed(
                    message: String(localized: "未能打开所选文件，当前角色和会话未发生变化。")
                )
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        switch model.characterPreviewState {
        case .idle:
            Section("兼容性预览") {
                ContentUnavailableView(
                    "尚未选择角色",
                    systemImage: "person.crop.square.dashed",
                    description: Text("支持 .vrm、.model3.json 与 Live2D 文件夹预检；ZIP 完整安全导入留待 J1B。")
                )
            }
        case let .inspecting(fileName):
            Section("兼容性预览") {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("正在检查角色元数据")
                            .font(.headline)
                        Text(fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        case let .ready(preview):
            compatibilitySections(preview)
        case let .failed(message):
            Section("无法预览") {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("重新选择") {
                    model.resetCharacterPreview()
                    isImporterPresented = true
                }
            }
        }
    }

    @ViewBuilder
    private func compatibilitySections(_ preview: CharacterCompatibilityPreview) -> some View {
        Section("角色文件") {
            LabeledContent("名称", value: preview.fileName)
            LabeledContent("格式", value: preview.format)
            if let inventory = preview.inventory {
                LabeledContent("文件清单", value: inventory)
            }
            if let fingerprint = preview.fingerprint {
                VStack(alignment: .leading, spacing: 6) {
                    Text("内容指纹（SHA-256）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(fingerprint)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }

        Section("已检测能力") {
            if preview.availableCapabilities.isEmpty {
                Text("尚无已验证能力")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(preview.availableCapabilities, id: \.self) { capability in
                    Label(capability, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }

        Section("未声明或尚未检测") {
            ForEach(preview.unavailableCapabilities, id: \.self) { capability in
                Label(capability, systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        }

        Section("加载边界") {
            LabeledContent("回退方式", value: preview.fallback)
            Text("这里只显示元数据兼容性，不代表原生 Live2D、RealityKit 或 Metal 已加载成功。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section("来源与权利") {
            LabeledContent("来源", value: preview.source)
            LabeledContent("权利状态", value: preview.rights)
        }
    }

    private var allowedContentTypes: [UTType] {
        [
            UTType(filenameExtension: "vrm") ?? .data,
            .json,
            .zip,
            .folder,
        ]
    }
}
