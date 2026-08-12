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
    let onUnavailable: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(fixture: fixture, onUnavailable: onUnavailable)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
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

        init(fixture: Live2DDevFixture, onUnavailable: @escaping () -> Void) {
            self.fixture = fixture
            self.onUnavailable = onUnavailable
            super.init()
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
