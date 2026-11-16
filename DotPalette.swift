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

struct SwatchCard: View {
    let colors: [Color]
    let selected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(selected ? 0.85 : 0.14), lineWidth: selected ? 1.5 : 0.6)
            )
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

    @State private var anchorIndex = 0
    @State private var drag: CGFloat = 0
    @State private var dragging = false

    private var step: CGFloat { max(1, cardWidth + spacing) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    SwatchCard(colors: colors(item), selected: item == selected)
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
    let style: CameraStyle
    var colors: [Color]

    // UI artwork only. Original YCam glass, color-rendering pipeline and
    // photographic-style recipes remain untouched. Gold/Cool Rose palette
    // references are sampled from user-provided iPhone UI screenshots.
    @ViewBuilder
    private var artwork: some View {
        if style == .gold || style == .coolRose {
            ScreenshotPaletteArtwork(style: style)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                .overlay(
                    LinearGradient(colors: [Color.blue.opacity(0.20), Color.clear, Color.orange.opacity(0.20)],
                                   startPoint: .leading, endPoint: .trailing)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                )
        }
    }

    var body: some View {
        artwork
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.26), lineWidth: 0.6)
            }
            .overlay {
                DotPaletteTouchSurface(point: $point)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
    }
}

// The 2D square appearance is cached by SwiftUI's Canvas redraw lifecycle;
// it does not use the selection position, so dragging the white cursor never
// recolors the background or recomputes the underlying photo filter.
private struct PaletteRGB {
    let r: Double
    let g: Double
    let b: Double

