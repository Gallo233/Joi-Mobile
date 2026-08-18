import CharacterRuntime
import ChatFeature
import CompanionCore
import OfflinePack
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

    /// The motion the character was last asked to play. Presentation only: a
    /// renderer that cannot play it, or a package that never declared it,
    /// changes nothing about the session, the transcript or the turn.
    private(set) var stageMotionCue: StageMotionCue?
    @ObservationIgnored private var stageMotionSequence = 0
    @ObservationIgnored private var stageTapIndex = 0

    /// Composer text. Editable draft only; never a transcript line.
    var chatDraft: String = ""
    /// App projection of the session store's accepted transcript ordering.
    private(set) var chatTranscript: [TranscriptEntry] = []
    private(set) var chatTurnState: ChatTurnState = .idle

    let companionSession: CompanionSessionStore
    let journeyContext = JourneyContextStore()
    let speechCoordinator = SpeechCoordinator()

    /// Plays the character's spoken line and exposes its amplitude for lip sync.
    let speechPlayer: SpeechPlayer

    /// Push-to-talk dictation into the composer (`G2-J2C`).
    let voiceInput = VoiceInput()

    /// Foreground-only location for a cached walk (`G2-J3A`).
    let walkLocation = WalkLocationProvider()

    /// The cached walk on the Map surface, and the latest reading of where the
    /// user is along it. The reading is a projection: `JourneyContextStore` is
    /// still the only thing that records progress.
    let walk = CachedWalk.sample
    private(set) var walkObservation: CachedRouteProgressObservation?
    private(set) var isWalking = false
    @ObservationIgnored private var walkSession: NavigationSessionID?

    /// The journey fact the user has offered to the conversation but not yet
    /// sent (`G2-J3B`). It is the preview and the payload at once, so what is
    /// shown is what travels. `nil` means the conversation carries no location.
    private(set) var pendingJourneyAttachment: JourneyAttachment?

    /// Spends each attachment's receipt exactly once. One approval authorises
    /// one turn, and the store — not the App's own bookkeeping — is what makes a
    /// replayed receipt fail.
    @ObservationIgnored private let journeyReceipts = JourneyUseReceiptStore()

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
        let endpoint = ChatBackendEndpoint.localMock()
        self.chatController = ChatSessionController(
            gateway: chatGateway ?? SSEChatGateway(endpoint: endpoint)
        )
        self.speechPlayer = SpeechPlayer(
            endpoint: endpoint.baseURL.appendingPathComponent("v1/speech")
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

    static let activeCharacterKey = "joi.character.active"

    /// Reactivates the character the user last chose. The identifier alone is
    /// remembered; the installer revalidates the sealed tree and issues a fresh
    /// lease before anything is drawn, so a mutated or removed installation
    /// falls back rather than being restored blindly.
    func restoreActiveCharacter() async {
        await refreshInstalledCharacters()
        guard let raw = UserDefaults.standard.string(forKey: Self.activeCharacterKey) else { return }
        let wanted = CharacterInstallationID(rawValue: raw)
        guard let entry = installedCharacters.first(where: {
            $0.installationID == wanted && $0.available && $0.activationAllowed
        }) else {
            UserDefaults.standard.removeObject(forKey: Self.activeCharacterKey)
            return
        }
        startActivation(entry)
    }

    // MARK: - Cached cultural walk (`G2-J3A`)

    /// Begins following the cached route. Location starts here, on a deliberate
    /// tap, and never at launch.
    func startWalk() {
        guard !isWalking else { return }
        let session = NavigationSessionID()
        walkSession = session
        isWalking = true
        Task { [journeyContext, walk] in await journeyContext.begin(route: walk.route, session: session) }
        walkLocation.start { [weak self] observation in
            self?.advanceWalk(with: observation, session: session)
        }
    }

    /// Ends the walk and drops the journey context. Stopping is complete: the
    /// route, the progress and the location subscription all go together, so a
    /// finished walk leaves nothing observing the user.
    func stopWalk() {
        guard isWalking else { return }
        isWalking = false
        walkSession = nil
        walkObservation = nil
        walkLocation.stop()
        // An un-sent offer goes with the walk. PRD §6.5 lists send, cancel,
        // expiry and revoke as what ends an attachment, and ending the journey it
        // was taken from is not on that list — but leaving a staged position
        // behind after the user has visibly stopped sharing is the surprise this
        // product should not spring, and the fact is worthless anyway.
        pendingJourneyAttachment = nil
        Task { [journeyContext] in await journeyContext.clear() }
    }

    /// Feeds one reading through the route engine and lets the journey store
    /// decide whether it counts. A reading for a session that is no longer
    /// current is refused by the store, which is why the session travels with it.
    private func advanceWalk(with location: LocationObservation, session: NavigationSessionID) {
        guard isWalking, walkSession == session else { return }
        guard let observed = try? walk.engine.observe(location, session: session) else {
            // An unusable reading is not progress. The last good one stays.
            return
        }
        walkObservation = observed
        Task { [journeyContext] in
            await journeyContext.reduce(observed.navigationObservation)
        }
    }

    /// Progress along the cached route, 0…1.
    var walkProgress: Double { walkObservation?.navigationObservation.candidateProgress ?? 0 }

    /// Chinese guidance for the current state of the walk, or `nil` while simply
    /// making progress.
    var walkGuidance: String? {
        guard let observed = walkObservation else { return nil }
        if observed.arrived { return walk.arrivalNote }
        guard let guidance = observed.returnGuidance else { return nil }
        return String(
            localized: "已偏离路线 \(Int(guidance.distanceMeters.rounded())) 米，朝\(Self.compass(guidance.bearingToRouteDegrees))走回去。"
        )
    }

    // MARK: - One-turn journey attachment (`G2-J3B`)

    /// Offers the current walk to the conversation, and moves to the surface
    /// where the decision is actually made.
    ///
    /// The snapshot is read from `JourneyContextStore`, which owns it; Chat never
    /// reads the journey directly, and what it is handed here has already been
    /// coarsened. Nothing is sent by this — the user still has to write and send
    /// a message, and may revoke before doing so.
    ///
    /// Gated on there being a journey rather than on the walk flag: the owner's
    /// snapshot is the fact, and asking it directly means the rule cannot be
    /// satisfied by a stale bool. An empty snapshot yields no attachment.
    func offerJourneyAttachment(now: Date = Date()) async {
        let journey = await journeyContext.current()
        guard let attachment = JourneyAttachment(
            journey: journey,
            routeTitle: walk.title,
            at: now
        ) else { return }
        pendingJourneyAttachment = attachment
        selectedSurface = .chat
    }

    /// Takes the offer back. The composer text is deliberately untouched: the
    /// user is withdrawing a location, not abandoning the question.
    func revokeJourneyAttachment() {
        pendingJourneyAttachment = nil
    }

    /// Whether the Map may offer its context at all. A walk that is not running
    /// has no fact to hand over, and the action stays unavailable rather than
    /// inventing one.
    var canOfferJourneyAttachment: Bool { isWalking }

    /// Eight-point compass, because a bearing in degrees is not walkable.
    static func compass(_ degrees: Double) -> String {
        let points = [
            String(localized: "北"), String(localized: "东北"), String(localized: "东"),
            String(localized: "东南"), String(localized: "南"), String(localized: "西南"),
            String(localized: "西"), String(localized: "西北"),
        ]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return points[Int((normalized / 45).rounded()) % 8]
    }

    /// Starts listening, if the microphone may be opened at all right now.
    ///
    /// Refused while a turn is in flight or while the character is speaking: the
    /// microphone would otherwise record the character's own voice back into the
    /// composer, and a companion talking to itself is worse than a button that
    /// declines.
    func beginVoiceInput() async {
        guard !chatTurnState.isPending, !speechPlayer.isSpeaking else { return }
        await voiceInput.begin()
    }

    /// Ends the utterance and leaves the words in the composer for the user to
    /// read before sending. Voice is an input method, not an instruction to act.
    func finishVoiceInput() {
        guard let text = voiceInput.finish() else { return }
        chatDraft = chatDraft.isEmpty ? text : chatDraft + text
    }

    func cancelVoiceInput() { voiceInput.cancel() }

    /// What the recogniser has heard so far, for the composer to show while the
    /// user is still holding the button.
    var voiceHeardSoFar: String {
        if case let .listening(partial) = voiceInput.state { return partial }
        return ""
    }

    /// Chinese copy for a voice-input state that needs explaining, or `nil`.
    var voiceMessage: String? { voiceInput.state.message }

    /// Speaks one accepted companion line, after asking the owner of speech
    /// whether it may.
    ///
    /// The app used to call the player directly, which made `SpeechCoordinator` a
    /// state owner in name only: last writer won inside the player and no
    /// priority existed anywhere. Routing through it means a newer line
    /// supersedes an older one by decision rather than by timing, and later place
    /// and route narration have somewhere to lose an argument to conversation.
    @discardableResult
    func speakCompanionLine(_ line: String) async -> SpeechGeneration? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // A line with nothing in it never claims the voice; DEC-021 would rather
        // stay silent than register an empty cue for something else to interpret.
        guard !text.isEmpty else { return nil }
        let snapshot = await companionSession.current()
        let cue = SpeechCue(
            cueID: UUID().uuidString.lowercased(),
            text: text,
            displayLocale: "zh-Hans",
            voiceLocale: "ja",
            priority: .conversation,
            sessionID: snapshot.sessionID,
            characterID: snapshot.selection.characterID
        )
        guard let generation = await speechCoordinator.begin(cue).acceptedGeneration else {
            // Something with higher priority holds the voice. Staying silent is
            // the whole point of asking.
            return nil
        }
        speechPlayer.speak(text)
        return generation
    }

    /// Asks the stage to play a declared motion. The name is semantic — `greet`,
    /// `happy` — and a character that never declared it simply does not move,
    /// which is why nothing here needs to know what the package contains.
    func requestStageMotion(_ motion: String) {
        stageMotionSequence += 1
        stageMotionCue = StageMotionCue(motion: motion, sequence: stageMotionSequence)
    }

    /// A tap on the character walks its declared non-idle motions in order, so
    /// every motion a package ships is reachable without this app inventing a
    /// gesture vocabulary the package never declared. A character with no
    /// gesture motions simply does not move.
    func tapStage() {
        let gestures = (stageContent?.motions ?? [])
            .filter { $0.motion != CharacterMotionV1.idleName && !$0.loops }
        guard !gestures.isEmpty else { return }
        let motion = gestures[stageTapIndex % gestures.count]
        stageTapIndex += 1
        requestStageMotion(motion.motion)
    }

    func toggleStageFraming() { stageFraming = stageFraming.next }
    func presentTranscript() { isTranscriptPresented = true }
    func dismissTranscript() { isTranscriptPresented = false }

    // MARK: - Chat turn

    /// Starts one conversation turn. The draft clears immediately so the field
    /// cannot be sent twice, but the text is only shown as pending until the
    /// backend accepts it.
    func sendChatMessage(now: Date = Date()) {
        let text = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatTurnState.isPending else { return }
        // Checked before the draft is cleared, so an expired attachment costs the
        // user a tap rather than their sentence. Sending the message with the
        // location silently dropped is the one thing that must not happen: the
        // question was written expecting it, and the answer would be wrong with
        // nothing on screen to say why.
        if let attachment = pendingJourneyAttachment, attachment.isExpired(at: now) {
            pendingJourneyAttachment = nil
            chatTurnState = .failed(
                message: String(localized: "这条位置信息已过期；请回到地图重新附带。"),
                retryable: false
            )
            return
        }
        chatDraft = ""
        chatTask?.cancel()
        chatTask = Task { [weak self] in
            await self?.runChatTurn(text: text)
        }
    }

    /// User-initiated stop. A late terminal event cannot append text afterwards
    /// because acceptance is keyed to the request that is still current.
    func stopChatTurn() {
        // Stopping the turn stops the voice: speech is part of the response, not
        // an independent thing that outlives it. The owner is told as well as the
        // player, so a line that finishes after this point is refused rather than
        // mistaken for the current one.
        speechPlayer.stop()
        Task { [speechCoordinator] in await speechCoordinator.cancel(reason: .userStopped) }
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
        // The attachment is bound to this request and no other: the receipt names
        // the thread and request IDs and carries the digest of the exact payload,
        // so it cannot be lifted onto a different turn or a different position.
        let attachment = pendingJourneyAttachment
        let request: ChatRequest
        do {
            request = try ChatRequest(
                requestID: requestID,
                threadID: snapshot.threadID,
                sessionID: snapshot.sessionID,
                characterID: snapshot.characterID,
                text: text,
                displayLocale: "zh-Hans",
                voiceLocale: "zh-CN",
                journeyAttachment: attachment?.payload,
                journeyReceipt: attachment?.receipt(threadID: snapshot.threadID, requestID: requestID)
            )
            // Spending the receipt is what makes "one turn" true rather than
            // stated. A second attempt on the same approval fails here, before
            // any request leaves.
            try await journeyReceipts.consume(for: request)
        } catch {
            chatTurnState = .failed(message: String(localized: "这条消息无法发送；对话没有变化。"), retryable: false)
            return
        }
        // Authorised and spent, so the offer is over. A turn that is later
        // cancelled does not bring it back: the approval was for this send, and
        // reviving it would let one decision serve two.
        pendingJourneyAttachment = nil

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
                    // Speech follows acceptance, never a draft: a line that was
                    // superseded or cancelled must never be spoken. The spoken
                    // language differs from the displayed text, so only an
                    // explicit `voiceLine` is ever sent to the voice.
                    if entry.author == .companion, let line = event.voiceLine {
                        await speakCompanionLine(line)
                    }
                    // The character reacts to its own accepted reply, for the
                    // same reason speech follows acceptance: a superseded or
                    // cancelled line must not animate anything.
                    if entry.author == .companion {
                        requestStageMotion("happy")
                    }
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
        startActivation(
            installationID: result.installationID,
            selection: CharacterSelection(
                characterID: result.manifest.characterID,
                displayName: result.manifest.displayName,
                installationID: result.installationID,
                contentID: result.contentID
            )
        )
    }

    /// Activates an already-installed character. Without this a character could
    /// only be activated in the same session it was imported, so a restart left
    /// the catalog unusable.
    func startActivation(_ entry: CharacterPackageCatalogEntry) {
        startActivation(
            installationID: entry.installationID,
            selection: CharacterSelection(
                characterID: entry.characterID,
                displayName: entry.displayName,
                installationID: entry.installationID,
                contentID: entry.contentID
            )
        )
    }

    private func startActivation(installationID: CharacterInstallationID, selection: CharacterSelection) {
        let generation = beginOperation()
        characterLibraryState = .activating(installationID)
        operationTask = Task { [weak self] in
            await self?.activate(installationID: installationID, selection: selection, generation: generation)
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

    private func activate(
        installationID: CharacterInstallationID,
        selection: CharacterSelection,
        generation: Int
    ) async {
        var acquired: ActiveRuntimeResource?
        do {
            try Task.checkCancellation()
            let expected = await companionSession.current()
            let handle = try await installer.prepareActivation(installationID)
            let rendererGeneration = RendererGeneration()
            acquired = ActiveRuntimeResource(handle: handle, generation: rendererGeneration)
            try Task.checkCancellation()
            let fallback = await renderer.load(handle, generation: rendererGeneration)
            try Task.checkCancellation()
            try await installer.validateActivation(handle)
            try Task.checkCancellation()
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
            // A character that just came on stage greets, if it declared how.
            // The cue is issued after the content access so the surface being
            // rebuilt for the new character is the one that receives it.
            requestStageMotion("greet")
            // Remembered so the companion the user was talking to is still there
            // after a restart. Only the identifier is stored; the installer
            // revalidates it on the next launch before anything is drawn.
            UserDefaults.standard.set(installationID.rawValue, forKey: Self.activeCharacterKey)
            if isCurrent(generation) {
                characterLibraryState = .idle
            }
            await refreshInstalledCharacters(ifCurrent: generation)
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
            if UserDefaults.standard.string(forKey: Self.activeCharacterKey) == entry.installationID.rawValue {
                UserDefaults.standard.removeObject(forKey: Self.activeCharacterKey)
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
