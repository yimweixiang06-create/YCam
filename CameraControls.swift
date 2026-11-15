import SwiftUI
import AVFoundation

// MARK: - 拍摄模式

enum CaptureMode: String, CaseIterable, Identifiable {
    case video = "视频"
    case photo = "照片"
    case portrait = "人像"
    var id: String { rawValue }
}

// MARK: - 各项设置的取值

enum FlashSetting: String, CaseIterable, Identifiable {
    case auto = "自动"
    case on = "开"
    case off = "关"
    var id: String { rawValue }

    var next: FlashSetting {
        switch self {
        case .auto: return .on
        case .on: return .off
        case .off: return .auto
        }
    }
}

enum AspectSetting: String, CaseIterable, Identifiable {
    case fourThree = "4:3"
    case sixteenNine = "16:9"
    case square = "1:1"
    case full = "全屏"
    var id: String { rawValue }

    /// 取景框 高 / 宽；全屏返回 nil（铺满屏幕）。
    var heightOverWidth: CGFloat? {
        switch self {
        case .fourThree: return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        case .square: return 1
        case .full: return nil
        }
    }

    /// 成片裁剪用的 宽 / 高；4:3 是相机原生比例，不裁剪。
    func cropAspect(screenAspect: CGFloat) -> CGFloat? {
        switch self {
        case .fourThree: return nil
        case .sixteenNine: return 9.0 / 16.0
        case .square: return 1
        case .full: return screenAspect
        }
    }
}

enum PhotoFormat: String, CaseIterable, Identifiable {
    case heif = "HEIF"
    case raw = "RAW"
    var id: String { rawValue }
}

struct VideoSpec: Hashable, Identifiable {
    let height: Int
    let fps: Int
    var id: String { "\(height)p\(fps)" }
    var title: String { (height >= 2160 ? "4K" : "HD 1080p") + " · \(fps) 帧" }
}

struct ZoomStop: Identifiable, Equatable {
    let label: String
    let display: CGFloat
    var id: String { label }
}

enum WhiteBalancePresets {
    static let items: [(title: String, kelvin: Int)] = [
        ("晴天", 5500), ("阴天", 6500), ("白炽灯", 3200), ("荧光灯", 4200)
    ]
}

/// 曝光时间（秒）显示成 1/250 这种形式。
func shutterText(_ seconds: Double) -> String {
    if seconds >= 0.5 { return String(format: "%.1f″", seconds) }
    return "1/\(Int((1 / max(seconds, 0.000_01)).rounded()))"
}

// MARK: - 抽屉里的功能（可编辑、可固定到顶部）

enum ControlID: String, CaseIterable, Identifiable {
    case flash, live, aspect, timer, exposure, style, filter, depth, night, format, focus, shutter, whiteBalance, histogram, grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flash: return "闪光灯"
        case .live: return "实况"
        case .aspect: return "宽高比"
        case .timer: return "计时器"
        case .exposure: return "曝光"
        case .style: return "摄影风格"
        case .filter: return "滤镜"
        case .depth: return "景深"
        case .night: return "夜间模式"
        case .format: return "格式"
        case .focus: return "对焦"
        case .shutter: return "快门速度"
        case .whiteBalance: return "白平衡"
        case .histogram: return "直方图"
        case .grid: return "网格"
        }
    }
}

/// 抽屉显示哪些功能、哪些固定在顶部一行；自动保存在手机里。
final class ControlLayout: ObservableObject {
    @Published private(set) var drawer: [ControlID]
    @Published private(set) var pinned: [ControlID]

    private static let drawerKey = "ycam.layout.drawer"
    private static let pinnedKey = "ycam.layout.pinned"
    static let maxPinned = 6
    static let essentials: [ControlID] = [.flash, .live, .timer, .exposure, .style, .aspect]

    init() {
        drawer = ControlLayout.load(ControlLayout.drawerKey) ?? ControlLayout.essentials
        pinned = ControlLayout.load(ControlLayout.pinnedKey) ?? []
    }

    private static func load(_ key: String) -> [ControlID]? {
        guard let raw = UserDefaults.standard.array(forKey: key) as? [String] else { return nil }
        return raw.compactMap { ControlID(rawValue: $0) }
    }

