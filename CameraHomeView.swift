import SwiftUI
import AVFoundation
import Photos
import UIKit

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

private struct FocusMark: Equatable {
    let id = UUID()
    let point: CGPoint
}

// MARK: - 主界面

struct CameraHomeView: View {
    @StateObject private var camera = CameraModel()
    @StateObject private var layout = ControlLayout()
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var glassNS

    @State private var sheet: Sheet = .closed
    @State private var gridOn = false
    @State private var modeDrag: CGFloat = 0
    @State private var modeDragging = false
    @State private var flashOverlay = false
    @State private var showDiagnostics = false
    @State private var pinchStart: CGFloat?
    @State private var focusMark: FocusMark?

    var body: some View {
        GeometryReader { geo in
            let m = UIMetrics(size: geo.size, topInset: geo.safeAreaInsets.top, bottomInset: geo.safeAreaInsets.bottom)
            ZStack {
                Color.black
                previewLayer(m)
                if gridOn { gridLayer(m) }
                touchLayer(m)
                Color.black
                    .opacity(flashOverlay ? 0.85 : 0)
                    .allowsHitTesting(false)
                overlays(m)
                controlsLayer(m)
                timerOverlay
                toastLayer(m)
                permissionOverlay
            }
            .frame(width: m.W, height: m.H)
        }
        .ignoresSafeArea()
        .statusBarHidden()
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
        .onChange(of: camera.isRecording) { _, recording in
            if recording { sheet = .closed }
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView()
        }
    }

    // MARK: 取景器

    private var hasPinned: Bool { !layout.pinned.isEmpty }
    private var isFramed: Bool { camera.mode != .video && camera.aspect != .full }

    private func previewFrame(_ m: UIMetrics) -> CGRect {
        guard camera.mode != .video, let ratio = camera.aspect.heightOverWidth else {
            return CGRect(x: 0, y: 0, width: m.W, height: m.H)
        }
        let width = m.vfWidth(pinned: hasPinned)
        let height = width * ratio
        let y = min(m.vfTop(pinned: hasPinned), max(m.top, m.H - height))
        return CGRect(x: (m.W - width) / 2, y: y, width: width, height: height)
    }

