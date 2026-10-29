import SwiftUI
import UIKit

// MARK: - 通用小组件

/// 面板头部：返回键（点击区域 48×44，避免“要点好几次才灵”）+ 标题 + 可选重置键。
struct PanelHeader<Center: View>: View {
    let m: UIMetrics
    let onBack: () -> Void
    let onReset: (() -> Void)?
    let center: () -> Center

    init(_ m: UIMetrics, onBack: @escaping () -> Void, onReset: (() -> Void)? = nil, @ViewBuilder center: @escaping () -> Center) {
        self.m = m
        self.onBack = onBack
        self.onReset = onReset
        self.center = center
    }

    var body: some View {
        ZStack {
            center()
            HStack {
                PanelIconButton(systemName: "chevron.left", m: m, label: "返回", action: onBack)
                Spacer(minLength: 0)
                if let onReset {
                    PanelIconButton(systemName: "arrow.counterclockwise", m: m, label: "重置", action: onReset)
                }
            }
        }
        .frame(height: 44 * m.s)
    }
}

struct PanelIconButton: View {
    let systemName: String
    let m: UIMetrics
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14 * m.s, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 34 * m.s, height: 34 * m.s)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .frame(width: 48 * m.s, height: 44 * m.s)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassButtonStyle())
        .accessibilityLabel(label)
    }
}

func panelTitle(_ text: String, _ m: UIMetrics) -> some View {
    Text(text)
        .font(.system(size: 14 * m.s, weight: .medium))
        .foregroundStyle(Color.white)
        .lineLimit(1)
}

