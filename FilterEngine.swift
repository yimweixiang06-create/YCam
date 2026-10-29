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
        var isPassthroughColor: Bool {
            cube == nil && recipe.bloom < 0.001 && recipe.grain < 0.001 && recipe.softness < 0.001
        }
    }

    static let cubeDimension = 32
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private let lock = NSLock()
    private var current: Snapshot
    private var desired = StyleSettings()
    private var version = 0
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
        lock.unlock()

        buildQueue.async { [weak self] in
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
        return FilterEngine.makeSnapshot(settings)
    }

    static func makeSnapshot(_ s: StyleSettings) -> Snapshot {
        let recipe = effectiveRecipe(for: s)
        let cube: Data? = recipe.isColorIdentity ? nil : buildCube(recipe)
        return Snapshot(settings: s, recipe: recipe, cube: cube)
    }

    /// 风格配方 × 调色盘浓度 + Apple 滤镜 + 色调板。
    /// 色调板按“调色盘使用公式”：横向 = 纯度（左灰 → 右纯），纵向 = 明度（上亮 → 下暗）。
    static func effectiveRecipe(for s: StyleSettings) -> LookRecipe {
        let k = Float(min(1, max(0, s.intensity)))
        var r = s.style.recipe.scaled(by: k).combined(with: s.filter.recipe)

        let purity = Float(max(0, min(1.25, s.point.x / 0.8)))        // x = 0.8 是风格的“原味”，0 = 灰
        r.temperature *= purity
        r.tint *= purity
        r.vibrance *= purity
        r.shadowTint = rgb(r.shadowTint.r * purity, r.shadowTint.g * purity, r.shadowTint.b * purity)
        r.highlightTint = rgb(r.highlightTint.r * purity, r.highlightTint.g * purity, r.highlightTint.b * purity)
        r.midGamma = rgb(1 + (r.midGamma.r - 1) * purity, 1 + (r.midGamma.g - 1) * purity, 1 + (r.midGamma.b - 1) * purity)
        let satMul: Float = purity <= 1 ? purity : 1 + (purity - 1) * 0.8
        r.saturation = max(0, r.saturation) * satMul

        let tone = Float((0.5 - s.point.y) * 2)                       // +1 最亮 … -1 最暗
        r.exposure += 0.6 * tone + Float(s.exposure)
        r.contrast -= 0.20 * tone
        return r
    }

    // MARK: Colour math (mirrored line by line in tools/style_check.py)

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
    static func buildCube(_ p: LookRecipe) -> Data {
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
                    let o = transform(r, g, b, p)
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
        if snap.recipe.softness > 0.001 {
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
        if snap.recipe.bloom > 0.001 {
            out = FilterEngine.applyBloom(out, amount: snap.recipe.bloom, extent: extent)
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

    /// 柔焦（珠光用）：与一张模糊版本按比例混合，让画面整体更朦胧、不那么锐。
    private static func applySoftness(_ image: CIImage, amount: Float, extent: CGRect) -> CIImage {
        let sigma = max(1.5, Double(extent.width) * 0.0035)
        let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
        let weight = CGFloat(min(0.9, amount))
        return blurred
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: weight)])
            .composited(over: image)
            .cropped(to: extent)
    }

    /// 柔光：缩小 → 高斯模糊 → 放大 → 以滤色混合叠回（Pearl / 空灵 / 明亮使用）。
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
            if let result {
                self.latestMask = result.mask
                self.latestCoverage = result.coverage
            }
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
