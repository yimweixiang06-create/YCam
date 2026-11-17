import UIKit
import CoreImage
import CoreGraphics
import Foundation
import Vision

/// 风格引擎：预览帧、录像帧、照片、实况动态部分都调用这里，保证“选中的风格 = 看到的 = 拍到的”。
///
/// 颜色部分由 `transform(...)` 逐点计算后烘焙成 32³ 3D LUT，交给 Core Image（GPU）执行；
/// 人像光效 / 景深用 Vision 人物分割蒙版；柔光、柔焦、胶片颗粒单独用 Core Image 滤镜叠加。
final class FilterEngine {
    static let shared = FilterEngine()

    /// 某一时刻的完整处理参数（不可变，可跨线程安全使用）。
    struct Snapshot {
        let settings: StyleSettings
        let recipe: LookRecipe     // 已叠加“浓度”“Apple 滤镜”“色调板”的有效配方
        let cube: Data?            // nil = 颜色部分不需要处理

        /// 是否需要人物分割蒙版（人像光效或景深）。
        var needsMask: Bool { settings.lighting != .off || settings.depth > 0.001 }

        /// 颜色 / 柔光 / 颗粒都不需要处理（视频模式下可以直接用相机原始帧，省掉整条 GPU 流水线）。
        var hasPaletteShift: Bool {
            settings.filter == .original && settings.intensity > 0.001 &&
                (abs(settings.point.x - 0.5) > 0.0005 || abs(settings.point.y - 0.5) > 0.0005)
        }

        var isPassthroughColor: Bool {
            cube == nil && !hasPaletteShift && recipe.bloom < 0.001 &&
                recipe.grain < 0.001 && recipe.softness < 0.001
        }
    }

    static let cubeDimension = 33          // 与 .cube 数据的 33 格对齐，LUT 节点不用再插值
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private let lock = NSLock()
    private var current: Snapshot
    private var desired = StyleSettings()
    private var version = 0
    private var pendingBuild: DispatchWorkItem?
    private let buildQueue = DispatchQueue(label: "ycam.style.build", qos: .userInitiated)

    private init() {
        current = FilterEngine.makeSnapshot(StyleSettings())
    }

    // MARK: Settings

    /// 界面改动风格后调用。LUT 在后台线程生成，连续拖动时只构建最新一次。
    func update(_ settings: StyleSettings) {
        lock.lock()
        desired = settings
        version += 1
        let v = version
        pendingBuild?.cancel()
        // Tone/color and portrait options change every touch but must not
        // rebuild the expensive 33^3 style cube. Apply these on the GPU now.
        let previous = current
        if sameBakedStyle(previous.settings, settings) {
            current = Snapshot(settings: settings, recipe: previous.recipe, cube: previous.cube)
            lock.unlock()
            return
        }
        // Only changes to the selected style, filter, strength or exposure
        // need an asynchronous LUT rebuild.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let latest = self.version
            let want = self.desired
            self.lock.unlock()
            guard latest == v else { return }
            let snap = FilterEngine.makeSnapshot(want)
            self.lock.lock()
            if self.version == v { self.current = snap }
            self.lock.unlock()
        }
        pendingBuild = work
        lock.unlock()
        buildQueue.asyncAfter(deadline: .now() + .milliseconds(16), execute: work)
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// 拍照时使用：保证拿到与按下快门瞬间界面状态完全一致的参数（必要时同步生成）。
    func snapshot(for settings: StyleSettings) -> Snapshot {
        lock.lock()
        let cur = current
        lock.unlock()
        if cur.settings == settings { return cur }
        if sameBakedStyle(cur.settings, settings) {
            return Snapshot(settings: settings, recipe: cur.recipe, cube: cur.cube)
        }
        return FilterEngine.makeSnapshot(settings)
    }

    private func sameBakedStyle(_ a: StyleSettings, _ b: StyleSettings) -> Bool {
        a.style == b.style && a.filter == b.filter &&
            a.intensity == b.intensity && a.exposure == b.exposure
    }

    static func makeSnapshot(_ s: StyleSettings) -> Snapshot {
        // Build a stable style LUT. The 2D pad is a live GPU adjustment.
        var base = s
        base.point = StyleSettings.defaultPoint
        let recipe = effectiveRecipe(for: base)
        // Traditional filters use only their own recipe. Do not leak the
        // selected Photographic Style's LUT into an ordinary photo filter.
        let lut: LutTable? = s.filter == .original
            ? s.style.lutName.flatMap { LutLibrary.shared.table(named: $0) }
            : nil
        let strength = Float(min(1, max(0, s.intensity)))
        let cube: Data? = (recipe.isColorIdentity && lut == nil) ? nil : buildCube(recipe, lut: lut, strength: strength)
        return Snapshot(settings: s, recipe: recipe, cube: cube)
    }

