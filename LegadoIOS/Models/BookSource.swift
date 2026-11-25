import Foundation

// MARK: - 解码辅助

extension KeyedDecodingContainer {
    /// 字段缺失、为 null 或类型不符时使用默认值，保证能解析各种来源的书源 JSON
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }

    func value<T: Decodable>(_ key: Key, _ fallback: T?) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

// MARK: - 书源

/// 与 Legado（阅读 3.0）书源 JSON 字段兼容
struct BookSource: Codable, Identifiable, Hashable {
    var bookSourceUrl: String = ""
    var bookSourceName: String = ""
    var bookSourceGroup: String?
    /// 0 文本 1 音频 2 图片 3 文件 4 视频
    var bookSourceType: Int = 0
    var bookUrlPattern: String?
    var customOrder: Int = 0
    var enabled: Bool = true
    var enabledExplore: Bool = true
    var jsLib: String?
    var enabledCookieJar: Bool? = true
    var concurrentRate: String?
    var header: String?
    var loginUrl: String?
    var loginUi: String?
    var loginCheckJs: String?
    var coverDecodeJs: String?
    var bookSourceComment: String?
    var variableComment: String?
    var lastUpdateTime: Int64 = 0
    var respondTime: Int64 = 180000
    var weight: Int = 0
    var exploreUrl: String?
    var exploreScreen: String?
    var ruleExplore: ExploreRule?
    var searchUrl: String?
    var ruleSearch: SearchRule?
    var ruleBookInfo: BookInfoRule?
    var ruleToc: TocRule?
    var ruleContent: ContentRule?
    var ruleReview: ReviewRule?

    var id: String { bookSourceUrl }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookSourceUrl = c.value(.bookSourceUrl, "")
        bookSourceName = c.value(.bookSourceName, "")
        bookSourceGroup = c.value(.bookSourceGroup, nil)
        bookSourceType = c.value(.bookSourceType, 0)
        bookUrlPattern = c.value(.bookUrlPattern, nil)
        customOrder = c.value(.customOrder, 0)
        enabled = c.value(.enabled, true)
        enabledExplore = c.value(.enabledExplore, true)
        jsLib = c.value(.jsLib, nil)
        enabledCookieJar = c.value(.enabledCookieJar, true)
        concurrentRate = c.value(.concurrentRate, nil)
        header = c.value(.header, nil)
        loginUrl = c.value(.loginUrl, nil)
        loginUi = c.value(.loginUi, nil)
        loginCheckJs = c.value(.loginCheckJs, nil)
        coverDecodeJs = c.value(.coverDecodeJs, nil)
        bookSourceComment = c.value(.bookSourceComment, nil)
        variableComment = c.value(.variableComment, nil)
        lastUpdateTime = c.value(.lastUpdateTime, 0)
        respondTime = c.value(.respondTime, 180000)
        weight = c.value(.weight, 0)
        exploreUrl = c.value(.exploreUrl, nil)
        exploreScreen = c.value(.exploreScreen, nil)
        ruleExplore = c.value(.ruleExplore, nil)
        searchUrl = c.value(.searchUrl, nil)
        ruleSearch = c.value(.ruleSearch, nil)
        ruleBookInfo = c.value(.ruleBookInfo, nil)
        ruleToc = c.value(.ruleToc, nil)
        ruleContent = c.value(.ruleContent, nil)
        ruleReview = c.value(.ruleReview, nil)
    }

    static func == (lhs: BookSource, rhs: BookSource) -> Bool {
        lhs.bookSourceUrl == rhs.bookSourceUrl
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bookSourceUrl)
    }
}

// MARK: - 各阶段规则

struct SearchRule: Codable, Hashable {
    var checkKeyWord: String?
    var bookList: String?
    var name: String?
    var author: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var updateTime: String?
    var bookUrl: String?
    var coverUrl: String?
    var wordCount: String?
}

struct ExploreRule: Codable, Hashable {
    var bookList: String?
    var name: String?
    var author: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var updateTime: String?
    var bookUrl: String?
    var coverUrl: String?
    var wordCount: String?
}

struct BookInfoRule: Codable, Hashable {
    var initRule: String?

    enum CodingKeys: String, CodingKey {
        case initRule = "init"
        case name, author, intro, kind, lastChapter, updateTime, coverUrl, tocUrl, wordCount, canReName, downloadUrls
    }
    var name: String?
    var author: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var updateTime: String?
    var coverUrl: String?
    var tocUrl: String?
    var wordCount: String?
    var canReName: String?
    var downloadUrls: String?
}

struct TocRule: Codable, Hashable {
    var preUpdateJs: String?
    var chapterList: String?
    var chapterName: String?
    var chapterUrl: String?
    var formatJs: String?
    var isVolume: String?
    var isVip: String?
    var isPay: String?
    var updateTime: String?
    var nextTocUrl: String?
}

struct ContentRule: Codable, Hashable {
    var content: String?
    var subContent: String?
    var title: String?
    var nextContentUrl: String?
    var webJs: String?
    var sourceRegex: String?
    var replaceRegex: String?
    var imageStyle: String?
    var imageDecode: String?
    var payAction: String?
    var callBackJs: String?
}

struct ReviewRule: Codable, Hashable {
    var reviewUrl: String?
    var avatarRule: String?
    var contentRule: String?
    var postTimeRule: String?
    var reviewQuoteUrl: String?
    var voteUpUrl: String?
    var voteDownUrl: String?
    var postReviewUrl: String?
    var postQuoteUrl: String?
    var deleteUrl: String?
}
