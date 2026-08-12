import MetalKit
import OSLog
import SwiftUI

/// Why the native stage could not present a model. A silent fallback is
/// untraceable, so every path that gives up names itself. Deliberately carries
/// no filesystem path: asset locations must stay out of logs.
enum Live2DUnavailableReason: String, Sendable {
    case noMetalDevice
    case noFixtureSupplied
    case modelRejected
    case rendererOrTexturesRejected
}

private let live2dLog = Logger(subsystem: "com.joi.mobile", category: "live2d")

/// Where a development build may find a local Live2D model. The path is supplied
/// by the environment, never committed: model payloads and their absolute paths
/// must stay out of this repository.
struct Live2DDevFixture {
    let directory: String
    let model3: String

    /// Development-only key. This exists so a developer who launched once with
    /// the environment variable can then open the app normally from the home
    /// screen. It is not the product path: a shipped build gets its model from
    /// the installed character library, never from a developer setting.
    private static let defaultsKey = "joi.live2d.devFixtureEntry"

    static var fromEnvironment: Live2DDevFixture? {
        let environment = ProcessInfo.processInfo.environment
        let supplied = environment["JOI_LIVE2D_FIXTURE_ENTRY_URL"]
        if let supplied, !supplied.isEmpty {
            // Remember it so a plain launch from the home screen also works.
            UserDefaults.standard.set(supplied, forKey: defaultsKey)
        }
        let remembered = UserDefaults.standard.string(forKey: defaultsKey)
        guard let entry = (supplied?.isEmpty == false ? supplied : remembered), !entry.isEmpty else {
            live2dLog.notice("live2d fixture: none supplied by environment or remembered")
            return nil
        }
        guard FileManager.default.isReadableFile(atPath: entry) else {
            // The path is intentionally not logged; only the fact of the miss.
            live2dLog.error("live2d fixture: supplied entry is not readable")
            return nil
        }
        let url = URL(fileURLWithPath: entry)
        return Live2DDevFixture(
            directory: url.deletingLastPathComponent().path,
            model3: url.lastPathComponent
        )
    }
}

