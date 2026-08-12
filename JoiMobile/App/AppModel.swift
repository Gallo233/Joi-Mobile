import CharacterRuntime
import ChatFeature
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

/// One conversation turn as the App may show it. `pending` text is not part of
/// the accepted transcript: it becomes a transcript line only when the backend
/// returns its `acceptedInput` event, so a turn can never append twice.
enum ChatTurnState: Equatable, Sendable {
    case idle
    /// `draft` is the replaceable in-progress projection of the companion's
    /// answer. It is never an accepted transcript line.
    case pending(text: String, phase: CompanionPublicPhase, draft: String?)
    case cancelled
    case failed(message: String, retryable: Bool)

    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
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

    /// Presentation-only stage framing. Never touches session or renderer state.
    var stageFraming: StageFraming = .fullBody
    var isTranscriptPresented = false

    /// Read access to the currently activated character's sealed content, issued
    /// by the installer. Set only after a successful `CompanionSessionStore` CAS,
    /// and cleared when the character is deactivated or removed, so the stage can
    /// never outlive the activation it is drawing.
    private(set) var stageContent: CharacterContentAccess?

    /// Composer text. Editable draft only; never a transcript line.
    var chatDraft: String = ""
    /// App projection of the session store's accepted transcript ordering.
    private(set) var chatTranscript: [TranscriptEntry] = []
    private(set) var chatTurnState: ChatTurnState = .idle

    let companionSession: CompanionSessionStore
    let journeyContext = JourneyContextStore()
    let speechCoordinator = SpeechCoordinator()

    private let installer: CharacterPackageInstaller
    private let renderer: any CharacterRenderer
    private let chatController: ChatSessionController
    private let chatProjection = ChatTurnProjection()
    private(set) var sessionSelection: CharacterSelection
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var operationGeneration = 0
    @ObservationIgnored private var activeRuntimeResource: ActiveRuntimeResource?
    @ObservationIgnored private var chatTask: Task<Void, Never>?
    @ObservationIgnored private var chatRequestID: String?

    /// The sole App projection of the session store. It changes only at
    /// construction and after a successful `CompanionSessionStore` CAS.
    var currentCharacterName: String { sessionSelection.displayName }

