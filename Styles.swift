import SwiftUI

// MARK: - Basic value types

struct RGB: Equatable {
    var r: Float
    var g: Float
    var b: Float
    static let zero = RGB(r: 0, g: 0, b: 0)
    static let one = RGB(r: 1, g: 1, b: 1)
}

@inline(__always) func rgb(_ r: Float, _ g: Float, _ b: Float) -> RGB { RGB(r: r, g: g, b: b) }

/// 参数化的“风格配方”。预览、照片、视频都使用同一份配方，避免三条路径效果不一致。
/// 参数顺序必须与声明顺序一致（成员初始化器要求）。
struct LookRecipe: Equatable {
    var exposure: Float = 0          // EV（线性光下的曝光）
    var contrast: Float = 0          // -1...1，围绕中灰的 S 曲线
    var saturation: Float = 1        // 整体饱和度
    var vibrance: Float = 0          // 额外提升低饱和颜色
    var temperature: Float = 0       // -1 冷 ... +1 暖
    var tint: Float = 0              // -1 偏绿 ... +1 偏品红
    var shadowTint: RGB = .zero      // 暗部偏色（伽马域加法）
    var highlightTint: RGB = .zero   // 亮部偏色
    var midGamma: RGB = .one         // 分通道中间调伽马（胶片串色）
    var blackLift: Float = 0         // 黑位抬升（褪色）
    var whiteRoll: Float = 0         // 高光压缩
    var mono: Float = 0              // 0...1 黑白程度
    var grain: Float = 0             // 0...1 颗粒（不进 LUT）
    var bloom: Float = 0             // 0...1 柔光（不进 LUT）
    var softness: Float = 0          // 0...1 柔焦（与模糊图混合，珠光使用）

    /// 将所有参数朝“无效果”方向按比例缩放（用于强度滑块）。
    func scaled(by k: Float) -> LookRecipe {
        func l(_ v: Float, _ identity: Float) -> Float { identity + (v - identity) * k }
        var r = LookRecipe()
        r.exposure = l(exposure, 0)
        r.contrast = l(contrast, 0)
        r.saturation = l(saturation, 1)
        r.vibrance = l(vibrance, 0)
        r.temperature = l(temperature, 0)
        r.tint = l(tint, 0)
        r.shadowTint = rgb(shadowTint.r * k, shadowTint.g * k, shadowTint.b * k)
        r.highlightTint = rgb(highlightTint.r * k, highlightTint.g * k, highlightTint.b * k)
        r.midGamma = rgb(l(midGamma.r, 1), l(midGamma.g, 1), l(midGamma.b, 1))
        r.blackLift = l(blackLift, 0)
        r.whiteRoll = l(whiteRoll, 0)
        r.mono = l(mono, 0)
        r.grain = grain * k
        r.bloom = bloom * k
        r.softness = softness * k
        return r
    }

    /// 把两份配方叠加（风格 + Apple 滤镜）。
    func combined(with o: LookRecipe) -> LookRecipe {
        var r = LookRecipe()
        r.exposure = exposure + o.exposure
        r.contrast = contrast + o.contrast
        r.saturation = saturation * o.saturation
        r.vibrance = vibrance + o.vibrance
        r.temperature = temperature + o.temperature
        r.tint = tint + o.tint
        r.shadowTint = rgb(shadowTint.r + o.shadowTint.r, shadowTint.g + o.shadowTint.g, shadowTint.b + o.shadowTint.b)
        r.highlightTint = rgb(highlightTint.r + o.highlightTint.r, highlightTint.g + o.highlightTint.g, highlightTint.b + o.highlightTint.b)
        r.midGamma = rgb(midGamma.r * o.midGamma.r, midGamma.g * o.midGamma.g, midGamma.b * o.midGamma.b)
        r.blackLift = blackLift + o.blackLift
        r.whiteRoll = whiteRoll + o.whiteRoll
        r.mono = max(mono, o.mono)
        r.grain = max(grain, o.grain)
        r.bloom = max(bloom, o.bloom)
        r.softness = max(softness, o.softness)
        return r
    }
    /// 颜色部分是否等于“无处理”（grain / bloom 另算）。
    var isColorIdentity: Bool {
        let e: Float = 0.0005
        func small(_ v: RGB) -> Bool { abs(v.r) < e && abs(v.g) < e && abs(v.b) < e }
        func one(_ v: RGB) -> Bool { abs(v.r - 1) < e && abs(v.g - 1) < e && abs(v.b - 1) < e }
        return abs(exposure) < e && abs(contrast) < e && abs(saturation - 1) < e
            && abs(vibrance) < e && abs(temperature) < e && abs(tint) < e
            && small(shadowTint) && small(highlightTint) && one(midGamma)
            && abs(blackLift) < e && abs(whiteRoll) < e && mono < e
    }
}

