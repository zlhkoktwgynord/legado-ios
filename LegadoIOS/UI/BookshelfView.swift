import SwiftUI

/// 书架：24sp 大标题 + 38pt 分组标签栏 + 列表 / 网格（1~5 列）
struct BookshelfView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var onSearch: () -> Void = {}

    @State private var path = NavigationPath()
    /// 0 列表 1 紧凑列表 2~5 网格列数
    @State private var columns: Int = UserDefaults.standard.integer(forKey: "shelfColumns")
    @State private var filter: Int = 0
    @State private var sortMode: Int = 0
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showSourceImport = false
    @State private var showSourceList = false
    @State private var toast: String?
    @State private var errorMessage: String?
    @State private var refreshing: Set<String> = []

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
            .onAppear { debugOpenReader() }
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

    // MARK: - 标题行（42pt）

    private var header: some View {
        HStack(spacing: 2) {
            Menu {
                Button("全部") { filter = 0 }
                Button("在读") { filter = 1 }
                Button("本地") { filter = 2 }
            } label: {
                HStack(spacing: 4) {
                    Text("书架")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(LegadoTheme.primaryText(scheme))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(LegadoTheme.secondaryText(scheme))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Menu {
                Button {
                    showImporter = true
                } label: {
                    Label("添加本地书籍", systemImage: "doc.badge.plus")
                }
                Button {
                    showSourceImport = true
                } label: {
                    Label("导入书源", systemImage: "square.and.arrow.down")
                }
                Button {
                    showSourceList = true
                } label: {
                    Label("书源管理", systemImage: "square.stack.3d.up")
                }
                Divider()
                Menu {
                    Button("列表") { setColumns(0) }
                    Button("紧凑列表") { setColumns(1) }
                    Button("2 列") { setColumns(2) }
                    Button("3 列") { setColumns(3) }
                    Button("4 列") { setColumns(4) }
                    Button("5 列") { setColumns(5) }
                } label: {
                    Label("书架布局", systemImage: "square.grid.3x3")
                }
                Menu {
                    Button("最近阅读") { sortMode = 0 }
                    Button("书名") { sortMode = 1 }
                    Button("加入顺序") { sortMode = 2 }
                } label: {
                    Label("排序", systemImage: "arrow.up.arrow.down")
                }
                Divider()
                Button {
                    showSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(LegadoTheme.primaryText(scheme).opacity(0.75))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(LegadoTheme.primaryText(scheme).opacity(0.75))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 42)
        .padding(.top, 6)
    }

    // MARK: - 分组标签栏（38pt）

    private var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                tagChip("全部", 0)
                tagChip("在读", 1)
                tagChip("本地", 2)
            }
            .padding(.horizontal, 3)
        }
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LegadoTheme.surface(scheme))
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func tagChip(_ title: String, _ value: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { filter = value }
        } label: {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(filter == value
                                 ? LegadoTheme.accent
                                 : LegadoTheme.primaryText(scheme))
                .padding(.horizontal, 12)
                .frame(minWidth: 36)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(filter == value ? LegadoTheme.card(scheme) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if books.isEmpty {
            emptyView
        } else if columns >= 2 {
            gridView
        } else {
            listView
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24),
                                     count: min(max(columns, 2), 5)),
                      spacing: 24) {
                ForEach(books) { book in
                    Button {
                        path.append(Route.reader(book, book.durChapterIndex))
                    } label: {
                        gridCell(book)
                    }
                    .buttonStyle(.plain)
                    .onLongPressGesture { path.append(Route.detail(book)) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 90)
        }
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(books) { book in
                    Button {
                        path.append(Route.reader(book, book.durChapterIndex))
                    } label: {
                        listCell(book, compact: columns == 1)
                    }
                    .buttonStyle(.plain)
                    .onLongPressGesture { path.append(Route.detail(book)) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 90)
        }
    }

    private func gridCell(_ book: Book) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay(
                        RemoteImage(urlString: book.customCoverUrl ?? book.coverUrl ?? "")
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                if refreshing.contains(book.bookUrl) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .padding(5)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Circle())
                        .padding(4)
                }
            }
            .padding(4)

            Text(book.name)
                .font(.system(size: 12))
                .foregroundColor(LegadoTheme.primaryText(scheme))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(4)
    }

    private func listCell(_ book: Book, compact: Bool) -> some View {
        let coverWidth: CGFloat = compact ? 48 : 66
        let coverHeight: CGFloat = compact ? 64 : 90

        return HStack(alignment: .top, spacing: 10) {
            Color.clear
                .frame(width: coverWidth, height: coverHeight)
                .overlay(RemoteImage(urlString: book.customCoverUrl ?? book.coverUrl ?? ""))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(book.name)
                        .font(.system(size: 16))
                        .foregroundColor(LegadoTheme.primaryText(scheme))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(updateText(book))
                        .font(.system(size: 13))
                        .foregroundColor(LegadoTheme.secondaryText(scheme))
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Image(systemName: "person")
                        .font(.system(size: 11))
                    Text(book.displayAuthor)
                        .font(.system(size: 13))
                        .lineLimit(1)
                }
                .foregroundColor(LegadoTheme.secondaryText(scheme))

                Text(readChapter(book))
                    .font(.system(size: 13))
                    .foregroundColor(LegadoTheme.secondaryText(scheme))
                    .lineLimit(1)

                if let latest = book.latestChapterTitle, !latest.isEmpty {
                    Text(latest)
                        .font(.system(size: 13))
                        .foregroundColor(LegadoTheme.tertiaryText(scheme))
                        .lineLimit(1)
                }
            }

            if refreshing.contains(book.bookUrl) {
                ProgressView().tint(LegadoTheme.accent)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func updateText(_ book: Book) -> String {
        guard book.lastCheckTime > 0 else { return "" }
        let date = Date(timeIntervalSince1970: Double(book.lastCheckTime) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func readChapter(_ book: Book) -> String {
        if let title = book.durChapterTitle, !title.isEmpty {
            return "已读：\(title)"
        }
        if book.totalChapterNum > 0 {
            return "共 \(book.totalChapterNum) 章"
        }
        return "未开始"
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
                 ? "导入书源之后，就能在搜索里找书了"
                 : "点右上角搜索找书，长按结果加入书架")
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

    private func debugOpenReader() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["LEGADO_SCREEN"] == "reader",
              path.isEmpty,
              let book = model.sortedBooks.first else { return }
        path.append(Route.reader(book, book.durChapterIndex))
        #endif
    }

    private func setColumns(_ value: Int) {
        columns = value
        UserDefaults.standard.set(value, forKey: "shelfColumns")
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
