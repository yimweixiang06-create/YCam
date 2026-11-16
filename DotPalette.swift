import SwiftUI
import UIKit

// MARK: - 六点图标（顶部胶囊里的“更多”按钮：3 × 2 圆点，与参考截图一致）

struct DotGrid: View {
    var columns: Int = 3
    var rows: Int = 2
    var dot: CGFloat = 3.6
    var gap: CGFloat = 3.4
    var color: Color = .white

    var body: some View {
        VStack(spacing: gap) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: gap) {
                    ForEach(0..<columns, id: \.self) { _ in
                        Circle().fill(color).frame(width: dot, height: dot)
                    }
                }
            }
        }
    }
}

// MARK: - 卡片 + 可横向滑动的轮播（摄影风格 / 滤镜通用）

/// Compact iOS-style symbolic swatch: icon ABOVE label. No photo cards.
struct SwatchCard: View {
    let colors: [Color]
    let label: String
    let symbol: String
    let selected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(Color.white.opacity(selected ? 0.18 : 0.09))
                Circle()
                    .fill(LinearGradient(colors: colors,
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.93))
                    .shadow(color: Color.black.opacity(0.50), radius: 1)
            }
            .frame(width: 36, height: 36)
            .overlay {
                Circle().strokeBorder(Color.white.opacity(selected ? 0.92 : 0.22),
                                      lineWidth: selected ? 1.7 : 0.7)
            }
            Text(label)
                .font(.system(size: 9, weight: selected ? .semibold : .medium))
                .foregroundStyle(Color.white.opacity(selected ? 1 : 0.70))
                .lineLimit(2)
                .minimumScaleFactor(0.76)
                .multilineTextAlignment(.center)
                .frame(height: 21, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// 横向滑动选择：手指拖动时实时切换（有触感反馈），松手后吸附到最近的卡片；也可以直接点按卡片。
struct SwatchCarousel<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selected: Item
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let spacing: CGFloat
    let colors: (Item) -> [Color]
    let name: (Item) -> String
    let shortName: (Item) -> String
    let symbol: String

    @State private var anchorIndex = 0
    @State private var drag: CGFloat = 0
    @State private var dragging = false

    private var step: CGFloat { max(1, cardWidth + spacing) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    SwatchCard(colors: colors(item), label: shortName(item),
                               symbol: symbol, selected: item == selected)
                        .frame(width: cardWidth, height: cardHeight)
                        .position(x: geo.size.width / 2 + CGFloat(index - anchorIndex) * step + drag,
                                  y: geo.size.height / 2)
                        .onTapGesture { choose(index) }
                        .accessibilityLabel(name(item))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(dragGesture)
        }
        .frame(height: cardHeight)
        .onAppear { anchorIndex = indexOf(selected) }
        .onChange(of: selected) { _, newValue in
            guard !dragging else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                anchorIndex = indexOf(newValue)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                dragging = true
                drag = value.translation.width
                let raw = CGFloat(anchorIndex) - drag / step
                let nearest = min(items.count - 1, max(0, Int(raw.rounded())))
                if items[nearest] != selected {
                    selected = items[nearest]
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { value in
                let projected = value.translation.width + 0.3 * (value.predictedEndTranslation.width - value.translation.width)
                let raw = CGFloat(anchorIndex) - projected / step
                let target = min(items.count - 1, max(0, Int(raw.rounded())))
                if items[target] != selected {
                    selected = items[target]
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                dragging = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    anchorIndex = target
                    drag = 0
                }
            }
    }

    private func choose(_ index: Int) {
        guard index >= 0, index < items.count else { return }
        if items[index] != selected { UISelectionFeedbackGenerator().selectionChanged() }
        selected = items[index]
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            anchorIndex = index
            drag = 0
        }
    }

    private func indexOf(_ item: Item) -> Int {
        items.firstIndex(of: item) ?? 0
    }
}

// MARK: - 摄影风格色调板：横向颜色 −100...100，纵向色调 +100...−100

struct DotPalette: View {
    @Binding var point: CGPoint
    var style: CameraStyle
    var filter: AppleFilter
    var intensity: Double