    init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = Double(r) / 255
        self.g = Double(g) / 255
        self.b = Double(b) / 255
    }

    private init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    func mixed(with other: PaletteRGB, fraction: Double) -> PaletteRGB {
        let t = max(0, min(1, fraction))
        return PaletteRGB(r: r + (other.r - r) * t,
                          g: g + (other.g - g) * t,
                          b: b + (other.b - b) * t)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

private struct PaletteReferenceRow {
    let y: Double
    let left: PaletteRGB
    let right: PaletteRGB
}

private struct ScreenshotPaletteArtwork: View {
    let style: CameraStyle

    private var rows: [PaletteReferenceRow] {
        switch style {
        case .gold:
            // Screenshot-derived UI-only greige -> gold -> deep brown.
            return [
                .init(y: 0.00, left: .init(188, 174, 161), right: .init(224, 174, 77)),
                .init(y: 0.18, left: .init(145, 116, 96), right: .init(165, 109, 35)),
                .init(y: 0.48, left: .init(88, 77, 66), right: .init(95, 65, 30)),
                .init(y: 0.78, left: .init(48, 38, 30), right: .init(49, 35, 19)),
                .init(y: 1.00, left: .init(26, 18, 13), right: .init(31, 20, 11))
            ]
        case .coolRose:
            // Screenshot-derived UI-only pale blush -> dusty rose -> plum.
            return [
                .init(y: 0.00, left: .init(203, 174, 177), right: .init(221, 210, 199)),
                .init(y: 0.18, left: .init(176, 122, 128), right: .init(178, 157, 144)),
                .init(y: 0.48, left: .init(121, 66, 70), right: .init(134, 105, 96)),
                .init(y: 0.78, left: .init(64, 31, 42), right: .init(70, 34, 48)),
                .init(y: 1.00, left: .init(37, 16, 28), right: .init(42, 17, 29))
            ]
        default:
            // Caller uses YCam's unchanged gradient for all other styles.
            return []
        }
    }

    var body: some View {
        let anchors = rows
        Canvas(opaque: true) { context, size in
            guard anchors.count >= 2, size.width > 0, size.height > 0 else { return }
            let strips = 96
            let bandHeight = size.height / CGFloat(strips)
            for index in 0..<strips {
                let t = (Double(index) + 0.5) / Double(strips)
                let upper = max(1, min(anchors.count - 1,
                    anchors.firstIndex(where: { $0.y >= t }) ?? anchors.count - 1))
                let lower = upper - 1
                let a = anchors[lower]
                let b = anchors[upper]
                let fraction = (t - a.y) / max(0.0001, b.y - a.y)
                let left = a.left.mixed(with: b.left, fraction: fraction).color
                let right = a.right.mixed(with: b.right, fraction: fraction).color
                let y = CGFloat(index) * bandHeight
                let band = Path(CGRect(x: 0, y: y, width: size.width,
                                       height: bandHeight + 0.7))
                context.fill(band, with: .linearGradient(
                    Gradient(colors: [left, right]),
                    startPoint: CGPoint(x: 0, y: y),
                    endPoint: CGPoint(x: size.width, y: y)))
            }
        }
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

/// Cached original 11x11 dotted background with free movement while held.
/// On release only, smoothly spring the white circle to the nearest dot.
@MainActor
private final class DotPaletteTrackingView: UIControl {
    private let columns = 11
    private let rows = 11
    private let inset: CGFloat = 9
    private let dotsLayer = CAShapeLayer()
    private let neutralPointLayer = CALayer()
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

        dotsLayer.fillColor = UIColor.white.withAlphaComponent(0.76).cgColor
        layer.addSublayer(dotsLayer)
        // The small pale dot at the neutral center is part of the reference
        // square; the large white cursor remains separately draggable.
        neutralPointLayer.backgroundColor = UIColor.white.withAlphaComponent(0.75).cgColor
        neutralPointLayer.bounds = CGRect(x: 0, y: 0, width: 5, height: 5)
        neutralPointLayer.cornerRadius = 2.5
        layer.addSublayer(neutralPointLayer)
        cursorLayer.backgroundColor = UIColor.white.cgColor
        cursorLayer.bounds = CGRect(x: 0, y: 0, width: 15, height: 15)
        cursorLayer.cornerRadius = 7.5
        cursorLayer.shadowColor = UIColor.black.cgColor
        cursorLayer.shadowOpacity = 0.32
        cursorLayer.shadowRadius = 3
        cursorLayer.shadowOffset = CGSize(width: 0, height: 1)
        layer.addSublayer(cursorLayer)

        isAccessibilityElement = true
        accessibilityTraits = [.adjustable]
        accessibilityLabel = "摄影风格调色盘"
        accessibilityHint = "拖动时自由移动，松手后自动吸附到最近的小圆点"
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
                    CGRect(x: p.x - 1.0, y: p.y - 1.0, width: 2.0, height: 2.0)))
            }
        }
        dotsLayer.frame = bounds
        dotsLayer.path = path.cgPath
        neutralPointLayer.position = dotPosition(col: 5, row: 5)
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
        let diameter: CGFloat = pressed ? 19 : 15
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

    private func snapToNearestDot() {
        let destination = CGPoint(
            x: (cursor.x * CGFloat(columns - 1)).rounded() / CGFloat(columns - 1),
            y: (cursor.y * CGFloat(rows - 1)).rounded() / CGFloat(rows - 1)
        )
        let from = cursorPosition()
        cursor = destination
        let to = cursorPosition()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.position = to
        if hypot(to.x - from.x, to.y - from.y) > 0.1 {
            // A single short travel path, with no permanent line or added UI.
            let motion = CASpringAnimation(keyPath: "position")
            motion.fromValue = NSValue(cgPoint: from)
            motion.toValue = NSValue(cgPoint: to)
            motion.mass = 0.65
            motion.stiffness = 300
            motion.damping = 24
            motion.initialVelocity = 0
            motion.duration = min(0.30, motion.settlingDuration)
            motion.isRemovedOnCompletion = true
            cursorLayer.add(motion, forKey: "snapOnRelease")
        }
        CATransaction.commit()
        accessibilityValue = "颜色 \(Int((cursor.x - 0.5) * 200))，色调 \(Int((0.5 - cursor.y) * 200))"
        publishSelection()
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let touch { moveCursor(to: touch.location(in: self), forceCommit: false) }
        touching = false
        animateCursorPress(false)
        snapToNearestDot()
        feedback.selectionChanged()
    }

    override func cancelTracking(with event: UIEvent?) {
        touching = false
        animateCursorPress(false)
        snapToNearestDot()
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
