import CharacterRuntime
import CompanionCore
import Foundation
import Observation

enum PrimarySurface: String, CaseIterable, Sendable {
    case chat
    case map
}

enum CharacterLibraryState: Equatable, Sendable {
    case idle
    case previewing(fileName: String)
    case preview(CharacterImportPreview)
    case installing(fileName: String)
    case installed(CharacterPackageInstallResult)
    case activating(CharacterInstallationID)
    case removing(CharacterInstallationID)
    case cancelled
    case failed(message: String)
}

struct CharacterImportPreview: Equatable, Sendable {
    let request: CharacterPackageImportRequest
    let fileName: String
    let receipt: CharacterPackagePreview

    static func == (lhs: CharacterImportPreview, rhs: CharacterImportPreview) -> Bool {
        lhs.fileName == rhs.fileName && lhs.receipt == rhs.receipt
    }
}

@MainActor
@Observable
final class AppModel {
    private struct ActiveRuntimeResource: Sendable {
        let handle: ValidatedCharacterPackageHandle
        let generation: RendererGeneration
    }
    var selectedSurface: PrimarySurface = .chat
    var isCharacterLibraryPresented = false
    var characterLibraryState: CharacterLibraryState = .idle
    var installedCharacters: [CharacterPackageCatalogEntry] = []

    let companionSession: CompanionSessionStore
    let journeyContext = JourneyContextStore()
    let speechCoordinator = SpeechCoordinator()

    private let installer: CharacterPackageInstaller
    private let renderer: any CharacterRenderer
    private(set) var sessionSelection: CharacterSelection
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var operationGeneration = 0
    @ObservationIgnored private var activeRuntimeResource: ActiveRuntimeResource?

    /// The sole App projection of the session store. It changes only at
    /// construction and after a successful `CompanionSessionStore` CAS.
    var currentCharacterName: String { sessionSelection.displayName }

    init(
        installer: CharacterPackageInstaller? = nil,
        renderer: any CharacterRenderer = StaticCharacterRenderer(),
        initialSelection: CharacterSelection = CharacterSelection(characterID: "joi.starter", displayName: "Joi"),
        threadID: String = "thread.local",
        sessionID: String = "session.local"
    ) {
        self.installer = installer ?? CharacterPackageInstaller(root: Self.defaultCharacterRoot())
        self.renderer = renderer
        self.sessionSelection = initialSelection
        self.companionSession = CompanionSessionStore(
            characterID: initialSelection.characterID,
            displayName: initialSelection.displayName,
            threadID: threadID,
            sessionID: sessionID
        )
    }

    func select(_ surface: PrimarySurface) { selectedSurface = surface }
    func presentCharacterLibrary() { isCharacterLibraryPresented = true }
    func dismissCharacterLibrary() {
        cancelCharacterImport()
        isCharacterLibraryPresented = false
    }
    func resetCharacterImport() {
        cancelActiveOperation()
        characterLibraryState = .idle
    }
    func cancelCharacterImport() {
        cancelActiveOperation()
        characterLibraryState = .cancelled
    }

    static func importRequest(for url: URL) -> CharacterPackageImportRequest? {
        switch url.pathExtension.lowercased() {
        case "joi-character": .joiCharacterArchive(url)
        case "vrm": .rawVRM(url)
        case "zip": .live2DArchive(url)
        default: nil
        }
    }

    func startPreview(at url: URL) {
        let generation = beginOperation()
        operationTask = Task { [weak self] in
            await self?.previewCharacter(at: url, generation: generation)
        }
    }

    func startInstall() {
        guard case let .preview(candidate) = characterLibraryState else { return }
        let generation = beginOperation()
        characterLibraryState = .installing(fileName: candidate.fileName)
        operationTask = Task { [weak self] in
            await self?.install(candidate, generation: generation)
        }
    }

    func startActivation(_ result: CharacterPackageInstallResult) {
        let generation = beginOperation()
        characterLibraryState = .activating(result.installationID)
        operationTask = Task { [weak self] in
            await self?.activate(result, generation: generation)
        }
    }

    func startRemoval(_ entry: CharacterPackageCatalogEntry) {
        let generation = beginOperation()
        characterLibraryState = .removing(entry.installationID)
        operationTask = Task { [weak self] in
            await self?.remove(entry, generation: generation)
        }
    }

    /// Kept async for deterministic unit tests. UI must use `startPreview(at:)`.
    func previewCharacter(at url: URL) async {
        let generation = beginOperation()
        await previewCharacter(at: url, generation: generation)
    }

