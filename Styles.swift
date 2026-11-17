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
    case fujiProvia, fujiVelvia, fujiAstia, fujiRealaAce, fujiClassicChrome, fujiClassicNeg, fujiProNeg, fujiEterna, fujiEternaBB

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "标准".ycamLocalized
        case .pearl: return "珠光 Pearl".ycamLocalized
        case .amber: return "琥珀色 Amber".ycamLocalized
        case .gold: return "金色 Gold".ycamLocalized
        case .roseGold: return "玫瑰金 Rose Gold".ycamLocalized
        case .coolRose: return "冷调玫瑰色 Cool Rose".ycamLocalized
        case .cool: return "冷调 Cool".ycamLocalized
        case .radiant: return "耀目 Bright".ycamLocalized
        case .neutral: return "自然 Neutral".ycamLocalized
        case .vibrant: return "鲜明 Vibrant".ycamLocalized
        case .warm: return "温馨 Warm".ycamLocalized
        case .ethereal: return "空灵 Ethereal".ycamLocalized
        case .dramatic: return "戏剧 Dramatic".ycamLocalized
        case .luminous: return "明亮 Luminous".ycamLocalized
        case .monochrome: return "黑白 Mono".ycamLocalized
        case .fuji400: return "FUJI 400"
        case .kodak800: return "KODAK 800"
        case .fujiCyan: return "FUJI 青调".ycamLocalized
        case .kodakWarmYellow: return "KODAK 暖黄".ycamLocalized
        case .fujiProvia: return "富士 PROVIA".ycamLocalized
        case .fujiVelvia: return "富士 Velvia".ycamLocalized
        case .fujiAstia: return "富士 ASTIA".ycamLocalized
        case .fujiRealaAce: return "富士 REALA ACE".ycamLocalized
        case .fujiClassicChrome: return "富士 经典铬 CC".ycamLocalized
        case .fujiClassicNeg: return "富士 经典负片 CN".ycamLocalized
        case .fujiProNeg: return "富士 PRO Neg".ycamLocalized
        case .fujiEterna: return "富士 ETERNA".ycamLocalized
        case .fujiEternaBB: return "富士 ETERNA BB".ycamLocalized
        }
    }

    /// 用户最新 iPhone 风格录屏中的「进入时白点/调色板」参考值。
    /// 按原片时间顺序：重复进入同一风格时以最后一次可见的稳定数值为准。
    /// 每个风格独立配置；配方及 LUT 保持原样，不能将某一风格的颜色套给其他风格。
    /// 未能明确对应到 YCam 风格名称的截图保留中性默认值，绝不猜测。
    /// 数据和局限：calibration/latest_style_entry_values_2026-11-17.json
    var referenceControls: (tone: Int, color: Int, intensity: Double) {
        switch self {
        case .pearl: return (18, 0, 1.0)
        case .amber: return (100, 100, 1.0)
        case .gold: return (20, 10, 0.85)
        case .roseGold: return (-20, -20, 0.75)
        case .coolRose: return (35, -10, 0.75)
        case .neutral: return (-70, -15, 1.0)
        case .vibrant: return (-30, 33, 1.0)
        case .radiant: return (35, 30, 1.0)
        case .warm: return (-75, -20, 1.0)
        default: return (0, 0, 1.0)
        }
    }

    var isFilm: Bool {
        switch self {
        case .fuji400, .kodak800, .fujiCyan, .kodakWarmYellow: return true
        case .fujiProvia, .fujiVelvia, .fujiAstia, .fujiRealaAce, .fujiClassicChrome, .fujiClassicNeg, .fujiProNeg, .fujiEterna, .fujiEternaBB: return true
        default: return false
        }
    }

    /// 用 .cube 数据做的风格（富士胶片模拟）：对应 Assets.xcassets 里的 LUT_<名字>.dataset；nil = 普通配方风格。
    var lutName: String? {
        switch self {
        case .fujiProvia: return "PROVIA"
        case .fujiVelvia: return "VELVIA"
        case .fujiAstia: return "ASTIA"
        case .fujiRealaAce: return "REALA"
        case .fujiClassicChrome: return "CC"
        case .fujiClassicNeg: return "CN"
        case .fujiProNeg: return "PRONEG"
        case .fujiEterna: return "ETERNA"
        case .fujiEternaBB: return "ETERNABB"
        default: return nil
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
        case .fujiProvia: return Color(red: 0.44, green: 0.62, blue: 0.86)
        case .fujiVelvia: return Color(red: 0.88, green: 0.22, blue: 0.30)
        case .fujiAstia: return Color(red: 0.96, green: 0.72, blue: 0.74)
        case .fujiRealaAce: return Color(red: 0.60, green: 0.74, blue: 0.62)
        case .fujiClassicChrome: return Color(red: 0.55, green: 0.60, blue: 0.52)
        case .fujiClassicNeg: return Color(red: 0.62, green: 0.70, blue: 0.50)
        case .fujiProNeg: return Color(red: 0.84, green: 0.74, blue: 0.68)
        case .fujiEterna: return Color(red: 0.40, green: 0.56, blue: 0.58)
        case .fujiEternaBB: return Color(red: 0.55, green: 0.56, blue: 0.58)
        }
    }

    /// 风格卡片的渐变色：把 3 个参考色（高光 / 肤色 / 暗部）送进该风格自己的配方，所见即所得（不是另外画的假色块）。
    // The 28 cards are invariant under 2D palette dragging. Compute each
    // three-stop gradient once, instead of repeating LUT lookups/colour math
    // whenever a frame, style control, or gesture updates SwiftUI.
    private static let cardColorCache: [CameraStyle: [Color]] = {
        var cache: [CameraStyle: [Color]] = [:]
        for style in CameraStyle.allCases {
            cache[style] = style.makeCardColors()
        }
        return cache
    }()

    var cardColors: [Color] { Self.cardColorCache[self] ?? [] }

    private func makeCardColors() -> [Color] {
        let samples: [(Float, Float, Float)] = [(0.93, 0.93, 0.95), (0.82, 0.60, 0.50), (0.16, 0.17, 0.20)]
        if let name = lutName, let lut = LutLibrary.shared.table(named: name) {
            return samples.map { sample in
                let out = lut.sample(sample.0, sample.1, sample.2)
                return Color(red: Double(out.0), green: Double(out.1), blue: Double(out.2))
            }
        }
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
        case .pearl: return LookRecipe(exposure: -0.015, contrast: 0.065, saturation: 1.01, vibrance: 0.04, temperature: 0.01, tint: 0.035, shadowTint: rgb(0.014, -0.005, 0.017), highlightTint: rgb(0.001, 0.001, 0.001), whiteRoll: 0.10)
        case .amber: return LookRecipe(exposure: -0.030, contrast: 0.090, saturation: 1.06, temperature: 0.30, tint: 0.09, highlightTint: rgb(0.016, 0.002, -0.010), whiteRoll: 0.09)
        case .gold: return LookRecipe(exposure: 0.005, contrast: 0.085, saturation: 0.99, temperature: 0.22, tint: -0.075, highlightTint: rgb(0.007, 0.008, -0.009), blackLift: 0.008, whiteRoll: 0.10)
        case .roseGold: return LookRecipe(exposure: -0.025, contrast: 0.055, saturation: 1.015, temperature: 0.145, tint: 0.17, highlightTint: rgb(0.008, 0.001, 0.008), whiteRoll: 0.08)
        case .coolRose: return LookRecipe(exposure: 0.005, contrast: 0.085, saturation: 1.015, temperature: -0.13, tint: 0.16, highlightTint: rgb(0.006, 0.000, 0.010), whiteRoll: 0.10)
        case .cool: return LookRecipe(exposure: -0.03, contrast: 0.08, saturation: 1.00, temperature: -0.28, tint: -0.03, highlightTint: rgb(-0.003, 0.004, 0.011))
        case .radiant: return LookRecipe(exposure: 0.015, contrast: 0.10, saturation: 1.045, vibrance: 0.12, shadowTint: rgb(-0.004, 0.004, 0.008), highlightTint: rgb(0.006, 0.001, 0.006), whiteRoll: 0.16)
        case .neutral: return LookRecipe(exposure: 0.00, contrast: 0.015, saturation: 0.995, temperature: -0.025, whiteRoll: 0.06)
        case .vibrant: return LookRecipe(exposure: -0.045, contrast: 0.095, saturation: 1.08, vibrance: 0.22, temperature: -0.12, tint: 0.065, highlightTint: rgb(-0.008, -0.010, 0.008), whiteRoll: 0.08)
        case .warm: return LookRecipe(exposure: 0.01, contrast: 0.04, saturation: 1.025, temperature: 0.17, tint: 0.01, whiteRoll: 0.09)
        case .ethereal: return LookRecipe(exposure: 0.025, contrast: -0.025, saturation: 0.97, temperature: -0.04, blackLift: 0.004, whiteRoll: 0.08)
        case .dramatic: return LookRecipe(exposure: -0.12, contrast: 0.60, saturation: 1.06, whiteRoll: 0.06)
        case .luminous: return LookRecipe(exposure: 0.045, contrast: 0.06, saturation: 1.04, vibrance: 0.10, whiteRoll: 0.10)
        case .monochrome: return LookRecipe(contrast: 0.16, mono: 1)
        case .fuji400: return LookRecipe(contrast: 0.12, saturation: 1.06, vibrance: 0.08, temperature: -0.10, tint: -0.05, shadowTint: rgb(-0.008, 0.010, 0.012), highlightTint: rgb(-0.002, 0.004, 0.002), midGamma: rgb(1.02, 0.97, 1.00), blackLift: 0.025, whiteRoll: 0.08, grain: 0.55)
        case .kodak800: return LookRecipe(exposure: 0.02, contrast: 0.02, saturation: 0.98, temperature: 0.16, tint: 0.03, shadowTint: rgb(0.008, 0.002, -0.004), highlightTint: rgb(0.010, 0.005, -0.012), midGamma: rgb(0.98, 1.00, 1.04), blackLift: 0.035, whiteRoll: 0.10, grain: 0.85)
        case .fujiCyan: return LookRecipe(contrast: 0.08, saturation: 1.00, temperature: -0.22, tint: -0.08, shadowTint: rgb(-0.020, 0.012, 0.022), highlightTint: rgb(-0.004, 0.006, 0.010), midGamma: rgb(1.07, 0.97, 0.95), blackLift: 0.025, whiteRoll: 0.08, grain: 0.50)
        case .kodakWarmYellow: return LookRecipe(contrast: 0.12, saturation: 1.12, vibrance: 0.05, temperature: 0.30, tint: -0.03, shadowTint: rgb(0.004, 0.000, -0.006), highlightTint: rgb(0.024, 0.016, -0.028), blackLift: 0.015, whiteRoll: 0.06, grain: 0.60)
        case .fujiProvia: return LookRecipe(contrast: 0.015, saturation: 1.005, whiteRoll: 0.025)
        case .fujiVelvia: return LookRecipe(contrast: 0.030, saturation: 1.025, whiteRoll: 0.040)
        case .fujiAstia: return LookRecipe(contrast: -0.015, saturation: 0.985, whiteRoll: 0.035)
        case .fujiRealaAce: return LookRecipe(contrast: 0.018, saturation: 0.995, tint: -0.006)
        case .fujiClassicChrome: return LookRecipe(contrast: 0.018, saturation: 0.980, blackLift: 0.003)
        case .fujiClassicNeg: return LookRecipe(contrast: 0.040, saturation: 1.000, blackLift: 0.005)
        case .fujiProNeg: return LookRecipe(contrast: -0.005, saturation: 0.980, tint: 0.004)
        case .fujiEterna: return LookRecipe(contrast: -0.018, saturation: 0.965, whiteRoll: 0.030)
        case .fujiEternaBB: return LookRecipe(contrast: 0.028, saturation: 0.970, blackLift: 0.006)
        }
    }
}

