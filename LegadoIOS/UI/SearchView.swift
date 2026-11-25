import SwiftUI

/// 「发现」页：书源列表（探索入口）
struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    @State private var path = NavigationPath()
    @State private var showSourceImport = false
    @State private var keyword = ""

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if filteredSources.isEmpty {
                        emptyView
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filteredSources) { source in
                                Button {
                                    path.append(Route.sourceDetail(source))
                                } label: {
                                    sourceCard(source)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 120)
            }
            .background(LegadoTheme.background(scheme).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                RouteView(route: route)
            }
        }
        .sheet(isPresented: $showSourceImport) { SourceImportView() }
    }

    private var filteredSources: [BookSource] {
        let query = keyword.trimmingCharacters(in: .whitespaces)
        let list = model.sources
        guard !query.isEmpty else { return list }
        return list.filter {
            $0.bookSourceName.localizedCaseInsensitiveContains(query)
                || $0.bookSourceUrl.localizedCaseInsensitiveContains(query)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("发现")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(LegadoTheme.primaryText(scheme))
                Spacer()
                Button {
                    showSourceImport = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("导入书源")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(LegadoTheme.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(
                        Capsule().fill(LegadoTheme.accent.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(LegadoTheme.tertiaryText(scheme))
                TextField("书源名称或地址", text: $keyword)
                    .font(.system(size: 14))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LegadoTheme.fill(scheme))
            )
        }
    }

    private func sourceCard(_ source: BookSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(source.bookSourceName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(LegadoTheme.primaryText(scheme))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Circle()
                    .fill(source.enabled ? LegadoTheme.accent : LegadoTheme.tertiaryText(scheme))
                    .frame(width: 6, height: 6)
            }

            Text(host(source.bookSourceUrl))
                .font(.system(size: 11))
                .foregroundColor(LegadoTheme.secondaryText(scheme))
                .lineLimit(1)

            Text(source.bookSourceGroup ?? (source.ruleSearch != nil ? "支持搜索" : "未配置搜索"))
                .font(.system(size: 11))
                .foregroundColor(LegadoTheme.tertiaryText(scheme))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LegadoTheme.card(scheme))
        )
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "safari")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(LegadoTheme.tertiaryText(scheme))
            Text(model.sources.isEmpty ? "还没有书源" : "没有匹配的书源")
                .font(.system(size: 15))
                .foregroundColor(LegadoTheme.secondaryText(scheme))
            Button {
                showSourceImport = true
            } label: {
                Text("导入书源")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(Capsule().fill(LegadoTheme.accent))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func host(_ url: String) -> String {
        guard let host = URL(string: url)?.host else { return url }
        return host
    }
}

