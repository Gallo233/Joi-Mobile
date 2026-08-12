import CompanionCore
import SwiftUI

struct ChatStageView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isComposerFocused: Bool

    private var characterName: String { model.currentCharacterName }

    /// True as soon as there is anything to read below the stage — an accepted
    /// line, pending text, a stop control or a failure. The conversation area
    /// must not stay collapsed while a turn is in flight or has failed.
    private var hasConversationContent: Bool {
        !model.chatTranscript.isEmpty || model.chatTurnState != .idle
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            stage
            transcript
            composer
        }
        .padding(.top, 14)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
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

    /// The stage shrinks once there is conversation to read, but never
    /// disappears: character presence is the product identity.
    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.indigo.opacity(0.55), .purple.opacity(0.25), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: hasConversationContent ? 30 : 52, weight: .light))
                    .symbolEffect(
                        .pulse,
                        options: reduceMotion || !model.chatTurnState.isPending ? .nonRepeating : .repeating
                    )
                if !hasConversationContent {
                    Text("原生角色舞台")
                        .font(.title3.weight(.semibold))
                    Text("Live2D / VRM 原生运行时通过验证前，将显示静态角色回退。")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(model.chatTurnState.isPending ? "Joi 角色舞台，正在回应" : "Joi 角色舞台，空闲")
        }
        .frame(maxHeight: hasConversationContent ? 132 : .infinity)
        .padding(.horizontal, 16)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.chatTranscript, id: \.eventID) { entry in
                        TranscriptBubble(entry: entry)
                            .id(entry.eventID)
                    }
                    turnStatus
                        .id(Self.statusAnchor)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.chatTranscript.count) { _, _ in
                withAnimation(reduceMotion ? nil : .snappy) {
                    proxy.scrollTo(Self.statusAnchor, anchor: .bottom)
                }
            }
            .onChange(of: model.chatTurnState) { _, _ in
                withAnimation(reduceMotion ? nil : .snappy) {
                    proxy.scrollTo(Self.statusAnchor, anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: hasConversationContent ? .infinity : 0)
        .opacity(hasConversationContent ? 1 : 0)
    }

    @ViewBuilder private var turnStatus: some View {
        switch model.chatTurnState {
        case .idle:
            EmptyView()
        case let .pending(text, _):
            VStack(alignment: .trailing, spacing: 6) {
                PendingBubble(text: text)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("\(characterName) 正在回应")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("停止") { model.stopChatTurn() }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.indigo)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
        case .cancelled:
            statusLine("已停止这次回应；对话没有变化。", symbol: "stop.circle", tint: .secondary)
        case let .failed(message, retryable):
            VStack(alignment: .leading, spacing: 6) {
                statusLine(message, symbol: "exclamationmark.triangle.fill", tint: .orange)
                if retryable {
                    Text("你可以重新发送这条消息。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statusLine(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField("给 \(characterName) 发消息", text: $model.chatDraft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($isComposerFocused)
                .submitLabel(.send)
                .onSubmit { model.sendChatMessage() }

            if model.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("按住说话", systemImage: "mic.fill") {}
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .background(Color.indigo, in: Circle())
                    .foregroundStyle(.white)
                    .disabled(true)
                    .accessibilityHint("语音输入尚未启用")
            } else {
                Button("发送", systemImage: "arrow.up") {
                    model.sendChatMessage()
                }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .background(Color.indigo, in: Circle())
                .foregroundStyle(.white)
                .disabled(model.chatTurnState.isPending)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 82)
    }

    private static let statusAnchor = "joi.chat.status"
}

private struct TranscriptBubble: View {
    let entry: TranscriptEntry

    private var isUser: Bool { entry.author == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(entry.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser ? AnyShapeStyle(Color.indigo) : AnyShapeStyle(.ultraThinMaterial),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .foregroundStyle(isUser ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
                .textSelection(.enabled)
            if !isUser { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isUser ? "我说：\(entry.text)" : "Joi 说：\(entry.text)")
    }
}

/// Text the user sent that the backend has not accepted yet. Deliberately
/// styled as unconfirmed so it never reads as an accepted transcript line.
private struct PendingBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.indigo.opacity(0.28), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("正在发送：\(text)")
    }
}
