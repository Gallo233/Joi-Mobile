import CompanionCore
import SwiftUI

/// How much of the character the stage frames. This is a presentation choice
/// only: it never changes the active character, the renderer generation or any
/// session state. A native renderer maps it onto its own view matrix; the static
/// fallback maps it onto scale and anchor.
enum StageFraming: String, CaseIterable, Sendable {
    case halfBody
    case fullBody

    var label: String {
        switch self {
        case .halfBody: String(localized: "半身")
        case .fullBody: String(localized: "全身")
        }
    }

    var symbol: String {
        switch self {
        case .halfBody: "person.crop.rectangle"
        case .fullBody: "arrow.up.left.and.arrow.down.right"
        }
    }

    var next: StageFraming {
        self == .fullBody ? .halfBody : .fullBody
    }

    /// Scale applied to the stage content, anchored so the face stays visible.
    var scale: CGFloat {
        switch self {
        case .halfBody: 1.75
        case .fullBody: 1.0
        }
    }

    var anchor: UnitPoint {
        switch self {
        case .halfBody: UnitPoint(x: 0.5, y: 0.18)
        case .fullBody: .center
        }
    }
}

/// The persistent character stage. It always fills its container: conversation
/// never squeezes it, because character presence is the product identity.
struct CharacterStageView: View {
    let framing: StageFraming
    let isResponding: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.62, green: 0.60, blue: 0.93).opacity(0.55),
                    Color(red: 0.86, green: 0.72, blue: 0.93).opacity(0.35),
                    Color(.systemBackground).opacity(0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            StaticCharacterPlaceholder(isResponding: isResponding, reduceMotion: reduceMotion)
                .scaleEffect(framing.scale, anchor: framing.anchor)
                .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: framing)
                .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isResponding
                ? String(localized: "角色舞台，正在回应")
                : String(localized: "角色舞台，空闲")
        )
        .accessibilityValue(framing.label)
    }
}

/// Deliberately a silhouette, not an illustration: it must read as an absent
/// character rather than impersonate one. It also gives the half/full-body
/// control something real to frame before a native runtime is admitted.
private struct StaticCharacterPlaceholder: View {
    let isResponding: Bool
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let unit = min(proxy.size.width, height) / 10
            VStack(spacing: unit * 0.22) {
                Spacer(minLength: 0)
                Circle()
                    .frame(width: unit * 2.1, height: unit * 2.1)
                RoundedRectangle(cornerRadius: unit * 0.9, style: .continuous)
                    .frame(width: unit * 3.4, height: unit * 3.6)
                HStack(spacing: unit * 0.5) {
                    Capsule().frame(width: unit * 0.9, height: unit * 2.9)
                    Capsule().frame(width: unit * 0.9, height: unit * 2.9)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.tertiary)
            // Only shown while a turn is open: an idle stage needs no ornament,
            // and a permanent glyph reads as an artifact rather than as state.
            .overlay(alignment: .center) {
                if isResponding {
                    Image(systemName: "sparkles")
                        .font(.system(size: unit * 1.1, weight: .light))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)
                        .offset(y: -height * 0.22)
                        .transition(.opacity)
                }
            }
        }
    }
}

/// Bottom-left stage controls, mirroring the desktop shell's affordances.
struct StageControls: View {
    let framing: StageFraming
    let onToggleFraming: () -> Void
    let onOpenTranscript: () -> Void
    let hasTranscript: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleFraming) {
                Label(framing.next.label, systemImage: framing.next.symbol)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "切换到") + framing.next.label)

            if hasTranscript {
                Button(action: onOpenTranscript) {
                    Label(String(localized: "聊天记录"), systemImage: "text.bubble")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.primary)
    }
}