/// 一排可选项（横向可滚动）。
struct ChipRow<Item: Hashable>: View {
    let items: [Item]
    let selected: Item?
    let m: UIMetrics
    let title: (Item) -> String
    var enabled: (Item) -> Bool = { _ in true }
    let onSelect: (Item) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8 * m.s) {
                ForEach(items, id: \.self) { item in
                    let isSelected = item == selected
                    Button { onSelect(item) } label: {
                        Text(title(item))
                            .font(.system(size: 14 * m.s, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.yellow : Color.white)
                            .padding(.horizontal, 14 * m.s)
                            .frame(height: 38 * m.s)
                            .background(Capsule().fill(Color.white.opacity(isSelected ? 0.24 : 0.12)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(GlassButtonStyle())
                    .opacity(enabled(item) ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 4 * m.s)
        }
    }
}

struct PanelSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01
    var onEnd: () -> Void = {}

    var body: some View {
        Slider(value: $value, in: range, step: step, onEditingChanged: { editing in
            if !editing { onEnd() }
        })
        .tint(Color.yellow)
    }
}

private func hint(_ text: String, _ m: UIMetrics) -> some View {
    Text(text)
        .font(.system(size: 11 * m.s))
        .foregroundStyle(Color.white.opacity(0.6))
        .multilineTextAlignment(.center)
}

// MARK: - 抽屉

struct ControlSpec {
    let title: String
    let icon: AnyView
    let active: Bool
    let enabled: Bool
    let action: () -> Void
}

struct DrawerCell: View {
    let spec: ControlSpec
    let m: UIMetrics

    var body: some View {
        Button(action: spec.action) {
            VStack(spacing: 7) {
                spec.icon
                    .foregroundStyle(spec.active ? Color.yellow : Color.white)
                    .frame(width: 58 * m.s, height: 58 * m.s)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                Text(spec.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassButtonStyle())
        .disabled(!spec.enabled)
        .opacity(spec.enabled ? 1 : 0.4)
        .accessibilityLabel(spec.title)
    }
}

struct DrawerPanel: View {
    let items: [ControlID]
    let m: UIMetrics
    let spec: (ControlID) -> ControlSpec

    var body: some View {
        let rows: [[ControlID]] = stride(from: 0, to: items.count, by: 3).map { start in
            Array(items[start..<min(start + 3, items.count)])
        }
        VStack(spacing: 14 * m.s) {
            Capsule()
                .fill(Color.white.opacity(0.45))
                .frame(width: 36 * m.s, height: 4 * m.s)
            if items.isEmpty {
                Text("抽屉是空的，点左上角“编辑”添加功能")
                    .font(.system(size: 14 * m.s))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(maxHeight: .infinity)
            } else {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(rows[r]) { id in
                            DrawerCell(spec: spec(id), m: m)
                        }
                        if rows[r].count < 3 {
                            ForEach(0..<(3 - rows[r].count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10 * m.s)
        .padding(.top, 10 * m.s)
        .padding(.bottom, 14 * m.s)
    }
}

/// 顶部固定的一行小图标（在“编辑”里选择固定哪些功能）。
struct PinnedRow: View {
    let items: [ControlID]
    let m: UIMetrics
    let spec: (ControlID) -> ControlSpec

    var body: some View {
        HStack(spacing: 14 * m.s) {
            ForEach(items) { id in
                let s = spec(id)
                Button(action: s.action) {
                    s.icon
                        .foregroundStyle(s.active ? Color.yellow : Color.white)
                        .frame(width: 36 * m.s, height: 36 * m.s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GlassButtonStyle())
                .disabled(!s.enabled)
                .opacity(s.enabled ? 1 : 0.4)
                .accessibilityLabel(s.title)
            }
        }
    }
}

// MARK: - 编辑：选择抽屉里放哪些功能 / 固定到顶部哪些

struct EditPanel: View {
    @ObservedObject var layout: ControlLayout
    let camera: CameraModel
    let m: UIMetrics
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 6 * m.s) {
            PanelHeader(m, onBack: onBack, onReset: { layout.reset() }) {
                panelTitle("编辑功能（\(layout.drawer.count) 个在抽屉里）", m)
            }
            hint("“抽屉”决定是否出现在 ⋯ 抽屉里；“顶部”把它固定到顶部一行（最多 \(ControlLayout.maxPinned) 个）。", m)
            ScrollView {
                VStack(spacing: 8 * m.s) {
                    ForEach(ControlID.allCases) { id in
                        row(id)
                    }
                }
                .padding(.vertical, 4 * m.s)
            }
        }
        .padding(.horizontal, 14 * m.s)
        .padding(.vertical, 8 * m.s)
    }

    private func row(_ id: ControlID) -> some View {
        HStack(spacing: 8 * m.s) {
            Text(id.title)
                .font(.system(size: 15 * m.s, weight: .medium))
                .foregroundStyle(Color.white)
            Spacer(minLength: 0)
            toggle("抽屉", on: layout.inDrawer(id)) { layout.toggleDrawer(id) }
            toggle("顶部", on: layout.isPinned(id)) {
                if !layout.togglePinned(id) {
                    camera.message = "顶部最多固定 \(ControlLayout.maxPinned) 个功能"
                }
            }
        }
        .padding(.horizontal, 12 * m.s)
        .frame(height: 44 * m.s)
        .background(RoundedRectangle(cornerRadius: 14 * m.s, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private func toggle(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13 * m.s, weight: .semibold))
                .foregroundStyle(on ? Color.black : Color.white)
                .frame(width: 52 * m.s, height: 32 * m.s)
                .background(Capsule().fill(on ? Color.yellow : Color.white.opacity(0.14)))
                .frame(width: 58 * m.s, height: 44 * m.s)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassButtonStyle())
    }
}

// MARK: - 各功能面板

struct AspectPanel: View {
    @ObservedObject var camera: CameraModel
    let m: UIMetrics
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 10 * m.s) {
            PanelHeader(m, onBack: onBack) { panelTitle("宽高比", m) }
            ChipRow(items: AspectSetting.allCases, selected: camera.aspect, m: m, title: { $0.rawValue }) { value in
                camera.aspect = value
                camera.markControlsChanged()
            }
            hint("视频固定全屏；照片按所选比例取景，成片也按同样比例裁剪。", m)
        }
        .padding(.horizontal, 14 * m.s)
        .padding(.vertical, 8 * m.s)
    }
}

struct TimerPanel: View {
    @ObservedObject var camera: CameraModel
    let m: UIMetrics
    let onBack: () -> Void
    @State private var custom = false

    private let options = [0, 3, 5, 10, -1]

    var body: some View {
        let isPreset = [0, 3, 5, 10].contains(camera.timerSeconds)
        let showCustom = custom || !isPreset
        VStack(spacing: 10 * m.s) {
            PanelHeader(m, onBack: onBack) {
                panelTitle(camera.timerSeconds == 0 ? "计时器：关" : "计时器：\(camera.timerSeconds) 秒", m)
            }
            ChipRow(items: options, selected: showCustom ? -1 : camera.timerSeconds, m: m, title: { value in
                value == 0 ? "关" : (value < 0 ? "自定义" : "\(value) 秒")
            }) { value in
                if value < 0 {
                    custom = true
                    if camera.timerSeconds == 0 { camera.timerSeconds = 15 }
                } else {
                    custom = false
                    camera.timerSeconds = value
                }
                camera.markControlsChanged()
            }
            if showCustom {
                HStack(spacing: 6 * m.s) {
                    PanelIconButton(systemName: "minus", m: m, label: "减少 1 秒") { adjust(-1) }
                    Text("\(camera.timerSeconds) 秒")
                        .font(.system(size: 22 * m.s, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.white)
                        .frame(width: 90 * m.s)
                    PanelIconButton(systemName: "plus", m: m, label: "增加 1 秒") { adjust(1) }
                }
            }
            hint("按快门后倒计时，再按一次快门可以取消；视频是倒计时结束后开始录制。", m)
        }
        .padding(.horizontal, 14 * m.s)
        .padding(.vertical, 8 * m.s)
    }

    private func adjust(_ delta: Int) {
        camera.timerSeconds = min(60, max(1, camera.timerSeconds + delta))
        camera.markControlsChanged()
    }
}

struct ExposurePanel: View {
    let camera: CameraModel
    let m: UIMetrics
    let onBack: () -> Void
    @State private var value: Double

    init(camera: CameraModel, m: UIMetrics, onBack: @escaping () -> Void) {
        self.camera = camera
        self.m = m
        self.onBack = onBack
        _value = State(initialValue: Double(camera.exposureBias))
    }

    var body: some View {
        let range = Double(camera.exposureRange.lowerBound)...Double(camera.exposureRange.upperBound)
        VStack(spacing: 12 * m.s) {
            PanelHeader(m, onBack: onBack, onReset: {
                value = 0
                camera.setExposureBias(0)
                camera.markControlsChanged()
            }) {
                panelTitle("曝光 \(String(format: "%+.1f", value)) EV", m)
            }
            HStack(spacing: 10) {
                Text("−").font(.system(size: 17, weight: .medium)).foregroundStyle(Color.white.opacity(0.8))
                PanelSlider(value: $value, range: range, step: 0.1) { camera.markControlsChanged() }
                Text("+").font(.system(size: 17, weight: .medium)).foregroundStyle(Color.white.opacity(0.8))
            }
            .padding(.horizontal, 14 * m.s)
        }
        .padding(.horizontal, 14 * m.s)
        .padding(.vertical, 8 * m.s)
        .onChange(of: value) { _, newValue in camera.setExposureBias(Float(newValue)) }
    }
}

struct DepthPanel: View {
    @ObservedObject var camera: CameraModel
    let m: UIMetrics
    let onBack: () -> Void

    var body: some View {
        let depth = camera.styleSettings.depth
        let fNumber = 16.0 - depth * (16.0 - 1.4)
        VStack(spacing: 10 * m.s) {
            PanelHeader(m, onBack: onBack, onReset: {
                camera.styleSettings.depth = camera.mode == .portrait ? 0.55 : 0
                camera.markControlsChanged()
            }) {
                panelTitle(depth < 0.001 ? "景深：关" : "景深  ƒ \(String(format: "%.1f", fNumber))", m)
            }
            HStack(spacing: 10) {
                Text("ƒ16").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.white.opacity(0.8))
                PanelSlider(value: Binding(get: { camera.styleSettings.depth },
                                           set: { camera.styleSettings.depth = $0 }),
                            range: 0...1, step: 0.05) { camera.markControlsChanged() }
                Text("ƒ1.4").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.white.opacity(0.8))
            }
            .padding(.horizontal, 14 * m.s)
            hint("背景虚化强度（画面里需要有人物）。人像模式默认开启，照片模式默认关闭。", m)
        }
        .padding(.horizontal, 14 * m.s)
        .padding(.vertical, 8 * m.s)
    }
}

struct StylesPanel: View {
    @ObservedObject var camera: CameraModel
    let m: UIMetrics
    let onBack: () -> Void
    let onCustom: () -> Void

    var body: some View {
        VStack(spacing: 8 * m.s) {
            PanelHeader(m, onBack: onBack) { panelTitle(camera.styleSettings.style.title, m) }
            Circle()
                .fill(Color.white)
                .frame(width: 5 * m.s, height: 5 * m.s)
            SwatchCarousel(items: CameraStyle.allCases,
                           selected: $camera.styleSettings.style,
                           cardWidth: 41 * m.s,
                           cardHeight: 52 * m.s,
                           spacing: 8 * m.s,
                           colors: { $0.cardColors },
                           name: { $0.title })
            Button { onCustom() } label: {
                Text("自定义")
                    .font(.system(size: 13 * m.s, weight: .medium))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 20 * m.s)
                    .frame(height: 30 * m.s)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .frame(height: 40 * m.s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassButtonStyle())
        }
        .padding(.horizontal, 12 * m.s)
        .padding(.vertical, 8 * m.s)
    }
}

/// 自定义（按“调色盘使用公式”）：纵向 = 明度（上亮 → 下暗），横向 = 纯度（左灰 → 右纯），下面的刻度条 = 调色盘浓度（淡 → 浓）。
struct CustomPalettePanel: View {
    @ObservedObject var camera: CameraModel
    let m: UIMetrics
    let onBack: () -> Void

    var body: some View {
        let settings = camera.styleSettings
        let tone = Int(((0.5 - settings.point.y) * 200).rounded())
        let purity = Int(min(125, settings.point.x / 0.8 * 100).rounded())
        let palette = Int((settings.intensity * 100).rounded())
        VStack(spacing: 10 * m.s) {
            PanelHeader(m, onBack: onBack, onReset: {
                camera.styleSettings.point = StyleSettings.defaultPoint
                camera.styleSettings.intensity = 1
            }) {
                HStack(spacing: 12 * m.s) {
                    valueLabel("明度", tone == 0 ? "00" : "\(tone)")
                    valueLabel("纯度", "\(purity)")
                    valueLabel("调色盘", "\(palette)")
                }
            }
            DotPalette(point: $camera.styleSettings.point, colors: settings.style.cardColors)
                .frame(width: 132 * m.s, height: 132 * m.s)
            TickSlider(value: $camera.styleSettings.intensity)
                .frame(width: 200 * m.s)
        }
        .padding(.horizontal, 12 * m.s)
        .padding(.vertical, 8 * m.s)
    }

    private func valueLabel(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12 * m.s))
                .foregroundStyle(Color.white.opacity(0.6))
            Text(value)
                .font(.system(size: 12 * m.s, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.white)
        }
    }
}

struct FiltersPanel: View {
    @ObservedObject var camera: CameraModel
    let m: UIMetrics
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 8 * m.s) {
            PanelHeader(m, onBack: onBack, onReset: { camera.styleSettings.filter = .original }) {
                panelTitle("滤镜：\(camera.styleSettings.filter.title)", m)
            }
            Circle()
                .fill(Color.white)
                .frame(width: 5 * m.s, height: 5 * m.s)
            SwatchCarousel(items: AppleFilter.allCases,
                           selected: $camera.styleSettings.filter,
                           cardWidth: 41 * m.s,
                           cardHeight: 52 * m.s,
                           spacing: 8 * m.s,
                           colors: { $0.cardColors },
                           name: { $0.title })
            hint("Apple 原有滤镜（鲜明 / 戏剧 / 单色 / 银色调 / 黑白），可以和摄影风格叠加。", m)
        }
        .padding(.horizontal, 12 * m.s)
        .padding(.vertical, 8 * m.s)
    }
}

