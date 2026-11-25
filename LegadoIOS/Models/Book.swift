import Foundation

// MARK: - 书籍

struct Book: Codable, Identifiable, Hashable {
    var bookUrl: String = ""
    var tocUrl: String = ""
    /// 书源 key（bookSourceUrl）
    var origin: String = ""
    var originName: String = ""
    var name: String = ""
    var author: String = ""
    var kind: String?
    var customTag: String?
    var coverUrl: String?
    var customCoverUrl: String?
    var intro: String?
    var customIntro: String?
    var charset: String?
    /// 0 文本 1 音频 2 图片 3 文件 4 视频
    var type: Int = 0
    var group: Int64 = 0
    var latestChapterTitle: String?
    var latestChapterTime: Int64 = 0
    var lastCheckTime: Int64 = 0
    var lastCheckCount: Int32 = 0
    var totalChapterNum: Int = 0
    var durChapterTitle: String?
    var durChapterIndex: Int = 0
    var durChapterPos: Int = 0
    var durChapterTime: Int64 = 0
    var wordCount: String?
    var canUpdate: Bool = true
    var order: Int = 0
    var originOrder: Int = 0
    var variable: String?

    var id: String { bookUrl }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookUrl = c.value(.bookUrl, "")
        tocUrl = c.value(.tocUrl, "")
        origin = c.value(.origin, "")
        originName = c.value(.originName, "")
        name = c.value(.name, "")
        author = c.value(.author, "")
        kind = c.value(.kind, nil)
        customTag = c.value(.customTag, nil)
        coverUrl = c.value(.coverUrl, nil)
        customCoverUrl = c.value(.customCoverUrl, nil)
        intro = c.value(.intro, nil)
        customIntro = c.value(.customIntro, nil)
        charset = c.value(.charset, nil)
        type = c.value(.type, 0)
        group = c.value(.group, 0)
        latestChapterTitle = c.value(.latestChapterTitle, nil)
        latestChapterTime = c.value(.latestChapterTime, 0)
        lastCheckTime = c.value(.lastCheckTime, 0)
        lastCheckCount = c.value(.lastCheckCount, 0)
        totalChapterNum = c.value(.totalChapterNum, 0)
        durChapterTitle = c.value(.durChapterTitle, nil)
        durChapterIndex = c.value(.durChapterIndex, 0)
        durChapterPos = c.value(.durChapterPos, 0)
        durChapterTime = c.value(.durChapterTime, 0)
        wordCount = c.value(.wordCount, nil)
        canUpdate = c.value(.canUpdate, true)
        order = c.value(.order, 0)
        originOrder = c.value(.originOrder, 0)
        variable = c.value(.variable, nil)
    }

    /// 本地书籍用 local://<id> 作为 bookUrl
    var isLocal: Bool { bookUrl.hasPrefix("local://") }

    static func localUrl(id: String) -> String { "local://\(id)" }
    static func localId(from bookUrl: String) -> String {
        bookUrl.replacingOccurrences(of: "local://", with: "")
    }

    var displayName: String { name }
    var displayAuthor: String { author.isEmpty ? "佚名" : author }

    func hash(into hasher: inout Hasher) { hasher.combine(bookUrl) }
}

// MARK: - 章节

struct BookChapter: Codable, Identifiable, Hashable {
    var url: String = ""
    var title: String = ""
    var isVolume: Bool = false
    var baseUrl: String = ""
    var bookUrl: String = ""
    var index: Int = 0
    var isVip: Bool = false
    var isPay: Bool = false
    var tag: String?
    var wordCount: String?
    var variable: String?
    /// 本地 TXT 章节在文件中的 UTF-16 偏移
    var start: Int64?
    var end: Int64?

    var id: String { "\(bookUrl)#\(index)#\(url)" }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = c.value(.url, "")
        title = c.value(.title, "")
        isVolume = c.value(.isVolume, false)
        baseUrl = c.value(.baseUrl, "")
        bookUrl = c.value(.bookUrl, "")
        index = c.value(.index, 0)
        isVip = c.value(.isVip, false)
        isPay = c.value(.isPay, false)
        tag = c.value(.tag, nil)
        wordCount = c.value(.wordCount, nil)
        variable = c.value(.variable, nil)
        start = c.value(.start, nil)
        end = c.value(.end, nil)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bookUrl)
        hasher.combine(index)
    }
}

// MARK: - 搜索结果

struct SearchBook: Codable, Identifiable, Hashable {
    var bookUrl: String = ""
    var origin: String = ""
    var originName: String = ""
    var originOrder: Int = 0
    var name: String = ""
    var author: String = ""
    var kind: String?
    var intro: String?
    var coverUrl: String?
    var latestChapterTitle: String?
    var wordCount: String?
    var variable: String?
    var type: Int = 0

    var id: String { "\(origin)|\(bookUrl)|\(name)|\(author)" }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookUrl = c.value(.bookUrl, "")
        origin = c.value(.origin, "")
        originName = c.value(.originName, "")
        originOrder = c.value(.originOrder, 0)
        name = c.value(.name, "")
        author = c.value(.author, "")
        kind = c.value(.kind, nil)
        intro = c.value(.intro, nil)
        coverUrl = c.value(.coverUrl, nil)
        latestChapterTitle = c.value(.latestChapterTitle, nil)
        wordCount = c.value(.wordCount, nil)
        variable = c.value(.variable, nil)
        type = c.value(.type, 0)
    }

    /// 转成书架里的 Book
    func toBook() -> Book {
        var b = Book()
        b.bookUrl = bookUrl
        b.origin = origin
        b.originName = originName
        b.originOrder = originOrder
        b.name = TextCleaner.cleanBookName(name)
        b.author = TextCleaner.cleanAuthor(author)
        b.kind = kind
        b.intro = intro
        b.coverUrl = coverUrl
        b.latestChapterTitle = latestChapterTitle
        b.wordCount = wordCount
        b.variable = variable
        b.type = type
        b.canUpdate = true
        return b
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - 阅读设置

struct ReaderConfig: Codable, Equatable {
    var fontSize: Double = 19
    var lineSpacing: Double = 8
    var paragraphSpacing: Double = 10
    var indent: Bool = true
    var fontFamily: String = ""      // 空 = 系统字体
    var letterSpacing: Double = 0.4
    var theme: ReaderTheme = .paper
    var padding: Double = 20
    var showStatusBar: Bool = false

    static let `default` = ReaderConfig()
}

enum ReaderTheme: String, Codable, CaseIterable, Identifiable {
    case paper, white, sepia, green, dark, black

    var id: String { rawValue }

    var name: String {
        switch self {
        case .paper: return "牛皮纸"
        case .white: return "纯白"
        case .sepia: return "护眼黄"
        case .green: return "豆绿"
        case .dark: return "深灰"
        case .black: return "纯黑"
        }
    }

    var backgroundHex: String {
        switch self {
        case .paper: return "#F5F1E6"
        case .white: return "#FFFFFF"
        case .sepia: return "#F8EFD8"
        case .green: return "#E3F0E0"
        case .dark: return "#1C1C1E"
        case .black: return "#000000"
        }
    }

    var textHex: String {
        switch self {
        case .paper: return "#2B2B2B"
        case .white: return "#222222"
        case .sepia: return "#4A3B22"
        case .green: return "#22331F"
        case .dark: return "#C9C9CE"
        case .black: return "#9A9A9A"
        }
    }

    var isDark: Bool { self == .dark || self == .black }
}