    private func save() {
        UserDefaults.standard.set(drawer.map { $0.rawValue }, forKey: ControlLayout.drawerKey)
        UserDefaults.standard.set(pinned.map { $0.rawValue }, forKey: ControlLayout.pinnedKey)
    }

    func inDrawer(_ id: ControlID) -> Bool { drawer.contains(id) }
    func isPinned(_ id: ControlID) -> Bool { pinned.contains(id) }

    func toggleDrawer(_ id: ControlID) {
        var keep = Set(drawer)
        if keep.contains(id) { keep.remove(id) } else { keep.insert(id) }
        drawer = ControlID.allCases.filter { keep.contains($0) }
        save()
    }

    /// 返回 false 表示顶部固定的数量已达上限。
    @discardableResult
    func togglePinned(_ id: ControlID) -> Bool {
        var list = pinned
        if let index = list.firstIndex(of: id) {
            list.remove(at: index)
        } else {
            guard list.count < ControlLayout.maxPinned else { return false }
            list.append(id)
        }
        pinned = list
        save()
        return true
    }

    func reset() {
        drawer = ControlLayout.essentials
        pinned = []
        save()
    }
}

// MARK: - 高频变化的状态单独放，避免整个界面跟着刷新

final class ZoomModel: ObservableObject {
    @Published var display: CGFloat = 1
    @Published var stops: [ZoomStop] = []
    @Published var minimum: CGFloat = 1
    @Published var maximum: CGFloat = 10
}

final class HistogramModel: ObservableObject {
    @Published var bins: [Float] = Array(repeating: 0, count: 64)
}

// MARK: - 面板 / 版式

enum Sheet: Equatable {
    case closed, drawer, edit, styles, custom, filters, exposure, depth, timer, aspect, format, focus, shutter, whiteBalance
}

/// iOS 27 相机 HUD 的统一安全区布局。固定快捷控件只能浮在取景画面上，绝不能改变取景画面的尺寸。
struct UIMetrics {
    let size: CGSize
    let top: CGFloat
    let bottomInset: CGFloat
    let s: CGFloat

    init(size: CGSize, topInset: CGFloat, bottomInset: CGFloat) {
        let scale = min(size.width / 402, size.height / 740)
        self.size = size
        self.s = scale
        self.top = max(topInset, 54 * scale)
        self.bottomInset = bottomInset
    }

    var W: CGFloat { size.width }
    var H: CGFloat { size.height }
    // 预览画面不受顶部自定义按钮数量影响。快捷栏使用 overlay 而不是修改图片宽度。
    var capsuleCenterY: CGFloat { top + 35 * s }
    var pinnedRowCenterY: CGFloat { capsuleCenterY + 47 * s }
    func vfTop(pinned: Bool) -> CGFloat { top + 69 * s }
    func vfWidth(pinned: Bool) -> CGFloat { W }
    var shutterCenterY: CGFloat { H - (max(bottomInset, 24 * s) + 119 * s) }
    var rowCenterY: CGFloat { H - (max(bottomInset, 24 * s) + 22 * s) }

    /// 顶部状态栏与底部控件各自保有独立空间；弹出菜单不能遮挡最上方的相机控制。
    var panelMaximumHeight: CGFloat {
        max(140 * s, H - (top + 94 * s) - panelBottomGap)
    }

    /// 面板底边停在 Home 指示条上方一点点。
    var panelBottomGap: CGFloat { max(bottomInset, 30 * s) + 6 * s }

    func panelHeight(_ sheet: Sheet, drawerCount: Int) -> CGFloat {
        let requested: CGFloat
        switch sheet {
        case .closed: return 0
        case .drawer:
            let rows = max(1, (drawerCount + 2) / 3)
            requested = (CGFloat(rows) * 98 + 62) * s
        case .edit: requested = 440 * s
        case .styles: requested = 200 * s
        case .custom: requested = 250 * s
        case .filters: requested = 190 * s
        case .exposure: requested = 150 * s
        case .depth: requested = 150 * s
        case .timer: requested = 245 * s
        case .aspect: requested = 140 * s
        case .format: requested = 245 * s
        case .focus: requested = 170 * s
        case .shutter: requested = 170 * s
        case .whiteBalance: requested = 230 * s
        }
        return min(requested, panelMaximumHeight)
    }
}
