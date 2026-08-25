import CompanionCore
import SwiftUI

/// Chat is a persistent full-bleed character stage with floating chrome. The
/// transcript is an opt-in drawer rather than a column, so conversation never
/// compresses the character.
struct ChatStageView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var characterName: String { model.currentCharacterName }

    var body: some View {
        ZStack {
            CharacterStageView(
                framing: model.stageFraming,
                isResponding: model.chatTurnState.isPending,
                speechPlayer: model.speechPlayer,
                stageContent: model.stageContent,
                motionCue: model.stageMotionCue,
                onStageTap: { model.tapStage() }
            )
            .ignoresSafeArea()

            chrome

            if model.isTranscriptPresented {
                drawerOverlay
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: model.isTranscriptPresented)
        // Presented rather than inline: deciding what a companion remembers
        // deserves the whole screen and an explicit confirm, not a control the
        // thumb can brush past.
        .sheet(item: Binding(get: { model.memoryProposal }, set: { if $0 == nil { model.rejectMemoryProposal() } })) { proposal in
            MemoryProposalSheet(model: model, proposal: proposal)
        }
        .sheet(item: Binding(get: { model.inspectedSources }, set: { if $0 == nil { model.dismissSources() } })) { inspected in
            SourceListView(inspected: inspected, onClose: { model.dismissSources() })
        }
    }

    private var chrome: some View {
        VStack(spacing: 12) {
            header
            Spacer(minLength: 0)
            StageControls(
                framing: model.stageFraming,
                onToggleFraming: { model.toggleStageFraming() },
                onOpenTranscript: { model.presentTranscript() },
                hasTranscript: !model.chatTranscript.isEmpty,
                onOpenMemories: { Task { await model.presentMemoryList() } }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            stageMessage
                .padding(.horizontal, 20)

            // Above the composer for the same reason the attachment card is:
            // it is a property of the message about to be written. Deliberately
            // not in the message slot, which would replace the character's last
            // reply for as long as the network stayed away.
            if model.isShowingCachedMode {
                CachedModeStrip()
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Directly above the composer, because it is a property of the
            // message about to be written rather than of the screen.
            if let attachment = model.pendingJourneyAttachment {
                JourneyAttachmentCard(
                    attachment: attachment,
                    minutesRemaining: attachment.minutesRemaining(at: Date()),
                    onRevoke: { model.revokeJourneyAttachment() }
                )
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            ChatComposer(
                draft: $model.chatDraft,
                isSending: model.chatTurnState.isPending,
                placeholder: String(localized: "给 \(characterName) 发消息"),
                onSend: { model.sendChatMessage() },
                isListening: model.voiceInput.state.isListening,
                partialSpeech: model.voiceHeardSoFar,
                onVoiceStart: { Task { await model.beginVoiceInput() } },
                onVoiceEnd: { model.finishVoiceInput() }
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 78)
        }
        .padding(.top, 6)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(characterName)
                    .font(.title2.bold())
                Text("本地会话")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("个人面板", systemImage: "person.crop.circle") { model.presentSettings() }
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
    }

    /// One slot above the composer: the companion's line, or an honest status.
    @ViewBuilder private var stageMessage: some View {
        // A voice-input problem outranks the turn status: the user just pressed
        // the button and needs to know why nothing happened. Tapping it clears.
        if let voiceMessage = model.voiceMessage {
            StageStatusBanner(
                message: voiceMessage,
                hint: nil,
                symbol: "mic.slash",
                tint: .orange
            )
            .onTapGesture { model.voiceInput.acknowledge() }
        } else {
            turnMessage
        }
    }

    @ViewBuilder private var turnMessage: some View {
        switch model.chatTurnState {
        case .idle:
            if let latest = model.latestCompanionLine {
                CompanionBubble(
                    characterName: characterName,
                    text: latest.text,
                    isDraft: false,
                    onStop: nil,
                    voiceFailure: model.speechFailureMessage,
                    onRetryVoice: model.speechFailureMessage == nil
                        ? nil
                        : { Task { await model.retryLastVoiceLine() } }
                )
                .transition(.opacity)
            }
        case let .pending(_, _, draft):
            CompanionBubble(
                characterName: characterName,
                text: draft ?? String(localized: "正在思考…"),
                isDraft: true,
                onStop: { model.stopChatTurn() }
            )
        case .cancelled:
            StageStatusBanner(
                message: String(localized: "已停止这次回应；对话没有变化。"),
                hint: nil,
                symbol: "stop.circle",
                tint: .secondary
            )
        case let .failed(message, retryable):
            StageStatusBanner(
                message: message,
                hint: retryable ? String(localized: "你可以重新发送这条消息。") : nil,
                symbol: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }
    }

    private var drawerOverlay: some View {
        HStack(spacing: 0) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { model.dismissTranscript() }
                .accessibilityLabel(String(localized: "收起聊天记录"))
                .accessibilityAddTraits(.isButton)

            TranscriptDrawer(
                transcript: model.chatTranscript,
                characterName: characterName,
                onClose: { model.dismissTranscript() },
                canRemember: { model.canRemember($0) },
                onRemember: { entry in Task { await model.proposeMemory(from: entry) } },
                claimSupport: { model.claimSupport(for: $0) },
                onOpenSources: { model.inspectSources(for: $0) },
                canOpenInMap: { model.canOpenInMap($0) },
                onOpenInMap: { model.proposeMapHandoff(from: $0) }
            )
            .frame(maxWidth: 330)
            .transition(.move(edge: .trailing))
        }
    }
}


/// Says the app is offline, and what that does not stop.
///
/// Quiet on purpose: being offline is a state the user may sit in for a whole
/// walk, so this reports rather than warns, and it never takes the slot the
/// character's own words use.
private struct CachedModeStrip: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.footnote)
            Text("没有网络，暂时无法对话。地图上的缓存路线仍然可用。")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
