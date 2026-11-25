import SwiftUI

/// 阅读界面的排版面板（仿原版底部面板）
struct ReaderStylePanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var config: Binding<ReaderConfig> { $model.readerConfig }

    var body: some View {
        VStack(spacing: 12) {
            themeRow
            pickerRow
            sliderRow("字号", value: config.fontSize, range: 12...32, step: 1)
            sliderRow("字距", value: config.letterSpacing, range: -1...4, step: 0.5)
            sliderRow("行距", value: config.lineSpacing, range: -4...24, step: 1)
            sliderRow("段距", value: config.paragraphSpacing, range: 0...30, step: 1)
            extraRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .onChange(of: model.readerConfig) { _ in
            model.saveReaderConfig()
        }
    }

    // MARK: - 主题

    private var themeRow: some View {
        HStack(spacing: 10) {
            ForEach(ReaderTheme.allCases) { theme in
                Button {
                    model.readerConfig.theme = theme
                } label: {
                    Circle()
                        .fill(Color(hex: theme.backgroundHex))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle().stroke(model.readerConfig.theme == theme
                                            ? Color.accentColor : Color.secondary.opacity(0.3),
                                            lineWidth: model.readerConfig.theme == theme ? 2 : 0.5)
                        )
                        .overlay(
                            Text("文")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: theme.textHex))
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button("完成") { dismiss() }
                .font(.system(size: 13))
        }
    }

    // MARK: - 字体 / 粗细 / 缩进

    private var pickerRow: some View {
        HStack(spacing: 8) {
            Menu {
                Button("系统") { model.readerConfig.fontFamily = "" }
                Button("宋体") { model.readerConfig.fontFamily = "Songti SC" }
                Button("黑体") { model.readerConfig.fontFamily = "PingFang SC" }
                Button("楷体") { model.readerConfig.fontFamily = "Kaiti SC" }
                Button("圆体") { model.readerConfig.fontFamily = "Yuanti SC" }
            } label: {
                pill(fontName, active: true)
            }

            ForEach([("细", 0), ("中", 1), ("粗", 2)], id: \.1) { title, weight in
                Button {
                    model.readerConfig.fontWeight = weight
                } label: {
                    pill(title, active: model.readerConfig.fontWeight == weight)
                }
                .buttonStyle(.plain)
            }

            Button {
                model.readerConfig.indent.toggle()
            } label: {
                pill("缩进", active: model.readerConfig.indent)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var fontName: String {
        switch model.readerConfig.fontFamily {
        case "": return "字体"
        case "Songti SC": return "宋体"
        case "PingFang SC": return "黑体"
        case "Kaiti SC": return "楷体"
        case "Yuanti SC": return "圆体"
        default: return "字体"
        }
    }

    private func pill(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(active ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            .foregroundColor(active ? .accentColor : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - 滑条

    private func sliderRow(_ title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           step: Double) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .frame(width: 34, alignment: .leading)

            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Slider(value: value, in: range, step: step)
                .tint(.red)

            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Text(display(value.wrappedValue, step: step))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func display(_ value: Double, step: Double) -> String {
        if step >= 1 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }

    private var extraRow: some View {
        HStack(spacing: 8) {
            Text("边距")
                .font(.system(size: 13))
            Slider(value: config.padding, in: 6...44, step: 2)
                .tint(.red)
            Text(String(format: "%.0f", model.readerConfig.padding))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }
}
