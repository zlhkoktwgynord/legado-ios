import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum Route: Hashable {
    case detail(Book)
    case searchBook(SearchBook)
    case reader(Book, Int)
    case sourceDetail(BookSource)
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: Int = 0
    @State private var showWelcome = false

    var body: some View {
        TabView(selection: $tab) {
            BookshelfView(selectedTab: $tab)
                .tabItem { Label("书架", systemImage: "books.vertical") }
                .tag(0)
            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                .tag(1)
            SourceListView()
                .tabItem { Label("书源", systemImage: "square.stack.3d.up") }
                .tag(2)
        }
        .onAppear {
            if model.sources.isEmpty && !showWelcome {
                showWelcome = true
            }
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeView(selectedTab: $tab)
        }
    }
}

/// 统一的路由出口
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .detail(let book):
            BookDetailView(book: book)
        case .searchBook(let searchBook):
            BookDetailView(searchBook: searchBook)
        case .reader(let book, let index):
            ReaderView(book: book, startIndex: index)
        case .sourceDetail(let source):
            SourceDetailView(source: source)
        }
    }
}

/// 首次启动引导：导入书源
struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTab: Int
    @State private var importText = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("欢迎使用 阅读 iOS")
                        .font(.title2).bold()
                    Text("本软件不提供任何书籍内容，需要先导入书源（与安卓「阅读」的书源 JSON 通用）。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("方式一：粘贴书源").font(.headline)
                        TextEditor(text: $importText)
                            .frame(height: 160)
                            .padding(6)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .font(.system(size: 12, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button {
                            importFromClipboard()
                        } label: {
                            Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            importNow()
                        } label: {
                            Text("导入书源").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(importText.isEmpty)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("方式二：从文件导入").font(.headline)
                        Text("进入「书源」页右上角 → 导入，可选择 .json / .txt 书源文件。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    if let message = message {
                        Text(message).font(.footnote).foregroundColor(.accentColor)
                    }

                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            .navigationTitle("开始")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("稍后") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("去书源页") {
                        selectedTab = 2
                        dismiss()
                    }
                }
            }
        }
    }

    private func importFromClipboard() {
        #if canImport(UIKit)
        if let text = UIPasteboard.general.string, !text.isEmpty {
            importText = text
        }
        #endif
    }

    private func importNow() {
        let result = model.importSources(importText)
        if result.added > 0 {
            message = "已导入 \(result.added) 个书源，共 \(result.total) 个"
            dismiss()
        } else {
            message = "没有解析到新的书源，请检查 JSON 格式"
        }
    }
}
