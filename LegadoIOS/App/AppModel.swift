import Foundation
import Combine

/// 全局状态：书源、书架、阅读设置
@MainActor
final class AppModel: ObservableObject {

    @Published var sources: [BookSource] = []
    @Published var books: [Book] = []
    @Published var readerConfig: ReaderConfig = .default
    @Published var recentKeywords: [String] = []
    @Published var replaceRules: [ReplaceRule] = []
    /// 0 跟随系统 1 浅色 2 深色
    @Published var appearance: Int = UserDefaults.standard.integer(forKey: "appearance")

    private let sourcesFile = "sources.json"
    private let booksFile = "books.json"
    private let recentFile = "recent.json"
    private let replaceFile = "replace.json"

    init() {
        load()
    }

    // MARK: - 读写

    func load() {
        sources = Storage.loadJSON([BookSource].self, sourcesFile) ?? []
        books = Storage.loadJSON([Book].self, booksFile) ?? []
        recentKeywords = Storage.loadJSON([String].self, recentFile) ?? []
        readerConfig = Storage.loadReaderConfig()
        if let saved = Storage.loadJSON([ReplaceRule].self, replaceFile) {
            replaceRules = saved
        } else {
            replaceRules = TextCleaner.defaultReplaceRules()
            Storage.saveJSON(replaceRules, replaceFile)
        }
    }

    func saveSources() {
        Storage.saveJSON(sources, sourcesFile)
    }

    func saveBooks() {
        Storage.saveJSON(books, booksFile)
    }

    func setAppearance(_ value: Int) {
        appearance = value
        UserDefaults.standard.set(value, forKey: "appearance")
    }

    func saveReaderConfig() {
        Storage.saveReaderConfig(readerConfig)
    }

    // MARK: - 书源

    var enabledSources: [BookSource] {
        // 4 = 视频书源，本应用不支持视频
        sources.filter { $0.enabled && $0.bookSourceType != 4 }
    }

    func source(for book: Book) -> BookSource? {
        sources.first { $0.bookSourceUrl == book.origin }
    }

    func source(for searchBook: SearchBook) -> BookSource? {
        sources.first { $0.bookSourceUrl == searchBook.origin }
    }

    @discardableResult
    func importSources(_ text: String) -> (added: Int, total: Int) {
        let parsed = SourceImporter.parse(text)
        guard !parsed.isEmpty else { return (0, sources.count) }
        var added = 0
        for source in parsed {
            if let index = sources.firstIndex(where: { $0.bookSourceUrl == source.bookSourceUrl }) {
                // 同名地址视为更新，保留启用状态
                var updated = source
                updated.enabled = sources[index].enabled
                sources[index] = updated
            } else {
                sources.append(source)
                added += 1
            }
        }
        saveSources()
        return (added, sources.count)
    }

    func setSourceEnabled(_ source: BookSource, enabled: Bool) {
        guard let index = sources.firstIndex(where: { $0.bookSourceUrl == source.bookSourceUrl }) else { return }
        sources[index].enabled = enabled
        saveSources()
    }

    func deleteSource(_ source: BookSource) {
        sources.removeAll { $0.bookSourceUrl == source.bookSourceUrl }
        saveSources()
    }

    func deleteSources(at offsets: IndexSet, from list: [BookSource]) {
        let targets = offsets.map { list[$0].bookSourceUrl }
        sources.removeAll { targets.contains($0.bookSourceUrl) }
        saveSources()
    }

    // MARK: - 替换净化

    func saveReplaceRules() {
        Storage.saveJSON(replaceRules, replaceFile)
    }

    func upsertReplaceRule(_ rule: ReplaceRule) {
        if let index = replaceRules.firstIndex(where: { $0.id == rule.id }) {
            replaceRules[index] = rule
        } else {
            replaceRules.append(rule)
        }
        saveReplaceRules()
    }

    func deleteReplaceRules(at offsets: IndexSet) {
        replaceRules.remove(atOffsets: offsets)
        saveReplaceRules()
    }

    func setReplaceRule(_ rule: ReplaceRule, enabled: Bool) {
        guard let index = replaceRules.firstIndex(where: { $0.id == rule.id }) else { return }
        replaceRules[index].enabled = enabled
        saveReplaceRules()
    }

    // MARK: - 书架

    func addToShelf(_ searchBook: SearchBook) -> Book {
        if let index = books.firstIndex(where: { $0.bookUrl == searchBook.bookUrl }) {
            return books[index]
        }
        var book = searchBook.toBook()
        book.durChapterIndex = 0
        book.durChapterTime = Int64(Date().timeIntervalSince1970 * 1000)
        books.insert(book, at: 0)
        saveBooks()
        return book
    }

    @discardableResult
    func addLocalBook(_ imported: LocalBookImporter.Imported) -> Book {
        var book = imported.book
        Storage.saveChapters(imported.chapters, bookUrl: book.bookUrl)
        if let index = books.firstIndex(where: { $0.bookUrl == book.bookUrl }) {
            books[index].totalChapterNum = imported.chapters.count
            books[index].latestChapterTitle = imported.chapters.last?.title
            saveBooks()
            return books[index]
        }
        book.totalChapterNum = imported.chapters.count
        book.latestChapterTitle = imported.chapters.last?.title
        books.insert(book, at: 0)
        saveBooks()
        return book
    }

    func removeBook(_ book: Book) {
        books.removeAll { $0.bookUrl == book.bookUrl }
        saveBooks()
    }

    func updateBook(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.bookUrl == book.bookUrl }) else { return }
        books[index] = book
        saveBooks()
    }

    func isOnShelf(_ bookUrl: String) -> Bool {
        books.contains { $0.bookUrl == bookUrl }
    }

    /// 最近阅读优先，其次按加入书架的顺序
    var sortedBooks: [Book] {
        books.sorted { lhs, rhs in
            if lhs.durChapterTime != rhs.durChapterTime {
                return lhs.durChapterTime > rhs.durChapterTime
            }
            return lhs.name < rhs.name
        }
    }

    // MARK: - 搜索记录

    func rememberKeyword(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentKeywords.removeAll { $0 == trimmed }
        recentKeywords.insert(trimmed, at: 0)
        if recentKeywords.count > 20 { recentKeywords.removeLast(recentKeywords.count - 20) }
        Storage.saveJSON(recentKeywords, recentFile)
    }

    func clearKeywords() {
        recentKeywords = []
        Storage.saveJSON(recentKeywords, recentFile)
    }

    // MARK: - 搜索

    func search(keyword: String, sources list: [BookSource]? = nil) -> AsyncStream<SourceSearchResult> {
        BookSearchService.search(keyword: keyword, sources: list ?? enabledSources)
    }
}
