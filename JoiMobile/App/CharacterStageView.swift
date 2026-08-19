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

/// The native character runtimes this binary was compiled with.
///
/// This is decided by the spec ladder, not by configuration: `project.yml`
/// admits neither runtime, `project.live2d.yml` adds Cubism, and
/// `project.native.yml` adds VRM on top. A default-spec build is legitimate —
/// it is exactly what a clone without the vendor SDKs gets — but it cannot draw
/// an activated Live2D or VRM character.
enum StageRuntimeAdmission {
    static let live2d: Bool = {
        #if JOI_LIVE2D
        return true
        #else
        return false
        #endif
    }()

    static let vrm: Bool = {
        #if JOI_VRM
        return true
        #else
        return false
        #endif
    }()

    static func admits(_ kind: CharacterRendererKind) -> Bool {
        switch kind {
        // The silhouette is what a `static` package renders. Nothing is missing.
        case .static: true
        case .live2d: live2d
        case .vrm: vrm
        }
    }
}

/// Why the stage is drawing a silhouette instead of the activated character.
///
/// Until this existed the stage had one fallback and it was silent, so three
/// unrelated situations rendered identically: no character activated, a
/// character this build cannot draw, and a runtime that failed to present one.
/// Only the first is a healthy state. The second has now cost three debugging
/// cycles — each spent rediscovering that a default-spec `xcodegen generate` had
/// replaced the native project — because a fault that looks exactly like a
/// healthy state is a fault nobody can see.
enum StageFallbackReason: Equatable, Sendable {
    /// The character needs a runtime this binary was not compiled with. Not a
    /// defect in the package or the model: a property of the build.
    case runtimeAbsentFromBuild(CharacterRendererKind)
    /// The runtime is present, and could not present this model.
    case runtimeCouldNotPresent(CharacterRendererKind)

    var message: String {
        switch self {
        case .runtimeAbsentFromBuild(let kind):
            String(localized: "此构建未包含 \(kind.stageName) 原生运行时，舞台以剪影代替角色。")
        case .runtimeCouldNotPresent(let kind):
            String(localized: "\(kind.stageName) 运行时未能显示这个角色，舞台以剪影代替。")
        }
    }

    /// Pure, so the spec ladder cannot make it untestable: the compile-time
    /// facts arrive as arguments rather than as reads, and every rung of the
    /// ladder runs the same cases.
    static func decide(
        renderer: CharacterRendererKind?,
        isAdmitted: Bool,
        presentationFailed: Bool
    ) -> StageFallbackReason? {
        guard let renderer else { return nil }
        guard isAdmitted else { return .runtimeAbsentFromBuild(renderer) }
        return presentationFailed ? .runtimeCouldNotPresent(renderer) : nil
    }
}

extension CharacterRendererKind {
    /// The runtime's own name, spelled as the spec files and build logs spell
    /// it, so the notice and the fix use the same word.
    var stageName: String {
        switch self {
        case .static: "static"
        case .live2d: "Live2D"
        case .vrm: "VRM"
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
        // The notice below is inside an ignored subtree, so without this the one
        // fact worth announcing would be the one VoiceOver could not reach.
        .accessibilityHint(fallbackReason?.message ?? "")
    }

    /// Why the silhouette is on screen, when it should not have to be.
    ///
    /// `nil` covers both healthy cases: a native surface is drawing, or no
    /// character is activated and the silhouette is the honest answer.
    var fallbackReason: StageFallbackReason? {
        StageFallbackReason.decide(
            renderer: stageContent?.renderer,
            isAdmitted: stageContent.map { StageRuntimeAdmission.admits($0.renderer) } ?? true,
            presentationFailed: nativeUnavailable
        )
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
            // Applied after the scale effect, so the notice is not framed with
            // the character: it is a statement about the build, not part of it.
            .overlay(alignment: .top) {
                if let fallbackReason {
                    StageFallbackNotice(reason: fallbackReason)
                        // Clears the floating header, which is drawn above this
                        // layer by the Chat surface rather than inside it: safe
                        // area, the title and the "本地会话" subtitle beneath it.
                        .padding(.top, 132)
                }
            }
    }
}

/// Says why the silhouette is there.
///
/// Deliberately plain and permanent rather than a toast: the condition it
/// reports lasts as long as the build does, so something that faded would be
/// worse than nothing at all.
private struct StageFallbackNotice: View {
    let reason: StageFallbackReason

    var body: some View {
        Text(reason.message)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 32)
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
    /// Opens what the character durably remembers (`G2-J2D`). Secondary by
    /// DEC-001, so it sits with the transcript rather than on the stage.
    var onOpenMemories: (() -> Void)?

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

            if let onOpenMemories {
                Button(action: onOpenMemories) {
                    Label(String(localized: "记忆"), systemImage: "bookmark")
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
