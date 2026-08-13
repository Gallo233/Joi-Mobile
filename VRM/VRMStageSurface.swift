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
/// The model comes from the installer-issued content access, so this surface can
/// only ever draw a character the session actually activated. Loading is
/// asynchronous; until it completes the view draws nothing and the stage keeps
/// showing its own background rather than a flash of empty scene.
struct VRMStageSurface: UIViewRepresentable {
    let entryURL: URL
    let framing: StageFraming
    let onUnavailable: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(entryURL: entryURL, onUnavailable: onUnavailable)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
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
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        coordinator.shutdown()
    }

    /// Owns the renderer. `VRMRenderer.draw(in:)` is main-actor isolated, and
    /// MTKView delegate callbacks arrive on the main thread, so the renderer is
    /// only ever touched from one place.
    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        var framing: StageFraming = .fullBody
        private let entryURL: URL
        private let onUnavailable: () -> Void
        private var renderer: VRMRenderer?
        private var queue: MTLCommandQueue?
        private var loadTask: Task<Void, Never>?
        private var reportedUnavailable = false

        init(entryURL: URL, onUnavailable: @escaping () -> Void) {
            self.entryURL = entryURL
            self.onUnavailable = onUnavailable
            super.init()
        }

        func attach(to view: MTKView) {
            guard let device = view.device, let queue = device.makeCommandQueue() else {
                return report(.noMetalDevice)
            }
            self.queue = queue
            loadTask = Task { [weak self] in
                guard let self else { return }
                do {
                    // Parsing and GPU upload of a 25 MB avatar must not block the
                    // first frames of the surface.
                    let model = try await VRMModel.load(from: entryURL, device: device)
                    guard !Task.isCancelled else { return }
                    let renderer = VRMRenderer(device: device)
                    renderer.loadModel(model)
                    self.renderer = renderer
                    vrmLog.notice("vrm model loaded and renderer ready")
                } catch {
                    report(.modelRejected)
                }
            }
        }

        func shutdown() {
            loadTask?.cancel()
            loadTask = nil
            renderer = nil
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
            // Without these the camera sits at the origin, inside the model, which
            // renders as a few stretched fragments. The renderer has no implicit
            // camera: the host owns framing entirely.
            renderer.projectionMatrix = Self.perspective(
                fovRadians: 45 * .pi / 180,
                aspect: Float(size.width / size.height),
                near: 0.01,
                far: 100
            )
            renderer.viewMatrix = Self.lookAt(
                eye: framing.vrmCameraPosition,
                center: framing.vrmCameraTarget
            )
            renderer.draw(in: view, commandBuffer: buffer, renderPassDescriptor: descriptor)
            buffer.present(drawable)
            buffer.commit()
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