    /// 色调/颜色算法以 (0,0) 为数学中性点；各风格的首次进入
    /// UI 位置/调色板强度由 StyleSettings.restoreStyleControls() 决定。
    /// 这些截图测得的 UI 默认值不等同于 Apple 专有 ISP 系数；
    /// 不改动独立风格配方或已校准的 Pearl 色彩曲线。
    static func effectiveRecipe(for s: StyleSettings) -> LookRecipe {
        let k = Float(min(1, max(0, s.intensity)))
        // Keep Apple-style traditional filters and YCam's 28 Photographic
        // Styles mutually exclusive in the color pipeline. This prevents
        // double warmth or hidden style/palette shifts on filter preview,
        // photographs and video, while preserving every style's own recipe.
        var r = s.filter == .original
            ? s.style.recipe.scaled(by: k)
            : s.filter.recipe
        r.exposure += Float(s.exposure)
        return r
    }

    // Each of YCam's 28 photographic styles has its own pad-to-image curve.
    // Shared algorithm != shared color recipe. Values not backed by paired
    // Apple/YCam captures are conservative artistic presets, not Apple ISP.
    private struct PhotoStyleResponse {
        let gamma: Double
        let left: Double
        let right: Double
        let upperCorner: Double
        let lowerCorner: Double
        let exposure: Double
    }

    private static func photoStyleResponse(for style: CameraStyle) -> PhotoStyleResponse {
        switch style {
        case .standard: return PhotoStyleResponse(gamma: 0.070, left: 0.260, right: 0.250, upperCorner: 0.280, lowerCorner: 0.440, exposure: 0.006)
        case .pearl: return PhotoStyleResponse(gamma: 0.072, left: 0.680, right: 0.310, upperCorner: 0.115, lowerCorner: 0.210, exposure: 0.012)
        case .amber: return PhotoStyleResponse(gamma: 0.120, left: 0.520, right: 0.300, upperCorner: 0.175, lowerCorner: 0.290, exposure: 0.016)
        case .gold: return PhotoStyleResponse(gamma: 0.125, left: 0.635, right: 0.568, upperCorner: 0.140, lowerCorner: 0.260, exposure: 0.018)
        case .roseGold: return PhotoStyleResponse(gamma: 0.115, left: 0.652, right: 0.563, upperCorner: 0.160, lowerCorner: 0.270, exposure: 0.013)
        case .coolRose: return PhotoStyleResponse(gamma: 0.107, left: 0.752, right: 0.690, upperCorner: 0.155, lowerCorner: 0.250, exposure: 0.010)
        case .cool: return PhotoStyleResponse(gamma: 0.102, left: 0.950, right: 0.543, upperCorner: 0.150, lowerCorner: 0.280, exposure: 0.009)
        case .neutral: return PhotoStyleResponse(gamma: 0.080, left: 0.791, right: 0.652, upperCorner: 0.180, lowerCorner: 0.300, exposure: 0.008)
        case .vibrant: return PhotoStyleResponse(gamma: 0.135, left: 0.587, right: 0.491, upperCorner: 0.140, lowerCorner: 0.260, exposure: 0.017)
        case .warm: return PhotoStyleResponse(gamma: 0.118, left: 0.610, right: 0.345, upperCorner: 0.185, lowerCorner: 0.290, exposure: 0.013)
        case .ethereal: return PhotoStyleResponse(gamma: 0.085, left: 0.500, right: 0.270, upperCorner: 0.190, lowerCorner: 0.330, exposure: 0.009)
        case .dramatic: return PhotoStyleResponse(gamma: 0.095, left: 0.425, right: 0.280, upperCorner: 0.230, lowerCorner: 0.320, exposure: 0.010)
        case .luminous: return PhotoStyleResponse(gamma: 0.105, left: 0.550, right: 0.310, upperCorner: 0.180, lowerCorner: 0.310, exposure: 0.012)
        case .radiant: return PhotoStyleResponse(gamma: 0.130, left: 0.540, right: 0.375, upperCorner: 0.175, lowerCorner: 0.270, exposure: 0.014)
        case .monochrome: return PhotoStyleResponse(gamma: 0.070, left: 0.200, right: 0.210, upperCorner: 0.300, lowerCorner: 0.360, exposure: 0.006)
        case .fuji400: return PhotoStyleResponse(gamma: 0.100, left: 0.440, right: 0.310, upperCorner: 0.260, lowerCorner: 0.330, exposure: 0.009)
        case .kodak800: return PhotoStyleResponse(gamma: 0.095, left: 0.480, right: 0.320, upperCorner: 0.220, lowerCorner: 0.300, exposure: 0.011)
        case .fujiCyan: return PhotoStyleResponse(gamma: 0.092, left: 0.450, right: 0.325, upperCorner: 0.250, lowerCorner: 0.350, exposure: 0.010)
        case .kodakWarmYellow: return PhotoStyleResponse(gamma: 0.104, left: 0.495, right: 0.350, upperCorner: 0.230, lowerCorner: 0.335, exposure: 0.013)
        case .fujiProvia: return PhotoStyleResponse(gamma: 0.088, left: 0.405, right: 0.290, upperCorner: 0.240, lowerCorner: 0.340, exposure: 0.009)
        case .fujiVelvia: return PhotoStyleResponse(gamma: 0.099, left: 0.390, right: 0.360, upperCorner: 0.255, lowerCorner: 0.345, exposure: 0.010)
        case .fujiAstia: return PhotoStyleResponse(gamma: 0.082, left: 0.425, right: 0.275, upperCorner: 0.235, lowerCorner: 0.355, exposure: 0.008)
        case .fujiRealaAce: return PhotoStyleResponse(gamma: 0.085, left: 0.415, right: 0.295, upperCorner: 0.245, lowerCorner: 0.325, exposure: 0.009)
        case .fujiClassicChrome: return PhotoStyleResponse(gamma: 0.093, left: 0.370, right: 0.315, upperCorner: 0.240, lowerCorner: 0.310, exposure: 0.010)
        case .fujiClassicNeg: return PhotoStyleResponse(gamma: 0.103, left: 0.385, right: 0.335, upperCorner: 0.265, lowerCorner: 0.320, exposure: 0.012)
        case .fujiProNeg: return PhotoStyleResponse(gamma: 0.077, left: 0.420, right: 0.282, upperCorner: 0.230, lowerCorner: 0.300, exposure: 0.007)
        case .fujiEterna: return PhotoStyleResponse(gamma: 0.075, left: 0.375, right: 0.265, upperCorner: 0.255, lowerCorner: 0.365, exposure: 0.008)
        case .fujiEternaBB: return PhotoStyleResponse(gamma: 0.098, left: 0.405, right: 0.302, upperCorner: 0.265, lowerCorner: 0.350, exposure: 0.011)
        }
    }

