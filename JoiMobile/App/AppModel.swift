import CharacterRuntime
import CompanionCore
import Foundation
import Observation

enum PrimarySurface: String, CaseIterable, Sendable {
    case chat
    case map
}

enum CharacterLibraryPreviewState: Equatable, Sendable {
    case idle
    case inspecting(fileName: String)
    case ready(CharacterCompatibilityPreview)
    case failed(message: String)
}

struct CharacterCompatibilityPreview: Equatable, Sendable {
    let fileName: String
    let format: String
    let availableCapabilities: [String]
    let unavailableCapabilities: [String]
    let fallback: String
    let fingerprint: String?
    let inventory: String?
    let source: String
    let rights: String
}

@MainActor
@Observable
final class AppModel {
    var selectedSurface: PrimarySurface = .chat
    var currentCharacterName = "Joi"
    var threadLabel = "本地会话"
    var isCharacterLibraryPresented = false
    var characterPreviewState: CharacterLibraryPreviewState = .idle

    let companionSession = CompanionSessionStore(
        characterID: "joi.starter",
        threadID: "thread.local",
        sessionID: "session.local"
    )
    let journeyContext = JourneyContextStore()
    let speechCoordinator = SpeechCoordinator()

    func select(_ surface: PrimarySurface) {
        selectedSurface = surface
    }

    func presentCharacterLibrary() {
        isCharacterLibraryPresented = true
    }

    func dismissCharacterLibrary() {
        isCharacterLibraryPresented = false
    }

    func resetCharacterPreview() {
        characterPreviewState = .idle
    }

    func previewCharacter(at url: URL) async {
        let fileName = url.lastPathComponent
        characterPreviewState = .inspecting(fileName: fileName)

        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let preview = try await Task.detached(priority: .userInitiated) {
                try CharacterPreviewAdmissionAdapter.inspect(url)
            }.value
            characterPreviewState = .ready(preview)
        } catch let error as CharacterDocumentPreviewError {
            characterPreviewState = .failed(message: error.localizedMessage)
        } catch {
            characterPreviewState = .failed(message: String(localized: "无法读取这个角色文件，请重新选择。"))
        }
    }
}

private enum CharacterDocumentPreviewError: Error, Sendable {
    case unsupportedFile
    case fileTooLarge
    case invalidMetadata
    case unsafeContent
    case incompleteAsset
    case archiveImportDeferred

    var localizedMessage: String {
        switch self {
        case .unsupportedFile:
            String(localized: "暂不支持这个文件。请选择 .vrm、.model3.json、Live2D 文件夹或 ZIP。")
        case .fileTooLarge:
            String(localized: "角色资产超过当前预览上限，未进行预览。")
        case .invalidMetadata:
            String(localized: "角色元数据无法安全解析，当前角色和会话未发生变化。")
        case .unsafeContent:
            String(localized: "角色资产包含不安全的路径、链接、文件类型或执行权限，已停止预览。")
        case .incompleteAsset:
            String(localized: "角色资产不完整或读取期间发生变化，当前角色和会话未发生变化。")
        case .archiveImportDeferred:
            String(localized: "Live2D ZIP 完整安全导入留待 J1B；当前角色和会话未发生变化。")
        }
    }
}

