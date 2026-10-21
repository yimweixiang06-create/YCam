import SwiftUI
import AVFoundation
import Photos
import UIKit

// MARK: - 状态与版式

private enum Sheet: Equatable {
    case closed, drawer, styles, custom, exposure
}

/// 版式：所有坐标都按你发的 iOS 26 截图量出来，再按屏幕宽度等比缩放（基准 402 × 874 pt）。
private struct Metrics {
    let size: CGSize
    let top: CGFloat
    let s: CGFloat

    init(size: CGSize, topInset: CGFloat) {
        let scale = size.width / 402
        self.size = size
        self.s = scale
        self.top = max(topInset, 54 * scale)
    }

    var W: CGFloat { size.width }
    var H: CGFloat { size.height }
    var capsuleCenterY: CGFloat { top + 35 * s }          // 右上角胶囊
    var vfTop: CGFloat { top + 69 * s }                   // 4:3 取景器上沿
    var vfHeight: CGFloat { W * 4 / 3 }
    var vfBottom: CGFloat { vfTop + vfHeight }
    var expandCenterY: CGFloat { vfBottom - 37 * s }      // 取景器下沿的“展开”按钮
    var shutterCenterY: CGFloat { H - 149 * s }
    var rowCenterY: CGFloat { H - 52 * s }                // 缩略图 / 模式切换 / 翻转 所在行

    func panelHeight(_ sheet: Sheet) -> CGFloat {
        switch sheet {
        case .closed: return 0
        case .drawer: return 246 * s
        case .styles: return 200 * s
        case .custom: return 246 * s
        case .exposure: return 140 * s
        }
    }
}

private struct GridLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 1...2 {
            let x = rect.minX + rect.width * CGFloat(i) / 3
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            let y = rect.minY + rect.height * CGFloat(i) / 3
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

// MARK: - 主界面

struct CameraHomeView: View {
    @StateObject private var camera = CameraModel()
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var glassNS

    @State private var sheet: Sheet = .closed       // ⋯ 抽屉 / 风格面板 / 自定义 / 曝光
    @State private var expanded = false           // 取景器全屏（4:3 ⇄ 全屏）
    @State private var gridOn = false
    @State private var modeDrag: CGFloat = 0      // 视频 / 照片 切换条里“透镜”的拖动偏移
    @State private var modeDragging = false
    @State private var flashOverlay = false       // 快门反馈（短暂变暗）
    @State private var showDiagnostics = false    // 长按右上角“⋯”打开诊断日志