    var body: some View {
        // Independent YCam 2D raster for EACH style. The previous shared
        // smoked-rose background hid most of the style-dependent colors.
        // Apple has not published these proprietary palette textures.
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        ZStack {
            shape.fill(style.swatch)
            Image(uiImage: PaletteColorMap.image(style: style, filter: filter, intensity: intensity))
                .resizable()
                .interpolation(.high)
                .saturation(style == .monochrome ? 0 : 1.04)
                .opacity(0.97)
                .allowsHitTesting(false)
            LinearGradient(stops: [
                .init(color: Color.white.opacity(0.04), location: 0),
                .init(color: .clear, location: 0.42),
                .init(color: Color.black.opacity(0.34), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
        }
        .clipShape(shape)
        .overlay {
            DotPaletteTouchSurface(point: $point)
                .clipShape(shape)
        }
    }
}

/// Cache one 33x33 RGBA color surface per style/filter/5%-strength combination.
/// Each source cell is evaluated independently for BOTH tone and color axes.
/// The raster is for the pad's visual guidance only; actual preview/photos
/// continue to use FilterEngine.process and its full-resolution GPU pipeline.
private enum PaletteColorMap {
    private static let side = 33
    private static let cache: NSCache<NSString, UIImage> = {
        let result = NSCache<NSString, UIImage>()
        result.countLimit = 64
        return result
    }()

    private static func clamp(_ value: Float) -> Float {
        min(1, max(0, value))
    }

    static func image(style: CameraStyle, filter: AppleFilter, intensity: Double) -> UIImage {
        let strengthStep = Int((min(1, max(0, intensity)) * 20).rounded())
        let key = NSString(string: "\(style.rawValue)|\(filter.rawValue)|\(strengthStep)")
        if let existing = cache.object(forKey: key) { return existing }

        let strength = Float(strengthStep) / 20
        var settings = StyleSettings()
        settings.style = style
        settings.filter = filter
        settings.intensity = Double(strength)
        let recipe = FilterEngine.effectiveRecipe(for: settings)
        let filmLut = style.lutName.flatMap { LutLibrary.shared.table(named: $0) }

        // Give each style a dominant source hue; averaging equally weighted
        // skin, sky and gray made every palette look identically beige.
        let representative = UIColor(style.swatch)
        var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
        let found = representative.getRed(&sr, green: &sg, blue: &sb, alpha: &sa)
        let primary = found
            ? (Float(sr), Float(sg), Float(sb))
            : (Float(0.56), Float(0.55), Float(0.56))
        let examples: [(Float, Float, Float, Float)] = [
            (primary.0, primary.1, primary.2, 0.72),
            (0.90, 0.52, 0.58, 0.12), // skin
            (0.44, 0.71, 0.88, 0.10), // sky
            (0.68, 0.70, 0.71, 0.06)  // gray
        ]
        var rgba = [UInt8](repeating: 255, count: side * side * 4)
        for row in 0..<side {
            let y = Float(row) / Float(side - 1)
            let tone = (0.5 - y) * 2 * strength
            for column in 0..<side {
                let x = Float(column) / Float(side - 1)
                let color = (x - 0.5) * 2 * strength

                let axes = FilterEngine.paletteAxes(style: style,
                                                    tone: Double(tone), color: Double(color))
                var sumR: Float = 0, sumG: Float = 0, sumB: Float = 0
                for (sr, sg, sb, weight) in examples {
                    var r = sr, g = sg, b = sb
                    if let filmLut {
                        let mapped = filmLut.sample(r, g, b)
                        r += (mapped.0 - r) * strength
                        g += (mapped.1 - g) * strength
                        b += (mapped.2 - b) * strength
                    }
                    (r, g, b) = FilterEngine.transform(r, g, b, recipe)
                    let gamma = Float(axes.gamma)
                    let gain = powf(2, Float(axes.exposure))
                    r = clamp(powf(clamp(r), gamma) * gain)
                    g = clamp(powf(clamp(g), gamma) * gain)
                    b = clamp(powf(clamp(b), gamma) * gain)

                    let luminosity = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    let chroma = max(r, max(g, b)) - min(r, min(g, b))
                    let vibrance = 1 + Float(axes.vibrance) * (1 - chroma)
                    let saturation = Float(axes.saturation)
                    let contrast = Float(axes.contrast)
                    let scale = vibrance * saturation
                    sumR += clamp(((luminosity + (r - luminosity) * scale) - 0.5) * contrast + 0.5) * weight
                    sumG += clamp(((luminosity + (g - luminosity) * scale) - 0.5) * contrast + 0.5) * weight
                    sumB += clamp(((luminosity + (b - luminosity) * scale) - 0.5) * contrast + 0.5) * weight
                }
                let i = (row * side + column) * 4
                rgba[i] = UInt8((clamp(sumR) * 255).rounded())
                rgba[i + 1] = UInt8((clamp(sumG) * 255).rounded())
                rgba[i + 2] = UInt8((clamp(sumB) * 255).rounded())
                rgba[i + 3] = 255
            }
        }

        let data = Data(rgba)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: side, height: side,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else {
            // A safe fallback for failed image allocation; never touch the camera.
            return UIImage()
        }
        let result = UIImage(cgImage: cgImage)
        cache.setObject(result, forKey: key)
        return result
    }
}

/// UIKit owns palette touches so a moving cursor never invalidates the
/// entire SwiftUI camera view on every screen refresh.
private struct DotPaletteTouchSurface: UIViewRepresentable {
    @Binding var point: CGPoint

    func makeUIView(context: Context) -> DotPaletteTrackingView {
        let view = DotPaletteTrackingView()
        view.configure(point: point, onChange: { point = $0 })
        return view
    }

    func updateUIView(_ uiView: DotPaletteTrackingView, context: Context) {
        uiView.configure(point: point, onChange: { point = $0 })
    }
}

/// Cached 11x11 decorative dots and one continuous cursor layer. Dots are
/// visual guides only; the cursor follows touch without snapping. Image
/// updates are coalesced while final release coordinates are exact.
@MainActor
private final class DotPaletteTrackingView: UIControl {
    private let columns = 11
    private let rows = 11
    private let inset: CGFloat = 12
    private let dotsLayer = CAShapeLayer()
    private let cursorLayer = CALayer()
    private let feedback = UISelectionFeedbackGenerator()
    private var cursor = CGPoint(x: 0.5, y: 0.5)
    private var touching = false
    private var lastCommitted = CGPoint(x: 0.5, y: 0.5)
    private var lastCommitTime: CFTimeInterval = 0
    private var lastDrawnSize = CGSize.zero
    private var onChange: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false

        // Dark outline keeps each point visible on the brightest palettes.
        dotsLayer.fillColor = UIColor.white.withAlphaComponent(0.93).cgColor
        dotsLayer.strokeColor = UIColor.black.withAlphaComponent(0.38).cgColor
        dotsLayer.lineWidth = 0.55
        layer.addSublayer(dotsLayer)
        cursorLayer.backgroundColor = UIColor.white.cgColor
        cursorLayer.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
        cursorLayer.cornerRadius = 9
        cursorLayer.shadowColor = UIColor.black.cgColor
        cursorLayer.shadowOpacity = 0.32
        cursorLayer.shadowRadius = 3
        cursorLayer.shadowOffset = CGSize(width: 0, height: 1)
        layer.addSublayer(cursorLayer)

        isAccessibilityElement = true
        accessibilityTraits = [.adjustable]
        accessibilityLabel = "摄影风格调色盘"
        accessibilityHint = "拖动白色圆点：向上提亮，向下压暗，向左淡色，向右浓色；不会吸附网格"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(point: CGPoint, onChange: @escaping (CGPoint) -> Void) {
        self.onChange = onChange
        guard !touching else { return }
        let next = CGPoint(x: min(1, max(0, point.x)),
                           y: min(1, max(0, point.y)))
        if abs(next.x - cursor.x) > 0.0005 || abs(next.y - cursor.y) > 0.0005 {
            cursor = next
            updateCursor()
        }
        lastCommitted = cursor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastDrawnSize else { return }
        lastDrawnSize = bounds.size
        let path = UIBezierPath()
        for r in 0..<rows {
            for c in 0..<columns {
                let p = dotPosition(col: c, row: r)
                path.append(UIBezierPath(ovalIn:
                    CGRect(x: p.x - 1.4, y: p.y - 1.4, width: 2.8, height: 2.8)))
            }
        }
        dotsLayer.frame = bounds
        dotsLayer.path = path.cgPath
        updateCursor()
    }

    private var normalizedPoint: CGPoint { cursor }

    private func cursorPosition() -> CGPoint {
        CGPoint(x: inset + cursor.x * max(0, bounds.width - inset * 2),
                y: inset + cursor.y * max(0, bounds.height - inset * 2))
    }

    private func dotPosition(col: Int, row: Int) -> CGPoint {
        let w = max(0, bounds.width - inset * 2)
        let h = max(0, bounds.height - inset * 2)
        return CGPoint(x: inset + CGFloat(col) * w / CGFloat(columns - 1),
                       y: inset + CGFloat(row) * h / CGFloat(rows - 1))
    }

    private func updateCursor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.position = cursorPosition()
        CATransaction.commit()
        accessibilityValue = "颜色 \(Int((normalizedPoint.x - 0.5) * 200))，色调 \(Int((0.5 - normalizedPoint.y) * 200))"
    }

    private func moveCursor(to location: CGPoint, forceCommit: Bool) {
        let w = max(1, bounds.width - inset * 2)
        let h = max(1, bounds.height - inset * 2)
        let next = CGPoint(x: min(1, max(0, (location.x - inset) / w)),
                           y: min(1, max(0, (location.y - inset) / h)))
        if abs(next.x - cursor.x) > 0.0001 || abs(next.y - cursor.y) > 0.0001 {
            cursor = next
            updateCursor()
        }
        let now = CACurrentMediaTime()
        if forceCommit || now - lastCommitTime >= 1.0 / 30.0 {
            publishSelection(at: now)
        }
    }

    private func publishSelection(at time: CFTimeInterval = CACurrentMediaTime()) {
        let next = normalizedPoint
        guard next != lastCommitted else { return }
        lastCommitted = next
        lastCommitTime = time
        onChange?(next)
    }

    private func animateCursorPress(_ pressed: Bool) {
        // Animate only the CALayer: camera preview/SwiftUI hierarchy stays
        // fixed while the user's finger moves across the palette.
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        let diameter: CGFloat = pressed ? 22 : 18
        cursorLayer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        cursorLayer.cornerRadius = diameter / 2
        CATransaction.commit()
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        touching = true
        feedback.prepare()
        animateCursorPress(true)
        moveCursor(to: touch.location(in: self), forceCommit: true)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        moveCursor(to: touch.location(in: self), forceCommit: false)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let touch {
            moveCursor(to: touch.location(in: self), forceCommit: true)
        } else {
            publishSelection()
        }
        touching = false
        animateCursorPress(false)
        feedback.selectionChanged()
    }

    override func cancelTracking(with event: UIEvent?) {
        touching = false
        animateCursorPress(false)
        publishSelection()
    }

    override func accessibilityIncrement() {
        cursor.x = min(1, cursor.x + 0.05)
        updateCursor()
        publishSelection()
    }

    override func accessibilityDecrement() {
        cursor.x = max(0, cursor.x - 0.05)
        updateCursor()
        publishSelection()
    }
}

// MARK: - 刻度滑块（“调色盘浓度”，淡 → 浓：− ||||||||| +）

struct TickSlider: View {
    @Binding var value: Double      // 0...1
    private let ticks = 11

    var body: some View {
        HStack(spacing: 10) {
            Text("−").font(.system(size: 17, weight: .medium)).opacity(0.8)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(0..<ticks, id: \.self) { i in
                        Capsule()
                            .fill(Double(i) / Double(ticks - 1) <= value + 0.001 ? Color.yellow : Color.white.opacity(0.35))
                            .frame(width: 2, height: 15)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { drag in
                        let t = min(1, max(0, drag.location.x / max(1, geo.size.width)))
                        let adjusted = (t * 100).rounded() / 100
                        if adjusted != value {
                            let previousStep = Int((value * 10).rounded(.down))
                            value = adjusted
                            if Int((adjusted * 10).rounded(.down)) != previousStep {
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                        }
                    }
                )
            }
            .frame(height: 26)
            Text("+").font(.system(size: 17, weight: .medium)).opacity(0.8)
        }
        .foregroundStyle(Color.white)
        .accessibilityElement()
        .accessibilityLabel("调色盘浓度")
        .accessibilityValue("\(Int((value * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 0.1 : -0.1
            value = min(1, max(0, (value + delta) * 10).rounded() / 10)
        }
    }
}