    // MARK: Colour math (mirrored line by line in tools/style_check.py)

    // The screenshots show large shadow/midtone movement but comparatively
    // modest white-paper movement. Apple Core Image's built-in CIToneCurve
    // preserves the black/white endpoints without a global exposure boost.
    // Each curve is independently fitted to its identified screenshot points.
    // NOT Apple's proprietary Photographic Styles rendering coefficients.
    private struct ScreenReferenceCurve {
        let shadow: Double
        let midtone: Double
        let highlight: Double
    }

    private static func screenReferenceCurve(for style: CameraStyle) -> ScreenReferenceCurve? {
        switch style {
        case .gold: return ScreenReferenceCurve(shadow: 0.14500, midtone: 0.16505, highlight: 0.04713)
        case .coolRose: return ScreenReferenceCurve(shadow: 0.11676, midtone: 0.15070, highlight: 0.02737)
        case .cool: return ScreenReferenceCurve(shadow: 0.14500, midtone: 0.17000, highlight: 0.04279)
        case .roseGold: return ScreenReferenceCurve(shadow: 0.14500, midtone: 0.17000, highlight: 0.03762)
        case .vibrant: return ScreenReferenceCurve(shadow: 0.12392, midtone: 0.13825, highlight: 0.03401)
        case .neutral: return ScreenReferenceCurve(shadow: 0.11966, midtone: 0.13169, highlight: 0.02558)
        default: return nil // No trustworthy screenshot group for these styles
        }
    }

    @inline(__always) private static func toLinear(_ v: Float) -> Float {
        v <= 0.04045 ? v / 12.92 : powf((v + 0.055) / 1.055, 2.4)
    }

    @inline(__always) private static func toGamma(_ v: Float) -> Float {
        v <= 0.0031308 ? v * 12.92 : 1.055 * powf(v, 1.0 / 2.4) - 0.055
    }

    @inline(__always) private static func clamp01(_ v: Float) -> Float { min(1, max(0, v)) }