// MARK: - Styles

/// 所有可选风格：Apple 式摄影风格 + 珠光 Pearl + 4 个胶片风格。
/// 每个风格都有各自独立的配方（FUJI 400 与 FUJI 青调、KODAK 800 与 KODAK 暖黄不再共用同一份处理）。
enum CameraStyle: String, CaseIterable, Identifiable {
    case standard, pearl
    case amber, gold, roseGold, coolRose, cool, neutral, vibrant, warm, ethereal, dramatic, luminous, radiant, monochrome
    case fuji400, kodak800, fujiCyan, kodakWarmYellow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "标准"
        case .pearl: return "珠光 Pearl"
        case .amber: return "琥珀色 Amber"
        case .gold: return "金色 Gold"
        case .roseGold: return "玫瑰金 Rose Gold"
        case .coolRose: return "冷调玫瑰色 Cool Rose"
        case .cool: return "冷调 Cool"
        case .radiant: return "耀目 Radiant"
        case .neutral: return "自然 Neutral"
        case .vibrant: return "鲜明 Vibrant"
        case .warm: return "温馨 Warm"
        case .ethereal: return "空灵 Ethereal"
        case .dramatic: return "戏剧 Dramatic"
        case .luminous: return "明亮 Luminous"
        case .monochrome: return "黑白 Mono"
        case .fuji400: return "FUJI 400"
        case .kodak800: return "KODAK 800"
        case .fujiCyan: return "FUJI 青调"
        case .kodakWarmYellow: return "KODAK 暖黄"
        }
    }

    var isFilm: Bool {
        switch self {
        case .fuji400, .kodak800, .fujiCyan, .kodakWarmYellow: return true
        default: return false
        }
    }

    /// 圆点与名称旁边显示的代表色（仅用于界面，不参与图像处理）。
    var swatch: Color {
        switch self {
        case .standard: return Color(red: 0.92, green: 0.92, blue: 0.92)
        case .pearl: return Color(red: 0.93, green: 0.86, blue: 0.96)
        case .amber: return Color(red: 0.96, green: 0.60, blue: 0.18)
        case .gold: return Color(red: 0.96, green: 0.80, blue: 0.34)
        case .roseGold: return Color(red: 0.93, green: 0.64, blue: 0.60)
        case .coolRose: return Color(red: 0.78, green: 0.62, blue: 0.80)
        case .cool: return Color(red: 0.50, green: 0.64, blue: 0.86)
        case .radiant: return Color(red: 0.62, green: 0.42, blue: 0.80)
        case .neutral: return Color(red: 0.72, green: 0.74, blue: 0.72)
        case .vibrant: return Color(red: 0.26, green: 0.80, blue: 0.52)
        case .warm: return Color(red: 0.97, green: 0.70, blue: 0.46)
        case .ethereal: return Color(red: 0.70, green: 0.86, blue: 0.96)
        case .dramatic: return Color(red: 0.42, green: 0.40, blue: 0.52)
        case .luminous: return Color(red: 1.00, green: 0.95, blue: 0.78)
        case .monochrome: return Color(red: 0.62, green: 0.62, blue: 0.62)
        case .fuji400: return Color(red: 0.20, green: 0.66, blue: 0.58)
        case .kodak800: return Color(red: 0.95, green: 0.58, blue: 0.30)
        case .fujiCyan: return Color(red: 0.16, green: 0.82, blue: 0.88)
        case .kodakWarmYellow: return Color(red: 0.98, green: 0.80, blue: 0.20)
        }
    }

    /// 风格卡片的渐变色：把 3 个参考色（高光 / 肤色 / 暗部）送进该风格自己的配方，所见即所得（不是另外画的假色块）。
    var cardColors: [Color] {
        let samples: [(Float, Float, Float)] = [(0.93, 0.93, 0.95), (0.82, 0.60, 0.50), (0.16, 0.17, 0.20)]
        let r = recipe
        return samples.map { sample in
            let out = FilterEngine.transform(sample.0, sample.1, sample.2, r)
            return Color(red: Double(out.0), green: Double(out.1), blue: Double(out.2))
        }
    }

    // 注意：每个 case 必须保持单行，tools/style_check.py 会解析这些数值做色彩自检。
    var recipe: LookRecipe {
        switch self {
        case .standard: return LookRecipe()
        case .pearl: return LookRecipe(exposure: -0.03, contrast: -0.22, saturation: 0.90, vibrance: 0.06, temperature: 0.00, tint: 0.05, shadowTint: rgb(-0.004, 0.006, 0.012), highlightTint: rgb(0.018, 0.006, 0.022), blackLift: 0.035, whiteRoll: 0.20, bloom: 0.22, softness: 0.55)
        case .amber: return LookRecipe(exposure: -0.02, contrast: 0.10, saturation: 1.10, temperature: 0.34, tint: 0.12, highlightTint: rgb(0.022, 0.002, -0.016))
        case .gold: return LookRecipe(exposure: 0.10, contrast: 0.02, saturation: 1.00, temperature: 0.30, tint: -0.14, highlightTint: rgb(0.012, 0.020, -0.016), blackLift: 0.010)
        case .roseGold: return LookRecipe(contrast: 0.02, saturation: 1.00, temperature: 0.18, tint: 0.14, highlightTint: rgb(0.016, 0.000, 0.004))
        case .coolRose: return LookRecipe(exposure: 0.05, contrast: 0.02, temperature: -0.20, tint: 0.08, highlightTint: rgb(0.006, -0.002, 0.008))
        case .cool: return LookRecipe(contrast: 0.06, saturation: 1.02, temperature: -0.30, tint: -0.04, highlightTint: rgb(-0.004, 0.004, 0.012))
        case .radiant: return LookRecipe(exposure: -0.05, contrast: 0.30, saturation: 1.14, vibrance: 0.20, shadowTint: rgb(-0.012, 0.010, 0.020), highlightTint: rgb(0.014, 0.000, 0.016), whiteRoll: 0.05)
        case .neutral: return LookRecipe(exposure: 0.10, contrast: -0.05, saturation: 0.92, temperature: -0.16)
        case .vibrant: return LookRecipe(contrast: 0.10, saturation: 1.16, vibrance: 0.30)
        case .warm: return LookRecipe(exposure: 0.04, contrast: 0.03, saturation: 1.04, temperature: 0.24, tint: 0.02)
        case .ethereal: return LookRecipe(exposure: 0.15, contrast: -0.20, saturation: 0.92, temperature: -0.04, blackLift: 0.03, whiteRoll: 0.10, bloom: 0.12)
        case .dramatic: return LookRecipe(exposure: -0.12, contrast: 0.60, saturation: 1.06, whiteRoll: 0.06)
        case .luminous: return LookRecipe(exposure: 0.25, contrast: -0.06, saturation: 1.05, vibrance: 0.12, whiteRoll: 0.14, bloom: 0.06)
        case .monochrome: return LookRecipe(contrast: 0.16, mono: 1)
        case .fuji400: return LookRecipe(contrast: 0.12, saturation: 1.06, vibrance: 0.08, temperature: -0.10, tint: -0.05, shadowTint: rgb(-0.008, 0.010, 0.012), highlightTint: rgb(-0.002, 0.004, 0.002), midGamma: rgb(1.02, 0.97, 1.00), blackLift: 0.025, whiteRoll: 0.08, grain: 0.55)
        case .kodak800: return LookRecipe(exposure: 0.04, contrast: 0.02, saturation: 0.98, temperature: 0.16, tint: 0.03, shadowTint: rgb(0.008, 0.002, -0.004), highlightTint: rgb(0.010, 0.005, -0.012), midGamma: rgb(0.98, 1.00, 1.04), blackLift: 0.035, whiteRoll: 0.10, grain: 0.85)
        case .fujiCyan: return LookRecipe(contrast: 0.08, saturation: 1.00, temperature: -0.22, tint: -0.08, shadowTint: rgb(-0.020, 0.012, 0.022), highlightTint: rgb(-0.004, 0.006, 0.010), midGamma: rgb(1.07, 0.97, 0.95), blackLift: 0.025, whiteRoll: 0.08, grain: 0.50)
        case .kodakWarmYellow: return LookRecipe(contrast: 0.12, saturation: 1.12, vibrance: 0.05, temperature: 0.30, tint: -0.03, shadowTint: rgb(0.004, 0.000, -0.006), highlightTint: rgb(0.024, 0.016, -0.028), blackLift: 0.015, whiteRoll: 0.06, grain: 0.60)
        }
    }
}

