import Foundation

/// 书签
struct Bookmark: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var bookUrl: String = ""
    var bookName: String = ""
    var chapterIndex: Int = 0
    var chapterTitle: String = ""
    var content: String = ""
    var createdAt: Int64 = 0

    init() {}

    init(book: Book, chapter: BookChapter, content: String) {
        self.bookUrl = book.bookUrl
        self.bookName = book.name
        self.chapterIndex = chapter.index
        self.chapterTitle = chapter.title
        self.content = String(content.prefix(120))
        self.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
    }
}

/// 备份 / 恢复：把书源、书架、设置、书签打成一个 JSON 文件
struct BackupPayload: Codable {
    var app: String = "LegadoIOS"
    var version: Int = 1
    var exportedAt: Int64 = 0
    var sources: [BookSource] = []
    var books: [Book] = []
    var bookmarks: [Bookmark] = []
    var replaceRules: [ReplaceRule] = []
    var readerConfig: ReaderConfig = .default
}

enum BackupService {

    static func make(sources: [BookSource],
                     books: [Book],
                     bookmarks: [Bookmark],
                     replaceRules: [ReplaceRule],
                     readerConfig: ReaderConfig) -> BackupPayload {
        var payload = BackupPayload()
        payload.exportedAt = Int64(Date().timeIntervalSince1970 * 1000)
        payload.sources = sources
        payload.books = books
        payload.bookmarks = bookmarks
        payload.replaceRules = replaceRules
        payload.readerConfig = readerConfig
        return payload
    }

    /// 写到临时目录，返回可直接分享的文件地址
    static func write(_ payload: BackupPayload) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let name = "legado-ios-backup-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func read(_ data: Data) throws -> BackupPayload {
        try JSONDecoder().decode(BackupPayload.self, from: data)
    }
}