    @inline(__always) private static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = clamp01((x - e0) / (e1 - e0))
        return t * t * (3 - 2 * t)
    }

    @inline(__always) private static func luma(_ r: Float, _ g: Float, _ b: Float) -> Float {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// 输入/输出均为 sRGB 编码的 0...1。
    static func transform(_ ir: Float, _ ig: Float, _ ib: Float, _ p: LookRecipe) -> (Float, Float, Float) {
        // 1. 线性光 + 曝光
        let gain = powf(2, p.exposure)
        var lr = toLinear(ir) * gain
        var lg = toLinear(ig) * gain
        var lb = toLinear(ib) * gain

        // 2. 色温 / 色调（保持亮度不变）
        let t = p.temperature
        let n = p.tint
        let wr = 1 + 0.22 * t + 0.03 * n
        let wg = 1 - 0.12 * n + 0.02 * t
        let wb = 1 - 0.28 * t + 0.03 * n
        let y0 = luma(lr, lg, lb)
        lr *= wr
        lg *= wg
        lb *= wb
        let y1 = luma(lr, lg, lb)
        if y1 > 1e-6 {
            let k = y0 / y1
            lr *= k
            lg *= k
            lb *= k
        }

        // 3. 回到伽马域
        var r = toGamma(clamp01(lr))
        var g = toGamma(clamp01(lg))
        var b = toGamma(clamp01(lb))

        // 4. 分通道中间调伽马（胶片串色）
        r = powf(r, p.midGamma.r)
        g = powf(g, p.midGamma.g)
        b = powf(b, p.midGamma.b)

        // 5. 对比度（S 曲线；为负时变平）
        let c = max(-1, min(1, p.contrast))
        r += c * (r * r * (3 - 2 * r) - r)
        g += c * (g * g * (3 - 2 * g) - g)
        b += c * (b * b * (3 - 2 * b) - b)

        // 6. 饱和度 / 自然饱和度
        let l1 = luma(r, g, b)
        let chroma = max(r, max(g, b)) - min(r, min(g, b))
        let sat = max(0, p.saturation * (1 + p.vibrance * (1 - chroma)))
        r = l1 + (r - l1) * sat
        g = l1 + (g - l1) * sat
        b = l1 + (b - l1) * sat

        // 7. 暗部 / 亮部偏色
        let l2 = luma(clamp01(r), clamp01(g), clamp01(b))
        let sw = 1 - smooth(0, 0.55, l2)
        let hw = smooth(0.45, 1.0, l2)
        r += p.shadowTint.r * sw + p.highlightTint.r * hw
        g += p.shadowTint.g * sw + p.highlightTint.g * hw
        b += p.shadowTint.b * sw + p.highlightTint.b * hw

        // 8. 黑位抬升 / 高光压缩
        r = clamp01(r)
        g = clamp01(g)
        b = clamp01(b)
        let bl = p.blackLift
        r = bl + r * (1 - bl)
        g = bl + g * (1 - bl)
        b = bl + b * (1 - bl)
        let wrl = p.whiteRoll
        if wrl != 0 {
            if r > 0.6 { let q = (r - 0.6) / 0.4; r -= wrl * 0.25 * q * q }
            if g > 0.6 { let q = (g - 0.6) / 0.4; g -= wrl * 0.25 * q * q }
            if b > 0.6 { let q = (b - 0.6) / 0.4; b -= wrl * 0.25 * q * q }
        }

        // 9. 黑白
        if p.mono > 0 {
            let l3 = luma(r, g, b)
            r += (l3 - r) * p.mono
            g += (l3 - g) * p.mono
            b += (l3 - b) * p.mono
        }
        return (clamp01(r), clamp01(g), clamp01(b))
    }

    /// 生成 RGBA(float32, 预乘) 的 3D LUT；红色变化最快，蓝色最慢（Core Image 要求的排列）。
    /// lut：.cube 风格的查找表（先过 LUT，按浓度与原色混合，再叠加色调板 / 滤镜这些配方调整）。
    static func buildCube(_ p: LookRecipe, lut: LutTable? = nil, strength: Float = 1) -> Data {
        let n = cubeDimension
        var floats = [Float](repeating: 0, count: n * n * n * 4)
        let inv = 1 / Float(n - 1)
        var i = 0
        for bi in 0..<n {
            let b = Float(bi) * inv
            for gi in 0..<n {
                let g = Float(gi) * inv
                for ri in 0..<n {
                    let r = Float(ri) * inv
                    var cr = r, cg = g, cb = b
                    if let lut {
                        let l = lut.sample(r, g, b)
                        cr = r + (l.0 - r) * strength
                        cg = g + (l.1 - g) * strength
                        cb = b + (l.2 - b) * strength
                    }
                    let o = transform(cr, cg, cb, p)
                    floats[i] = o.0
                    floats[i + 1] = o.1
                    floats[i + 2] = o.2
                    floats[i + 3] = 1
                    i += 4
                }
            }
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    // MARK: Core Image pipeline

    /// 对一帧（或整张照片）应用当前风格。任何一步失败都会退回上一步结果，保证预览不会变黑。
    /// mask：人物分割蒙版（白 = 人物）；只有人像光效 / 景深用到。
    func process(_ image: CIImage, snapshot: Snapshot? = nil, grainScale: CGFloat = 1, mask: CIImage? = nil) -> CIImage {
        let snap = snapshot ?? self.snapshot()
        let extent = image.extent
        var out = image

        if snap.needsMask, let mask {
            out = FilterEngine.applyLighting(out, mask: mask, lighting: snap.settings.lighting, depth: snap.settings.depth)
        }
        if snap.settings.filter != .original && snap.recipe.softness > 0.001 {
            // Styles are always spatially sharp. Optional softness is not
            // allowed to leak into any Photographic Style, including Pearl.
            out = FilterEngine.applySoftness(out, amount: snap.recipe.softness, extent: extent)
        }
        if let cube = snap.cube,
           let filter = CIFilter(name: "CIColorCubeWithColorSpace", parameters: [
               kCIInputImageKey: out,
               "inputCubeDimension": FilterEngine.cubeDimension,
               "inputCubeData": cube,
               "inputColorSpace": FilterEngine.srgb
           ]),
           let result = filter.outputImage {
            out = result
        }
        if snap.hasPaletteShift {
            // Color is evaluated by Core Image for every pixel, not taken from
            // a single palette dot or applied as a uniform RGB overlay.
            // The style's baked LUT stays fixed during touch; the 2D pad
            // only modulates tone / chroma with conservative skin-safe limits.
            // These are YCam approximations, NOT Apple's proprietary coefficients.
            let k = min(1.0, max(0.0, snap.settings.intensity))
            let screenCurve = FilterEngine.screenReferenceCurve(for: snap.settings.style)
            // Round-one Pearl measurements: 4,096 RGB patches in four screen
            // photographs and a separate 16-step grayscale strip. The center
            // reference is only a camera preview, so the baked Pearl default
            // stays unchanged. These are conservative approximations, NOT
            // Apple's camera ISP or a device-independent 3D LUT.
            let isRound1Pearl = snap.settings.style == .pearl
            // Screenshots with palette 75 still show nearly gray at the far
            // left of Cool. Keep the horizontal pad independent from the
            // same linear scaling used for the style's base recipe.
            let colorScale = screenCurve == nil ? k : min(1.0, k * 1.35)
            let color = min(1.0, max(-1.0, Double((snap.settings.point.x - 0.5) * 2))) * colorScale
            let rawTone = min(1.0, max(-1.0, Double((0.5 - snap.settings.point.y) * 2))) * k
            let upperRight = max(0.0, color) * max(0.0, rawTone)
            let upperLeft = max(0.0, -color) * max(0.0, rawTone)
            let lowerLeft = max(0.0, -color) * max(0.0, -rawTone)
            let lowerRight = max(0.0, color) * max(0.0, -rawTone)
            // Per-style screenshot response, not a universal exposure/color
            // mapping. The supplied photos show much stronger upper/lower
            // separation and near-neutral colors at the far left edge.
            let response = FilterEngine.photoStyleResponse(for: snap.settings.style)
            let tone = screenCurve == nil ? rawTone * (1.0 - response.upperCorner * upperRight - response.upperCorner * upperLeft
                                 - response.lowerCorner * lowerLeft - response.lowerCorner * lowerRight) : rawTone
            // Upper +3%, lower direct -2%; keep palette axis centered.
            let zoneSaturation = 1.0 + (rawTone >= 0 ? 0.03 : 0.02) * rawTone
            // Use a gentle curve per style; 0.48/0.50 Pearl gamma and
            // negative lower-tone exposure were lifting whites and shadows
            // excessively. Positive exposure * signed tone is symmetric.
            let gammaResponse = response.gamma
            let exposureResponse = response.exposure

            if isRound1Pearl && abs(rawTone) > 0.0001 {
                // Preserve both end points: do not lift true white to clipping.
                // Upper and lower endpoints are intentionally asymmetric:
                // measured upper gray-strip midtones +35..45/255 and lower
                // -20..25/255 vs the same display chart in Standard.
                let up = rawTone > 0
                let shadow = up ? 0.100 : 0.070
                let midtone = up ? 0.145 : 0.080
                let highlight = up ? 0.045 : 0.015
                out = out.applyingFilter("CIToneCurve", parameters: [
                    "inputPoint0": CIVector(x: 0, y: 0),
                    "inputPoint1": CIVector(x: 0.18, y: CGFloat(0.18 + rawTone * shadow)),
                    "inputPoint2": CIVector(x: 0.55, y: CGFloat(0.55 + rawTone * midtone)),
                    "inputPoint3": CIVector(x: 0.90, y: CGFloat(0.90 + rawTone * highlight)),
                    "inputPoint4": CIVector(x: 1, y: 1)
                ])
            } else if abs(tone) > 0.0001 {
                if let screenCurve {
                    // Five anchored values protect neutral white paper and
                    // true black, while independently matching the shadows,
                    // floor midtones and paper/highlight changes in screenshots.
                    // This is a COLOR/TONE filter, never Gaussian blur.
                    let p0 = CIVector(x: 0, y: 0)
                    let p1 = CIVector(x: 0.18, y: CGFloat(0.18 + tone * screenCurve.shadow))
                    let p2 = CIVector(x: 0.55, y: CGFloat(0.55 + tone * screenCurve.midtone))
                    let p3 = CIVector(x: 0.90, y: CGFloat(0.90 + tone * screenCurve.highlight))
                    let p4 = CIVector(x: 1, y: 1)
                    out = out.applyingFilter("CIToneCurve", parameters: [
                        "inputPoint0": p0,
                        "inputPoint1": p1,
                        "inputPoint2": p2,
                        "inputPoint3": p3,
                        "inputPoint4": p4
                    ])
                } else {
                    // User-supplied reference points are not available for
                    // this style: retain its own conservative gamma/EV curve.
                    out = out.applyingFilter("CIGammaAdjust", parameters: [
                        "inputPower": 1 - gammaResponse * tone
                    ])
                    out = out.applyingFilter("CIExposureAdjust", parameters: [
                        kCIInputEVKey: exposureResponse * tone
                    ])
                }
            }
            if abs(color) > 0.0001 && !isRound1Pearl {
                // CIVibrance is color-dependent (protects skin better than
                // blanket desaturation). Keep all positions well above gray.
                out = out.applyingFilter("CIVibrance", parameters: [
                    "inputAmount": 0.18 * color
                ])
            }
            // Color ratio is measured independently at each corner, rather
            // than applying one global recipe to every photographic style.
            // The upper-right screen image showed 1.426x chroma but also
            // substantial channel clipping, so conservatively cap at 1.34x.
            let pearlVertical = min(1.0, max(0.0, (rawTone + 1.0) * 0.5))
            let pearlLeft = 0.243 + 0.026 * pearlVertical
            let pearlRight = 1.160 + 0.180 * pearlVertical
            let pearlSaturation = color < 0
                ? 1.0 + (-color) * (pearlLeft - 1.0)
                : 1.0 + color * (pearlRight - 1.0)
            if isRound1Pearl {
                // Pearl-only branch; other photographic styles keep their
                // exact, previously verified original color-control code.
                out = out.applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: pearlSaturation,
                    kCIInputContrastKey: 1.0
                ])
            } else {
                out = out.applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: (1 + color * (color >= 0 ? response.right : response.left)) * zoneSaturation,
                    kCIInputContrastKey: 1 - 0.04 * tone + 0.03 * upperRight + 0.04 * upperLeft
                ])
            }
            if upperLeft > 0.05 && !isRound1Pearl {
                // Subtle detail recovery at upper-left; no blur or glow.
                out = out.applyingFilter("CISharpenLuminance", parameters: [
                    "inputSharpness": 0.16 * upperLeft
                ])
            }
        }
        if snap.settings.filter != .original && snap.recipe.bloom > 0.001 {
            // No style-added glow: preserves highlight texture and edge detail.
            out = FilterEngine.applyBloom(out, amount: snap.recipe.bloom, extent: extent)
        }
        // 珠光只做轻度亮度边缘强化，不增加任何空间模糊／磨皮。
        // 不动景深蒙版，真正的背景虚化只能由用户开启景深。
        if snap.settings.style == .pearl && snap.settings.filter == .original && snap.settings.intensity > 0.01 {
            // Keep Pearl detail clean, never add a haze/soft-focus blend.
            out = out.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": 0.09])
        }
        if snap.recipe.grain > 0.001 {
            out = FilterEngine.applyGrain(out, amount: snap.recipe.grain, scale: grainScale, extent: extent)
        }
        return out
    }

    /// 人像光效 + 景深：蒙版内是人物，蒙版外是背景。
    private static func applyLighting(_ image: CIImage, mask rawMask: CIImage, lighting: PortraitLighting, depth: Double) -> CIImage {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1, rawMask.extent.width > 0, rawMask.extent.height > 0 else { return image }

        // 蒙版缩放到画面大小，并略微羽化边缘
        let sx = extent.width / rawMask.extent.width
        let sy = extent.height / rawMask.extent.height
        let scaled = rawMask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        let mask = scaled.clampedToExtent()
            .applyingGaussianBlur(sigma: max(1.5, Double(extent.width) * 0.003))
            .cropped(to: extent)

        let effective: PortraitLighting = (lighting == .off) ? .natural : lighting
        let blurSigma = max(3.0, Double(extent.width) * (0.004 + 0.022 * depth))
        let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: blurSigma).cropped(to: extent)
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: extent)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)

        func blend(_ foreground: CIImage, over background: CIImage) -> CIImage {
            foreground.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: background,
                kCIInputMaskImageKey: mask
            ])
        }
        func adjust(_ source: CIImage, ev: Double = 0, contrast: Double = 1, saturation: Double = 1) -> CIImage {
            var result = source
            if ev != 0 {
                result = result.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: ev])
            }
            return result.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: contrast,
                kCIInputSaturationKey: saturation
            ])
        }

        switch effective {
        case .off, .natural:
            return blend(image, over: blurred)
        case .studio:
            return blend(adjust(image, ev: 0.35, contrast: 1.04, saturation: 1.04),
                         over: adjust(blurred, ev: -0.45))
        case .contour:
            var subject = adjust(image, ev: -0.05, contrast: 1.28, saturation: 1.05)
            if let gradient = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: extent.minX, y: extent.midY),
                "inputPoint1": CIVector(x: extent.maxX, y: extent.midY),
                "inputColor0": CIColor(red: 1, green: 1, blue: 1),
                "inputColor1": CIColor(red: 0.5, green: 0.5, blue: 0.5)
            ])?.outputImage?.cropped(to: extent) {
                subject = subject.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: gradient])
            }
            return blend(subject, over: adjust(blurred, ev: -0.55))
        case .stage:
            return blend(adjust(image, ev: 0.10, contrast: 1.08), over: black)
        case .stageMono:
            return blend(adjust(image, ev: 0.10, contrast: 1.15, saturation: 0), over: black)
        case .highKeyMono:
            return blend(adjust(image, ev: 0.45, contrast: 0.95, saturation: 0), over: white)
        }
    }

    /// 可选柔焦实现（当前摄影风格默认均不会启用）；不要用它来制作珠光。
    private static func applySoftness(_ image: CIImage, amount: Float, extent: CGRect) -> CIImage {
        let sigma = max(1.5, Double(extent.width) * 0.0035)
        let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
        let weight = CGFloat(min(0.9, amount))
        return blurred
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: weight)])
            .composited(over: image)
            .cropped(to: extent)
    }

    /// 可选柔光实现（所有摄影风格初始配方均为 bloom = 0，避免全画面雾化）。
    private static func applyBloom(_ image: CIImage, amount: Float, extent: CGRect) -> CIImage {
        let scale: CGFloat = 0.25
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let sigma = max(2.0, Double(extent.width * scale) * 0.012)
        let blurred = small.clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .cropped(to: small.extent)
        let up = blurred
            .transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
            .cropped(to: extent)
        let weighted = up.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(min(0.5, amount)))
        ])
        return weighted
            .applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: extent)
    }

    /// 胶片颗粒：单色噪点 + 柔光混合；每一帧随机偏移，避免“静止纱窗”。
    private static func applyGrain(_ image: CIImage, amount: Float, scale: CGFloat, extent: CGRect) -> CIImage {
        guard let base = CIFilter(name: "CIRandomGenerator")?.outputImage else { return image }
        let ox = CGFloat.random(in: 0..<2048)
        let oy = CGFloat.random(in: 0..<2048)
        var noise = base.transformed(by: CGAffineTransform(translationX: ox, y: oy))
        if scale > 1.01 {
            noise = noise.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        noise = noise.cropped(to: extent)
        let alpha = CGFloat(min(0.30, 0.22 * amount))
        let gray = noise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.3333, y: 0.3333, z: 0.3333, w: 0),
            "inputGVector": CIVector(x: 0.3333, y: 0.3333, z: 0.3333, w: 0),
            "inputBVector": CIVector(x: 0.3333, y: 0.3333, z: 0.3333, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
        return gray
            .applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: extent)
    }
}

