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
    /// Why this line had no voice, if it had none (`FAIL-006`). Shown *on* the
    /// bubble rather than in place of it, because PRD §7 asks for the readable
    /// text to be preserved and a banner would have replaced it.
    var voiceFailure: String? = nil
    /// Speaks it again. Offered, never performed on its own — see
    /// `AppModel.retryLastVoiceLine`.
    var onRetryVoice: (() -> Void)? = nil

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
            if !isDraft, let voiceFailure {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.slash")
                        .font(.caption2)
                    Text(voiceFailure)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    if let onRetryVoice {
                        Button(String(localized: "重试"), action: onRetryVoice)
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(.indigo)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
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
    /// Whether a given line may be proposed as memory, and what to do when the
    /// user asks for it (`G2-J2D`).
    var canRemember: (TranscriptEntry) -> Bool = { _ in false }
    var onRemember: (TranscriptEntry) -> Void = { _ in }
    /// What stands behind each answer, and how to open it (`G2-J3C`).
    var claimSupport: (TranscriptEntry) -> ClaimSupport = { _ in .unsourced }
    var onOpenSources: (TranscriptEntry) -> Void = { _ in }
    /// Explicit, inspected Chat → Map handoff (`G2-J5M`).
    var canOpenInMap: (TranscriptEntry) -> Bool = { _ in false }
    var onOpenInMap: (TranscriptEntry) -> Void = { _ in }

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
                                TranscriptRow(
                                    entry: entry,
                                    characterName: characterName,
                                    onRemember: canRemember(entry) ? { onRemember(entry) } : nil,
                                    onOpenSources: claimSupport(entry) == .unsourced
                                        ? nil
                                        : { onOpenSources(entry) },
                                    onOpenInMap: canOpenInMap(entry)
                                        ? { onOpenInMap(entry) }
                                        : nil,
                                    sourcesWithheld: {
                                        if case .withheld = claimSupport(entry) { return true }
                                        return false
                                    }()
                                )
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
    /// `nil` when this line may not be remembered. The control is absent rather
    /// than disabled: eligibility is the backend's answer, and a greyed-out
    /// button invites the user to argue with a decision the app does not own.
    var onRemember: (() -> Void)?
    /// `nil` when this answer carried no sources at all. An unsourced line has
    /// nothing to open, and offering an empty list would imply otherwise.
    var onOpenSources: (() -> Void)?
    /// Present only for accepted user lines in the active transcript.
    var onOpenInMap: (() -> Void)?
    /// True when the answer arrived with citations and none of them may stand.
    /// Marked on the line itself rather than only inside the sheet, because a
    /// reader who never opens it still needs to know.
    var sourcesWithheld: Bool = false

    private var isUser: Bool { entry.author == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(isUser ? String(localized: "我") : characterName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let onRemember {
                    Button(String(localized: "记住"), systemImage: "bookmark", action: onRemember)
                        .labelStyle(.iconOnly)
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.indigo)
                        .accessibilityLabel(String(localized: "记住这句话"))
                }
                if let onOpenSources {
                    Button(
                        String(localized: "查看来源"),
                        systemImage: sourcesWithheld ? "exclamationmark.triangle.fill" : "text.book.closed",
                        action: onOpenSources
                    )
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(sourcesWithheld ? .orange : .teal)
                    .accessibilityLabel(
                        sourcesWithheld
                            ? String(localized: "这条说法没有可用来源")
                            : String(localized: "查看来源")
                    )
                }
            }
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
            if let onOpenInMap {
                Button(action: onOpenInMap) {
                    Label(String(localized: "在地图中查找"), systemImage: "map")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.indigo)
                .accessibilityHint(String(localized: "先检查和编辑搜索文字"))
            }
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
    /// Push-to-talk. While listening the field shows what has been heard so far,
    /// so the user can see the recogniser keeping up rather than trusting it.
    var isListening: Bool = false
    var partialSpeech: String = ""
    var onVoiceStart: () -> Void = {}
    var onVoiceEnd: () -> Void = {}

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField(
                isListening ? String(localized: "正在听……") : placeholder,
                text: isListening ? .constant(partialSpeech) : $draft,
                axis: .vertical
            )
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .disabled(isListening)
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
                // Press and hold. A tap-to-toggle microphone leaves the user
                // unsure whether it is still listening; holding makes the answer
                // the position of their own thumb.
                Label(String(localized: "按住说话"), systemImage: isListening ? "waveform" : "mic.fill")
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(
                        isSending ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.indigo.opacity(0.9)),
                        in: Circle()
                    )
                    .foregroundStyle(isSending ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.white))
                    .scaleEffect(isListening ? 1.18 : 1)
                    .animation(.snappy(duration: 0.18), value: isListening)
                    .contentShape(Circle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in if !isSending, !isListening { onVoiceStart() } }
                            .onEnded { _ in if isListening { onVoiceEnd() } }
                    )
                    .accessibilityLabel(String(localized: "按住说话"))
                    .accessibilityHint(String(localized: "按住录音，松开把文字放进输入框"))
            }
        }
    }
}

/// The one-turn journey attachment, shown before it is sent (`G2-J3B`).
///
/// This card is the whole consent surface: every field it prints is a field of
/// the payload that will travel, at the payload's own resolution. It exists so
/// that "explicit, inspectable attachment" in DEC-002 means the user can read
/// the position being shared rather than trust a label saying one is attached.
struct JourneyAttachmentCard: View {
    let attachment: JourneyAttachment
    let minutesRemaining: Int
    let onRevoke: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(String(localized: "将随这条消息发送一次"), systemImage: "location.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.indigo)
                Spacer()
                Button(String(localized: "撤销"), role: .destructive, action: onRevoke)
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Text("路线：\(attachment.routeTitle)")
                .font(.caption)
                .foregroundStyle(.primary)
            if let progress = attachment.progressLine {
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let position = attachment.positionLine {
                Text(position)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // Said plainly, because the coordinate above is rounded and a user
            // reading three decimals deserves to know that is all there is.
            Text("位置精度约 100 米，\(minutesRemaining) 分钟后过期")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.indigo.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
