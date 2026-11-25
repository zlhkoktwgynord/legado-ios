import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var model: AppModel

    @State private var keyword = ""
    @State private var results: [SourceSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var path = NavigationPath()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                searchBar
                Divider()
                content
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                RouteView(route: route)
            }
            .onDisappear { searchTask?.cancel() }
        }
    }

    // MARK: - 搜索框

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("书名或作者", text: $keyword)
                    .focused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { startSearch() }
                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                if isSearching {
                    cancelSearch()
                } else {
                    startSearch()
                }
            } label: {
                Text(isSearching ? "停止" : "搜索")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty && !isSearching)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            progressBar
        }
        if model.enabledSources.isEmpty {
            EmptyStateView(icon: "square.stack.3d.up.slash",
                           title: "没有可用的书源",
                           message: "请先在「书源」页导入并启用书源")
        } else if results.isEmpty && !isSearching {
            suggestionList
        } else {
            resultList
        }
    }

    private var progressBar: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.8)
            Text("已返回 \(results.count) / \(model.enabledSources.count) 个书源")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var suggestionList: some View {
        List {
            if !model.recentKeywords.isEmpty {
                Section {
                    ForEach(model.recentKeywords, id: \.self) { word in
                        Button {
                            keyword = word
                            startSearch()
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.secondary)
                                Text(word)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button(role: .destructive) {
                        model.clearKeywords()
                    } label: {
                        Text("清空搜索历史").font(.footnote)
                    }
                } header: {
                    Text("最近搜索")
                }
            }
            Section {
                Text("共 \(model.enabledSources.count) 个书源可用，搜索会并发请求它们。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } header: {
                Text("提示")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var resultList: some View {
        List {
            ForEach(results) { group in
                Section {
                    if group.books.isEmpty {
                        Text(group.error ?? "没有搜索到结果")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(group.books) { book in
                            Button {
                                path.append(Route.searchBook(book))
                            } label: {
                                SearchBookRow(book: book)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    HStack {
                        Text(group.sourceName)
                        Spacer()
                        if !group.books.isEmpty {
                            Text("\(group.books.count) 本")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 动作

    private func startSearch() {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        focused = false
        searchTask?.cancel()
        results = []
        isSearching = true
        model.rememberKeyword(query)

        searchTask = Task { @MainActor in
            for await result in model.search(keyword: query) {
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.15)) {
                    results.append(result)
                }
            }
            if !Task.isCancelled {
                results.sort { lhs, rhs in
                    if lhs.books.count != rhs.books.count { return lhs.books.count > rhs.books.count }
                    return lhs.sourceName < rhs.sourceName
                }
            }
            isSearching = false
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }
}

struct SearchBookRow: View {
    let book: SearchBook

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BookCover(url: book.coverUrl, title: book.name, width: 46, height: 62, radius: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(book.author)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let kind = book.kind, !kind.isEmpty {
                    Text(kind)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if let latest = book.latestChapterTitle, !latest.isEmpty {
                    Text("最新：\(latest)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