// MARK: - 人物分割（Vision）

/// 人像光效 / 景深需要知道“人在哪”：视频帧异步更新蒙版（上一帧没算完就跳过），照片同步用高质量。
final class PersonSegmenter: @unchecked Sendable {
    static let shared = PersonSegmenter()

    private let lock = NSLock()
    private var latestMask: CIImage?
    private var latestCoverage: Float = 0
    private var busy = false
    private let queue = DispatchQueue(label: "ycam.vision", qos: .userInitiated)

    private init() {}

    func submit(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        if busy {
            lock.unlock()
            return
        }
        busy = true
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            let result = PersonSegmenter.segment(VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]), quality: .fast)
            self.lock.lock()
            self.busy = false
            // Clear the old segmentation when a person leaves the view.
            // Prevents a stale silhouette from blurring the wrong background.
            self.latestMask = result?.mask
            self.latestCoverage = result?.coverage ?? 0
            self.lock.unlock()
        }
    }

    /// 最近一次的人物蒙版；画面里没有人时返回 nil。
    func current() -> CIImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let mask = latestMask, latestCoverage > 0.01 else { return nil }
        return mask
    }

    func reset() {
        lock.lock()
        latestMask = nil
        latestCoverage = 0
        lock.unlock()
    }

    /// 照片：同步、高质量；没检测到人时返回 nil。
    func segmentSync(_ image: CIImage) -> CIImage? {
        guard let result = PersonSegmenter.segment(VNImageRequestHandler(ciImage: image, options: [:]), quality: .accurate),
              result.coverage > 0.01 else { return nil }
        return result.mask
    }

    private static func segment(_ handler: VNImageRequestHandler,
                                quality: VNGeneratePersonSegmentationRequest.QualityLevel) -> (mask: CIImage, coverage: Float)? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = quality
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = (request.results as? [VNPixelBufferObservation])?.first else { return nil }
        let buffer = observation.pixelBuffer
        return (CIImage(cvPixelBuffer: buffer), coverage(of: buffer))
    }

    /// 蒙版里“人物”所占比例（抽样计算，足够判断有没有人）。
    private static func coverage(of buffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0 else { return 0 }
        let pointer = base.assumingMemoryBound(to: UInt8.self)
        let stepX = max(1, width / 48)
        let stepY = max(1, height / 48)
        var sum = 0
        var count = 0
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                sum += Int(pointer[y * rowBytes + x])
                count += 1
                x += stepX
            }
            y += stepY
        }
        return count == 0 ? 0 : Float(sum) / Float(count * 255)
    }
}