// MARK: - 人像光效（人像模式）

enum PortraitLighting: String, CaseIterable, Identifiable {
    case off, natural, studio, contour, stage, stageMono, highKeyMono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "关".ycamLocalized
        case .natural: return "自然光".ycamLocalized
        case .studio: return "摄影棚光".ycamLocalized
        case .contour: return "轮廓光".ycamLocalized
        case .stage: return "舞台光".ycamLocalized
        case .stageMono: return "舞台光单色".ycamLocalized
        case .highKeyMono: return "高调单色光".ycamLocalized
        }
    }
}

// MARK: - Apple 原有滤镜（鲜明 / 戏剧 / 单色 …）

enum AppleFilter: String, CaseIterable, Identifiable {
    case original, vivid, vividWarm, vividCool, dramatic, dramaticWarm, dramaticCool, mono, silvertone, noir

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "原图".ycamLocalized
        case .vivid: return "鲜明".ycamLocalized
        case .vividWarm: return "鲜暖色".ycamLocalized
        case .vividCool: return "鲜冷色".ycamLocalized
        case .dramatic: return "戏剧".ycamLocalized
        case .dramaticWarm: return "戏剧暖色".ycamLocalized
        case .dramaticCool: return "戏剧冷色".ycamLocalized
        case .mono: return "单色".ycamLocalized
        case .silvertone: return "银色调".ycamLocalized
        case .noir: return "黑白".ycamLocalized
        }
    }

    var recipe: LookRecipe {
        switch self {
        case .original: return LookRecipe()
        case .vivid: return LookRecipe(contrast: 0.10, saturation: 1.28, vibrance: 0.15)
        case .vividWarm: return LookRecipe(exposure: 0.26, contrast: 0.03, saturation: 1.38, vibrance: 0.17, temperature: 0.34, tint: 0.07, blackLift: 0.06, whiteRoll: 0.10)
        case .vividCool: return LookRecipe(exposure: 0.29, contrast: 0.12, saturation: 1.25, vibrance: 0.12, temperature: -0.47, tint: -0.03, blackLift: 0.04, whiteRoll: 0.09)
        case .dramatic: return LookRecipe(exposure: -0.03, contrast: 0.41, saturation: 0.74, temperature: 0.01, tint: 0.01, blackLift: 0.04, whiteRoll: 0.08)
        case .dramaticWarm: return LookRecipe(exposure: -0.18, contrast: 0.53, saturation: 0.77, vibrance: 0.05, temperature: 0.52, tint: -0.015, whiteRoll: 0.03)
        case .dramaticCool: return LookRecipe(exposure: -0.08, contrast: 0.45, saturation: 0.82, temperature: -0.20, whiteRoll: 0.05)
        case .mono: return LookRecipe(exposure: 0.10, contrast: 0.35, whiteRoll: 0.03, mono: 1)
        case .silvertone: return LookRecipe(exposure: 0.35, contrast: 0.24, temperature: 0.46, tint: 0.03, blackLift: 0.055, whiteRoll: 0.08, mono: 0.88)
        case .noir: return LookRecipe(exposure: 0.08, contrast: 0.88, whiteRoll: 0.01, mono: 1)
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
    /// iPhone 摄影风格调色盘：水平颜色 −100...+100，垂直色调 +100...−100。
    /// 注意这些是 YCam 的控制刻度，不是 Apple 未公开的底层色彩参数。
    var point = CGPoint(x: 0.5, y: 0.5)
    /// 调色盘强度 0...1（0 = 原始配方不生效）。
    var intensity: Double = 1.0
    /// 保留字段（曝光现在由相机硬件补偿控制）。
    var exposure: Double = 0
    /// 人像光效（只在人像模式里不为 .off）。
    var lighting: PortraitLighting = .off
    /// 景深：背景虚化强度 0...1（0 = 关）。
    var depth: Double = 0

    static let defaultPoint = CGPoint(x: 0.5, y: 0.5)

    /// 每次选风格或点重置，恢复该风格最新截图支持的进入位置和强度。
    mutating func restoreStyleControls() {
        let reference = style.referenceControls
        point = CGPoint(x: CGFloat(reference.color + 100) / 200,
                        y: CGFloat(100 - reference.tone) / 200)
        intensity = reference.intensity
    }

    var isPaletteDefault: Bool {
        let reference = style.referenceControls
        let desiredX = CGFloat(reference.color + 100) / 200
        let desiredY = CGFloat(100 - reference.tone) / 200
        return abs(point.x - desiredX) < 0.001 && abs(point.y - desiredY) < 0.001
    }

    var isIdentity: Bool {
        style == .standard && filter == .original && isPaletteDefault && abs(exposure) < 0.001
            && lighting == .off && depth < 0.001
    }
}