// MARK: - 人像光效（人像模式）

enum PortraitLighting: String, CaseIterable, Identifiable {
    case off, natural, studio, contour, stage, stageMono, highKeyMono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "关"
        case .natural: return "自然光"
        case .studio: return "摄影棚光"
        case .contour: return "轮廓光"
        case .stage: return "舞台光"
        case .stageMono: return "舞台光单色"
        case .highKeyMono: return "高调单色光"
        }
    }
}

// MARK: - Apple 原有滤镜（鲜明 / 戏剧 / 单色 …）

enum AppleFilter: String, CaseIterable, Identifiable {
    case original, vivid, vividWarm, vividCool, dramatic, dramaticWarm, dramaticCool, mono, silvertone, noir

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "原图"
        case .vivid: return "鲜明"
        case .vividWarm: return "鲜暖色"
        case .vividCool: return "鲜冷色"
        case .dramatic: return "戏剧"
        case .dramaticWarm: return "戏剧暖色"
        case .dramaticCool: return "戏剧冷色"
        case .mono: return "单色"
        case .silvertone: return "银色调"
        case .noir: return "黑白"
        }
    }

    var recipe: LookRecipe {
        switch self {
        case .original: return LookRecipe()
        case .vivid: return LookRecipe(contrast: 0.10, saturation: 1.28, vibrance: 0.15)
        case .vividWarm: return LookRecipe(contrast: 0.10, saturation: 1.25, vibrance: 0.12, temperature: 0.22)
        case .vividCool: return LookRecipe(contrast: 0.10, saturation: 1.25, vibrance: 0.12, temperature: -0.22)
        case .dramatic: return LookRecipe(exposure: -0.08, contrast: 0.45, saturation: 0.82, whiteRoll: 0.05)
        case .dramaticWarm: return LookRecipe(exposure: -0.08, contrast: 0.45, saturation: 0.82, temperature: 0.20, whiteRoll: 0.05)
        case .dramaticCool: return LookRecipe(exposure: -0.08, contrast: 0.45, saturation: 0.82, temperature: -0.20, whiteRoll: 0.05)
        case .mono: return LookRecipe(contrast: 0.10, mono: 1)
        case .silvertone: return LookRecipe(exposure: 0.04, contrast: 0.02, blackLift: 0.04, whiteRoll: 0.05, mono: 1)
        case .noir: return LookRecipe(exposure: -0.10, contrast: 0.55, mono: 1)
        }
    }

    /// 滤镜卡片的渐变色：把 3 个参考色送进该滤镜自己的配方。
    var cardColors: [Color] {
        let samples: [(Float, Float, Float)] = [(0.93, 0.93, 0.95), (0.82, 0.60, 0.50), (0.16, 0.17, 0.20)]
        let r = recipe
        return samples.map { sample in
            let out = FilterEngine.transform(sample.0, sample.1, sample.2, r)
            return Color(red: Double(out.0), green: Double(out.1), blue: Double(out.2))
        }
    }
}

