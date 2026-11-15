import SwiftUI
import AVFoundation

/// 显示“已套用风格”的实时画面。
/// 旧版本用 AVCaptureVideoPreviewLayer，只能显示原始画面，所以预览不会随风格变化；
/// 现在预览、照片、视频都使用 FilterEngine 处理后的同一路画面。
final class FilteredPreviewView: UIView {
    // Keep the SwiftUI container fixed; rotate only the preview sublayer.
    // This avoids rotating/re-rendering every 4K frame in software.
    let displayLayer = AVSampleBufferDisplayLayer()
    private var mirrored = false
    private var lastOrientation: UIInterfaceOrientation = .portrait

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        displayLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDisplayGeometry()
    }

    func setMirrored(_ newValue: Bool) {
        guard mirrored != newValue else { return }
        mirrored = newValue
        updateDisplayGeometry()
    }

    func setOrientation(_ newValue: UIInterfaceOrientation) {
        let resolved: UIInterfaceOrientation = newValue == .unknown ? .portrait : newValue
        guard lastOrientation != resolved else { return }
        lastOrientation = resolved
        updateDisplayGeometry()
    }

    private func updateDisplayGeometry() {
        let landscape = lastOrientation.isLandscape
        let rotation: CGFloat
        switch lastOrientation {
        case .landscapeLeft: rotation = -.pi / 2
        case .landscapeRight: rotation = .pi / 2
        default: rotation = 0
        }
        let mirror = CGAffineTransform(scaleX: mirrored ? -1 : 1, y: 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.bounds = CGRect(origin: .zero,
            size: landscape ? CGSize(width: bounds.height, height: bounds.width) : bounds.size)
        displayLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        displayLayer.setAffineTransform(CGAffineTransform(rotationAngle: rotation).concatenating(mirror))
        CATransaction.commit()
    }
}

struct FilteredCameraPreview: UIViewRepresentable {
    @ObservedObject var camera: CameraModel

    func makeUIView(context: Context) -> FilteredPreviewView {
        let view = FilteredPreviewView()
        camera.attach(displayLayer: view.displayLayer)
        return view
    }

    func updateUIView(_ view: FilteredPreviewView, context: Context) {
        // 取景框的形状由 SwiftUI 决定（照片 4:3 / 视频与展开状态全屏），这里始终铺满，所见即所得。
        view.displayLayer.videoGravity = .resizeAspectFill
        view.setMirrored(camera.position == .front)
        let orientation = view.window?.windowScene?.interfaceOrientation
            ?? UIApplication.shared.connectedScenes.compactMap {
                ($0 as? UIWindowScene)?.interfaceOrientation
            }.first ?? .portrait
        view.setOrientation(orientation)
    }
}

/// 全屏透明触摸层（UIKit 手势）：点按 / 单指滑动 / 双指捏合变焦。
struct TouchCatcher: UIViewRepresentable {
    var onTap: (CGPoint) -> Void
    var onSwipe: (CGSize) -> Void
    var onPinchBegan: () -> Void
    var onPinchChanged: (CGFloat) -> Void
    var onPinchEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        let coordinator = context.coordinator
        coordinator.parent = self
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:)))
        for recognizer in [tap, pan, pinch] as [UIGestureRecognizer] {
            recognizer.delegate = coordinator
            view.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TouchCatcher?
        private var lastZoomUpdate = 0.0

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            parent?.onTap(gesture.location(in: gesture.view))
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view else { return }
            let t = gesture.translation(in: view)
            parent?.onSwipe(CGSize(width: t.x, height: t.y))
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                lastZoomUpdate = 0
                parent?.onPinchBegan()
            case .changed:
                // Limit expensive AVCaptureDevice configuration while keeping gesture responsive.
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastZoomUpdate >= (1.0 / 45.0) {
                    lastZoomUpdate = now
                    parent?.onPinchChanged(gesture.scale)
                }
            case .ended, .cancelled, .failed:
                // The last position must always be applied, even after coalesced updates.
                if gesture.state == .ended { parent?.onPinchChanged(gesture.scale) }
                parent?.onPinchEnded()
            default: break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
