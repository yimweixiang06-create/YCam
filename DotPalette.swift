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

// MARK: - 色调板（11 × 11）：横向 = 纯度（左灰 → 右纯），纵向 = 明度（上亮 → 下暗）

struct DotPalette: View {
    @Binding var point: CGPoint
    var colors: [Color]

    private let columns = 11
    private let rows = 11
    private let inset: CGFloat = 12
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .overlay(
                        // 左边偏灰（低纯度），右边保持风格本色（高纯度）
                        LinearGradient(colors: [Color(white: 0.55).opacity(0.85), Color(white: 0.55).opacity(0.0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    )
                Canvas { context, canvasSize in
                    for row in 0..<rows {
                        for col in 0..<columns {
                            let p = position(col: col, row: row, in: canvasSize)
                            let rect = CGRect(x: p.x - 1.4, y: p.y - 1.4, width: 2.8, height: 2.8)
                            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.75)))
                        }
                    }
                }
                Circle()
                    .fill(Color.white)
                    .frame(width: dragging ? 15 : 12, height: dragging ? 15 : 12)
                    .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
                    .position(position(col: selectedColumn, row: selectedRow, in: size))
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: selectedColumn * 100 + selectedRow)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        select(at: value.location, in: size)
                    }
                    .onEnded { _ in dragging = false }
            )
            .accessibilityElement()
            .accessibilityLabel("色调板")
            .accessibilityValue("纯度第\(selectedColumn + 1)列，明度第\(selectedRow + 1)行")
            .accessibilityHint("左右调节纯度，上下调节明度")
            .accessibilityAdjustableAction { direction in
                let delta: CGFloat = direction == .increment ? 1 : -1
                let next = min(CGFloat(columns - 1), max(0, CGFloat(selectedColumn) + delta))
                point = CGPoint(x: next / CGFloat(columns - 1), y: point.y)
            }
        }
    }

    private var selectedColumn: Int {
        min(columns - 1, max(0, Int((point.x * CGFloat(columns - 1)).rounded())))
    }

    private var selectedRow: Int {
        min(rows - 1, max(0, Int((point.y * CGFloat(rows - 1)).rounded())))
    }

    private func position(col: Int, row: Int, in size: CGSize) -> CGPoint {
        CGPoint(x: inset + CGFloat(col) * max(0, size.width - inset * 2) / CGFloat(columns - 1),
                y: inset + CGFloat(row) * max(0, size.height - inset * 2) / CGFloat(rows - 1))
    }

    private func select(at location: CGPoint, in size: CGSize) {
        let usableWidth = max(1, size.width - inset * 2)
        let usableHeight = max(1, size.height - inset * 2)
        let col = min(columns - 1, max(0, Int(((location.x - inset) / usableWidth * CGFloat(columns - 1)).rounded())))
        let row = min(rows - 1, max(0, Int(((location.y - inset) / usableHeight * CGFloat(rows - 1)).rounded())))
        let next = CGPoint(x: CGFloat(col) / CGFloat(columns - 1), y: CGFloat(row) / CGFloat(rows - 1))
        guard next != point else { return }
        point = next
        UISelectionFeedbackGenerator().selectionChanged()
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
                        let snapped = (t * Double(ticks - 1)).rounded() / Double(ticks - 1)
                        if snapped != value {
                            value = snapped
                            UISelectionFeedbackGenerator().selectionChanged()
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