    init(
        installer: CharacterPackageInstaller? = nil,
        renderer: any CharacterRenderer = StaticCharacterRenderer(),
        chatGateway: (any ChatGateway)? = nil,
        initialSelection: CharacterSelection = CharacterSelection(characterID: "joi.starter", displayName: "Joi"),
        threadID: String = "thread.local",
        sessionID: String = "session.local"
    ) {
        self.installer = installer ?? CharacterPackageInstaller(root: Self.defaultCharacterRoot())
        self.renderer = renderer
        // The default endpoint is the local contract mock in `Backend/`. A public
        // build must inject the official HTTPS proxy; `ChatBackendEndpoint`
        // refuses any non-loopback plain-HTTP host.
        self.chatController = ChatSessionController(
            gateway: chatGateway ?? SSEChatGateway(endpoint: .localMock())
        )
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

    /// The last accepted companion line, shown in the stage bubble.
    var latestCompanionLine: TranscriptEntry? {
        chatTranscript.last { $0.author == .companion }
    }

    func toggleStageFraming() { stageFraming = stageFraming.next }
    func presentTranscript() { isTranscriptPresented = true }
    func dismissTranscript() { isTranscriptPresented = false }

    // MARK: - Chat turn

    /// Starts one conversation turn. The draft clears immediately so the field
    /// cannot be sent twice, but the text is only shown as pending until the
    /// backend accepts it.
    func sendChatMessage() {
        let text = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatTurnState.isPending else { return }
        chatDraft = ""
        chatTask?.cancel()
        chatTask = Task { [weak self] in
            await self?.runChatTurn(text: text)
        }
    }

    /// User-initiated stop. A late terminal event cannot append text afterwards
    /// because acceptance is keyed to the request that is still current.
    func stopChatTurn() {
        guard let requestID = chatRequestID else { return }
        chatTask?.cancel()
        chatTask = nil
        Task { [chatController] in await chatController.cancel(requestID: requestID) }
        chatRequestID = nil
        chatTurnState = .cancelled
    }

    /// Kept async so tests can await a full turn. UI must use `sendChatMessage()`.
    func runChatTurn(text: String) async {
        let snapshot = await companionSession.current()
        let requestID = UUID().uuidString.lowercased()
        let request: ChatRequest
        do {
            request = try ChatRequest(
                requestID: requestID,
                threadID: snapshot.threadID,
                sessionID: snapshot.sessionID,
                characterID: snapshot.characterID,
                text: text,
                displayLocale: "zh-Hans",
                voiceLocale: "zh-CN"
            )
        } catch {
            chatTurnState = .failed(message: String(localized: "这条消息无法发送；对话没有变化。"), retryable: false)
            return
        }

        chatRequestID = requestID
        chatTurnState = .pending(text: text, phase: .received, draft: nil)
        do {
            let events = try await chatController.send(request) { [weak self] event in
                await self?.observeInFlight(event, pendingText: text, requestID: requestID)
            }
            try Task.checkCancellation()
            guard chatRequestID == requestID else { return }
            await apply(events, threadID: snapshot.threadID, requestID: requestID)
        } catch is CancellationError {
            guard chatRequestID == requestID else { return }
            chatRequestID = nil
            chatTurnState = .cancelled
        } catch {
            guard chatRequestID == requestID else { return }
            chatRequestID = nil
            chatTurnState = chatFailure(for: error)
        }
    }

    /// Shows progress while the turn is still open. It only ever updates the
    /// replaceable draft and phase; acceptance happens once, in `apply`, after
    /// the stream reaches its terminal event.
    private func observeInFlight(
        _ event: CompanionEventV1,
        pendingText: String,
        requestID: String
    ) {
        guard chatRequestID == requestID, chatTurnState.isPending else { return }
        guard case let .pending(_, _, existingDraft) = chatTurnState else { return }
        switch chatProjection.effect(of: event) {
        case let .draft(text):
            chatTurnState = .pending(text: pendingText, phase: event.phase, draft: text ?? existingDraft)
        case .append, .status, .diagnostic:
            chatTurnState = .pending(text: pendingText, phase: event.phase, draft: existingDraft)
        }
    }

    private func apply(_ events: [CompanionEventV1], threadID: String, requestID: String) async {
        var latestPhase = CompanionPublicPhase.received
        var diagnostic: ChatTurnState?
        for event in events {
            switch chatProjection.effect(of: event) {
            case let .append(entry):
                if await companionSession.appendAccepted(entry, threadID: threadID) {
                    chatTranscript.append(entry)
                }
                latestPhase = event.phase
            case let .status(phase):
                latestPhase = phase
            case .draft:
                // A replaceable projection. This slice shows no partial text
                // because the mock proxy returns whole events; wiring token
                // streaming needs a backend that actually chunks them.
                latestPhase = event.phase
            case let .diagnostic(phase, errorCode):
                latestPhase = phase
                diagnostic = Self.diagnosticFailure(errorCode)
            }
        }
        guard chatRequestID == requestID else { return }
        chatRequestID = nil
        if let diagnostic {
            chatTurnState = diagnostic
        } else if latestPhase == .done {
            chatTurnState = .idle
        } else {
            // A stream that ended before a terminal event is not a success.
            chatTurnState = .failed(message: String(localized: "这次回应没有完成；对话没有变化。"), retryable: true)
        }
    }

    /// Maps the proxy's stable, provider-independent `errorCode` values. The
    /// backend deliberately never names a provider or model, so an unrecognised
    /// code must still degrade to honest copy rather than raw text.
    static func diagnosticFailure(_ errorCode: String?) -> ChatTurnState {
        switch errorCode {
        case nil:
            return .failed(message: String(localized: "这次回应没有完成；对话没有变化。"), retryable: true)
        case "upstream_unavailable":
            return .failed(message: String(localized: "服务暂时无法回应，请稍后再试。"), retryable: true)
        case "upstream_rejected":
            return .failed(message: String(localized: "这次请求未获授权；对话没有变化。"), retryable: false)
        default:
            return .failed(message: String(localized: "这次回应没有完成；对话没有变化。"), retryable: true)
        }
    }

    private func chatFailure(for error: Error) -> ChatTurnState {
        if let transport = error as? ChatTransportError {
            let message: String
            switch transport {
            case .insecureEndpoint:
                message = String(localized: "服务地址不安全，已阻止发送。")
            case .unauthorized:
                message = String(localized: "这次请求未获授权；对话没有变化。")
            case .rateLimited, .serverUnavailable:
                message = String(localized: "服务暂时无法回应，请稍后再试。")
            case .invalidRequest, .malformedStream, .notStreaming, .backend:
                message = String(localized: "无法连接到 Joi 的服务；对话没有变化。")
            }
            return .failed(message: message, retryable: transport.isRetryable)
        }
        if error is ChatSessionError {
            return .failed(message: String(localized: "收到了不属于这次对话的回应，已丢弃。"), retryable: true)
        }
        return .failed(message: String(localized: "无法连接到 Joi 的服务；对话没有变化。"), retryable: true)
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
            // Read access is issued after the CAS, from the handle that just won
            // it, so the stage draws the character the session actually holds.
            stageContent = try? await installer.contentAccess(for: handle)
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
            if stageContent?.installationID == entry.installationID {
                stageContent = nil
            }
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