struct FormatPanel: View {
    @ObservedObject var camera: CameraModel
    let m: UIMetrics
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 10 * m.s) {
            PanelHeader(m, onBack: onBack) { panelTitle("格式", m) }
            if camera.mode == .video {
                sectionTitle("视频分辨率 / 帧率（按设备支持自动列出）")
                ChipRow(items: camera.videoSpecs, selected: camera.videoSpec, m: m, title: { $0.title }) { spec in
                    camera.selectVideoSpec(spec)
                    camera.markControlsChanged()
                }
                hint("4K / 60 帧在使用风格或滤镜时对手机压力较大；不用风格时直接写入相机原始画面。", m)
            } else {
                sectionTitle("照片格式")
                ChipRow(items: PhotoFormat.allCases, selected: camera.photoFormat, m: m,
                        title: { $0.rawValue },
                        enabled: { $0 == .heif || camera.rawSupported }) { format in
                    if format == .raw && !camera.rawSupported {
                        camera.message = "此设备或当前镜头不支持 RAW"
                    } else {
                        camera.photoFormat = format
                        camera.markControlsChanged()
                    }
                }
                sectionTitle("分辨率")
                ChipRow(items: PhotoResolutionChoice.allCases, selected: camera.photoResolution, m: m,
                        title: { choice in
                    choice == .max ? "最大 \(camera.resolutionTitles[0])" : "一半 \(camera.resolutionTitles[1])"
                }) { choice in
                    camera.photoResolution = choice
                    camera.markControlsChanged()
                }
                hint("RAW 会同时保存一张 DNG；最大分辨率或 RAW 时不能拍实况。", m)
            }
        }
        .padding(.horizontal, 14 * m.s)
        .padding(.vertical, 8 * m.s)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12 * m.s, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4 * m.s)
    }
}

