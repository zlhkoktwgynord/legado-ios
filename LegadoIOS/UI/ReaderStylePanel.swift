import SwiftUI
import UniformTypeIdentifiers

/// 阅读排版面板（对齐原版：顶部标签行 + 四条滑条 + 翻页动画 + 文字颜色和背景）
struct ReaderStylePanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showPadding = false
    @State private var showFontImporter = false
    @State private var fontTick = 0

    private var config: Binding<ReaderConfig> { $model.readerConfig }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                tagRow
                sliderRow("字号", value: config.fontSize, range: 12...32, step: 1)
                sliderRow("字距", value: config.letterSpacing, range: -1...4, step: 0.5)
                sliderRow("行距", value: config.lineSpacing, range: -4...24, step: 1)
                sliderRow("段距", value: config.paragraphSpacing, range: 0...30, step: 1)
                if showPadding {
                    sliderRow("边距", value: config.padding, range: 6...44, step: 2)
                }
                Divider().padding(.vertical, 2)
                animationRow
                Divider().padding(.vertical, 2)
                themeRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .onChange(of: model.readerConfig) { _ in model.saveReaderConfig() }
        .fileImporter(isPresented: $showFontImporter,
                      allowedContentTypes: [.font],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let name = FontStore.importFont(from: url) {
                    model.readerConfig.fontFamily = name
                    fontTick += 1
                }
            }
        }
    }

    // MARK: - 标签行

    private var tagRow: some View {
        HStack(spacing: 8) {
            Menu {
                Button("细") { model.readerConfig.fontWeight = 0 }
                Button("中") { model.readerConfig.fontWeight = 1 }
                Button("粗") { model.readerConfig.fontWeight = 2 }
            } label: {
                tag(weightName)
            }

            Menu {
                Button("系统") { model.readerConfig.fontFamily = "" }
                Button("宋体") { model.readerConfig.fontFamily = "Songti SC" }
                Button("黑体") { model.readerConfig.fontFamily = "PingFang SC" }
                Button("楷体") { model.readerConfig.fontFamily = "Kaiti SC" }
                Button("圆体") { model.readerConfig.fontFamily = "Yuanti SC" }
                if !FontStore.importedFonts().isEmpty {
                    Divider()
                    ForEach(FontStore.importedFonts(), id: \.name) { item in
                        Button(item.display) { model.readerConfig.fontFamily = item.name }
                    }
                }
                Divider()
                Button("导入自定义字体…") { showFontImporter = true }
            } label: {
                tag(fontName)
            }
            .id(fontTick)

            Button {
                model.readerConfig.indent.toggle()
            } label: {
                tag("缩进", active: model.readerConfig.indent)
            }
            .buttonStyle(.plain)

            Button {
                showPadding.toggle()
            } label: {
                tag("边距", active: showPadding)
            }
            .buttonStyle(.plain)

            Button("完成") { dismiss() }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var weightName: String {
        switch model.readerConfig.fontWeight {
        case 0: return "细"
        case 2: return "粗"
        default: return "中"
        }
    }

    private var fontName: String {
        switch model.readerConfig.fontFamily {
        case "Songti SC": return "宋体"
        case "PingFang SC": return "黑体"
        case "Kaiti SC": return "楷体"
        case "Yuanti SC": return "圆体"
        default: return "字体"
        }
    }

    private func tag(_ title: String, active: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(active ? Color.accentColor : Color.secondary.opacity(0.45),
                            lineWidth: active ? 1.5 : 1)
            )
            .foregroundColor(active ? .accentColor : .primary)
    }

    // MARK: - 滑条

    private func sliderRow(_ title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           step: Double) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14))
                .frame(width: 38, alignment: .leading)

            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13))
                    .frame(width: 22)
            }
            .buttonStyle(.plain)

            Slider(value: value, in: range, step: step)
                .tint(.orange)

            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13))
                    .frame(width: 22)
            }
            .buttonStyle(.plain)

            Text(display(value.wrappedValue, step: step))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func display(_ value: Double, step: Double) -> String {
        if step >= 1 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }

    // MARK: - 翻页动画

    private var animationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("翻页动画")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                animButton("覆盖", 0)
                animButton("滑动", 1)
                animButton("无动画", 2)
                animDisabled("仿真")
                animDisabled("滚动")
            }
        }
    }

    private func animButton(_ title: String, _ value: Int) -> some View {
        Button {
            model.readerConfig.pageAnim = value
        } label: {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(model.readerConfig.pageAnim == value
                            ? Color.orange.opacity(0.9) : Color.secondary.opacity(0.08))
                .foregroundColor(model.readerConfig.pageAnim == value ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func animDisabled(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.05))
            .foregroundColor(.secondary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    // MARK: - 颜色与背景

    private var themeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("文字颜色和背景")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                ForEach(ReaderTheme.allCases) { theme in
                    Button {
                        model.readerConfig.theme = theme
                    } label: {
                        Group {
                            if theme == .system {
                                Circle().fill(LinearGradient(colors: [.white, .black],
                                                             startPoint: .topLeading,
                                                             endPoint: .bottomTrailing))
                            } else {
                                Circle().fill(Color(hex: theme.backgroundHex))
                                    .overlay(Text("文")
                                        .font(.system(size: 13))
                                        .foregroundColor(Color(hex: theme.textHex)))
                            }
                        }
                        .frame(width: 40, height: 40)
                            .overlay(
                                Circle().stroke(model.readerConfig.theme == theme
                                                ? Color.accentColor : Color.secondary.opacity(0.35),
                                                lineWidth: model.readerConfig.theme == theme ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }
}
