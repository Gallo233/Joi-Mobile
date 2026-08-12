import CompanionCore
import SwiftUI

/// The companion's current line, floating over the stage. It shows either the
/// replaceable streaming draft or the last accepted line, and says which:
/// an in-progress draft must never look like a settled answer.
struct CompanionBubble: View {
    let characterName: String
    let text: String
    let isDraft: Bool
    let onStop: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(characterName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if isDraft {
                    ProgressView().controlSize(.mini)
                    if let onStop {
                        Spacer(minLength: 4)
                        Button(String(localized: "停止"), action: onStop)
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(.indigo)
                    }
                }
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isDraft
                ? String(localized: "\(characterName) 正在输入：\(text)")
                : String(localized: "\(characterName) 说：\(text)")
        )
    }
}

/// A short, non-destructive status line shown in place of the bubble.
struct StageStatusBanner: View {
    let message: String
    let hint: String?
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(message, systemImage: symbol)
                .font(.footnote.weight(.medium))
                .foregroundStyle(tint)
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Collapsible transcript. It is opt-in on purpose: the stage is the default
/// view, and only users who want the history pay screen space for it.
struct TranscriptDrawer: View {
    let transcript: [TranscriptEntry]
    let characterName: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("聊天记录")
                    .font(.headline)
                Spacer()
                Button(String(localized: "收起"), systemImage: "sidebar.trailing", action: onClose)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(String(localized: "收起聊天记录"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Divider()

            if transcript.isEmpty {
                Spacer()
                Text("还没有对话记录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(transcript, id: \.eventID) { entry in
                                TranscriptRow(entry: entry, characterName: characterName)
                                    .id(entry.eventID)
                            }
                        }
                        .padding(16)
                    }
                    .onAppear {
                        if let last = transcript.last { proxy.scrollTo(last.eventID, anchor: .bottom) }
                    }
                    .onChange(of: transcript.count) { _, _ in
                        if let last = transcript.last { proxy.scrollTo(last.eventID, anchor: .bottom) }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .accessibilityAddTraits(.isModal)
    }
}

private struct TranscriptRow: View {
    let entry: TranscriptEntry
    let characterName: String

    private var isUser: Bool { entry.author == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            Text(isUser ? String(localized: "我") : characterName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.text)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    isUser ? AnyShapeStyle(Color.indigo) : AnyShapeStyle(.thinMaterial),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .foregroundStyle(isUser ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isUser
                ? String(localized: "我说：\(entry.text)")
                : String(localized: "\(characterName) 说：\(entry.text)")
        )
    }
}

/// The composer. Voice stays visible but disabled until push-to-talk exists, so
/// the control does not silently disappear and then reappear later.
struct ChatComposer: View {
    @Binding var draft: String
    let isSending: Bool
    let placeholder: String
    let onSend: () -> Void

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
                .submitLabel(.send)
                .onSubmit(onSend)

            if canSend {
                Button(String(localized: "发送"), systemImage: "arrow.up", action: onSend)
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(Color.indigo, in: Circle())
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
            } else {
                Button(String(localized: "按住说话"), systemImage: "mic.fill") {}
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(
                        isSending ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.indigo.opacity(0.9)),
                        in: Circle()
                    )
                    .foregroundStyle(isSending ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.white))
                    .buttonStyle(.plain)
                    .disabled(true)
                    .accessibilityHint(String(localized: "语音输入尚未启用"))
            }
        }
    }
}