struct FocusPanel: View {
    let camera: CameraModel
    let m: UIMetrics
    let onBack: () -> Void
    @State private var manual: Bool
    @State private var lens: Double

    init(camera: CameraModel, m: UIMetrics, onBack: @escaping () -> Void) {
        self.camera = camera
        self.m = m
        self.onBack = onBack
        _manual = State(initialValue: camera.focusLens != nil)
        _lens = State(initialValue: Double(camera.focusLens ?? 0.5))
    }

    var body: some View {
        VStack(spacing: 10 * m.s) {
            PanelHeader(m, onBack: onBack, onReset: {
                manual = false
                camera.setFocusLens(nil)
                camera.markControlsChanged()
            }) {
                panelTitle(manual ? "对焦：手动" : "对焦：自动", m)
            }
            ChipRow(items: [false, true], selected: manual, m: m, title: { $0 ? "手动" : "自动" }) { value in
                manual = value
                camera.setFocusLens(value ? Float(lens) : nil)
                camera.markControlsChanged()
            }
            if manual {
                HStack(spacing: 10) {
                    Text("近").font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.8))
                    PanelSlider(value: $lens, range: 0...1, step: 0.01) { camera.markControlsChanged() }
                    Text("远").font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.8))
                }
                .padding(.horizontal, 14 * m.s)
            } else {
                hint("自动：点按画面任意位置可以在那里对焦并测光。", m)
            }
        }
        .padding(.horizontal, 14 * m.s)
        .padding(.vertical, 8 * m.s)
        .onChange(of: lens) { _, newValue in
            if manual { camera.setFocusLens(Float(newValue)) }
        }
    }
}

