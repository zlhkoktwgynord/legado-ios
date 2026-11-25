import SwiftUI

struct BookDetailView: View {
    @EnvironmentObject private var model: AppModel

    private let searchBookValue: SearchBook?
    @State private var book: Book
    @State private var chapters: [BookChapter] = []
    @State private var loading = false
    @State private var loadingToc = false
    @State private var error: String?
    @State private var showAllChapters = false
    @State private var showSwitch = false
    @State private var caching = false
    @State private var cacheProgress: Double = 0
    @State private var cachedCount = 0

    init(book: Book) {
        self.searchBookValue = nil
        _book = State(initialValue: book)
    }

    init(searchBook: SearchBook) {
        self.searchBookValue = searchBook
        _book = State(initialValue: searchBook.toBook())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let error = error {
                    ErrorBanner(message: error)
                }
                actionRow
                if let intro = book.intro, !intro.isEmpty {
                    section(title: "简介") {
                        Text(intro)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if caching {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: cacheProgress)
                        Text("正在缓存 \(Int(cacheProgress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                chapterSection
            }
            .padding(16)
        }
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        load(force: true)
                    } label: {
                        Label("刷新详情与目录", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        showSwitch = true
                    } label: {
                        Label("换源", systemImage: "arrow.left.arrow.right")
                    }
                    Button {
                        cacheAll()
                    } label: {
                        Label("缓存全本", systemImage: "arrow.down.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(loading)
            }
        }
        .onAppear {
            load(force: false)
            cachedCount = CacheService.cachedCount(book)
        }
        .sheet(isPresented: $showSwitch) {
            SwitchSourceView(book: book) { updated in
                book = updated
                chapters = Storage.loadChapters(updated.bookUrl)
                cachedCount = 0
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            BookCover(url: book.coverUrl, title: book.name, width: 96, height: 132)
            VStack(alignment: .leading, spacing: 6) {
                Text(book.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(book.author.isEmpty ? "佚名" : book.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    if let kind = book.kind, !kind.isEmpty {
                        TagChip(text: kind)
                    }
                    if let words = book.wordCount, !words.isEmpty {
                        TagChip(text: words)
                    }
                }
                if let latest = book.latestChapterTitle, !latest.isEmpty {
                    Text("最新：\(latest)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Text(book.originName)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 按钮

    private var actionRow: some View {
        HStack(spacing: 10) {
            if model.isOnShelf(book.bookUrl) {
                NavigationLink(value: Route.reader(book, book.durChapterIndex)) {
                    Text(chapters.isEmpty ? "开始阅读" : "继续阅读")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Button {
                    model.removeBook(book)
                } label: {
                    Text("移出")
                        .font(.subheadline)
                        .frame(width: 70)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            } else {
                Button {
                    let added = model.addToShelf(searchBookValue ?? searchBookFromBook())
                    book = added
                } label: {
                    Label("加入书架", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                NavigationLink(value: Route.reader(book, 0)) {
                    Text("试读")
                        .font(.subheadline)
                        .frame(width: 70)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    // MARK: - 目录

    private var chapterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("目录")
                    .font(.headline)
                if !chapters.isEmpty {
                    Text("共 \(chapters.count) 章")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if loadingToc {
                    ProgressView().scaleEffect(0.7)
                }
            }
            if chapters.isEmpty {
                if loading {
                    LoadingRow(text: "正在获取目录…")
                } else {
                    Text("暂无目录，请点右上角刷新")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else {
                let shown = showAllChapters ? chapters : Array(chapters.prefix(30))
                VStack(spacing: 0) {
                    ForEach(shown) { chapter in
                        NavigationLink(value: Route.reader(book, chapter.index)) {
                            HStack {
                                Text(chapter.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .foregroundColor(.primary)
                                Spacer()
                                if chapter.isVip {
                                    Text("VIP").font(.caption2).foregroundColor(.orange)
                                }
                            }
                            .padding(.vertical, 9)
                            Divider()
                        }
                        .buttonStyle(.plain)
                    }
                }
                if chapters.count > 30 {
                    Button {
                        showAllChapters.toggle()
                    } label: {
                        Text(showAllChapters ? "收起" : "查看全部 \(chapters.count) 章")
                            .font(.footnote)
                    }
                }
            }
        }
    }

    private func section<Content: View>(title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    // MARK: - 数据

    private func searchBookFromBook() -> SearchBook {
        var item = SearchBook()
        item.bookUrl = book.bookUrl
        item.origin = book.origin
        item.originName = book.originName
        item.originOrder = book.originOrder
        item.name = book.name
        item.author = book.author
        item.kind = book.kind
        item.intro = book.intro
        item.coverUrl = book.coverUrl
        item.latestChapterTitle = book.latestChapterTitle
        item.wordCount = book.wordCount
        item.variable = book.variable
        item.type = book.type
        return item
    }

    private func cacheAll() {
        guard let source = model.source(for: book) else {
            error = "找不到这本书对应的书源"
            return
        }
        guard !caching, !chapters.isEmpty else { return }
        caching = true
        cacheProgress = 0
        let list = chapters
        Task { @MainActor in
            let done = await CacheService.downloadAll(book: book, source: source, chapters: list) { finished, total in
                Task { @MainActor in
                    cacheProgress = Double(finished) / Double(max(total, 1))
                }
            }
            caching = false
            cachedCount = done
            if done < list.count {
                error = "已缓存 \(done)/\(list.count) 章，其余失败（可在阅读时重试）"
            }
        }
    }

    private func load(force: Bool) {
        guard !loading else { return }
        guard let source = model.source(for: book) else {
            error = "找不到这本书对应的书源，可能已被删除"
            return
        }
        loading = true
        if force { chapters = [] }
        Task { @MainActor in
            defer { loading = false }
            do {
                if book.name.isEmpty || book.intro == nil || book.tocUrl.isEmpty {
                    book = try await BookService.loadInfo(book: book, source: source)
                }
                loadingToc = true
                chapters = try await BookService.loadToc(book: book, source: source, force: force)
                loadingToc = false
                if model.isOnShelf(book.bookUrl) {
                    var updated = book
                    updated.totalChapterNum = chapters.count
                    updated.latestChapterTitle = chapters.last?.title ?? updated.latestChapterTitle
                    updated.lastCheckTime = Int64(Date().timeIntervalSince1970 * 1000)
                    model.updateBook(updated)
                    book = updated
                }
                error = nil
            } catch {
                loadingToc = false
                self.error = error.localizedDescription
            }
        }
    }
}