    private func previewLayer(_ m: UIMetrics) -> some View {
        let rect = previewFrame(m)
        return FilteredCameraPreview(camera: camera)
            .frame(width: rect.width, height: rect.height)
            .clipped()
            .position(x: rect.midX, y: rect.midY)
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: rect)
    }

    private func gridLayer(_ m: UIMetrics) -> some View {
        let rect = previewFrame(m)
        return GridLines()
            .stroke(Color.white.opacity(0.38), lineWidth: 0.6)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    /// 全屏触摸层：点按 = 对焦 / 收起面板；左右滑 = 切换 视频 · 照片 · 人像；向上滑 = 打开抽屉；向下滑 = 收起；双指捏合 = 变焦。
    private func touchLayer(_ m: UIMetrics) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) > 60, abs(dx) > abs(dy) * 1.5 {
                        stepMode(dx > 0 ? -1 : 1)      // 向右滑 = 上一个模式（与系统相机一致）
                    } else if dy < -60, abs(dy) > abs(dx) * 1.5, sheet == .closed {
                        go(.drawer)
                    } else if dy > 60, abs(dy) > abs(dx) * 1.5, sheet != .closed {
                        go(.closed)
                    }
                }
            )
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    handleTap(value.location, m)
                }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if pinchStart == nil { pinchStart = camera.zoom.display }
                        camera.setZoom(display: (pinchStart ?? 1) * value.magnification)
                    }
                    .onEnded { _ in pinchStart = nil }
            )
    }

    private func handleTap(_ point: CGPoint, _ m: UIMetrics) {
        if sheet != .closed {
            go(.closed)
            return
        }
        let rect = previewFrame(m)
        guard rect.contains(point) else { return }
        camera.focus(atViewPoint: CGPoint(x: point.x - rect.minX, y: point.y - rect.minY), viewSize: rect.size)
        let mark = FocusMark(point: point)
        focusMark = mark
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if focusMark?.id == mark.id {
                withAnimation(.easeOut(duration: 0.2)) { focusMark = nil }
            }
        }
    }

    @ViewBuilder
    private func overlays(_ m: UIMetrics) -> some View {
        if camera.histogramEnabled {
            let rect = previewFrame(m)
            HistogramView(model: camera.histogram, m: m)
                .position(x: rect.minX + 84 * m.s, y: rect.minY + 56 * m.s)
                .allowsHitTesting(false)
        }
        if let mark = focusMark {
            FocusSquare(m: m)
                .id(mark.id)
                .position(mark.point)
        }
    }

    // MARK: 控件层

    private func controlsLayer(_ m: UIMetrics) -> some View {
        let rect = previewFrame(m)
        let rawBase = isFramed ? rect.maxY - 37 * m.s : m.shutterCenterY - 72 * m.s
        let baseY = min(rawBase, m.shutterCenterY - 72 * m.s)        // 展开按钮中心
        let pillsY = baseY - 52 * m.s
        let lightingY = pillsY - 70 * m.s
        return ZStack {
            topCapsule(m)
                .position(x: m.W - 73 * m.s, y: m.capsuleCenterY)
            if sheet == .drawer || sheet == .edit {
                editButton(m)
                    .position(x: 18 * m.s + 33 * m.s, y: m.capsuleCenterY)
            }
            if hasPinned {
                PinnedRow(items: layout.pinned, m: m, spec: { spec($0, m) })
                    .position(x: m.W / 2, y: m.pinnedRowCenterY)
            }
            if camera.isRecording {
                recordingBadge
                    .position(x: m.W / 2, y: m.capsuleCenterY)
            }
            if sheet == .closed {
                ZoomPills(model: camera.zoom, m: m) { stop in
                    camera.setZoom(display: stop.display, ramp: true)
                }
                .position(x: m.W / 2, y: pillsY)
                if camera.mode == .portrait {
                    lightingStrip(m)
                        .position(x: m.W / 2, y: lightingY)
                }
                if camera.mode != .video {
                    expandButton(m)
                        .position(x: m.W / 2, y: baseY)
                }
            }
            bottomControls(m)
            sheetPanel(m)
        }
        .frame(width: m.W, height: m.H)
        .foregroundStyle(Color.white)
    }

    // MARK: 右上角胶囊：闪光灯 / 实况 / 更多

    private var liveEffective: Bool {
        camera.mode == .photo && camera.livePhotoSupported && camera.livePhotoEnabled
            && camera.photoFormat == .heif && camera.photoResolution == .half
            && camera.aspect == .fourThree && camera.styleSettings.depth < 0.001
    }

    private func topCapsule(_ m: UIMetrics) -> some View {
        HStack(spacing: 0) {
            Button { camera.cycleFlash() } label: {
                flashGlyph(m, size: 16)
                    .frame(width: 32 * m.s, height: 38 * m.s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassButtonStyle())
            .disabled(!camera.flashAvailable)
            .opacity(camera.flashAvailable ? 1 : 0.45)
            .accessibilityLabel("闪光灯")

            Button { liveTapped() } label: {
                liveGlyph(m, size: 17)
                    .frame(width: 32 * m.s, height: 38 * m.s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassButtonStyle())
            .accessibilityLabel("实况照片")

            // 点按 = 打开 / 关闭控制抽屉；长按约 1 秒 = 打开诊断日志
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

    private func editButton(_ m: UIMetrics) -> some View {
        Button { go(sheet == .edit ? .drawer : .edit) } label: {
            Text(sheet == .edit ? "完成" : "编辑")
                .font(.system(size: 13 * m.s, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12 * m.s)
                .frame(height: 26 * m.s)
                .glassSurface(Capsule(), interactive: true)
                .frame(minWidth: 66 * m.s, minHeight: 44 * m.s)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassButtonStyle())
        .accessibilityLabel(sheet == .edit ? "完成编辑" : "编辑抽屉里的功能")
    }

    // MARK: 图标

    private func symbol(_ name: String, _ size: CGFloat, _ m: UIMetrics) -> AnyView {
        AnyView(Image(systemName: name).font(.system(size: size * m.s, weight: .semibold)))
    }

    private func badged(_ name: String, badge: String, size: CGFloat, _ m: UIMetrics) -> AnyView {
        AnyView(
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: name)
                    .font(.system(size: size * m.s, weight: .semibold))
                Text(badge)
                    .font(.system(size: 7.5 * m.s, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .frame(width: 11 * m.s, height: 11 * m.s)
                    .background(Circle().fill(Color.white))
                    .offset(x: 4 * m.s, y: 4 * m.s)
            }
        )
    }

    private func flashIcon(_ m: UIMetrics, size: CGFloat) -> AnyView {
        if camera.mode == .video {
            return symbol(camera.flashSetting == .on ? "flashlight.on.fill" : "flashlight.off.fill", size, m)
        }
        switch camera.flashSetting {
        case .auto: return badged("bolt.fill", badge: "A", size: size, m)
        case .on: return symbol("bolt.fill", size, m)
        case .off: return symbol("bolt.slash.fill", size, m)
        }
    }

    private func flashGlyph(_ m: UIMetrics, size: CGFloat) -> some View {
        flashIcon(m, size: size)
            .foregroundStyle(camera.flashSetting == .on ? Color.yellow : Color.white)
    }

    private func liveIcon(_ m: UIMetrics, size: CGFloat) -> AnyView {
        liveEffective ? badged("livephoto", badge: "A", size: size, m) : symbol("livephoto.slash", size, m)
    }

    private func liveGlyph(_ m: UIMetrics, size: CGFloat) -> some View {
        liveIcon(m, size: size).foregroundStyle(Color.white)
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
        if camera.photoFormat == .raw || camera.photoResolution == .max
            || camera.aspect != .fourThree || camera.styleSettings.depth > 0.001 {
            camera.message = "RAW、最大分辨率、非 4:3 取景或景深开启时不能拍实况"
            return
        }
        camera.livePhotoEnabled.toggle()
        camera.message = camera.livePhotoEnabled ? "实况照片已开启（可以配合摄影风格）" : "实况照片已关闭"
        camera.markControlsChanged()
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

    // MARK: 抽屉里每个功能：图标 / 状态 / 动作（抽屉和顶部固定行共用）

    private func spec(_ id: ControlID, _ m: UIMetrics) -> ControlSpec {
        let s = camera.styleSettings
        let photoLike = camera.mode != .video
        switch id {
        case .flash:
            return ControlSpec(title: id.title, icon: flashIcon(m, size: 22), active: camera.flashSetting == .on,
                               enabled: camera.flashAvailable, action: { camera.cycleFlash() })
        case .live:
            return ControlSpec(title: id.title, icon: liveIcon(m, size: 24), active: liveEffective,
                               enabled: camera.mode == .photo && camera.livePhotoSupported, action: { liveTapped() })
        case .aspect:
            return ControlSpec(title: id.title, icon: AnyView(Text(camera.aspect.rawValue).font(.system(size: 16 * m.s, weight: .bold))),
                               active: camera.aspect != .fourThree, enabled: photoLike, action: { go(.aspect) })
        case .timer:
            let icon: AnyView = camera.timerSeconds > 0
                ? AnyView(Text("\(camera.timerSeconds)").font(.system(size: 22 * m.s, weight: .semibold).monospacedDigit()))
                : symbol("timer", 24, m)
            return ControlSpec(title: id.title, icon: icon, active: camera.timerSeconds > 0, enabled: true, action: { go(.timer) })
        case .exposure:
            return ControlSpec(title: id.title, icon: symbol("plusminus", 24, m), active: abs(camera.exposureBias) > 0.01,
                               enabled: true, action: { go(.exposure) })
        case .style:
            let icon = AnyView(DotGrid(columns: 3, rows: 3, dot: 3.8 * m.s, gap: 3.4 * m.s,
                                       color: s.style == .standard && s.isPaletteDefault ? Color.white : Color.yellow))
            return ControlSpec(title: id.title, icon: icon, active: s.style != .standard || !s.isPaletteDefault,
                               enabled: true, action: { go(.styles) })
        case .filter:
            return ControlSpec(title: id.title, icon: symbol("camera.filters", 24, m), active: s.filter != .original,
                               enabled: true, action: { go(.filters) })
        case .depth:
            let icon = AnyView(Text("ƒ").font(.system(size: 28 * m.s, weight: .medium, design: .serif).italic()))
            return ControlSpec(title: id.title, icon: icon, active: s.depth > 0.001, enabled: photoLike, action: { go(.depth) })
        case .night:
            let icon: AnyView = camera.nightEnabled ? badged("moon.fill", badge: "A", size: 22, m) : symbol("moon", 22, m)
            return ControlSpec(title: id.title, icon: icon, active: camera.nightEnabled, enabled: true, action: { camera.toggleNight() })
        case .format:
            let top = camera.mode == .video ? (camera.videoSpec.height >= 2160 ? "4K" : "HD") : camera.photoFormat.rawValue
            let bottom = camera.mode == .video ? "\(camera.videoSpec.fps)"
                : camera.resolutionTitles[camera.photoResolution == .max ? 0 : 1].replacingOccurrences(of: " MP", with: "")
            let icon = AnyView(
                VStack(spacing: 0) {
                    Text(top).font(.system(size: 15 * m.s, weight: .bold))
                    Text(bottom).font(.system(size: 11 * m.s, weight: .semibold))
                }
            )
            return ControlSpec(title: id.title, icon: icon, active: false, enabled: true, action: { go(.format) })
        case .focus:
            return ControlSpec(title: id.title, icon: symbol("viewfinder", 24, m), active: camera.focusLens != nil,
                               enabled: true, action: { go(.focus) })
        case .shutter:
            return ControlSpec(title: id.title, icon: symbol("speedometer", 24, m), active: camera.shutterSeconds != nil,
                               enabled: true, action: { go(.shutter) })
        case .whiteBalance:
            return ControlSpec(title: id.title, icon: symbol("cloud.sun", 24, m), active: camera.whiteBalanceKelvin != nil,
                               enabled: true, action: { go(.whiteBalance) })
        case .histogram:
            return ControlSpec(title: id.title, icon: symbol("chart.bar.fill", 22, m), active: camera.histogramEnabled,
                               enabled: true, action: { camera.setHistogram(!camera.histogramEnabled) })
        case .grid:
            return ControlSpec(title: id.title, icon: symbol("squareshape.split.3x3", 24, m), active: gridOn,
                               enabled: true, action: { gridOn.toggle() })
        }
    }

    // MARK: 取景器上的“展开”按钮 / 人像光效

    private func expandButton(_ m: UIMetrics) -> some View {
        let isFull = camera.aspect == .full
        return Button { toggleExpanded() } label: {
            Image(systemName: isFull ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13 * m.s, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 38 * m.s, height: 38 * m.s)
                .glassSurface(Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(GlassButtonStyle())
        .accessibilityLabel(isFull ? "收起取景器（4:3）" : "展开取景器（全屏）")
    }

    private func toggleExpanded() {
        guard camera.mode != .video else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            camera.aspect = camera.aspect == .full ? .fourThree : .full
        }
        camera.markControlsChanged()
    }

    private func lightingStrip(_ m: UIMetrics) -> some View {
        let items = PortraitLighting.allCases.filter { $0 != .off }
        let current = camera.styleSettings.lighting
        let found = camera.personDetected
        return VStack(spacing: 6 * m.s) {
            Text(found ? current.title : "\(current.title)（未检测到人物）")
                .font(.system(size: 12 * m.s, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 10 * m.s)
                .frame(height: 22 * m.s)
                .background(Capsule().fill(found ? Color.yellow : Color.white.opacity(0.85)))
            HStack(spacing: 6 * m.s) {
                ForEach(items) { item in
                    Button { selectLighting(item) } label: {
                        Image(systemName: item == current ? "hexagon.fill" : "hexagon")
                            .font(.system(size: 17 * m.s, weight: .semibold))
                            .foregroundStyle(item == current ? Color.yellow : Color.white)
                            .frame(width: 38 * m.s, height: 38 * m.s)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(GlassButtonStyle())
                    .accessibilityLabel(item.title)
                }
            }
            .padding(.horizontal, 8 * m.s)
            .frame(height: 42 * m.s)
            .glassSurface(Capsule(), interactive: true)
            .gesture(
                DragGesture(minimumDistance: 14).onEnded { value in
                    guard let index = items.firstIndex(of: current) else { return }
                    if value.translation.width > 24, index > 0 {
                        selectLighting(items[index - 1])
                    } else if value.translation.width < -24, index < items.count - 1 {
                        selectLighting(items[index + 1])
                    }
                }
            )
        }
    }

    private func selectLighting(_ item: PortraitLighting) {
        guard item != camera.styleSettings.lighting else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        camera.styleSettings.lighting = item
    }

    // MARK: 快门 / 缩略图 / 视频·照片·人像 / 翻转

    @ViewBuilder
    private func bottomControls(_ m: UIMetrics) -> some View {
        let idle = sheet == .closed
        let panelTop = m.H - m.panelBottomGap - m.panelHeight(sheet, drawerCount: layout.drawer.count)
        let shutterY = idle ? m.shutterCenterY : panelTop - 67 * m.s     // 面板打开时快门上移，停在面板上方
        if sheet != .drawer && sheet != .edit {
            shutterButton(m)
                .position(x: m.W / 2, y: shutterY)
        }
        if idle {
            thumbnailButton(m)
                .position(x: 60 * m.s, y: m.rowCenterY)
            modePill(m)
                .position(x: m.W / 2, y: m.rowCenterY)
            flipButton(m)
                .position(x: m.W - 60 * m.s, y: m.rowCenterY)
        }
    }

    private var shutterDisabled: Bool {
        !camera.cameraReady || camera.isCapturingPhoto || camera.isFinalizingVideo
    }

    private func shutterButton(_ m: UIMetrics) -> some View {
        let outer = 81 * m.s
        let inner = 69 * m.s
        let isVideo = camera.mode == .video
        return Button { shutterTapped(m) } label: {
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .frame(width: outer, height: outer)
                    .glassSurface(Circle(), interactive: true)
                RoundedRectangle(cornerRadius: camera.isRecording ? 8 * m.s : inner / 2, style: .continuous)
                    .fill(isVideo ? Color.red : Color.white)
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
        if camera.timerCountdown != nil { return "取消倒计时" }
        switch camera.mode {
        case .photo, .portrait: return "拍照"
        case .video: return camera.isRecording ? "停止录制" : "开始录制"
        }
    }

    private func shutterTapped(_ m: UIMetrics) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        let crop: CGFloat? = camera.mode == .video ? nil : camera.aspect.cropAspect(screenAspect: m.W / m.H)
        camera.triggerCapture(cropAspect: crop)
    }

    private func thumbnailButton(_ m: UIMetrics) -> some View {
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

    private func flipButton(_ m: UIMetrics) -> some View {
        let enabled = camera.cameraReady && !camera.isRecording && !camera.isCapturingPhoto
            && !camera.isFinalizingVideo && camera.timerCountdown == nil
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

    /// 视频 | 照片 | 人像：文字固定，官方 Liquid Glass“透镜”跟手指滑动，松手后吸附到最近的一项。
    private func modePill(_ m: UIMetrics) -> some View {
        let modes = CaptureMode.allCases
        let count = CGFloat(modes.count)
        let labelW = 66 * m.s
        let index = modes.firstIndex(of: camera.mode) ?? 0
        let lensOffset = (CGFloat(index) - (count - 1) / 2) * labelW + modeDrag
        let pillWidth = labelW * count + 8 * m.s
        return ZStack {
            Capsule()
                .fill(Color.clear)
                .frame(width: pillWidth, height: 48 * m.s)
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
                        .frame(width: labelW, height: 44 * m.s)
                        .contentShape(Rectangle())
                        .onTapGesture { selectMode(item) }
                        .accessibilityLabel(item.rawValue)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(item == camera.mode ? .isSelected : [])
                }
            }
        }
        .frame(width: pillWidth, height: 48 * m.s)
        .contentShape(Capsule())
        .gesture(modeDragGesture(labelW: labelW, index: index, count: modes.count))
    }

    private func modeDragGesture(labelW: CGFloat, index: Int, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                modeDragging = true
                let low = -CGFloat(index) * labelW
                let high = CGFloat(count - 1 - index) * labelW
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

    private func stepMode(_ delta: Int) {
        let modes = CaptureMode.allCases
        guard let index = modes.firstIndex(of: camera.mode) else { return }
        selectMode(modes[min(modes.count - 1, max(0, index + delta))])
    }

    private func selectMode(_ target: CaptureMode) {
        guard target != camera.mode else { return }
        if camera.isRecording || camera.isFinalizingVideo || camera.isCapturingPhoto || camera.timerCountdown != nil {
            camera.message = "正在拍摄、录制或倒计时，完成后才能切换模式"
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy(duration: 0.25)) {
            sheet = .closed
            camera.setMode(target)
        }
    }

    // MARK: 底部面板（高斯磨砂）

    private func go(_ target: Sheet) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { sheet = target }
    }

    @ViewBuilder
    private func sheetPanel(_ m: UIMetrics) -> some View {
        let count = layout.drawer.count
        switch sheet {
        case .closed:
            EmptyView()
        case .drawer:
            panel(m, height: m.panelHeight(.drawer, drawerCount: count)) {
                DrawerPanel(items: layout.drawer, m: m, spec: { spec($0, m) })
            }
        case .edit:
            panel(m, height: m.panelHeight(.edit, drawerCount: count)) {
                EditPanel(layout: layout, camera: camera, m: m, onBack: { go(.drawer) })
            }
        case .styles:
            panel(m, height: m.panelHeight(.styles, drawerCount: count)) {
                StylesPanel(camera: camera, m: m, onBack: { go(.drawer) }, onCustom: { go(.custom) })
            }
        case .custom:
            panel(m, height: m.panelHeight(.custom, drawerCount: count)) {
                CustomPalettePanel(camera: camera, m: m, onBack: { go(.styles) })
            }
        case .filters:
            panel(m, height: m.panelHeight(.filters, drawerCount: count)) {
                FiltersPanel(camera: camera, m: m, onBack: { go(.drawer) })
            }
        case .exposure:
            panel(m, height: m.panelHeight(.exposure, drawerCount: count)) {
                ExposurePanel(camera: camera, m: m, onBack: { go(.drawer) })
            }
        case .depth:
            panel(m, height: m.panelHeight(.depth, drawerCount: count)) {
                DepthPanel(camera: camera, m: m, onBack: { go(.drawer) })
            }
        case .timer:
            panel(m, height: m.panelHeight(.timer, drawerCount: count)) {
                TimerPanel(camera: camera, m: m, onBack: { go(.drawer) })
            }
        case .aspect:
            panel(m, height: m.panelHeight(.aspect, drawerCount: count)) {
                AspectPanel(camera: camera, m: m, onBack: { go(.drawer) })
            }
        case .format:
            panel(m, height: m.panelHeight(.format, drawerCount: count)) {
                FormatPanel(camera: camera, m: m, onBack: { go(.drawer) })
            }
        case .focus:
            panel(m, height: m.panelHeight(.focus, drawerCount: count)) {
                FocusPanel(camera: camera, m: m, onBack: { go(.drawer) })
            }
        case .shutter:
            panel(m, height: m.panelHeight(.shutter, drawerCount: count)) {
                ShutterPanel(camera: camera, m: m, onBack: { go(.drawer) })
            }
        case .whiteBalance:
            panel(m, height: m.panelHeight(.whiteBalance, drawerCount: count)) {
                WhiteBalancePanel(camera: camera, m: m, onBack: { go(.drawer) })
            }
        }
    }

    /// 所有面板共用：高斯磨砂底板（面板之间切换时底板平滑变形），底边停在 Home 指示条上方一点点。
    private func panel<Content: View>(_ m: UIMetrics, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: m.W - 18 * m.s, height: height)
            .background(alignment: .top) {
                // 只在顶部小横条这一块响应“向下滑收起”，不和面板里的按钮抢手势
                Color.clear
                    .frame(width: 160 * m.s, height: 30 * m.s)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 12).onEnded { value in
                            if value.translation.height > 30 { go(.closed) }
                        }
                    )
            }
            .frostedPanel(RoundedRectangle(cornerRadius: 38 * m.s, style: .continuous),
                          morph: GlassMorph(id: "sheet", namespace: glassNS))
            .position(x: m.W / 2, y: m.H - m.panelBottomGap - height / 2)
    }

    // MARK: 倒计时 / 提示 / 权限

    @ViewBuilder
    private var timerOverlay: some View {
        if let seconds = camera.timerCountdown {
            Text("\(seconds)")
                .font(.system(size: 120, weight: .thin, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.45), radius: 8)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func toastLayer(_ m: UIMetrics) -> some View {
        if let text = camera.message {
            Text(text)
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(maxWidth: m.W - 48 * m.s)
                .position(x: m.W / 2, y: m.capsuleCenterY + (hasPinned ? 92 : 62) * m.s)
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