struct ShutterPanel: View {
    let camera: CameraModel
    let m: UIMetrics
    let onBack: () -> Void
    @State private var manual: Bool
    @State private var position: Double      // 0...1，对数刻度

    init(camera: CameraModel, m: UIMetrics, onBack: @escaping () -> Void) {
        self.camera = camera
        self.m = m
        self.onBack = onBack
        _manual = State(initialValue: camera.shutterSeconds != nil)
        let range = camera.shutterRange
        let seconds = camera.shutterSeconds ?? 1.0 / 60
        let t = (log(seconds) - log(range.lowerBound)) / max(0.0001, log(range.upperBound) - log(range.lowerBound))
        _position = State(initialValue: min(1, max(0, t)))
    }

    private var seconds: Double {
        let range = camera.shutterRange
        return exp(log(range.lowerBound) + position * (log(range.upperBound) - log(range.lowerBound)))
    }

    var body: some View {
        VStack(spacing: 10 * m.s) {
            PanelHeader(m, onBack: onBack, onReset: {
                manual = false
                camera.setShutterSeconds(nil)
                camera.markControlsChanged()
            }) {
                panelTitle(manual ? "快门速度：\(shutterText(seconds)) 秒" : "快门速度：自动", m)
            }
            ChipRow(items: [false, true], selected: manual, m: m, title: { $0 ? "手动" : "自动" }) { value in
                manual = value
                camera.setShutterSeconds(value ? seconds : nil)
                camera.markControlsChanged()
            }
            if manual {
                HStack(spacing: 10) {
                    Text("快").font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.8))
                    PanelSlider(value: $position, range: 0...1, step: 0.01) { camera.markControlsChanged() }
                    Text("慢").font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.8))
                }
                .padding(.horizontal, 14 * m.s)
                hint("手动快门会自动调整 ISO 保持亮度；慢快门请拿稳手机。", m)
            }
        }
        .padding(.horizontal, 14 * m.s)
        .padding(.vertical, 8 * m.s)
        .onChange(of: position) { _, _ in
            if manual { camera.setShutterSeconds(seconds) }
        }
    }
}