// MARK: - .cube 查找表（富士胶片模拟）

/// 33×33×33 的 3D LUT（UInt16 RGB，红色变化最快），三线性插值。输入输出都是 0...1 的 sRGB 伽马值。
final class LutTable: @unchecked Sendable {
    let size: Int
    private let values: [Float]

    init?(data: Data, size: Int = 33) {
        let count = size * size * size * 3
        guard data.count == count * 2 else { return nil }
        let bytes = [UInt8](data)
        var floats = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let v = UInt16(bytes[2 * i]) | (UInt16(bytes[2 * i + 1]) << 8)
            floats[i] = Float(v) / 65535
        }
        self.size = size
        self.values = floats
    }

    func sample(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let m = Float(size - 1)
        let x = min(max(r, 0), 1) * m
        let y = min(max(g, 0), 1) * m
        let z = min(max(b, 0), 1) * m
        let x0 = min(Int(x), size - 2)
        let y0 = min(Int(y), size - 2)
        let z0 = min(Int(z), size - 2)
        let fx = x - Float(x0)
        let fy = y - Float(y0)
        let fz = z - Float(z0)
        var out: (Float, Float, Float) = (0, 0, 0)
        for dz in 0...1 {
            for dy in 0...1 {
                for dx in 0...1 {
                    let w = (dx == 1 ? fx : 1 - fx) * (dy == 1 ? fy : 1 - fy) * (dz == 1 ? fz : 1 - fz)
                    let i = (((z0 + dz) * size + (y0 + dy)) * size + (x0 + dx)) * 3
                    out.0 += w * values[i]
                    out.1 += w * values[i + 1]
                    out.2 += w * values[i + 2]
                }
            }
        }
        return out
    }
}

/// 从 Assets.xcassets 里的 LUT_<名字>.dataset 读取并缓存查找表；找不到时返回 nil（风格退回“无处理”，不会崩溃）。
final class LutLibrary: @unchecked Sendable {
    static let shared = LutLibrary()
    private let lock = NSLock()
    private var cache: [String: LutTable] = [:]

    func table(named name: String) -> LutTable? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[name] { return cached }
        guard let asset = NSDataAsset(name: "LUT_" + name), let table = LutTable(data: asset.data) else { return nil }
        cache[name] = table
        return table
    }
}