private enum CharacterPreviewAdmissionAdapter {
    static func inspect(_ url: URL) throws -> CharacterCompatibilityPreview {
        let fileName = url.lastPathComponent
        let lowercasedName = fileName.lowercased()

        if lowercasedName.hasSuffix(".zip") {
            throw CharacterDocumentPreviewError.archiveImportDeferred
        }

        let disclosure = CharacterFixtureDisclosure(
            sourceStatus: .userSelected,
            rightsStatus: .unverified,
            rightsNotice: "rights-pending-local-preview"
        )
        let admitter = CharacterFixtureAdmitter()
        let admitted: AdmittedCharacterFixture
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                let entryURL = try live2DEntryURL(in: url)
                admitted = try admitter.admitLive2D(
                    entryURL: entryURL,
                    policy: CharacterFixtureAdmissionPolicy(fingerprint: .computeOnly),
                    disclosure: disclosure
                )
            } else if lowercasedName.hasSuffix(".model3.json") {
                admitted = try admitter.admitLive2D(
                    entryURL: url,
                    policy: CharacterFixtureAdmissionPolicy(fingerprint: .computeOnly),
                    disclosure: disclosure
                )
            } else if lowercasedName.hasSuffix(".vrm") {
                admitted = try admitter.admitVRM(
                    fileURL: url,
                    policy: CharacterFixtureAdmissionPolicy(
                        fingerprint: .computeOnly,
                        maximumBytes: CharacterPackageLimits.maximumArchiveBytes
                    ),
                    disclosure: disclosure
                )
            } else {
                throw CharacterDocumentPreviewError.unsupportedFile
            }
        } catch let error as CharacterFixtureAdmissionError {
            throw previewError(for: error)
        }

        return makePreview(from: admitted.compatibility, fileName: fileName)
    }

    private static func makePreview(
        from compatibility: CharacterFixtureCompatibilityResult,
        fileName: String
    ) -> CharacterCompatibilityPreview {
        let format = formatLabel(compatibility.format)
        let capabilities = compatibility.capabilities
        let omissions = Set(compatibility.omissions)
        var available: [String] = []
        var unavailable: [String] = []

        switch compatibility.format {
        case .live2D:
            appendCapability(String(localized: "动作"), isAvailable: capabilities.motion, omission: "motion:undeclared", omissions: omissions, to: &available, unavailable: &unavailable)
            appendCapability(String(localized: "表情"), isAvailable: capabilities.expression, omission: "expression:undeclared", omissions: omissions, to: &available, unavailable: &unavailable)
            appendCapability(String(localized: "物理"), isAvailable: capabilities.physics, omission: "physics:undeclared", omissions: omissions, to: &available, unavailable: &unavailable)
            appendCapability(String(localized: "姿势"), isAvailable: capabilities.pose, omission: "pose:undeclared", omissions: omissions, to: &available, unavailable: &unavailable)
            appendCapability(String(localized: "口型"), isAvailable: capabilities.lipSync, omission: "lipSync:undeclared", omissions: omissions, to: &available, unavailable: &unavailable)
            if omissions.contains("eyeBlink:undeclared") {
                unavailable.append(String(localized: "眨眼：未声明"))
            } else {
                available.append(String(localized: "眨眼"))
            }
            unavailable.append(String(localized: "视线：等待原生运行时检测"))
            unavailable.append(String(localized: "原生 Cubism / Metal 渲染：尚未验证"))
        case .vrm0, .vrm1:
            appendCapability(String(localized: "Humanoid 骨骼"), isAvailable: capabilities.pose, omission: "humanoid:undeclared", omissions: omissions, to: &available, unavailable: &unavailable)
            appendCapability(String(localized: "MToon 材质"), isAvailable: !omissions.contains("mtoon:undeclared"), omission: "mtoon:undeclared", omissions: omissions, to: &available, unavailable: &unavailable)
            appendCapability(String(localized: "表情"), isAvailable: capabilities.expression, omission: "expression:undeclared", omissions: omissions, to: &available, unavailable: &unavailable)
            appendCapability(String(localized: "视线"), isAvailable: capabilities.lookAt, omission: "lookAt:undeclared", omissions: omissions, to: &available, unavailable: &unavailable)
            appendCapability(String(localized: "约束"), isAvailable: capabilities.constraints, omission: "constraints:undeclared", omissions: omissions, to: &available, unavailable: &unavailable)
            appendCapability(String(localized: "Spring Bone"), isAvailable: capabilities.springBone, omission: "springBone:undeclared", omissions: omissions, to: &available, unavailable: &unavailable)
            appendCapability(String(localized: "VRMA 动画"), isAvailable: capabilities.animation, omission: "vrma:undeclared", omissions: omissions, to: &available, unavailable: &unavailable)
            appendCapability(String(localized: "口型"), isAvailable: capabilities.lipSync, omission: "lipSync:undeclared", omissions: omissions, to: &available, unavailable: &unavailable)
            unavailable.append(String(localized: "原生 RealityKit / Metal 渲染：尚未验证"))
        case .vrma, .gltf2:
            unavailable.append(String(localized: "不能作为当前角色直接激活"))
            unavailable.append(String(localized: "原生 RealityKit / Metal 渲染：尚未验证"))
        }

        if !compatibility.hashVerified {
            unavailable.append(String(localized: "内容指纹：已计算，尚无可信摘要可供比对"))
        }

        return CharacterCompatibilityPreview(
            fileName: fileName,
            format: format,
            availableCapabilities: available,
            unavailableCapabilities: unavailable,
            fallback: fallbackLabel(compatibility),
            fingerprint: compatibility.contentSHA256,
            inventory: String.localizedStringWithFormat(
                String(localized: "%lld 个文件 · %@"),
                compatibility.fileCount,
                ByteCountFormatter.string(fromByteCount: Int64(compatibility.expandedBytes), countStyle: .file)
            ),
            source: sourceLabel(fileName: fileName),
            rights: String(localized: "权利待确认；不会随应用或仓库分发")
        )
    }

    private static func appendCapability(
        _ label: String,
        isAvailable: Bool,
        omission: String,
        omissions: Set<String>,
        to available: inout [String],
        unavailable: inout [String]
    ) {
        if isAvailable {
            available.append(label)
        } else if omissions.contains(omission) {
            unavailable.append(String.localizedStringWithFormat(String(localized: "%@：未声明"), label))
        } else {
            unavailable.append(String.localizedStringWithFormat(String(localized: "%@：尚未检测"), label))
        }
    }

    private static func formatLabel(_ format: CharacterFixtureFormat) -> String {
        switch format {
        case .live2D: String(localized: "Live2D Cubism")
        case .vrm0: String(localized: "VRM 0.x")
        case .vrm1: String(localized: "VRM 1.0")
        case .vrma: String(localized: "VRMA 动画")
        case .gltf2: String(localized: "glTF 2.0")
        }
    }

    private static func fallbackLabel(_ compatibility: CharacterFixtureCompatibilityResult) -> String {
        if compatibility.fallback != nil {
            return String(localized: "静态角色回退（缺少核心能力）")
        }
        return String(localized: "静态角色回退（原生运行时通过前）")
    }

    private static func sourceLabel(fileName: String) -> String {
        String.localizedStringWithFormat(String(localized: "本机选择 · %@"), fileName)
    }

    private static func live2DEntryURL(in directoryURL: URL) throws -> URL {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.lastPathComponent.lowercased().hasSuffix(".model3.json") }
        guard entries.count == 1, let entry = entries.first else {
            throw CharacterDocumentPreviewError.incompleteAsset
        }
        return entry
    }

    private static func previewError(
        for error: CharacterFixtureAdmissionError
    ) -> CharacterDocumentPreviewError {
        switch error {
        case .contentTooLarge, .tooManyFiles:
            .fileTooLarge
        case .pathEscape, .symlink, .executable, .unsupportedFileType, .privatePathDisclosure:
            .unsafeContent
        case .live2DInspection, .vrmInspection, .contentTypeMismatch:
            .invalidMetadata
        case .missingPath, .notDirectory, .notRegularFile, .unreadable, .fileCountMismatch, .fileChanged:
            .incompleteAsset
        case .notFileURL, .relativeEnvironmentPath, .invalidExpectedSHA256, .sha256Mismatch:
            .unsupportedFile
        }
    }
}