struct WhiteBalancePanel: View {
    let camera: CameraModel
    let m: UIMetrics
    let onBack: () -> Void
    @State private var kelvin: Double
    @State private var selected: Int      // -2 自动, -1 自定义, 其余 = 预设色温

    init(camera: CameraModel, m: UIMetrics, onBack: @escaping () -> Void) {
        self.camera = camera
        self.m = m
        self.onBack = onBack
        let current = camera.whiteBalanceKelvin
        _kelvin = State(initialValue: Double(current ?? 5500))
        if let current {
            let isPreset = WhiteBalancePresets.items.contains { $0.kelvin == current }
            _selected = State(initialValue: isPreset ? current : -1)
        } else {
            _selected = State(initialValue: -2)
        }
    }

    private var options: [Int] {
        [-2] + WhiteBalancePresets.items.map { $0.kelvin } + [-1]
    }

    private func title(_ value: Int) -> String {
        if value == -2 { return "自动" }
        if value == -1 { return "自定义" }
        return WhiteBalancePresets.items.first { $0.kelvin == value }?.title ?? "\(value)K"
    }

    var body: some View {
        VStack(spacing: 10 * m.s) {
            PanelHeader(m, onBack: onBack, onReset: {
                selected = -2
                camera.setWhiteBalance(kelvin: nil)
                camera.markControlsChanged()
            }) {
                panelTitle(selected == -2 ? "白平衡：自动" : "白平衡：\(Int(kelvin)) K", m)
            }
            ChipRow(items: options, selected: selected, m: m, title: { title($0) }) { value in
                selected = value
                if value == -2 {
                    camera.setWhiteBalance(kelvin: nil)
                } else if value == -1 {
                    camera.setWhiteBalance(kelvin: Int(kelvin))
                } else {
                    kelvin = Double(value)
                    camera.setWhiteBalance(kelvin: value)
                }
                camera.markControlsChanged()
            }
            if selected == -1 {
                HStack(spacing: 10) {
                    Text("冷").font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.8))
                    PanelSlider(value: $kelvin, range: 2500...8000, step: 100) { camera.markControlsChanged() }
                    Text("暖").font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.8))
                }
                .padding(.horizontal, 14 * m.s)
            } else if selected == -2 {
                hint("默认：自动，根据画面实时分析白平衡。", m)
            }
        }
        .padding(.horizontal, 14 * m.s)
        .padding(.vertical, 8 * m.s)
        .onChange(of: kelvin) { _, newValue in
            if selected == -1 { camera.setWhiteBalance(kelvin: Int(newValue)) }
        }
    }
}

