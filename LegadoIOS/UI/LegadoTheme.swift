import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 对齐安卓「阅读」默认主题的配色 / 圆角 / 组件
/// 日间：背景 #F7F7FA，卡片白，顶栏 #F1F2F6，强调色 Material Red 600
/// 夜间：背景 #121212，卡片 #1E1E1E，顶栏 #252528
enum LegadoTheme {

    /// 安卓版默认强调色（md_red_600）
    static let accent = Color(hex: "#E53935")

    static func isDark(_ scheme: ColorScheme) -> Bool { scheme == .dark }

    static func background(_ scheme: ColorScheme) -> Color {
        isDark(scheme) ? Color(hex: "#111113") : Color(hex: "#F7F7FA")
    }

    /// 顶栏 / 标签栏底色
    static func surface(_ scheme: ColorScheme) -> Color {
        isDark(scheme) ? Color(hex: "#252528") : Color(hex: "#F1F2F6")
    }

    static func card(_ scheme: ColorScheme) -> Color {
        isDark(scheme) ? Color(hex: "#1C1C1E") : Color(hex: "#FFFFFF")
    }

    static func primaryText(_ scheme: ColorScheme) -> Color {
        Color(white: isDark(scheme) ? 1 : 0, opacity: 0.87)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        Color(white: isDark(scheme) ? 1 : 0, opacity: isDark(scheme) ? 0.70 : 0.54)
    }

    static func tertiaryText(_ scheme: ColorScheme) -> Color {
        Color(white: isDark(scheme) ? 1 : 0, opacity: 0.38)
    }

    static func divider(_ scheme: ColorScheme) -> Color {
        Color(white: isDark(scheme) ? 1 : 0, opacity: 0.10)
    }

    static func fill(_ scheme: ColorScheme) -> Color {
        Color(white: isDark(scheme) ? 1 : 0, opacity: 0.06)
    }
}

// MARK: - 毛玻璃外壳（对应安卓的 LiquidGlassView）

struct GlassSurface<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var shadow: Bool = true
    private let content: Content

    init(cornerRadius: CGFloat = 24, shadow: Bool = true, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(shadow ? 0.10 : 0), radius: 12, x: 0, y: 4)
    }
}

// MARK: - 小按钮

struct LegadoIconButton: View {
    let system: String
    var size: CGFloat = 34
    var iconSize: CGFloat = 17
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(tint ?? Color.primary.opacity(0.75))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 设置列表行

struct LegadoListRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var showChevron: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundColor(LegadoTheme.secondaryText(scheme))
                .frame(width: 24)
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(LegadoTheme.primaryText(scheme))
            Spacer()
            if let detail = detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(LegadoTheme.secondaryText(scheme))
                    .lineLimit(1)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(LegadoTheme.tertiaryText(scheme))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .contentShape(Rectangle())
    }
}

struct LegadoSectionCard<Content: View>: View {
    let title: String?
    private let content: Content
    @Environment(\.colorScheme) private var scheme

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(LegadoTheme.secondaryText(scheme))
                    .padding(.horizontal, 6)
            }
            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LegadoTheme.card(scheme))
            )
        }
    }
}

struct LegadoDivider: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle()
            .fill(LegadoTheme.divider(scheme))
            .frame(height: 0.5)
            .padding(.leading, 54)
    }
}

/// 只圆上面两个角（阅读底部面板用）
struct RoundedCorner: Shape {
    var radius: CGFloat = 10
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        #if canImport(UIKit)
        let path = UIBezierPath(roundedRect: rect,
                                byRoundingCorners: corners,
                                cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
        #else
        return Path(roundedRect: rect, cornerRadius: radius)
        #endif
    }
}
