import SwiftUI

/// 书架：顶部「书架 ▾」+ 分组标签栏 + 网格/列表两种样式
struct BookshelfView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var onSearch: () -> Void = {}
    var onOpenDrawer: () -> Void = {}

    @State private var path = NavigationPath()
    @State private var style: Int = UserDefaults.standard.integer(forKey: "shelfStyle")
    @State private var filter: Int = 0
    @State private var sortMode: Int = 0
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showSourceImport = false
    @State private var showSourceList = false
    @State private var toast: String?
    @State private var errorMessage: String?
    @State private var refreshing: Set<String> = []

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                tagBar
                content
            }
            .background(LegadoTheme.background(scheme).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                RouteView(route: route)
            }
            .overlay(alignment: .bottom) {
                if let toast = toast {
                    Text(toast)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.78))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(.bottom, 92)
                        .transition(.opacity)
                }
            }
            .alert("出错了", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } })) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showSourceImport) { SourceImportView() }
        .sheet(isPresented: $showSourceList) { SourceListView() }
        .sheet(isPresented: $showImporter) {
            DocumentPicker { url in
                showImporter = false
                handlePicked(url)
            }
            .ignoresSafeArea()
        }
    }

    private var books: [Book] {
        var list = model.books
        switch filter {
        case 1: list = list.filter { $0.durChapterIndex > 0 || $0.durChapterTime > 0 }
        case 2: list = list.filter { $0.isLocal }
        default: break
        }
        switch sortMode {
        case 1: list.sort { $0.name < $1.name }
        case 2: list.sort { $0.bookUrl < $1.bookUrl }
        default:
            list.sort { lhs, rhs in
                if lhs.durChapterTime != rhs.durChapterTime {
                    return lhs.durChapterTime > rhs.durChapterTime
                }
                return lhs.name < rhs.name
            }
        }
        return list
    }

    // MARK: - 顶部标题

    private var header: some View {
        HStack(spacing: 4) {
            Menu {
                Button {
                    setStyle(0)
                } label: {
                    Label("网格视图", systemImage: "square.grid.3x3")
                }
                Button {
                    setStyle(1)
                } label: {
                    Label("列表视图", systemImage: "list.bullet")
                }
            } label: {
                HStack(spacing: 2) {
                    Text("书架")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(LegadoTheme.primaryText(scheme))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(LegadoTheme.secondaryText(scheme))
                }
            }

            Spacer()

            Menu {
                Button("最近阅读") { sortMode = 0 }
                Button("书名") { sortMode = 1 }
                Button("加入顺序") { sortMode = 2 }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(LegadoTheme.secondaryText(scheme))
                    .frame(width: 34, height: 34)
            }

            Menu {
                Button {
                    showSourceImport = true
                } label: {
                    Label("导入书源", systemImage: "square.and.arrow.down")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("导入本地 TXT", systemImage: "doc.badge.plus")
                }
                Divider()
                Button {
                    showSourceList = true
                } label: {
                    Label("书源管理", systemImage: "square.stack.3d.up")
                }
                Button {
                    showSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(LegadoTheme.secondaryText(scheme))
                    .frame(width: 34, height: 34)
            }

            Button {
                onOpenDrawer()
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 18))
                    .foregroundColor(LegadoTheme.secondaryText(scheme))
                    .frame(width: 34, height: 34)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - 分组标签栏

    private var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tagChip("全部", 0)
                tagChip("在读", 1)
                tagChip("本地", 2)
                Button {
                    showSourceImport = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(LegadoTheme.secondaryText(scheme))
                        .frame(width: 32, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(LegadoTheme.fill(scheme))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .padding(.bottom, 6)
    }

    private func tagChip(_ title: String, _ value: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { filter = value }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: filter == value ? .semibold : .regular))
                .foregroundColor(filter == value ? LegadoTheme.accent : LegadoTheme.secondaryText(scheme))
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(filter == value ? LegadoTheme.accent.opacity(0.14) : LegadoTheme.fill(scheme))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if books.isEmpty {
            emptyView
        } else if style == 1 {
            listView
        } else {
            gridView
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 18) {
                ForEach(books) { book in
                    Button {
                        path.append(Route.reader(book, book.durChapterIndex))
                    } label: {
                        gridCell(book)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menuItems(book) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 110)
        }
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(books) { book in
                    Button {
                        path.append(Route.reader(book, book.durChapterIndex))
                    } label: {
                        listCell(book)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menuItems(book) }
                    LegadoDivider()
                        .padding(.leading, 0)
                }
            }
            .padding(.bottom, 110)
        }
    }

    private func gridCell(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay(
                        RemoteImage(urlString: book.customCoverUrl ?? book.coverUrl ?? "")
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                    )

                if book.isLocal {
                    Text("本地")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(LegadoTheme.accent.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .padding(4)
                }

                if refreshing.contains(book.bookUrl) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }

            Text(book.name)
                .font(.system(size: 12))
                .foregroundColor(LegadoTheme.primaryText(scheme))
                .lineLimit(1)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func listCell(_ book: Book) -> some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 56, height: 76)
                .overlay(RemoteImage(urlString: book.customCoverUrl ?? book.coverUrl ?? ""))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(book.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(LegadoTheme.primaryText(scheme))
                    .lineLimit(1)
                Text(book.displayAuthor)
                    .font(.system(size: 12))
                    .foregroundColor(LegadoTheme.secondaryText(scheme))
                    .lineLimit(1)
                Text(readState(book))
                    .font(.system(size: 12))
                    .foregroundColor(LegadoTheme.tertiaryText(scheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if refreshing.contains(book.bookUrl) {
                ProgressView().tint(LegadoTheme.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func readState(_ book: Book) -> String {
        if book.totalChapterNum > 0 {
            let index = min(book.durChapterIndex + 1, book.totalChapterNum)
            return "读至 \(index)/\(book.totalChapterNum) 章"
        }
        return book.durChapterTitle ?? "未读"
    }

    @ViewBuilder
    private func menuItems(_ book: Book) -> some View {
        Button {
            path.append(Route.detail(book))
        } label: {
            Label("书籍详情", systemImage: "info.circle")
        }
        Button {
            refreshToc(book)
        } label: {
            Label("刷新目录", systemImage: "arrow.triangle.2.circlepath")
        }
        Divider()
        Button(role: .destructive) {
            model.removeBook(book)
        } label: {
            Label("移出书架", systemImage: "trash")
        }
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(LegadoTheme.tertiaryText(scheme))
            Text(model.sources.isEmpty ? "还没有书源" : "书架是空的")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(LegadoTheme.primaryText(scheme))
            Text(model.sources.isEmpty
                 ? "导入书源之后，就能在「搜索」里找书了"
                 : "在右上角搜索里找书，长按结果加入书架")
                .font(.system(size: 13))
                .foregroundColor(LegadoTheme.secondaryText(scheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 12) {
                Button {
                    showSourceImport = true
                } label: {
                    Text("导入书源")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .frame(height: 42)
                        .background(Capsule().fill(LegadoTheme.accent))
                }
                .buttonStyle(.plain)

                Button {
                    onSearch()
                } label: {
                    Text("去搜索")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(LegadoTheme.primaryText(scheme))
                        .padding(.horizontal, 22)
                        .frame(height: 42)
                        .background(Capsule().fill(LegadoTheme.fill(scheme)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
            Spacer()
            Spacer()
        }
    }

    // MARK: - 动作

    private func setStyle(_ value: Int) {
        style = value
        UserDefaults.standard.set(value, forKey: "shelfStyle")
    }

    private func refreshToc(_ book: Book) {
        guard let source = model.source(for: book) else {
            errorMessage = "找不到这本书对应的书源"
            return
        }
        refreshing.insert(book.bookUrl)
        Task { @MainActor in
            defer { refreshing.remove(book.bookUrl) }
            do {
                let result = try await BookService.refreshToc(book: book, source: source)
                var updated = book
                updated.totalChapterNum = result.chapters.count
                updated.latestChapterTitle = result.chapters.last?.title
                model.updateBook(updated)
                toast = result.added > 0 ? "更新了 \(result.added) 章" : "目录已是最新"
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                toast = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handlePicked(_ url: URL) {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        guard ["txt", "text", "md", "log", ""].contains(ext) else {
            errorMessage = "目前只支持 TXT 文件（选中的是 .\(ext)）"
            return
        }
        Task { @MainActor in
            do {
                let data = try Data(contentsOf: url)
                guard !data.isEmpty else {
                    errorMessage = "文件是空的，或者系统没有复制成功"
                    return
                }
                let imported = try await Task.detached(priority: .userInitiated) {
                    try LocalBookImporter.load(data: data, fileName: name)
                }.value
                let book = model.addLocalBook(imported)
                try? await Task.sleep(nanoseconds: 300_000_000)
                path.append(Route.reader(book, 0))
            } catch {
                errorMessage = "导入失败：\(error.localizedDescription)"
            }
        }
    }
}
