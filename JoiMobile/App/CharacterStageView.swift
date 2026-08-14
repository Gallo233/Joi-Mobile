import CharacterRuntime
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

/// One request for the character to play a motion it declared.
///
/// The sequence number is what makes a repeat visible: asking for `happy` twice
/// in a row is two events, and a plain name would compare equal and be dropped
/// by SwiftUI's diffing.
struct StageMotionCue: Equatable, Sendable {
    let motion: String
    let sequence: Int
}

/// The persistent character stage. It always fills its container: conversation
/// never squeezes it, because character presence is the product identity.
struct CharacterStageView: View {
    let framing: StageFraming
    let isResponding: Bool
    /// Polled by a native renderer for mouth opening.
    var speechPlayer: SpeechPlayer?
    /// The activated character's content, when one is active. This is the product
    /// path; a developer fixture is only consulted when nothing is activated.
    var stageContent: CharacterContentAccess?
    /// The latest motion the session asked the character to play.
    var motionCue: StageMotionCue?
    /// A tap that landed on the character rather than on the chrome above it.
    var onStageTap: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set when a native runtime was expected but could not present the model.
    /// The stage then shows the static fallback, never a blank or half-drawn
    /// character.
    @State private var nativeUnavailable = false

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

            characterContent
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isResponding
                ? String(localized: "角色舞台，正在回应")
                : String(localized: "角色舞台，空闲")
        )
        .accessibilityValue(framing.label)
    }

    /// A native model is presented only when this build admitted the runtime and
    /// a model was explicitly supplied. Every Live2D name stays inside the
    /// conditional so the default build has no such symbol at all.
    @ViewBuilder private var characterContent: some View {
        #if JOI_VRM
        if !nativeUnavailable, let vrm = stageContent, vrm.renderer == .vrm {
            VRMStageSurface(
                content: vrm,
                framing: framing,
                motionCue: motionCue,
                amplitude: speechPlayer,
                onUnavailable: { nativeUnavailable = true }
            )
            .id(vrm.contentID.rawValue)
            .ignoresSafeArea()
            // A SwiftUI gesture, so the composer and the stage controls drawn
            // above this layer win the touches that land on them.
            .onTapGesture(perform: onStageTap)
        } else {
            live2DOrStatic
        }
        #else
        live2DOrStatic
        #endif
    }

    /// Live2D is tried before the static fallback. Kept separate so the VRM
    /// branch above can reuse it without duplicating the conditional.
    @ViewBuilder private var live2DOrStatic: some View {
        #if JOI_LIVE2D
        if !nativeUnavailable, let live2d = liveModelSource {
            Live2DStageSurface(
                fixture: live2d,
                framing: framing,
                amplitude: speechPlayer,
                onUnavailable: { nativeUnavailable = true }
            )
            // Keyed by content so activating a different character rebuilds the
            // surface rather than reusing a coordinator bound to the old model.
            .id(live2d.directory + "/" + live2d.model3)
            .ignoresSafeArea()
        } else {
            staticPlaceholder
        }
        #else
        staticPlaceholder
        #endif
    }

    #if JOI_LIVE2D
    /// The activated character wins. Only a `live2d` package can drive the native
    /// surface; a `static` or `vrm` package correctly falls through to the
    /// placeholder rather than being fed to the wrong runtime.
    private var liveModelSource: Live2DDevFixture? {
        if let stageContent {
            guard stageContent.renderer == .live2d else { return nil }
            return Live2DDevFixture(
                directory: stageContent.root.path,
                model3: stageContent.entryPath
            )
        }
        return Live2DDevFixture.fromEnvironment
    }
    #endif

    private var staticPlaceholder: some View {
        StaticCharacterPlaceholder(isResponding: isResponding, reduceMotion: reduceMotion)
            .scaleEffect(framing.scale, anchor: framing.anchor)
            .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: framing)
            .clipped()
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
