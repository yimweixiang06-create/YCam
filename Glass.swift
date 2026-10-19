import SwiftUI

// MARK: - 玻璃封装
//
// iOS 26+：只使用 Apple 官方 SwiftUI Liquid Glass API
//   （参见 developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views）：
//   • glassEffect(_:in:)            —— 给任意视图加 Liquid Glass
//   • Glass.regular.interactive()   —— 对触摸 / 拖动实时响应（与 .buttonStyle(.glass) 相同的反馈）
//   • GlassEffectContainer          —— 多块玻璃放在同一容器里渲染 / 融合 / 变形
//   • glassEffectID(_:in:)          —— 容器内的形变过渡（收起条 ⇄ 展开面板）
//   iOS 26 路径里不叠加任何 Material。
//
// iOS 18–25：没有 Liquid Glass，自动改用“磨砂模糊玻璃”（系统 Material + 高光描边）。
//   布局、手势、滑动切换逻辑与 iOS 26 完全相同（同一份代码），只是玻璃换成磨砂模糊；
//   点按 / 拖动的反馈用缩放近似 interactive()，面板展开用 matchedGeometryEffect 近似形变。
//   这是降级效果，不是官方 Liquid Glass（没有折射和实时高光）。
//
// `#if compiler(>=6.2)`：被旧 Xcode 打开时也能编译（只有磨砂降级）；官方玻璃需要 Xcode 26 SDK，
// GitHub Actions 工作流会强制使用 Xcode 26。

/// 玻璃形变 ID：iOS 26 → glassEffectID；iOS 18–25 → matchedGeometryEffect（只作用于玻璃底板）。
struct GlassMorph {
    let id: String
    let namespace: Namespace.ID
}

struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var interactive: Bool = false
    var tint: Color? = nil
    /// 滑块 / 透镜这类“叠在玻璃上的小玻璃”：iOS 18–25 的磨砂版会更亮一些才看得见。
    var lens: Bool = false
    var morph: GlassMorph? = nil

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            officialGlass(content)
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    @ViewBuilder
    private func officialGlass(_ content: Content) -> some View {
        let glass = Self.makeGlass(interactive: interactive, tint: tint)
        if let morph {
            content
                .glassEffect(glass, in: shape)
                .glassEffectID(morph.id, in: morph.namespace)
        } else {
            content.glassEffect(glass, in: shape)
        }
    }

    @available(iOS 26.0, *)
    private static func makeGlass(interactive: Bool, tint: Color?) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
    #endif

    @ViewBuilder
    private func legacy(_ content: Content) -> some View {
        content.background {
            if let morph {
                LegacyGlassBackground(shape: shape, lens: lens, tint: tint)
                    .matchedGeometryEffect(id: morph.id, in: morph.namespace)
            } else {
                LegacyGlassBackground(shape: shape, lens: lens, tint: tint)
            }
        }
    }
}

// BEGIN LEGACY
/// iOS 18–25 的磨砂玻璃：系统模糊 Material + 轻微提亮 + 渐变高光描边。
/// 整个 App 里只有这里允许出现 Material（iOS 26 路径不会走到这里）。
struct LegacyGlassBackground<S: Shape>: View {
    let shape: S
    var lens: Bool = false
    var tint: Color? = nil

    var body: some View {
        let material: Material = lens ? .thin : .ultraThin
        shape
            .fill(material)
            .overlay(shape.fill(Color.white.opacity(lens ? 0.20 : 0.07)))
            .overlay {
                if let tint { shape.fill(tint.opacity(0.28)) }
            }
            .overlay(
                shape.stroke(
                    LinearGradient(colors: [Color.white.opacity(lens ? 0.70 : 0.50),
                                            Color.white.opacity(0.08),
                                            Color.white.opacity(0.26)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    lineWidth: 0.8
                )
            )
    }
}
// END LEGACY

extension View {
    /// 在视图后面放一块玻璃（iOS 26 官方 Liquid Glass / iOS 18–25 磨砂玻璃）。
    /// 请在 padding / frame 等外观修饰符之后调用（官方文档要求）。
    func glassSurface<S: Shape>(_ shape: S,
                                interactive: Bool = false,
                                tint: Color? = nil,
                                lens: Bool = false,
                                morph: GlassMorph? = nil) -> some View {
        modifier(GlassSurface(shape: shape, interactive: interactive, tint: tint, lens: lens, morph: morph))
    }

    /// iOS 18–25 上给“正在被拖动的透镜”加按压缩放（iOS 26 由官方 interactive() 负责，不重复处理）。
    func legacyPressScale(_ active: Bool, scale: CGFloat = 1.08) -> some View {
        modifier(LegacyPressScale(active: active, scale: scale))
    }
}

struct LegacyPressScale: ViewModifier {
    let active: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .scaleEffect(active ? scale : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: active)
        }
    }
}

/// 玻璃按钮的按压反馈：iOS 26 由 interactive() 负责（这里不做任何事）；
/// iOS 18–25 用弹簧缩放来近似。
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let legacy = Self.isLegacy
        return configuration.label
            .scaleEffect(legacy && configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private static var isLegacy: Bool {
        if #available(iOS 26.0, *) { return false } else { return true }
    }
}

/// 官方 GlassEffectContainer 的封装：把相邻的玻璃元素放进同一个容器，系统才会正确融合 / 形变。
/// iOS 18–25 没有容器概念，直接透传内容。
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    let content: () -> Content

    init(spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}