/// 搜索页：顶部输入框 + 按书源分组的结果
struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var keyword = ""
    @State private var results: [SourceSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var path = NavigationPath()
    @State private var toast: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                topBar
                if results.isEmpty && !isSearching {
                    historyView
                } else {
                    resultsView
                }
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
                        .padding(.bottom, 24)
                }
            }
        }
        .onDisappear { searchTask?.cancel() }
        .onAppear {
            if let screen = ProcessInfo.processInfo.environment["LEGADO_QUERY"], !screen.isEmpty {
                keyword = screen
                startSearch()
            } else {
                focused = true
            }
        }
    }

    // MARK: - 顶部

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(LegadoTheme.primaryText(scheme))
                    .frame(width: 30, height: 38)
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(LegadoTheme.tertiaryText(scheme))
                TextField("书名或作者", text: $keyword)
                    .font(.system(size: 15))
                    .focused($focused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { startSearch() }
                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                        results = []
                        searchTask?.cancel()
                        isSearching = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(LegadoTheme.tertiaryText(scheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LegadoTheme.card(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(LegadoTheme.divider(scheme), lineWidth: 1)
            )

            Button {
                startSearch()
            } label: {
                Text("搜索")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isSearching ? LegadoTheme.tertiaryText(scheme) : LegadoTheme.accent)
            }
            .buttonStyle(.plain)
            .disabled(isSearching || keyword.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: - 搜索历史

    private var historyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if model.recentKeywords.isEmpty {
                    Text("输入书名或作者，会在所有启用的书源里同时搜索")
                        .font(.system(size: 13))
                        .foregroundColor(LegadoTheme.tertiaryText(scheme))
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Text("搜索历史")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(LegadoTheme.secondaryText(scheme))
                        Spacer()
                        Button {
                            model.clearKeywords()
                        } label: {
                            Text("清空")
                                .font(.system(size: 12))
                                .foregroundColor(LegadoTheme.secondaryText(scheme))
                        }
                        .buttonStyle(.plain)
                    }

                    FlowLayout(spacing: 8) {
                        ForEach(model.recentKeywords, id: \.self) { word in
                            Button {
                                keyword = word
                                startSearch()
                            } label: {
                                Text(word)
                                    .font(.system(size: 13))
                                    .foregroundColor(LegadoTheme.primaryText(scheme))
                                    .padding(.horizontal, 12)
                                    .frame(height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .fill(LegadoTheme.fill(scheme))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 60)
        }
    }

    // MARK: - 结果

    private var resultsView: some View {
        ScrollView {
            LazyVStack(spacing: 14, pinnedViews: []) {
                if isSearching {
                    HStack(spacing: 8) {
                        ProgressView().tint(LegadoTheme.accent)
                        Text("正在搜索 \(model.enabledSources.count) 个书源…")
                            .font(.system(size: 12))
                            .foregroundColor(LegadoTheme.secondaryText(scheme))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }

                ForEach(results) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Text(section.sourceName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(LegadoTheme.secondaryText(scheme))
                            if let error = section.error {
                                Text(error)
                                    .font(.system(size: 11))
                                    .foregroundColor(LegadoTheme.accent)
                                    .lineLimit(1)
                            } else {
                                Text("\(section.books.count) 本")
                                    .font(.system(size: 11))
                                    .foregroundColor(LegadoTheme.tertiaryText(scheme))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)

                        ForEach(section.books) { book in
                            SearchBookRow(book: book) {
                                path.append(Route.searchBook(book))
                            } onAdd: {
                                addToShelf(book)
                            }
                        }
                    }
                }

                if !isSearching && results.allSatisfy({ $0.books.isEmpty }) {
                    VStack(spacing: 8) {
                        Text("没有找到这本书")
                            .font(.system(size: 14))
                            .foregroundColor(LegadoTheme.secondaryText(scheme))
                        Text("换个关键词，或者检查书源是否启用")
                            .font(.system(size: 12))
                            .foregroundColor(LegadoTheme.tertiaryText(scheme))
                    }
                    .padding(.top, 60)
                }
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - 动作

    private func startSearch() {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !model.enabledSources.isEmpty else {
            toast = "还没有启用的书源"
            return
        }
        model.rememberKeyword(trimmed)
        searchTask?.cancel()
        results = []
        isSearching = true
        focused = false
        searchTask = Task {
            for await result in model.search(keyword: trimmed) {
                if Task.isCancelled { break }
                results.append(result)
            }
            if !Task.isCancelled {
                isSearching = false
            }
        }
    }

    private func addToShelf(_ searchBook: SearchBook) {
        _ = model.addToShelf(searchBook)
        toast = "已加入书架"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            toast = nil
        }
    }
}

/// 搜索结果一行
struct SearchBookRow: View {
    let book: SearchBook
    var onOpen: () -> Void
    var onAdd: () -> Void

    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                Color.clear
                    .frame(width: 72, height: 104)
                    .overlay(RemoteImage(urlString: book.coverUrl ?? ""))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(book.name)
                        .font(.system(size: 17))
                        .foregroundColor(LegadoTheme.primaryText(scheme))
                        .lineLimit(1)
                    Text(book.author)
                        .font(.system(size: 12))
                        .foregroundColor(LegadoTheme.secondaryText(scheme))
                        .lineLimit(1)
                    if let latest = book.latestChapterTitle, !latest.isEmpty {
                        Text("最新：\(latest)")
                            .font(.system(size: 11))
                            .foregroundColor(LegadoTheme.tertiaryText(scheme))
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(book.originName)
                            .font(.system(size: 10))
                            .foregroundColor(LegadoTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(LegadoTheme.accent.opacity(0.10))
                            )
                        if let kind = book.kind, !kind.isEmpty {
                            Text(kind)
                                .font(.system(size: 10))
                                .foregroundColor(LegadoTheme.tertiaryText(scheme))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)

                Button {
                    onAdd()
                } label: {
                    Image(systemName: model.isOnShelf(bookUrl: book.bookUrl) ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(model.isOnShelf(bookUrl: book.bookUrl)
                                         ? LegadoTheme.tertiaryText(scheme)
                                         : LegadoTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(LegadoTheme.fill(scheme))
                        )
                }
                .buttonStyle(.plain)
                .disabled(model.isOnShelf(bookUrl: book.bookUrl))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 简单的流式布局（搜索历史标签用）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width && rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
