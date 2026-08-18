import CharacterRuntime
import CompanionCore
import MetalKit
import OSLog
import SwiftUI
import VRMMetalKit

private let vrmLog = Logger(subsystem: "com.joi.mobile", category: "vrm")

/// Why the VRM stage could not present a model. Named for the same reason the
/// Live2D reasons are: a silent fallback is untraceable.
enum VRMUnavailableReason: String, Sendable {
    case noMetalDevice
    case modelRejected
}

extension StageFraming {
    /// Camera placement per framing. A VRM avatar is roughly 1.5 m tall with its
    /// origin at the feet, so these are metres in model space rather than the
    /// abstract zoom the Live2D stage uses.
    var vrmCameraPosition: SIMD3<Float> {
        switch self {
        case .fullBody: SIMD3<Float>(0, 0.85, 2.3)
        case .halfBody: SIMD3<Float>(0, 1.32, 0.85)
        }
    }

    var vrmCameraTarget: SIMD3<Float> {
        switch self {
        case .fullBody: SIMD3<Float>(0, 0.85, 0)
        case .halfBody: SIMD3<Float>(0, 1.30, 0)
        }
    }
}

/// Renders one VRM model with VRMMetalKit's Metal renderer.
///
/// The model and its motion clips both come from the installer-issued content
/// access, so this surface can only ever draw a character the session actually
/// activated and can only ever play a clip that manifest validation declared and
/// re-hashed. Loading is asynchronous; until it completes the view draws nothing
/// and the stage keeps showing its own background rather than a flash of empty
/// scene.
struct VRMStageSurface: UIViewRepresentable {
    let content: CharacterContentAccess
    let framing: StageFraming
    /// A motion the session asked for. Carries a sequence number so asking for
    /// the same motion twice in a row still replays it.
    var motionCue: StageMotionCue?
    /// Polled each frame for mouth opening. Nil means the mouth stays closed.
    weak var amplitude: SpeechPlayer?
    let onUnavailable: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content, amplitude: amplitude, onUnavailable: onUnavailable)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        // No gesture recognizer here, deliberately. One on this view fires for
        // taps that land on the composer and the stage controls drawn above it,
        // because a UIKit recognizer on the Metal view does not lose to SwiftUI
        // chrome the way a SwiftUI gesture on the same layer does — it swallowed
        // every attempt to type. Tap-to-play is a SwiftUI gesture on the stage,
        // routed through the session, so z-order decides who gets the touch.
        view.device = MTLCreateSystemDefaultDevice()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.layer.isOpaque = false
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.framing = framing
        context.coordinator.apply(motionCue)
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        coordinator.shutdown()
    }

    /// Owns the renderer. `VRMRenderer.draw(in:)` is main-actor isolated, and
    /// MTKView delegate callbacks arrive on the main thread, so the renderer,
    /// the model and the animation player are only ever touched from one place.
    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        var framing: StageFraming = .fullBody
        private let content: CharacterContentAccess
        private weak var amplitude: SpeechPlayer?
        private let onUnavailable: () -> Void
        private var renderer: VRMRenderer?
        private var model: VRMModel?
        private let player = AnimationPlayer()
        /// Declared clips, parsed once. A tap must not pay a GLB parse.
        private var clips: [String: AnimationClip] = [:]
        /// The motion this character holds between events, and the one now
        /// playing. A package may name idle explicitly; otherwise the first
        /// looping clip is it.
        private var idleName: String?
        private var playingMotion: String?
        /// A motion asked for before the model finished loading. Activation
        /// issues its greeting roughly a second before a 25 MB avatar is ready,
        /// so dropping it would silently lose every greeting.
        private var pendingMotion: String?
        private var lastCueSequence: Int?
        private var queue: MTLCommandQueue?
        private var loadTask: Task<Void, Never>?
        private var lastFrame: CFTimeInterval?
        private var reportedUnavailable = false
        private var hasLoggedMouth = false
        /// Whether this Metal device can run the renderer's spring-bone kernels.
        /// Decided once from the device, because the answer cannot change.
        private var supportsSpringBone = false
        private var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?

        init(
            content: CharacterContentAccess,
            amplitude: SpeechPlayer?,
            onUnavailable: @escaping () -> Void
        ) {
            self.content = content
            self.amplitude = amplitude
            self.onUnavailable = onUnavailable
            super.init()
        }

        func attach(to view: MTKView) {
            guard let device = view.device, let queue = device.makeCommandQueue() else {
                return report(.noMetalDevice)
            }
            self.queue = queue
            // Non-uniform threadgroups arrived with Apple4 (A11), so every real
            // target device has them and the Simulator does not.
            supportsSpringBone = device.supportsFamily(.apple4)
            vrmLog.notice("""
                vrm device: \(device.name, privacy: .public) \
                springBone \(self.supportsSpringBone, privacy: .public)
                """)
            loadTask = Task { [weak self] in
                guard let self else { return }
                do {
                    // Parsing and GPU upload of a 25 MB avatar must not block the
                    // first frames of the surface.
                    //
                    // Collider augmentation is off. The loader otherwise adds a
                    // synthetic head/brow capsule and leg capsules on top of the
                    // ones the model authors, to rescue rigs whose hair sinks into
                    // the forehead. This character authors ten collider groups of
                    // its own, and the extra head capsule pushes every hair strand
                    // off the skull: the side locks splay out well past the
                    // shoulders and the silhouette reads as wind rather than as a
                    // breathing idle. The SDK documents this exact escape and
                    // warns that augmentation moves resting spring positions.
                    let model = try await VRMModel.load(
                        from: content.entryURL,
                        device: device,
                        options: VRMLoadingOptions(augmentSpringBoneColliders: false)
                    )
                    guard !Task.isCancelled else { return }
                    let renderer = VRMRenderer(device: device)
                    // Without warmup: spring bones must settle against the first
                    // animated pose, not against the bind pose, or the hair snaps
                    // on the first frame that plays.
                    renderer.loadModelWithoutWarmup(model)
                    // The renderer starts with no lights, which renders MToon as a
                    // flat dark texture and reads as "the model loaded but looks
                    // wrong". This is the cel-shading rig the SDK's own CLI uses:
                    // one key light, a dim front fill, dark ambient, and
                    // radiometric normalisation so authored intensities are not
                    // scaled down by the shader's Lambert term.
                    renderer.setLight(
                        0,
                        direction: SIMD3<Float>(-0.2, 0.5, -0.85),
                        color: SIMD3<Float>(1, 1, 1),
                        intensity: 1.0
                    )
                    renderer.disableLight(1)
                    renderer.setLight(
                        2,
                        direction: SIMD3<Float>(0, 0.2, 1),
                        color: SIMD3<Float>(1, 1, 1),
                        intensity: 0.3
                    )
                    renderer.setAmbientColor(SIMD3<Float>(0.04, 0.04, 0.04))
                    renderer.setLightNormalizationMode(.radiometric)

                    // Framing comes from the model's own bounds rather than
                    // hardcoded metres, so a wide T-pose is not cropped and a
                    // differently proportioned avatar still fits.
                    let (minBounds, maxBounds) = model.calculateBoundingBox()
                    bounds = (minBounds, maxBounds)
                    self.model = model
                    self.renderer = renderer
                    vrmLog.notice("""
                        vrm model loaded: bounds \(maxBounds - minBounds, privacy: .public) \
                        center \((minBounds + maxBounds) / 2, privacy: .public)
                        """)

                    // Idle first, so the character stops holding a bind pose as
                    // early as possible; the rest of the clips load behind it.
                    startAnimation(model: model, renderer: renderer)
                    await loadRemainingClips(model: model)
                } catch {
                    report(.modelRejected)
                }
            }
        }

        /// Starts the looping clip, plays anything that was asked for while the
        /// model was loading, then settles the spring bones against the pose that
        /// will actually be drawn. A character with no declared motions keeps its
        /// bind pose, which is honest: nothing in the package says how it moves.
        private func startAnimation(model: VRMModel, renderer: VRMRenderer) {
            let idle = content.motions.first { $0.motion == CharacterMotionV1.idleName }
                ?? content.motions.first { $0.loops }
            if let idle, let clip = loadClip(idle, model: model) {
                idleName = idle.motion
                play(clip, named: idle.motion, looping: true)
            } else {
                vrmLog.notice("vrm idle: package declares no looping motion; holding bind pose")
            }
            if let pending = pendingMotion {
                pendingMotion = nil
                play(motion: pending)
            }
            // Frame zero before warmup: settling the springs against the bind
            // pose and then jumping to an animated frame snaps the hair.
            player.update(deltaTime: 0, model: model)

            // Spring bones are a capability, not a given. Every spring-bone
            // kernel in the renderer is issued with `dispatchThreads`, which
            // requires non-uniform threadgroup support; the Simulator's Metal
            // device declares none, so each of those dispatches is an invalid
            // call there. With Metal API Validation on — Xcode's default for a
            // Run — the first one aborts the process during warmup. It only
            // looked fine from a plain `simctl launch`, where validation is off
            // and the illegal call goes unchecked. The renderer has no gate of
            // its own, so the host supplies one and says so rather than
            // crashing or pretending.
            guard supportsSpringBone else {
                vrmLog.notice("""
                    vrm spring bone unavailable: this Metal device has no \
                    non-uniform threadgroups; animation plays without hair physics
                    """)
                return
            }
            // Warmup runs the solver against that pose, so the springs do not
            // start cold and bounce on the first drawn frame.
            renderer.warmupPhysics(steps: 30)
            // Off by default in the renderer, so hair and cloth stay rigid until
            // the host asks for them. Nothing moves the springs but bone motion,
            // which is why this only became visible once a clip played.
            //
            // No global gravity is set, deliberately. The renderer's own CLI adds
            // a downward external force to any rig authoring `gravityPower == 0`,
            // on the theory that such hair has nothing pulling it down. That is
            // wrong for authored hair: this model's seven hair groups pair
            // `gravityPower: 0` with `stiffiness ≈ 0.85` and `dragForce: 0.4`,
            // which is a rig built to hold its silhouette and merely lag behind
            // the head. Adding the force its author left out swings the strands
            // away from the head during a breathing idle, so the hair reads like a
            // dance clip. Global gravity is spec-additive and defaults to zero;
            // honouring the rig means leaving per-joint `gravityPower` as the only
            // gravity source.
            renderer.enableSpringBone = true
        }

        /// The remaining clips are parsed one at a time with a yield between
        /// them: a multi-megabyte VRMA parse on the main actor would otherwise
        /// stall the frames the idle animation is already drawing.
        private func loadRemainingClips(model: VRMModel) async {
            for motion in content.motions where clips[motion.motion] == nil {
                guard !Task.isCancelled else { return }
                await Task.yield()
                _ = loadClip(motion, model: model)
            }
            vrmLog.notice("""
                vrm motions ready: \(self.clips.count, privacy: .public) of \
                \(self.content.motions.count, privacy: .public) declared
                """)
        }

        @discardableResult
        private func loadClip(_ motion: CharacterMotionV1, model: VRMModel) -> AnimationClip? {
            if let cached = clips[motion.motion] { return cached }
            guard let url = content.animationURL(forMotion: motion.motion) else { return nil }
            do {
                let clip = try VRMAnimationLoader.loadVRMA(from: url, model: model)
                clips[motion.motion] = clip
                vrmLog.notice("""
                    vrm clip loaded: \(motion.motion, privacy: .public) \
                    \(clip.duration, privacy: .public)s \
                    \(clip.jointTracks.count, privacy: .public) joints
                    """)
                return clip
            } catch {
                // One unreadable clip must not cost the character its other
                // motions, so this is reported and skipped rather than fatal.
                vrmLog.error("vrm clip rejected: \(motion.motion, privacy: .public)")
                return nil
            }
        }

        private func play(_ clip: AnimationClip, named motion: String, looping: Bool) {
            player.load(clip)
            player.isLooping = looping
            player.play()
            playingMotion = motion
        }

        /// Plays a declared motion by name. Unknown names are ignored: the
        /// package decides what this character can do, not the caller.
        func play(motion: String) {
            guard let model else {
                pendingMotion = motion
                vrmLog.notice("vrm motion deferred: \(motion, privacy: .public) arrived before the model")
                return
            }
            guard let declared = content.motions.first(where: { $0.motion == motion }),
                  let clip = loadClip(declared, model: model) else {
                vrmLog.notice("vrm motion ignored: \(motion, privacy: .public) is not declared")
                return
            }
            play(clip, named: motion, looping: declared.loops)
            vrmLog.notice("vrm motion playing: \(motion, privacy: .public)")
        }

        func apply(_ cue: StageMotionCue?) {
            guard let cue, cue.sequence != lastCueSequence else { return }
            lastCueSequence = cue.sequence
            play(motion: cue.motion)
        }

        func shutdown() {
            loadTask?.cancel()
            loadTask = nil
            player.stop()
            clips.removeAll()
            renderer = nil
            model = nil
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            _ = renderer?.updateDrawableSize(size)
        }

        func draw(in view: MTKView) {
            guard let renderer,
                  let queue,
                  let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let buffer = queue.makeCommandBuffer() else {
                return
            }
            let size = view.drawableSize
            guard size.width > 0, size.height > 0 else { return }
            advanceAnimation(renderer: renderer)
            // Without these the camera sits at the origin, inside the model, which
            // renders as a few stretched fragments. The renderer has no implicit
            // camera: the host owns framing entirely.
            renderer.projectionMatrix = Self.perspective(
                fovRadians: 45 * .pi / 180,
                aspect: Float(size.width / size.height),
                near: 0.01,
                far: 100
            )
            let (eye, target) = camera(aspect: Float(size.width / size.height))
            renderer.viewMatrix = Self.lookAt(eye: eye, center: target)
            renderer.draw(in: view, commandBuffer: buffer, renderPassDescriptor: descriptor)
            buffer.present(drawable)
            buffer.commit()
        }

        /// Advances the clip by real elapsed time and returns to idle when a
        /// one-shot ends, so a greeting is a gesture the character comes back
        /// from rather than a pose it is left stuck in.
        private func advanceAnimation(renderer: VRMRenderer) {
            guard let model else { return }
            let now = CACurrentMediaTime()
            // A large delta after a pause would fast-forward the clip and yank
            // the spring bones, so it is clamped exactly as the Live2D stage's is.
            let delta = lastFrame.map { min(now - $0, 0.1) } ?? 0
            lastFrame = now
            player.update(deltaTime: Float(delta), model: model)
            player.applyMorphWeights(to: renderer.expressionController)
            // After the clip's own morphs, so a clip that animates the mouth
            // does not fight the voice. The clip wrote only the keys it carries,
            // so this is a clean override of one viseme rather than a reset.
            driveMouth(renderer: renderer)
            guard player.isFinished,
                  playingMotion != idleName,
                  let idleName,
                  let clip = clips[idleName] else { return }
            play(clip, named: idleName, looping: true)
        }

        /// Opens the mouth by the amplitude of the audio actually playing.
        ///
        /// One viseme, driven by loudness. Amplitude carries no phoneme
        /// information, so blending `ih`/`ou`/`ee`/`oh` from it would be
        /// inventing speech shapes the audio never implies — DEC-021's rule is
        /// that this product stays still rather than mimes. Silence is written
        /// every frame too, so the mouth closes on its own with no bookkeeping.
        ///
        /// `.aa` covers both VRM versions: the loader maps VRM 0.x's `a`
        /// blend-shape group onto the VRM 1.0 `aa` preset, and a model that
        /// declares neither simply has nothing bound to the weight.
        private func driveMouth(renderer: VRMRenderer) {
            let opening = min(max(amplitude?.currentAmplitude ?? 0, 0), 1)
            renderer.setExpression(.aa, weight: opening)
            if opening > 0.05, !hasLoggedMouth {
                hasLoggedMouth = true
                vrmLog.notice("vrm lip sync: mouth driven by played audio")
            }
        }

        /// Frames the model from its measured bounds. Full body fits the whole
        /// height and width, including outstretched arms; half body aims at the
        /// head. Distance is derived from the field of view rather than guessed,
        /// so nothing is cropped on a narrow phone screen.
        private func camera(aspect: Float) -> (SIMD3<Float>, SIMD3<Float>) {
            guard let bounds else {
                return (SIMD3<Float>(0, 1, 2.5), SIMD3<Float>(0, 1, 0))
            }
            let centre = (bounds.min + bounds.max) / 2
            let extent = bounds.max - bounds.min
            let halfFov = (45 * Float.pi / 180) / 2
            switch framing {
            case .fullBody:
                // Fit whichever axis is tighter on this screen.
                let neededForHeight = (extent.y / 2) / tan(halfFov)
                let neededForWidth = (extent.x / 2) / (tan(halfFov) * max(aspect, 0.0001))
                let distance = max(neededForHeight, neededForWidth) * 1.12 + extent.z
                return (
                    SIMD3<Float>(centre.x, centre.y, centre.z + distance),
                    SIMD3<Float>(centre.x, centre.y, centre.z)
                )
            case .halfBody:
                // The head sits near the top of the bounds; frame from the chest up.
                let headY = bounds.max.y - extent.y * 0.09
                let framedHeight = extent.y * 0.32
                let distance = (framedHeight / 2) / tan(halfFov) + extent.z
                return (
                    SIMD3<Float>(centre.x, headY, centre.z + distance),
                    SIMD3<Float>(centre.x, headY, centre.z)
                )
            }
        }

        /// Right-handed look-at, matching the convention the renderer's own CLI
        /// uses so the model is not mirrored or inside out.
        private static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>) -> matrix_float4x4 {
            let up = SIMD3<Float>(0, 1, 0)
            let forward = simd_normalize(center - eye)
            let right = simd_normalize(simd_cross(forward, up))
            let trueUp = simd_cross(right, forward)
            return matrix_float4x4(columns: (
                SIMD4<Float>(right.x, trueUp.x, -forward.x, 0),
                SIMD4<Float>(right.y, trueUp.y, -forward.y, 0),
                SIMD4<Float>(right.z, trueUp.z, -forward.z, 0),
                SIMD4<Float>(-simd_dot(right, eye), -simd_dot(trueUp, eye), simd_dot(forward, eye), 1)
            ))
        }

        private static func perspective(
            fovRadians: Float,
            aspect: Float,
            near: Float,
            far: Float
        ) -> matrix_float4x4 {
            let y = 1 / tan(fovRadians * 0.5)
            let x = y / max(aspect, 0.0001)
            let z = far / (near - far)
            return matrix_float4x4(columns: (
                SIMD4<Float>(x, 0, 0, 0),
                SIMD4<Float>(0, y, 0, 0),
                SIMD4<Float>(0, 0, z, -1),
                SIMD4<Float>(0, 0, z * near, 0)
            ))
        }

        private func report(_ reason: VRMUnavailableReason) {
            guard !reportedUnavailable else { return }
            reportedUnavailable = true
            vrmLog.error("vrm stage unavailable: \(reason.rawValue, privacy: .public)")
            onUnavailable()
        }
    }
}
