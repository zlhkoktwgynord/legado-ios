import SwiftUI

/// 「我的」页：书源 / 净化 / 外观 / 缓存 / 关于
struct MyConfigView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    @State private var showSourceImport = false
    @State private var showAbout = false
    @State private var showClearCache = false
    @State private var showClearDone = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    profileCard

                    LegadoSectionCard("内容") {
                        NavigationLink {
                            SourceListView()
                        } label: {
                            LegadoListRow(icon: "square.stack.3d.up", title: "书源管理",
                                          detail: "\(model.sources.count) 个")
                        }
                        .buttonStyle(.plain)
                        LegadoDivider()
                        Button {
                            showSourceImport = true
                        } label: {
                            LegadoListRow(icon: "square.and.arrow.down", title: "导入书源", showChevron: false)
                        }
                        .buttonStyle(.plain)
                        LegadoDivider()
                        NavigationLink {
                            ReplaceRulesView()
                        } label: {
                            LegadoListRow(icon: "wand.and.stars", title: "替换净化",
                                          detail: "\(model.replaceRules.count) 条")
                        }
                        .buttonStyle(.plain)
                    }

                    LegadoSectionCard("阅读") {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            LegadoListRow(icon: "textformat", title: "阅读排版与外观")
                        }
                        .buttonStyle(.plain)
                        LegadoDivider()
                        appearanceRow
                    }

                    LegadoSectionCard("其他") {
                        Button {
                            showClearCache = true
                        } label: {
                            LegadoListRow(icon: "internaldrive", title: "清空正文缓存",
                                          detail: showClearDone ? "已清空" : nil,
                                          showChevron: false)
                        }
                        .buttonStyle(.plain)
                        LegadoDivider()
                        Button {
                            showAbout = true
                        } label: {
                            LegadoListRow(icon: "info.circle", title: "关于阅读",
                                          detail: appVersion)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("本软件不提供任何书籍内容，书源由使用者自行导入，请支持正版。")
                        .font(.system(size: 11))
                        .foregroundColor(LegadoTheme.tertiaryText(scheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .background(LegadoTheme.background(scheme).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showSourceImport) { SourceImportView() }
        .confirmationDialog("清空已缓存的章节正文？", isPresented: $showClearCache, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                Storage.clearContentCache()
                showClearDone = true
            }
            Button("取消", role: .cancel) {}
        }
        .alert("关于阅读 iOS", isPresented: $showAbout) {
            Button("好", role: .cancel) {}
        } message: {
            Text("阅读 iOS \(appVersion)\nLegado 书源兼容的原生 SwiftUI 移植\n\n不提供书籍内容，仅提供解析规则。")
        }
    }

    private var profileCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LegadoTheme.accent.opacity(0.14))
                Image(systemName: "book.fill")
                    .font(.system(size: 20))
                    .foregroundColor(LegadoTheme.accent)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text("阅读")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(LegadoTheme.primaryText(scheme))
                Text("书架 \(model.books.count) 本 · 书源 \(model.sources.count) 个")
                    .font(.system(size: 12))
                    .foregroundColor(LegadoTheme.secondaryText(scheme))
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LegadoTheme.card(scheme))
        )
    }

    private var appearanceRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 17))
                .foregroundColor(LegadoTheme.secondaryText(scheme))
                .frame(width: 24)
            Text("外观")
                .font(.system(size: 16))
                .foregroundColor(LegadoTheme.primaryText(scheme))
            Spacer()
            HStack(spacing: 0) {
                ForEach(Array(["跟随系统", "浅色", "深色"].enumerated()), id: \.offset) { index, title in
                    Button {
                        model.setAppearance(index)
                    } label: {
                        Text(title)
                            .font(.system(size: 12, weight: model.appearance == index ? .semibold : .regular))
                            .foregroundColor(model.appearance == index
                                             ? LegadoTheme.accent
                                             : LegadoTheme.secondaryText(scheme))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(model.appearance == index
                                          ? LegadoTheme.accent.opacity(0.14)
                                          : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.1"
        return "v\(version)"
    }
}