/// Renders one Live2D model with Metal. Failure at any stage is reported through
/// `onUnavailable` so the stage can show the honest static fallback instead of a
/// blank or half-drawn character.
struct Live2DStageSurface: UIViewRepresentable {
    let fixture: Live2DDevFixture
    let framing: StageFraming
    /// Polled each frame for mouth opening. Nil means the mouth stays closed.
    weak var amplitude: SpeechPlayer?
    let onUnavailable: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(fixture: fixture, amplitude: amplitude, onUnavailable: onUnavailable)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        // Touch drives look-at and the model's own gesture motions.
        view.addGestureRecognizer(
            UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        )
        view.addGestureRecognizer(
            UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        )
        view.device = MTLCreateSystemDefaultDevice()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.layer.isOpaque = false
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .invalid
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.framing = framing
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        coordinator.shutdown()
    }

    /// Owns the model. Cubism's global state is not thread-safe, and MTKView
    /// delegate callbacks arrive on the main thread, which is the single place
    /// this model is ever touched.
    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        var framing: StageFraming = .fullBody
        private let fixture: Live2DDevFixture
        private let onUnavailable: () -> Void
        private var model: JoiLive2DModel?
        private var queue: MTLCommandQueue?
        private var lastFrame: CFTimeInterval?
        private var reportedUnavailable = false
        private var rendererPrepared = false

        private weak var amplitude: SpeechPlayer?

        init(
            fixture: Live2DDevFixture,
            amplitude: SpeechPlayer?,
            onUnavailable: @escaping () -> Void
        ) {
            self.fixture = fixture
            self.amplitude = amplitude
            self.onUnavailable = onUnavailable
            super.init()
        }

        /// Look-at follows the finger while it is down and recentres on release,
        /// so the character does not stare at wherever the last touch ended.
        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            switch recognizer.state {
            case .began, .changed:
                let point = recognizer.location(in: view)
                let (x, y) = Self.modelPoint(point, in: view.bounds.size)
                model?.setLookTargetX(x, y: y)
            case .ended, .cancelled, .failed:
                model?.setLookTargetX(0, y: 0)
                // A flick is a gesture the model may declare a motion for.
                let velocity = recognizer.velocity(in: view)
                if abs(velocity.y) > 900, abs(velocity.y) > abs(velocity.x) {
                    _ = model?.startMotion(inGroup: velocity.y < 0 ? "FlickUp" : "FlickDown", index: 0)
                } else if abs(velocity.x) > 900 {
                    _ = model?.startMotion(inGroup: "Flick", index: 0)
                }
            default:
                break
            }
        }

        /// A tap inside a declared hit area plays that area's motion; elsewhere it
        /// plays the general tap motion. A model that declares neither simply does
        /// nothing, which is why the return value is checked.
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let model, let view = recognizer.view else { return }
            let (x, y) = Self.modelPoint(recognizer.location(in: view), in: view.bounds.size)
            if model.hitTestArea("Body", atX: x, y: y) {
                if model.startMotion(inGroup: "Tap@Body", index: 0) { return }
            }
            _ = model.startMotion(inGroup: "Tap", index: 0)
        }

        /// Converts a view point into the model's own -1...1 space, undoing the
        /// same scale the draw pass applies so a tap lands where it looks.
        private static func modelPoint(_ point: CGPoint, in size: CGSize) -> (Float, Float) {
            guard size.width > 0, size.height > 0 else { return (0, 0) }
            let clipX = Float(point.x / size.width) * 2 - 1
            // View y grows downward; model y grows upward.
            let clipY = 1 - Float(point.y / size.height) * 2
            let zoom = StageFraming.fullBody.modelZoom
            let scaleX = zoom * Float(size.height / size.width)
            return (clipX / max(scaleX, 0.0001), clipY / max(zoom, 0.0001))
        }

        func attach(to view: MTKView) {
            guard let device = view.device, let queue = device.makeCommandQueue() else {
                return report(.noMetalDevice)
            }
            self.queue = queue
            JoiLive2DModel.configureRenderDevice(device)
            let loaded: JoiLive2DModel
            do {
                loaded = try JoiLive2DModel(
                    modelDirectory: fixture.directory,
                    model3FileName: fixture.model3
                )
            } catch {
                return report(.modelRejected)
            }
            let facts = loaded.facts
            live2dLog.notice("""
                live2d model loaded: canvas \(facts.canvasWidth, privacy: .public)x\
                \(facts.canvasHeight, privacy: .public) ppu \(facts.pixelsPerUnit, privacy: .public) \
                parameters \(facts.parameterCount, privacy: .public) parts \
                \(facts.partCount, privacy: .public) drawables \(facts.drawableCount, privacy: .public) \
                idleMotions \(facts.idleMotionCount, privacy: .public) expressions \
                \(facts.expressionCount, privacy: .public) eyeBlink \(facts.hasEyeBlink, privacy: .public) \
                breath \(facts.hasBreath, privacy: .public) physics \(facts.hasPhysics, privacy: .public) \
                pose \(facts.hasPose, privacy: .public)
                """)
            self.model = loaded
        }

        func shutdown() {
            model?.shutdown()
            model = nil
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let model,
                  let queue,
                  let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let buffer = queue.makeCommandBuffer() else {
                return
            }

            // The clipping-mask buffer needs the real drawable size, which is not
            // known until the view has laid out, so the renderer is created here
            // rather than at attach time.
            if !rendererPrepared {
                guard let device = view.device,
                      model.prepareRenderer(
                        with: device,
                        maskWidth: UInt(view.drawableSize.width),
                        maskHeight: UInt(view.drawableSize.height)
                      ) else {
                    self.model = nil
                    model.shutdown()
                    return report(.rendererOrTexturesRejected)
                }
                rendererPrepared = true
            }

            let now = CACurrentMediaTime()
            let delta = lastFrame.map { min(now - $0, 0.1) } ?? 0
            lastFrame = now
            // Mouth opening comes from the audio actually playing, so silence
            // closes it without any separate bookkeeping.
            model.setLipSyncValue(amplitude?.currentAmplitude ?? 0)
            model.update(withDelta: delta)

            let width = Float(view.drawableSize.width)
            let height = Float(view.drawableSize.height)
            guard width > 0, height > 0 else { return }
            // A square model canvas is fitted to the viewport height, so the
            // character fills the stage and its transparent side margins are what
            // gets cropped. Aspect is preserved because scaleX * width equals
            // scaleY * height.
            let zoom = framing.modelZoom
            let scaleY = zoom
            let scaleX = zoom * height / width
            let viewport = MTLViewport(
                originX: 0, originY: 0,
                width: Double(width), height: Double(height),
                znear: 0, zfar: 1
            )
            model.draw(
                with: buffer,
                renderPassDescriptor: descriptor,
                viewport: viewport,
                scaleX: scaleX,
                scaleY: scaleY,
                translateY: framing.modelTranslateY
            )
            buffer.present(drawable)
            buffer.commit()
        }

        private func report(_ reason: Live2DUnavailableReason) {
            guard !reportedUnavailable else { return }
            reportedUnavailable = true
            live2dLog.error("live2d stage unavailable: \(reason.rawValue, privacy: .public)")
            onUnavailable()
        }
    }
}

extension StageFraming {
    /// Model-space zoom. Half body magnifies and shifts the model down so the
    /// face lands in the upper third of the stage.
    var modelZoom: Float {
        switch self {
        case .fullBody: 1.0
        case .halfBody: 1.9
        }
    }

    var modelTranslateY: Float {
        switch self {
        case .fullBody: 0
        case .halfBody: -0.65
        }
    }
}
