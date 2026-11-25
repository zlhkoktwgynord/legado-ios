import Foundation

/// 一个书源的搜索结果
struct SourceSearchResult: Identifiable, Sendable {
    var id: String
    var sourceName: String
    var books: [SearchBook]
    var error: String?
    var cost: Double = 0
}

/// 并发信号量，限制同时请求的书源数量
actor AsyncSemaphore {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ count: Int) {
        available = max(1, count)
    }

    func wait() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

enum BookSearchService {

    /// 多书源并发搜索，按书源逐个返回结果
    static func search(keyword: String,
                       sources: [BookSource],
                       maxConcurrent: Int = 5) -> AsyncStream<SourceSearchResult> {
        AsyncStream { continuation in
            let task = Task {
                let semaphore = AsyncSemaphore(maxConcurrent)
                await withTaskGroup(of: SourceSearchResult.self) { group in
                    for source in sources {
                        group.addTask {
                            await semaphore.wait()
                            defer { Task { await semaphore.signal() } }
                            if Task.isCancelled {
                                return SourceSearchResult(id: source.bookSourceUrl,
                                                          sourceName: source.bookSourceName,
                                                          books: [],
                                                          error: "已取消")
                            }
                            let start = Date()
                            do {
                                let books = try await SourceEngine(source: source).search(keyword)
                                let cost = Date().timeIntervalSince(start)
                                return SourceSearchResult(id: source.bookSourceUrl,
                                                          sourceName: source.bookSourceName,
                                                          books: books,
                                                          cost: cost)
                            } catch {
                                return SourceSearchResult(id: source.bookSourceUrl,
                                                          sourceName: source.bookSourceName,
                                                          books: [],
                                                          error: error.localizedDescription,
                                                          cost: Date().timeIntervalSince(start))
                            }
                        }
                    }
                    for await result in group {
                        continuation.yield(result)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// 详情 / 目录 / 正文的统一入口，带本地缓存
enum BookService {

    static func loadInfo(book: Book, source: BookSource) async throws -> Book {
        try await SourceEngine(source: source).loadBookInfo(book)
    }

    static func loadToc(book: Book, source: BookSource, force: Bool = false) async throws -> [BookChapter] {
        if !force {
            let cached = Storage.loadChapters(book.bookUrl)
            if !cached.isEmpty { return cached }
        }
        let chapters = try await SourceEngine(source: source).loadToc(book)
        Storage.saveChapters(chapters, bookUrl: book.bookUrl)
        return chapters
    }

    /// 本地书籍正文
    static func loadLocalContent(book: Book, chapter: BookChapter) throws -> String {
        if let cached = Storage.loadContent(book.bookUrl, index: chapter.index) {
            return cached
        }
        let text = try LocalBookImporter.content(book: book, chapter: chapter)
        Storage.saveContent(text, bookUrl: book.bookUrl, index: chapter.index)
        return text
    }

    static func loadContent(book: Book, chapter: BookChapter, source: BookSource,
                            force: Bool = false) async throws -> String {
        if !force, let cached = Storage.loadContent(book.bookUrl, index: chapter.index) {
            return cached
        }
        let text = try await SourceEngine(source: source).loadContent(book, chapter: chapter)
        Storage.saveContent(text, bookUrl: book.bookUrl, index: chapter.index)
        return text
    }

    /// 刷新目录：返回新增章节数
    @discardableResult
    static func refreshToc(book: Book, source: BookSource) async throws -> (chapters: [BookChapter], added: Int) {
        let old = Storage.loadChapters(book.bookUrl)
        let chapters = try await SourceEngine(source: source).loadToc(book)
        Storage.saveChapters(chapters, bookUrl: book.bookUrl)
        return (chapters, max(0, chapters.count - old.count))
    }
}