// MARK: - 取景器上的小组件

struct ZoomPills: View {
    @ObservedObject var model: ZoomModel
    let m: UIMetrics
    let onSelect: (ZoomStop) -> Void

    var body: some View {
        if model.stops.count > 1 {
            pills
        }
    }

    private var pills: some View {
        let current = model.display
        let nearest = model.stops.min { abs($0.display - current) < abs($1.display - current) }
        return HStack(spacing: 4 * m.s) {
            ForEach(model.stops) { stop in
                let isSelected = stop == nearest
                Button { onSelect(stop) } label: {
                    Text(isSelected ? zoomText(current) : stop.label)
                        .font(.system(size: (isSelected ? 13 : 12) * m.s, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.yellow : Color.white)
                        .frame(width: 36 * m.s, height: 36 * m.s)
                        .background(Circle().fill(isSelected ? Color.white.opacity(0.16) : Color.clear))
                        .contentShape(Circle())
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
        .padding(.horizontal, 4 * m.s)
        .frame(height: 40 * m.s)
        .glassSurface(Capsule(), interactive: true)
    }

    private func zoomText(_ value: CGFloat) -> String {
        if value < 0.95 { return String(format: "%.1f×", value).replacingOccurrences(of: "0.", with: ".") }
        if abs(value - value.rounded()) < 0.05 { return "\(Int(value.rounded()))×" }
        return String(format: "%.1f×", value)
    }
}

struct HistogramView: View {
    @ObservedObject var model: HistogramModel
    let m: UIMetrics

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let bins = model.bins
                guard !bins.isEmpty else { return }
                let w = geo.size.width / CGFloat(bins.count)
                for (i, value) in bins.enumerated() {
                    let h = max(1, geo.size.height * CGFloat(value))
                    path.addRect(CGRect(x: CGFloat(i) * w, y: geo.size.height - h, width: max(1, w - 0.5), height: h))
                }
            }
            .fill(Color.white.opacity(0.85))
        }
        .frame(width: 112 * m.s, height: 54 * m.s)
        .padding(8 * m.s)
        .background(RoundedRectangle(cornerRadius: 12 * m.s, style: .continuous).fill(Color.black.opacity(0.45)))
        .accessibilityLabel("直方图")
    }
}

struct FocusSquare: View {
    let m: UIMetrics
    @State private var appeared = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(Color.yellow, lineWidth: 1.4)
            .frame(width: 74 * m.s, height: 74 * m.s)
            .overlay(
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 12 * m.s))
                    .foregroundStyle(Color.yellow)
                    .offset(x: 52 * m.s)
            )
            .scaleEffect(appeared ? 1 : 1.35)
            .opacity(appeared ? 1 : 0.4)
            .onAppear {
                withAnimation(.easeOut(duration: 0.22)) { appeared = true }
            }
            .allowsHitTesting(false)
    }
}
