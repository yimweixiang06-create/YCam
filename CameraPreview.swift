import SwiftUI
import AVFoundation

/// 显示“已套用风格”的实时画面。
/// 旧版本用 AVCaptureVideoPreviewLayer，只能显示原始画面，所以预览不会随风格变化；
/// 现在预览、照片、视频都使用 FilterEngine 处理后的同一路画面。
final class FilteredPreviewView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 前置镜头的取景画面做镜像（与系统相机一致）；保存的照片 / 视频不镜像。
    func setMirrored(_ mirrored: Bool) {
        let target: CGAffineTransform = mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        guard displayLayer.affineTransform() != target else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.setAffineTransform(target)
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
    }
}