// MARK: - 界面上的全部风格状态

/// 预览、拍照、录像都读取同一个值，因此“名称 / 预览 / 成片”不会不同步。
struct StyleSettings: Equatable {
    var style: CameraStyle = .standard
    var filter: AppleFilter = .original
    /// 色调板（按“调色盘使用公式”）：横向 = 纯度（左灰 → 右纯），纵向 = 明度（上亮 → 下暗）。
    /// 默认点在第 8 列（x = 0.8）、中间一行：风格的“原味”。
    var point = CGPoint(x: 0.8, y: 0.5)
    /// 调色盘浓度 0...1（淡 → 浓，1 = 完整配方）。
    var intensity: Double = 1.0
    /// 保留字段（曝光现在由相机硬件补偿控制）。
    var exposure: Double = 0
    /// 人像光效（只在人像模式里不为 .off）。
    var lighting: PortraitLighting = .off
    /// 景深：背景虚化强度 0...1（0 = 关）。
    var depth: Double = 0

    static let defaultPoint = CGPoint(x: 0.8, y: 0.5)

    var isPaletteDefault: Bool {
        abs(point.x - 0.8) < 0.001 && abs(point.y - 0.5) < 0.001
    }

    var isIdentity: Bool {
        style == .standard && filter == .original && isPaletteDefault && abs(exposure) < 0.001
            && lighting == .off && depth < 0.001
    }
}
