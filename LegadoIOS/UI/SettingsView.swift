import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var cacheSize: String = "计算中…"
    @State private var showCleanAlert = false
    @State private var message: String?
    @State private var showStyle = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("外观", selection: Binding(
                        get: { model.appearance },
                        set: { model.setAppearance($0) })) {
                        Text("跟随系统").tag(0)
                        Text("浅色").tag(1)
                        Text("深色").tag(2)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("外观")
                }

                Section {
                    Button {
                        showStyle = true
                    } label: {
                        Label("阅读排版", systemImage: "textformat")
                    }
                    NavigationLink {
                        ReplaceRulesView()
                    } label: {
                        Label("替换净化", systemImage: "wand.and.stars")
                    }
                    HStack {
                        Label("默认主题", systemImage: "circle.lefthalf.filled")
                        Spacer()
                        Text(model.readerConfig.theme.name).foregroundColor(.secondary)
                    }
                } header: {
                    Text("阅读")
                }

                if let message = message {
                    Section {
                        Text(message).font(.footnote).foregroundColor(.accentColor)
                    }
                }

                Section {
                    HStack {
                        Label("缓存占用", systemImage: "internaldrive")
                        Spacer()
                        Text(cacheSize).foregroundColor(.secondary)
                    }
                    Button {
                        showCleanAlert = true
                    } label: {
                        Label("清除正文缓存", systemImage: "trash")
                    }
                } header: {
                    Text("存储")
                } footer: {
                    Text("清除后再次阅读会重新联网抓取正文。")
                }

                Section {
                    HStack {
                        Text("书源")
                        Spacer()
                        Text("\(model.sources.count) 个 / 启用 \(model.enabledSources.count) 个")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("书架")
                        Spacer()
                        Text("\(model.books.count) 本").foregroundColor(.secondary)
                    }
                } header: {
                    Text("数据")
                }

                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(Self.version).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("兼容")
                        Spacer()
                        Text("Legado 3.0 书源").foregroundColor(.secondary)
                    }
                } header: {
                    Text("关于")
                } footer: {
                    Text("本软件不提供任何书籍内容；书源规则来自用户自行导入的 JSON。请支持正版。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showStyle) {
                ReaderStylePanel()
                    .presentationDetents([.height(380)])
            }
            .onAppear {
                calcCache()
            }
            .alert("清除缓存？", isPresented: $showCleanAlert) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) {
                    Storage.clearContentCache()
                    calcCache()
                    message = "已清除"
                }
            } message: {
                Text("已下载的章节正文会被删除。")
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func calcCache() {
        let url = Storage.cacheDir
        // 递归统计
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: url,
                                                           includingPropertiesForKeys: [.fileSizeKey]) {
            for case let file as URL in enumerator {
                if let values = try? file.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = values.fileSize {
                    total += Int64(fileSize)
                }
            }
        }
        cacheSize = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
