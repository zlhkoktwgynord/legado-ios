import SwiftUI

/// 「我的」页：40pt 搜索框 + 四组卡片式设置（无图标，行高 60pt）
struct MyConfigView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    @State private var showSourceImport = false
    @State private var showAbout = false
    @State private var showClearCache = false
    @State private var cleared = false
    @State private var keyword = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    searchField

                    group("内容与规则") {
                        link("书源管理", "\(model.sources.count) 个") { SourceListView() }
                        row("导入书源") { showSourceImport = true }
                        link("替换净化", "\(model.replaceRules.count) 条") { ReplaceRulesView() }
                        row("导入本地 TXT") { showImporter = true }
                    }

                    group("外观与 AI") {
                        link("主题与排版", appAppearance) { SettingsView() }
                        appearanceRow
                    }

                    group("同步与服务") {
                        row("缓存管理", detail: cleared ? "已清空" : nil) { showClearCache = true }
                        disabledRow("备份与恢复", "还没移植")
                        disabledRow("Web 服务", "还没移植")
                    }

                    group("工具与关于") {
                        disabledRow("书签", "还没移植")
                        disabledRow("文件管理", "还没移植")
                        row("关于", detail: appVersion) { showAbout = true }
                    }

                    Text("本软件不提供任何书籍内容，书源由使用者自行导入，请支持正版。")
                        .font(.system(size: 12))
                        .foregroundColor(LegadoTheme.secondaryText(scheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 100)
            }
            .background(LegadoTheme.background(scheme).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showSourceImport) { SourceImportView() }
        .sheet(isPresented: $showImporter) {
            DocumentPicker { url in
                showImporter = false
                importLocal(url)
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("清空已缓存的章节正文？", isPresented: $showClearCache, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                Storage.clearContentCache()
                cleared = true
            }
            Button("取消", role: .cancel) {}
        }
        .alert("关于阅读 iOS", isPresented: $showAbout) {
            Button("好", role: .cancel) {}
        } message: {
            Text("阅读 iOS \(appVersion)\nLegado 书源兼容的原生 SwiftUI 移植\n\n不提供书籍内容，仅提供解析规则。")
        }
    }

    @State private var showImporter = false

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundColor(LegadoTheme.tertiaryText(scheme))
            TextField("搜索", text: $keyword)
                .font(.system(size: 14))
                .autocorrectionDisabled()
            if !keyword.isEmpty {
                Button {
                    keyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(LegadoTheme.tertiaryText(scheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LegadoTheme.card(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LegadoTheme.divider(scheme), lineWidth: 1)
        )
        .padding(.top, 4)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(LegadoTheme.accent)
                .padding(.leading, 4)
                .padding(.top, 12)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LegadoTheme.card(scheme))
            )
        }
    }

    private func row(_ title: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(LegadoTheme.primaryText(scheme))
                Spacer()
                if let detail = detail {
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundColor(LegadoTheme.secondaryText(scheme))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(LegadoTheme.tertiaryText(scheme))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func link<Destination: View>(_ title: String, _ detail: String? = nil,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(LegadoTheme.primaryText(scheme))
                Spacer()
                if let detail = detail {
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundColor(LegadoTheme.secondaryText(scheme))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(LegadoTheme.tertiaryText(scheme))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func disabledRow(_ title: String, _ note: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(LegadoTheme.tertiaryText(scheme))
            Spacer()
            Text(note)
                .font(.system(size: 13))
                .foregroundColor(LegadoTheme.tertiaryText(scheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
    }

    private var appearanceRow: some View {
        HStack {
            Text("主题模式")
                .font(.system(size: 16))
                .foregroundColor(LegadoTheme.primaryText(scheme))
            Spacer()
            HStack(spacing: 2) {
                ForEach(Array(["跟随系统", "浅色", "深色"].enumerated()), id: \.offset) { index, title in
                    Button {
                        model.setAppearance(index)
                    } label: {
                        Text(title)
                            .font(.system(size: 13, weight: model.appearance == index ? .medium : .regular))
                            .foregroundColor(model.appearance == index
                                             ? LegadoTheme.accent
                                             : LegadoTheme.secondaryText(scheme))
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(model.appearance == index
                                          ? LegadoTheme.accent.opacity(0.12)
                                          : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
    }

    private var appAppearance: String {
        switch model.appearance {
        case 1: return "浅色"
        case 2: return "深色"
        default: return "跟随系统"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "4.0"
        return "v\(version)"
    }

    private func importLocal(_ url: URL) {
        let name = url.lastPathComponent
        Task { @MainActor in
            do {
                let data = try Data(contentsOf: url)
                let imported = try await Task.detached(priority: .userInitiated) {
                    try LocalBookImporter.load(data: data, fileName: name)
                }.value
                _ = model.addLocalBook(imported)
            } catch {
                print("导入失败", error)
            }
        }
    }
}