    private func previewCharacter(at url: URL, generation: Int) async {
        guard let request = Self.importRequest(for: url) else {
            setState(.failed(message: String(localized: "暂不支持这个文件。请选择 .joi-character、.vrm 或 Live2D ZIP。")), ifCurrent: generation)
            return
        }
        setState(.previewing(fileName: url.lastPathComponent), ifCurrent: generation)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try Task.checkCancellation()
            let receipt = try await installer.preview(request)
            try Task.checkCancellation()
            setState(.preview(CharacterImportPreview(request: request, fileName: url.lastPathComponent, receipt: receipt)), ifCurrent: generation)
        } catch is CancellationError {
            setState(.cancelled, ifCurrent: generation)
        } catch {
            setState(.failed(message: importMessage(for: error)), ifCurrent: generation)
        }
    }

    private func install(_ candidate: CharacterImportPreview, generation: Int) async {
        let url = Self.url(for: candidate.request)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try Task.checkCancellation()
            let result = try await installer.install(candidate.request)
            try Task.checkCancellation()
            guard isCurrent(generation) else { return }
            characterLibraryState = .installed(result)
            await refreshInstalledCharacters(ifCurrent: generation)
        } catch is CancellationError {
            setState(.cancelled, ifCurrent: generation)
        } catch {
            setState(.failed(message: importMessage(for: error)), ifCurrent: generation)
        }
    }

    func refreshInstalledCharacters() async {
        installedCharacters = await installer.list()
    }

    private func refreshInstalledCharacters(ifCurrent generation: Int) async {
        let entries = await installer.list()
        guard isCurrent(generation) else { return }
        installedCharacters = entries
    }

    private func activate(_ result: CharacterPackageInstallResult, generation: Int) async {
        var acquired: ActiveRuntimeResource?
        do {
            try Task.checkCancellation()
            let expected = await companionSession.current()
            let handle = try await installer.prepareActivation(result.installationID)
            let rendererGeneration = RendererGeneration()
            acquired = ActiveRuntimeResource(handle: handle, generation: rendererGeneration)
            try Task.checkCancellation()
            let fallback = await renderer.load(handle, generation: rendererGeneration)
            try Task.checkCancellation()
            try await installer.validateActivation(handle)
            try Task.checkCancellation()
            let selection = CharacterSelection(
                characterID: result.manifest.characterID,
                displayName: result.manifest.displayName,
                installationID: result.installationID,
                contentID: result.contentID
            )
            guard isCurrent(generation), await companionSession.activate(selection: selection, expecting: expected.selection) else {
                if let acquired { await releaseActivationResource(acquired) }
                setState(.failed(message: String(localized: "角色已在其他操作中切换；当前会话保持不变。")), ifCurrent: generation)
                return
            }
            // CAS is the activation linearization point. Once it succeeds the
            // App projection must follow the store even if the sheet closes.
            let previous = activeRuntimeResource
            activeRuntimeResource = acquired
            acquired = nil
            sessionSelection = (await companionSession.current()).selection
            if isCurrent(generation) {
                characterLibraryState = .installed(result)
            }
            if let previous { await releaseActivationResource(previous) }
            // This label is intentionally conservative: the App-owned renderer
            // only establishes C1/C2 fallback, never native success.
            _ = fallback
        } catch is CancellationError {
            if let acquired { await releaseActivationResource(acquired) }
            setState(.cancelled, ifCurrent: generation)
        } catch {
            if let acquired { await releaseActivationResource(acquired) }
            setState(.failed(message: String(localized: "无法安全切换到此角色；当前角色和会话未发生变化。")), ifCurrent: generation)
        }
    }

    private func remove(_ entry: CharacterPackageCatalogEntry, generation: Int) async {
        do {
            let current = await companionSession.current()
            guard current.selection.installationID != entry.installationID else {
                setState(.failed(message: String(localized: "当前角色不能移除，请先切换到其他角色。")), ifCurrent: generation)
                return
            }
            try await installer.remove(entry.installationID)
            guard isCurrent(generation) else { return }
            await refreshInstalledCharacters(ifCurrent: generation)
            guard isCurrent(generation) else { return }
            characterLibraryState = .idle
        } catch {
            setState(.failed(message: String(localized: "无法移除此角色；聊天、记忆和行程未发生变化。")), ifCurrent: generation)
        }
    }

    private func releaseActivationResource(_ resource: ActiveRuntimeResource) async {
        await renderer.release(generation: resource.generation)
        await installer.releaseActivation(resource.handle)
    }

    private func beginOperation() -> Int {
        operationTask?.cancel()
        operationGeneration += 1
        return operationGeneration
    }

    private func cancelActiveOperation() {
        operationTask?.cancel()
        operationTask = nil
        operationGeneration += 1
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == operationGeneration && !Task.isCancelled
    }

    private func setState(_ state: CharacterLibraryState, ifCurrent generation: Int) {
        guard isCurrent(generation) else { return }
        characterLibraryState = state
    }

    func fallbackLabel(for result: CharacterPackageInstallResult) -> String {
        result.manifest.portraitPath == nil
            ? String(localized: "静态 Joi 回退（角色肖像不可用）")
            : String(localized: "静态角色回退（原生运行时尚未验证）")
    }

    private static func url(for request: CharacterPackageImportRequest) -> URL {
        switch request {
        case let .joiCharacterArchive(url), let .rawVRM(url), let .live2DArchive(url): url
        }
    }

    private static func defaultCharacterRoot() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("JoiMobile", isDirectory: true)
    }

    private func importMessage(for error: Error) -> String {
        guard let failure = error as? CharacterPackageImportFailure else {
            return String(localized: "无法安全导入此角色；当前角色和会话未发生变化。")
        }
        switch failure.code {
        case .notFound: return String(localized: "找不到所选文件，请重新选择。")
        case .unsupportedArchiveProfile: return String(localized: "此角色格式暂无法安全导入；当前角色和会话未发生变化。")
        case .malformedArchive, .unsafeArchive: return String(localized: "发现不安全或损坏的内容，未安装此角色。")
        case .hashMismatch: return String(localized: "角色内容校验不一致，未安装此角色。")
        default: return String(localized: "角色文件未通过安全检查，未安装此角色。")
        }
    }
}
