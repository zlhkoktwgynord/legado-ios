import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct SourceListView: View {
    @EnvironmentObject private var model: AppModel

    @State private var searchText = ""
    @State private var showImport = false
    @State private var showSettings = false
    @State private var path = NavigationPath()
    @State private var message: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if model.sources.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("还没有书源")
                                .font(.headline)
                            Text("书源是 JSON 规则，和安卓「阅读」通用。可以从文件、剪贴板或网址导入。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Button {
                                showImport = true
                            } label: {
                                Label("导入书源", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    Section {
                        ForEach(filteredSources) { source in
                            NavigationLink(value: Route.sourceDetail(source)) {
                                row(source)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    model.deleteSource(source)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    model.setSourceEnabled(source, enabled: !source.enabled)
                                } label: {
                                    Label(source.enabled ? "禁用" : "启用",
                                          systemImage: source.enabled ? "pause" : "play")
                                }
                                .tint(.orange)
                            }
                        }
                    } header: {
                        Text("共 \(model.sources.count) 个，已启用 \(model.enabledSources.count) 个")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "搜索书源名称或地址")
            .navigationTitle("书源")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showImport = true
                        } label: {
                            Label("导入书源", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            importFromClipboard()
                        } label: {
                            Label("从剪贴板导入", systemImage: "doc.on.clipboard")
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                RouteView(route: route)
            }
            .sheet(isPresented: $showImport) {
                SourceImportView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("提示", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } })) {
                Button("好的", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var filteredSources: [BookSource] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let sorted = model.sources.sorted { lhs, rhs in
            if lhs.customOrder != rhs.customOrder { return lhs.customOrder < rhs.customOrder }
            return lhs.bookSourceName < rhs.bookSourceName
        }
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            $0.bookSourceName.localizedCaseInsensitiveContains(query)
                || $0.bookSourceUrl.localizedCaseInsensitiveContains(query)
        }
    }

    private func row(_ source: BookSource) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(source.enabled ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(source.bookSourceName.isEmpty ? "未命名书源" : source.bookSourceName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(source.bookSourceUrl)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let group = source.bookSourceGroup, !group.isEmpty {
                TagChip(text: group)
            }
        }
    }

    private func importFromClipboard() {
        #if canImport(UIKit)
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            message = "剪贴板里没有内容"
            return
        }
        let result = model.importSources(text)
        message = result.added > 0
            ? "已导入 \(result.added) 个书源，共 \(result.total) 个"
            : "没有解析到新的书源"
        #endif
    }
}

// MARK: - 导入

struct SourceImportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var urlString = ""
    @State private var showFilePicker = false
    @State private var message: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .font(.system(size: 12, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("粘贴书源 JSON…")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("粘贴书源")
                } footer: {
                    Text("支持阅读 3.0 的书源数组，或每行一个书源对象")
                }

                Section("从文件或链接") {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("选择文件", systemImage: "folder")
                    }
                    HStack {
                        TextField("书源地址（http/https）", text: $urlString)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button("导入") { importFromURL() }
                            .disabled(urlString.isEmpty || loading)
                    }
                    if loading { LoadingRow(text: "下载中…") }
                }

                if let message = message {
                    Section {
                        Text(message).font(.footnote).foregroundColor(.accentColor)
                    }
                }
            }
            .navigationTitle("导入书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { doImport() }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .fileImporter(isPresented: $showFilePicker,
                          allowedContentTypes: [.json, .plainText, .text],
                          allowsMultipleSelection: false) { result in
                handleFile(result)
            }
        }
    }

    private func doImport() {
        let result = model.importSources(text)
        if result.added > 0 {
            dismiss()
        } else {
            message = "没有解析到新的书源，请检查 JSON 是否正确"
        }
    }

    private func importFromURL() {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            message = "链接格式不正确"
            return
        }
        loading = true
        Task { @MainActor in
            defer { loading = false }
            do {
                let response = try await HTTPClient.shared.send(HTTPRequest(url: url.absoluteString))
                text = response.text
                message = "已下载，请点右上角导入"
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                if let content = String(data: data, encoding: .utf8) {
                    text = content
                } else if let content = String(data: data, encoding: .unicode) {
                    text = content
                } else {
                    message = "文件编码无法识别"
                }
            } catch {
                message = error.localizedDescription
            }
        case .failure(let error):
            message = error.localizedDescription
        }
    }
}

// MARK: - 书源详情

struct SourceDetailView: View {
    @EnvironmentObject private var model: AppModel
    let source: BookSource
    @State private var testKeyword = ""
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        Form {
            Section("基本信息") {
                LabeledContent("名称", value: source.bookSourceName)
                LabeledContent("地址", value: source.bookSourceUrl)
                if let group = source.bookSourceGroup {
                    LabeledContent("分组", value: group)
                }
                Toggle("启用", isOn: Binding(
                    get: { current?.enabled ?? source.enabled },
                    set: { model.setSourceEnabled(source, enabled: $0) }))
            }

            Section("调试") {
                HStack {
                    TextField("搜索关键字", text: $testKeyword)
                    Button("测试") { test() }
                        .disabled(testKeyword.isEmpty || testing)
                }
                if testing { LoadingRow(text: "请求中…") }
                if let result = testResult {
                    Text(result).font(.footnote).foregroundColor(.secondary)
                }
            }

            Section("规则") {
                ruleRow("搜索地址", source.searchUrl)
                ruleRow("搜索列表", source.ruleSearch?.bookList)
                ruleRow("书名", source.ruleSearch?.name)
                ruleRow("作者", source.ruleSearch?.author)
                ruleRow("目录", source.ruleToc?.chapterList)
                ruleRow("正文", source.ruleContent?.content)
            }

            Section {
                Button(role: .destructive) {
                    model.deleteSource(source)
                } label: {
                    Text("删除书源")
                }
            }
        }
        .navigationTitle(source.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var current: BookSource? {
        model.sources.first { $0.bookSourceUrl == source.bookSourceUrl }
    }

    @ViewBuilder
    private func ruleRow(_ title: String, _ value: String?) -> some View {
        if let value = value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(3)
            }
        }
    }

    private func test() {
        testing = true
        testResult = nil
        Task { @MainActor in
            defer { testing = false }
            do {
                let books = try await SourceEngine(source: source).search(testKeyword)
                if books.isEmpty {
                    testResult = "没有结果"
                } else {
                    testResult = books.prefix(5)
                        .map { "\($0.name) / \($0.author)" }
                        .joined(separator: "\n")
                }
            } catch {
                testResult = "失败：\(error.localizedDescription)"
            }
        }
    }
}
