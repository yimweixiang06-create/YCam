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
    var colors: [Color]

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [
                Color(red: 0.24, green: 0.17, blue: 0.22),
                (colors.last ?? .pink).opacity(0.63),
                Color(red: 0.12, green: 0.10, blue: 0.15)
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            // Up = brighter, down = deeper, left = quieter colors, right = richer.
            .overlay(
                LinearGradient(colors: [Color.white.opacity(0.22), .clear, Color.black.opacity(0.56)],
                               startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
            .overlay(
                LinearGradient(colors: [Color.gray.opacity(0.34), .clear, (colors.last ?? .orange).opacity(0.20)],
                               startPoint: .leading, endPoint: .trailing)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
            .overlay {
                DotPaletteTouchSurface(point: $point)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
    private var lastHapticColumn = -1
    private var lastHapticRow = -1
    private var lastHapticTime: CFTimeInterval = 0
    private var onChange: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false

        dotsLayer.fillColor = UIColor.white.withAlphaComponent(0.76).cgColor
        layer.addSublayer(dotsLayer)
        cursorLayer.backgroundColor = UIColor.white.cgColor
        cursorLayer.bounds = CGRect(x: 0, y: 0, width: 19, height: 19)
        cursorLayer.cornerRadius = 9.5
        cursorLayer.borderWidth = 1.2
        cursorLayer.borderColor = UIColor.white.withAlphaComponent(0.86).cgColor
        cursorLayer.shadowColor = UIColor.black.cgColor
        cursorLayer.shadowOpacity = 0.32
        cursorLayer.shadowRadius = 3
        cursorLayer.shadowOffset = CGSize(width: 0, height: 1)
        layer.addSublayer(cursorLayer)

        isAccessibilityElement = true
        accessibilityTraits = [.adjustable]
        accessibilityLabel = "摄影风格调色盘"
        accessibilityHint = "轻点任意位置或按住白色圆点连续拖动；白点实时跟随手指，松手停在当前颜色，不吸附网格"
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
        // 点阵与白色手柄只移动一个 CALayer，不逐帧重绘 SwiftUI。
        // GPU 上的色调/颜色使用轻量实时参数；LUT 重建不由点阵位置触发。
        if forceCommit || now - lastCommitTime >= 1.0 / 60.0 {
            publishSelection(at: now)
        }
        if touching {
            let col = Int((next.x * CGFloat(columns - 1)).rounded())
            let row = Int((next.y * CGFloat(rows - 1)).rounded())
            if (col != lastHapticColumn || row != lastHapticRow) &&
                now - lastHapticTime >= 0.07 {
                lastHapticColumn = col
                lastHapticRow = row
                lastHapticTime = now
                feedback.selectionChanged()
                feedback.prepare()
            }
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
        CATransaction.setAnimationDuration(UIAccessibility.isReduceMotionEnabled ? 0 : 0.10)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        let diameter: CGFloat = pressed ? 29 : 19
        cursorLayer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        cursorLayer.cornerRadius = diameter / 2
        CATransaction.commit()
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        touching = true
        feedback.prepare()
        lastHapticColumn = -1
        lastHapticRow = -1
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

// MARK: - 摄影风格强度：参考录屏的渐变胶囊轨道与白色手柄，连续拖动。

struct TickSlider: View {
    @Binding var value: Double      // 0...1

    var body: some View {
        HStack(spacing: 10) {
            Text("−").font(.system(size: 17, weight: .medium)).opacity(0.85)
            GeometryReader { geo in
                let travel = max(0, geo.size.width - 18)
                ZStack {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color(red: 0.18, green: 0.28, blue: 0.38),
                                     Color(red: 0.36, green: 0.25, blue: 0.34),
                                     Color(red: 0.74, green: 0.47, blue: 0.53)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(height: 17)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7))
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.36), radius: 2, y: 1)
                        .position(x: 9 + CGFloat(min(1, max(0, value))) * travel,
                                  y: geo.size.height / 2)
                        .allowsHitTesting(false)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let next = min(1, max(0, (drag.location.x - 9) / max(1, travel)))
                            let adjusted = (next * 100).rounded() / 100
                            guard adjusted != value else { return }
                            let previousStep = Int((value * 10).rounded(.down))
                            value = adjusted
                            if Int((adjusted * 10).rounded(.down)) != previousStep {
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                        }
                )
            }
            .frame(height: 30)
            Text("+").font(.system(size: 17, weight: .medium)).opacity(0.85)
        }
        .foregroundStyle(Color.white)
        .accessibilityElement()
        .accessibilityLabel("调色盘浓度")
        .accessibilityValue("\(Int((value * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 0.01 : -0.01
            value = min(1, max(0, ((value + delta) * 100).rounded() / 100))
        }
    }
}
