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
    }

    private var chrome: some View {
        VStack(spacing: 12) {
            header
            Spacer(minLength: 0)
            StageControls(
                framing: model.stageFraming,
                onToggleFraming: { model.toggleStageFraming() },
                onOpenTranscript: { model.presentTranscript() },
                hasTranscript: !model.chatTranscript.isEmpty
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            stageMessage
                .padding(.horizontal, 20)

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
            Button("个人面板", systemImage: "person.crop.circle") {}
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
                    onStop: nil
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
                onClose: { model.dismissTranscript() }
            )
            .frame(maxWidth: 330)
            .transition(.move(edge: .trailing))
        }
    }
}