    var body: some View {
        GeometryReader { geo in
            let m = Metrics(size: geo.size, topInset: geo.safeAreaInsets.top)
            ZStack {
                Color.black
                previewLayer(m)
                if gridOn { gridLayer(m) }
                touchLayer()
                Color.black
                    .opacity(flashOverlay ? 0.85 : 0)
                    .allowsHitTesting(false)
                controlsLayer(m)
                toastLayer(m)
                permissionOverlay
            }
            .frame(width: m.W, height: m.H)
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
        .task { await camera.requestAndStart() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await camera.requestAndStart() }
            default:
                camera.sceneWillResignActive()
            }
        }
        .onChange(of: camera.shutterPulse) { _, _ in
            flashOverlay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.2)) { flashOverlay = false }
            }
        }
    }

    // MARK: 取景器

    private var framed: Bool { camera.mode == .photo && !expanded }

    private func previewLayer(_ m: Metrics) -> some View {
        let height = framed ? m.vfHeight : m.H
        let centerY = framed ? m.vfTop + m.vfHeight / 2 : m.H / 2
        return FilteredCameraPreview(camera: camera)
            .frame(width: m.W, height: height)
            .clipped()
            .position(x: m.W / 2, y: centerY)
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: framed)
    }

    private func gridLayer(_ m: Metrics) -> some View {
        let height = framed ? m.vfHeight : m.H
        let centerY = framed ? m.vfTop + m.vfHeight / 2 : m.H / 2
        return GridLines()
            .stroke(Color.white.opacity(0.38), lineWidth: 0.6)
            .frame(width: m.W, height: height)
            .position(x: m.W / 2, y: centerY)
            .allowsHitTesting(false)
    }

    /// 全屏触摸层：左右滑 = 切换 视频 / 照片；向上滑 = 打开 ⋯ 抽屉；向下滑 / 点按 = 收起面板。
    private func touchLayer() -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                if sheet != .closed { go(.closed) }
            }
            .gesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) > 60, abs(dx) > abs(dy) * 1.5 {
                        selectMode(dx > 0 ? .video : .photo)      // 向右滑 = 视频（与系统相机一致）
                    } else if dy < -60, abs(dy) > abs(dx) * 1.5, sheet == .closed {
                        go(.drawer)
                    } else if dy > 60, abs(dy) > abs(dx) * 1.5, sheet != .closed {
                        go(.closed)
                    }
                }
            )
    }

    // MARK: 控件层

    private func controlsLayer(_ m: Metrics) -> some View {
        ZStack {
            topCapsule(m)
                .position(x: m.W - 73 * m.s, y: m.capsuleCenterY)
            if camera.isRecording {
                recordingBadge
                    .position(x: m.W / 2, y: m.capsuleCenterY)
            }
            if camera.mode == .photo && sheet == .closed {
                expandButton(m)
                    .position(x: m.W / 2, y: m.expandCenterY)
            }
            bottomControls(m)
            GlassGroup(spacing: 20) {
                sheetPanel(m)
            }
        }
        .frame(width: m.W, height: m.H)
        .foregroundStyle(Color.white)
    }

    // MARK: 右上角胶囊：闪光灯 / 实况 / 更多

    private var liveEffective: Bool {
        camera.livePhotoSupported && camera.livePhotoEnabled && camera.styleSettings.isIdentity && !expanded
    }

    private func topCapsule(_ m: Metrics) -> some View {
        HStack(spacing: 0) {
            Button { camera.toggleFlash() } label: {
                flashGlyph(m)
                    .frame(width: 32 * m.s, height: 38 * m.s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassButtonStyle())
            .disabled(!camera.flashAvailable)
            .opacity(camera.flashAvailable ? 1 : 0.45)
            .accessibilityLabel("闪光灯")

            Button { liveTapped() } label: {
                liveGlyph(m)
                    .frame(width: 32 * m.s, height: 38 * m.s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassButtonStyle())
            .accessibilityLabel("实况照片")

            DotGrid(dot: 3.4 * m.s, gap: 3.2 * m.s)
                .frame(width: 32 * m.s, height: 38 * m.s)
                .contentShape(Rectangle())
                .onTapGesture { go(sheet == .closed ? .drawer : .closed) }
                .onLongPressGesture(minimumDuration: 0.8) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showDiagnostics = true
                }
                .accessibilityElement()
                .accessibilityLabel("更多控制")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("长按打开诊断日志")
        }
        .padding(.horizontal, 6 * m.s)
        .frame(width: 108 * m.s, height: 38 * m.s)
        .glassSurface(Capsule(), interactive: true)
    }

    private func flashGlyph(_ m: Metrics) -> some View {
        Image(systemName: camera.flashEnabled ? "bolt.fill" : "bolt.slash.fill")
            .font(.system(size: 16 * m.s, weight: .semibold))
            .foregroundStyle(camera.flashEnabled ? Color.yellow : Color.white)
    }

    private func liveGlyph(_ m: Metrics) -> some View {
        let on = liveEffective
        return ZStack(alignment: .bottomTrailing) {
            Image(systemName: on ? "livephoto" : "livephoto.slash")
                .font(.system(size: 17 * m.s, weight: .semibold))
                .foregroundStyle(Color.white)
            if on {
                Text("A")
                    .font(.system(size: 7.5 * m.s, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .frame(width: 11 * m.s, height: 11 * m.s)
                    .background(Circle().fill(Color.white))
                    .offset(x: 4 * m.s, y: 4 * m.s)
            }
        }
    }

    private func liveTapped() {
        guard camera.mode == .photo else {
            camera.message = "实况照片只能在照片模式使用"
            return
        }
        guard camera.livePhotoSupported else {
            camera.message = "此设备或当前设置不支持实况照片"
            return
        }
        if !camera.styleSettings.isIdentity || expanded {
            camera.message = "使用摄影风格或全屏取景时，实况照片会自动关闭"
            return
        }
        camera.livePhotoEnabled.toggle()
        camera.message = camera.livePhotoEnabled ? "实况照片已开启" : "实况照片已关闭"
    }

    private var recordingBadge: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(camera.recordingStart ?? context.date)))
            HStack(spacing: 7) {
                Circle().fill(Color.red).frame(width: 9, height: 9)
                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                    .font(.system(.callout, design: .rounded).monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassSurface(Capsule())
        }
    }

    // MARK: 取景器下沿的“展开”按钮

    private func expandButton(_ m: Metrics) -> some View {
        Button { toggleExpanded() } label: {
            Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13 * m.s, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 38 * m.s, height: 38 * m.s)
                .glassSurface(Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(GlassButtonStyle())
        .accessibilityLabel(expanded ? "收起取景器（4:3）" : "展开取景器（全屏）")
    }

    private func toggleExpanded() {
        guard camera.mode == .photo else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { expanded.toggle() }
    }

    // MARK: 快门 / 缩略图 / 视频·照片 / 翻转

    private func bottomControls(_ m: Metrics) -> some View {
        let idle = sheet == .closed
        let panelTop = m.H - 8 * m.s - m.panelHeight(sheet)
        let shutterY = idle ? m.shutterCenterY : panelTop - 67 * m.s     // 面板打开时快门上移，停在面板上方
        return Group {
            shutterButton(m)
                .position(x: m.W / 2, y: shutterY)
                .opacity(sheet == .drawer ? 0 : 1)
                .allowsHitTesting(sheet != .drawer)
            thumbnailButton(m)
                .position(x: 60 * m.s, y: m.rowCenterY)
                .opacity(idle ? 1 : 0)
                .allowsHitTesting(idle)
            modePill(m)
                .position(x: m.W / 2, y: m.rowCenterY)
                .opacity(idle ? 1 : 0)
                .allowsHitTesting(idle)
            flipButton(m)
                .position(x: m.W - 60 * m.s, y: m.rowCenterY)
                .opacity(idle ? 1 : 0)
                .allowsHitTesting(idle)
        }
    }

    private var shutterDisabled: Bool {
        !camera.cameraReady || camera.isCapturingPhoto || camera.isFinalizingVideo
    }

    private func shutterButton(_ m: Metrics) -> some View {
        let outer = 81 * m.s
        let inner = 69 * m.s
        return Button { shutterTapped(m) } label: {
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .frame(width: outer, height: outer)
                    .glassSurface(Circle(), interactive: true)
                RoundedRectangle(cornerRadius: camera.isRecording ? 8 * m.s : inner / 2, style: .continuous)
                    .fill(camera.mode == .video ? Color.red : Color.white)
                    .frame(width: camera.isRecording ? 30 * m.s : inner,
                           height: camera.isRecording ? 30 * m.s : inner)
                    .animation(.spring(response: 0.25, dampingFraction: 0.78), value: camera.isRecording)
            }
            .frame(width: outer, height: outer)
            .contentShape(Circle())
        }
        .buttonStyle(GlassButtonStyle())
        .disabled(shutterDisabled)
        .opacity(shutterDisabled && !camera.isFinalizingVideo ? 0.5 : 1)
        .accessibilityLabel(shutterLabel)
    }

    private var shutterLabel: String {
        switch camera.mode {
        case .photo: return "拍照"
        case .video: return camera.isRecording ? "停止录制" : "开始录制"
        }
    }

    private func shutterTapped(_ m: Metrics) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        switch camera.mode {
        case .photo:
            camera.capturePhoto(cropAspect: expanded ? m.W / m.H : nil)   // 全屏取景时成片按所见裁剪
        case .video:
            if camera.isRecording {
                camera.stopRecording()
            } else {
                camera.startRecording()
            }
        }
    }

    private func thumbnailButton(_ m: Metrics) -> some View {
        Button { camera.openPhotos() } label: {
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 48 * m.s, height: 48 * m.s)
                    .glassSurface(Circle(), interactive: true)
                Group {
                    if let image = camera.lastThumbnail {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 18 * m.s, weight: .medium))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 43 * m.s, height: 43 * m.s)
                .clipShape(Circle())
            }
            .frame(width: 48 * m.s, height: 48 * m.s)
            .contentShape(Circle())
        }
        .buttonStyle(GlassButtonStyle())
        .accessibilityLabel("打开照片图库")
    }

    private func flipButton(_ m: Metrics) -> some View {
        let enabled = camera.cameraReady && !camera.isRecording && !camera.isCapturingPhoto && !camera.isFinalizingVideo
        return Button { camera.flipCamera() } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 19 * m.s, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 48 * m.s, height: 48 * m.s)
                .glassSurface(Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(GlassButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel("切换前后镜头")
    }

    /// 视频 | 照片：文字固定，官方 Liquid Glass“透镜”跟手指滑动，松手后吸附到最近的一项。
    private func modePill(_ m: Metrics) -> some View {
        let modes = CaptureMode.allCases
        let labelW = 71 * m.s
        let index = modes.firstIndex(of: camera.mode) ?? 0
        let lensOffset = (CGFloat(index) - 0.5) * labelW + modeDrag
        return ZStack {
            Capsule()
                .fill(Color.clear)
                .frame(width: labelW * 2 + 8 * m.s, height: 48 * m.s)
                .glassSurface(Capsule())
            Capsule()
                .fill(Color.clear)
                .frame(width: labelW, height: 40 * m.s)
                .glassSurface(Capsule(), interactive: true, lens: true)
                .legacyPressScale(modeDragging)
                .offset(x: lensOffset)
            HStack(spacing: 0) {
                ForEach(modes) { item in
                    Text(item.rawValue)
                        .font(.system(size: 15 * m.s, weight: .semibold))
                        .foregroundStyle(item == camera.mode ? Color.yellow : Color.white)
                        .frame(width: labelW, height: 40 * m.s)
                        .contentShape(Rectangle())
                        .onTapGesture { selectMode(item) }
                        .accessibilityLabel(item.rawValue)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(item == camera.mode ? .isSelected : [])
                }
            }
        }
        .frame(width: labelW * 2 + 8 * m.s, height: 48 * m.s)
        .contentShape(Capsule())
        .gesture(modeDragGesture(labelW: labelW, index: index))
    }

    private func modeDragGesture(labelW: CGFloat, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                modeDragging = true
                let low = -CGFloat(index) * labelW
                let high = CGFloat(1 - index) * labelW
                modeDrag = min(high, max(low, value.translation.width))
            }
            .onEnded { value in
                modeDragging = false
                let projected = value.translation.width + 0.3 * (value.predictedEndTranslation.width - value.translation.width)
                let modes = CaptureMode.allCases
                let target = min(modes.count - 1, max(0, Int((CGFloat(index) + projected / labelW).rounded())))
                withAnimation(.snappy(duration: 0.25)) { modeDrag = 0 }
                selectMode(modes[target])
            }
    }

    private func selectMode(_ target: CaptureMode) {
        guard target != camera.mode else { return }
        if camera.isRecording || camera.isFinalizingVideo || camera.isCapturingPhoto {
            camera.message = "正在拍摄或录制，完成后才能切换模式"
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy(duration: 0.25)) {
            sheet = .closed
            camera.setMode(target)
        }
    }

    // MARK: 底部面板（⋯ 抽屉 → 风格 → 自定义 / 曝光）

    private func go(_ target: Sheet) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { sheet = target }
    }

    @ViewBuilder
    private func sheetPanel(_ m: Metrics) -> some View {
        switch sheet {
        case .closed:
            EmptyView()
        case .drawer:
            panel(m, height: m.panelHeight(.drawer)) { drawerContent(m) }
        case .styles:
            panel(m, height: m.panelHeight(.styles)) { stylesContent(m) }
        case .custom:
            panel(m, height: m.panelHeight(.custom)) { customContent(m) }
        case .exposure:
            panel(m, height: m.panelHeight(.exposure)) { exposureContent(m) }
        }
    }

    /// 所有面板共用同一个玻璃 ID：在 iOS 26 上互相“液态变形”，iOS 18 上用磨砂底板做近似过渡。
    private func panel<Content: View>(_ m: Metrics, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: m.W - 18 * m.s, height: height)
            .background(alignment: .top) {
                Color.clear
                    .frame(height: 64 * m.s)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 14).onEnded { value in
                            if value.translation.height > 36 { go(.closed) }       // 向下滑收起
                        }
                    )
            }
            .glassSurface(RoundedRectangle(cornerRadius: 38 * m.s, style: .continuous),
                          morph: GlassMorph(id: "sheet", namespace: glassNS))
            .position(x: m.W / 2, y: m.H - 8 * m.s - height / 2)
    }

    // MARK: ⋯ 抽屉

    private func drawerContent(_ m: Metrics) -> some View {
        let d = 58 * m.s
        return VStack(spacing: 14 * m.s) {
            Capsule()
                .fill(Color.white.opacity(0.45))
                .frame(width: 36 * m.s, height: 4 * m.s)
            HStack(alignment: .top, spacing: 0) {
                drawerButton("闪光灯", diameter: d, active: camera.flashEnabled, enabled: camera.flashAvailable) {
                    camera.toggleFlash()
                } icon: {
                    Image(systemName: camera.flashEnabled ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 22 * m.s, weight: .semibold))
                }
                drawerButton("实况", diameter: d, active: liveEffective, enabled: camera.mode == .photo && camera.livePhotoSupported) {
                    liveTapped()
                } icon: {
                    Image(systemName: liveEffective ? "livephoto" : "livephoto.slash")
                        .font(.system(size: 24 * m.s, weight: .semibold))
                }
                drawerButton("宽高比", diameter: d, active: expanded, enabled: camera.mode == .photo) {
                    toggleExpanded()
                } icon: {
                    Text(expanded ? "全屏" : "4:3")
                        .font(.system(size: 16 * m.s, weight: .bold))
                }
            }
            HStack(alignment: .top, spacing: 0) {
                drawerButton("曝光", diameter: d, active: abs(camera.styleSettings.exposure) > 0.01, enabled: true) {
                    go(.exposure)
                } icon: {
                    Image(systemName: "plusminus")
                        .font(.system(size: 24 * m.s, weight: .semibold))
                }
                drawerButton("风格", diameter: d, active: !camera.styleSettings.isIdentity, enabled: true) {
                    go(.styles)
                } icon: {
                    DotGrid(columns: 3, rows: 3, dot: 3.8 * m.s, gap: 3.4 * m.s,
                            color: camera.styleSettings.isIdentity ? Color.white : Color.yellow)
                }
                drawerButton("网格", diameter: d, active: gridOn, enabled: true) {
                    gridOn.toggle()
                } icon: {
                    Image(systemName: "squareshape.split.3x3")
                        .font(.system(size: 24 * m.s, weight: .medium))
                }
            }
        }
        .padding(.horizontal, 10 * m.s)
        .padding(.top, 10 * m.s)
        .padding(.bottom, 14 * m.s)
    }

    private func drawerButton<Icon: View>(_ title: String,
                                          diameter: CGFloat,
                                          active: Bool,
                                          enabled: Bool,
                                          action: @escaping () -> Void,
                                          @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                icon()
                    .foregroundStyle(active ? Color.yellow : Color.white)
                    .frame(width: diameter, height: diameter)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(title)
    }

    // MARK: 风格面板（标题 + 圆点指示 + 卡片轮播 + 自定义）

    private func stylesContent(_ m: Metrics) -> some View {
        VStack(spacing: 8 * m.s) {
            panelHeader(m, onBack: { go(.drawer) }, reset: nil) {
                Text(camera.styleSettings.style.title)
                    .font(.system(size: 14 * m.s, weight: .medium))
                    .foregroundStyle(Color.white)
            }
            Circle()
                .fill(Color.white)
                .frame(width: 5 * m.s, height: 5 * m.s)
            StyleCarousel(selected: $camera.styleSettings.style,
                          cardWidth: 41 * m.s,
                          cardHeight: 52 * m.s,
                          spacing: 8 * m.s)
            Button { go(.custom) } label: {
                Text("自定义")
                    .font(.system(size: 13 * m.s, weight: .medium))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 20 * m.s)
                    .frame(height: 30 * m.s)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .contentShape(Capsule())
            }
            .buttonStyle(GlassButtonStyle())
        }
        .padding(.horizontal, 12 * m.s)
        .padding(.vertical, 12 * m.s)
    }

    // MARK: 自定义（色调 / 颜色 / 调色板）

    private func customContent(_ m: Metrics) -> some View {
        let settings = camera.styleSettings
        let tone = Int(((0.5 - settings.point.y) * 200).rounded())
        let color = Int(((settings.point.x - 0.5) * 200).rounded())
        let palette = Int((settings.intensity * 100).rounded())
        return VStack(spacing: 10 * m.s) {
            panelHeader(m, onBack: { go(.styles) }, reset: { resetStyle() }) {
                HStack(spacing: 12 * m.s) {
                    valueLabel("色调", tone, m)
                    valueLabel("颜色", color, m)
                    valueLabel("调色板", palette, m)
                }
            }
            DotPalette(point: $camera.styleSettings.point, colors: settings.style.cardColors)
                .frame(width: 132 * m.s, height: 132 * m.s)
            TickSlider(value: $camera.styleSettings.intensity)
                .frame(width: 200 * m.s)
        }
        .padding(.horizontal, 12 * m.s)
        .padding(.vertical, 12 * m.s)
    }

    private func valueLabel(_ title: String, _ value: Int, _ m: Metrics) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12 * m.s))
                .foregroundStyle(Color.white.opacity(0.6))
            Text(value == 0 ? "00" : "\(value)")
                .font(.system(size: 12 * m.s, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.white)
        }
    }

    private func resetStyle() {
        camera.styleSettings = StyleSettings()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: 曝光

    private func exposureContent(_ m: Metrics) -> some View {
        VStack(spacing: 14 * m.s) {
            panelHeader(m, onBack: { go(.drawer) }, reset: { camera.styleSettings.exposure = 0 }) {
                Text("曝光 \(String(format: "%+.1f", camera.styleSettings.exposure)) EV")
                    .font(.system(size: 14 * m.s, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white)
            }
            HStack(spacing: 10) {
                Text("−").font(.system(size: 17, weight: .medium)).opacity(0.8)
                Slider(value: $camera.styleSettings.exposure, in: -1.5...1.5, step: 0.1)
                    .tint(Color.yellow)
                Text("+").font(.system(size: 17, weight: .medium)).opacity(0.8)
            }
            .padding(.horizontal, 14 * m.s)
        }
        .padding(.horizontal, 12 * m.s)
        .padding(.vertical, 12 * m.s)
    }

    // MARK: 面板通用头部

    private func panelHeader<Center: View>(_ m: Metrics,
                                           onBack: @escaping () -> Void,
                                           reset: (() -> Void)?,
                                           @ViewBuilder center: () -> Center) -> some View {
        ZStack {
            center()
            HStack {
                flatCircleButton("chevron.left", size: 34 * m.s, label: "返回", action: onBack)
                Spacer()
                if let reset {
                    flatCircleButton("arrow.counterclockwise", size: 34 * m.s, label: "重置", action: reset)
                }
            }
        }
    }

    private func flatCircleButton(_ systemName: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(GlassButtonStyle())
        .accessibilityLabel(label)
    }

    // MARK: 提示 / 权限

    @ViewBuilder
    private func toastLayer(_ m: Metrics) -> some View {
        if let text = camera.message {
            Text(text)
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(maxWidth: m.W - 48 * m.s)
                .position(x: m.W / 2, y: m.capsuleCenterY + 62 * m.s)
                .transition(.opacity)
                .allowsHitTesting(false)
                .task(id: text) {
                    try? await Task.sleep(nanoseconds: 2_600_000_000)
                    if camera.message == text {
                        withAnimation(.easeInOut(duration: 0.25)) { camera.message = nil }
                    }
                }
        }
    }

    @ViewBuilder
    private var permissionOverlay: some View {
        if camera.permission == .denied {
            ZStack {
                Color.black.opacity(0.55)
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill").font(.system(size: 34))
                    Text("需要相机权限").font(.title3.weight(.semibold))
                    Text("YCam 需要使用相机才能取景、拍照和录像。请在系统设置中允许相机权限。")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .opacity(0.85)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("打开设置")
                            .font(.headline)
                            .padding(.horizontal, 28)
                            .frame(height: 48)
                            .glassSurface(Capsule(), interactive: true)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(GlassButtonStyle())
                }
                .foregroundStyle(Color.white)
                .padding(24)
                .glassSurface(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .padding(32)
            }
        }
    }
}
