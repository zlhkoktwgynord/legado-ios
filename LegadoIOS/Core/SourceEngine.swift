import Foundation

enum EngineError: LocalizedError {
    case noSourceUrl
    case noSearchUrl
    case emptyList(String)
    case emptyContent
    case message(String)

    var errorDescription: String? {
        switch self {
        case .noSourceUrl: return "书源缺少地址"
        case .noSearchUrl: return "书源没有配置搜索地址"
        case .emptyList(let name): return "\(name)为空"
        case .emptyContent: return "正文内容为空"
        case .message(let msg): return msg
        }
    }
}

/// 单个书源的抓取引擎：搜索 / 详情 / 目录 / 正文
final class SourceEngine {
    let source: BookSource

    init(source: BookSource) {
        self.source = source
    }

    // MARK: - 请求

    func fetch(_ ruleUrl: String,
               baseUrl: String = "",
               book: Book? = nil,
               chapter: BookChapter? = nil,
               key: String? = nil,
               page: Int? = nil) async throws -> HTTPResponse {
        let plan = AnalyzeURL.build(ruleUrl: ruleUrl,
                                    source: source,
                                    book: book,
                                    chapter: chapter,
                                    key: key,
                                    page: page,
                                    baseUrl: baseUrl)
        guard !plan.url.isEmpty else { throw EngineError.noSourceUrl }
        if plan.useWebView {
            Log.info("书源要求 webView，暂按普通请求处理：\(plan.url)")
        }
        let request = HTTPRequest(url: plan.url,
                                  method: plan.method,
                                  headers: plan.headers,
                                  body: plan.body,
                                  timeout: 25)
        let response = try await HTTPClient.shared.send(request)
        Log.info("请求成功 \(response.statusCode) \(plan.url)")
        return response
    }

    // MARK: - 搜索

    func search(_ keyword: String, page: Int = 1) async throws -> [SearchBook] {
        guard let searchUrl = source.searchUrl, !searchUrl.isEmpty else {
            throw EngineError.noSearchUrl
        }
        let response = try await fetch(searchUrl,
                                       baseUrl: source.bookSourceUrl,
                                       key: keyword,
                                       page: page)
        return try parseBookList(response, isSearch: true)
    }

    private func parseBookList(_ response: HTTPResponse, isSearch: Bool) throws -> [SearchBook] {
        let baseUrl = response.url.absoluteString
        let rule = source.ruleSearch ?? SearchRule()
        var listRule = rule.bookList ?? ""
        var reverse = false
        if listRule.hasPrefix("-") {
            reverse = true
            listRule.removeFirst()
        } else if listRule.hasPrefix("+") {
            listRule.removeFirst()
        }

        let analyzer = AnalyzeRule(source: source)
        analyzer.baseUrl = baseUrl
        analyzer.redirectUrl = baseUrl
        analyzer.setContent(response.text, baseUrl: baseUrl)

        // 如果搜索地址直接就是详情页
        if let pattern = source.bookUrlPattern, !pattern.isEmpty,
           baseUrl.range(of: pattern, options: .regularExpression) != nil {
            if let parsed = parseBookInfoPage(response.text, url: baseUrl, base: baseUrl) {
                return [parsed.book]
            }
        }

        let elements = analyzer.getElements(listRule)
        if elements.isEmpty {
            // 没有列表时，按详情页解析一次
            if let parsed = parseBookInfoPage(response.text, url: baseUrl, base: baseUrl) {
                return [parsed.book]
            }
            return []
        }

        var books: [SearchBook] = []
        for item in elements {
            guard let book = parseSearchItem(item, rule: rule, baseUrl: baseUrl) else { continue }
            if !books.contains(where: { $0.bookUrl == book.bookUrl && $0.name == book.name }) {
                books.append(book)
            }
        }
        if reverse { books.reverse() }
        Log.info("\(source.bookSourceName) 搜索到 \(books.count) 本")
        return books
    }

    private func parseSearchItem(_ item: Any, rule: SearchRule, baseUrl: String) -> SearchBook? {
        let analyzer = AnalyzeRule(source: source)
        analyzer.baseUrl = baseUrl
        analyzer.redirectUrl = baseUrl
        analyzer.setContent(item)

        let name = TextCleaner.cleanBookName(analyzer.getString(rule.name))
        guard !name.isEmpty else { return nil }

        var book = SearchBook()
        book.origin = source.bookSourceUrl
        book.originName = source.bookSourceName
        book.originOrder = source.customOrder
        book.type = source.bookSourceType
        book.name = name
        book.author = TextCleaner.cleanAuthor(analyzer.getString(rule.author))
        book.kind = analyzer.getStringList(rule.kind)?.joined(separator: ",")
        book.intro = TextCleaner.htmlToPlain(analyzer.getString(rule.intro))
        book.latestChapterTitle = analyzer.getString(rule.lastChapter)
        book.wordCount = TextCleaner.formatWordCount(analyzer.getString(rule.wordCount))

        let cover = analyzer.getString(rule.coverUrl)
        if !cover.isEmpty {
            book.coverUrl = URLTool.absolute(base: baseUrl, cover)
        }
        let bookUrl = analyzer.getString(rule.bookUrl, isUrl: true)
        book.bookUrl = bookUrl.isEmpty ? baseUrl : bookUrl
        return book
    }

    // MARK: - 详情

    func loadBookInfo(_ book: Book) async throws -> Book {
        var result = book
        let url = book.bookUrl.isEmpty ? book.tocUrl : book.bookUrl
        guard !url.isEmpty else { throw EngineError.noSourceUrl }
        let response = try await fetch(url, baseUrl: book.bookUrl)
        let baseUrl = response.url.absoluteString
        if let parsed = parseBookInfoPage(response.text, url: book.bookUrl, base: baseUrl) {
            let info = parsed.book
            if !info.name.isEmpty { result.name = info.name }
            if !info.author.isEmpty { result.author = info.author }
            if let kind = info.kind, !kind.isEmpty { result.kind = kind }
            if let intro = info.intro, !intro.isEmpty { result.intro = intro }
            if let cover = info.coverUrl, !cover.isEmpty { result.coverUrl = cover }
            if let latest = info.latestChapterTitle, !latest.isEmpty {
                result.latestChapterTitle = latest
            }
            if let words = info.wordCount, !words.isEmpty { result.wordCount = words }
            result.tocUrl = parsed.tocUrl
            result.bookUrl = book.bookUrl
        }
        return result
    }

    private func parseBookInfoPage(_ html: String, url: String, base: String)
        -> (book: SearchBook, tocUrl: String)? {
        let rule = source.ruleBookInfo ?? BookInfoRule()
        let analyzer = AnalyzeRule(source: source)
        analyzer.isFromBookInfo = true
        analyzer.baseUrl = base
        analyzer.redirectUrl = base
        analyzer.setContent(html, baseUrl: base)

        if let initRule = rule.initRule, !initRule.isEmpty {
            if let first = analyzer.getElements(initRule).first {
                analyzer.setContent(first)
            }
        }

        var book = SearchBook()
        book.origin = source.bookSourceUrl
        book.originName = source.bookSourceName
        book.originOrder = source.customOrder
        book.type = source.bookSourceType
        book.bookUrl = url.isEmpty ? base : url

        let name = TextCleaner.cleanBookName(analyzer.getString(rule.name))
        book.name = name
        book.author = TextCleaner.cleanAuthor(analyzer.getString(rule.author))
        book.kind = analyzer.getStringList(rule.kind)?.joined(separator: ",")
        book.intro = TextCleaner.htmlToPlain(analyzer.getString(rule.intro))
        book.latestChapterTitle = analyzer.getString(rule.lastChapter)
        book.wordCount = TextCleaner.formatWordCount(analyzer.getString(rule.wordCount))
        let cover = analyzer.getString(rule.coverUrl)
        if !cover.isEmpty { book.coverUrl = URLTool.absolute(base: base, cover) }

        // 目录地址
        let tocUrl = analyzer.getString(rule.tocUrl, isUrl: true)
        return (book, tocUrl.isEmpty ? base : tocUrl)
    }

    // MARK: - 目录

    func loadToc(_ book: Book) async throws -> [BookChapter] {
        let tocRule = source.ruleToc ?? TocRule()
        let startUrl = book.tocUrl.isEmpty ? book.bookUrl : book.tocUrl

        var listRule = tocRule.chapterList ?? ""
        var reverse = false
        if listRule.hasPrefix("-") {
            reverse = true
            listRule.removeFirst()
        } else if listRule.hasPrefix("+") {
            listRule.removeFirst()
        }

        var chapters: [BookChapter] = []
        var nextUrl = startUrl
        var visited = Set<String>()
        var pageCount = 0

        while !nextUrl.isEmpty && !visited.contains(nextUrl) && pageCount < 30 {
            visited.insert(nextUrl)
            pageCount += 1
            let response = try await fetch(nextUrl,
                                           baseUrl: book.bookUrl.isEmpty ? nextUrl : book.bookUrl,
                                           book: book)
            let baseUrl = response.url.absoluteString
            let analyzer = AnalyzeRule(source: source, book: book)
            analyzer.baseUrl = baseUrl
            analyzer.redirectUrl = baseUrl
            analyzer.setContent(response.text, baseUrl: baseUrl)

            let elements = analyzer.getElements(listRule)
            for (offset, item) in elements.enumerated() {
                let chapterAnalyzer = AnalyzeRule(source: source, book: book)
                chapterAnalyzer.baseUrl = baseUrl
                chapterAnalyzer.redirectUrl = baseUrl
                chapterAnalyzer.setContent(item)

                let title = chapterAnalyzer.getString(tocRule.chapterName)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }

                var chapter = BookChapter()
                chapter.bookUrl = book.bookUrl
                chapter.baseUrl = baseUrl
                chapter.title = title
                chapter.index = chapters.count + offset
                let url = chapterAnalyzer.getString(tocRule.chapterUrl, isUrl: true)
                chapter.url = url.isEmpty ? baseUrl : url
                chapter.tag = chapterAnalyzer.getString(tocRule.updateTime)
                if chapterAnalyzer.getString(tocRule.isVip).lowercased() == "true" {
                    chapter.isVip = true
                }
                chapters.append(chapter)
            }

            if let nextRule = tocRule.nextTocUrl, !nextRule.isEmpty {
                let nextList = analyzer.getStringList(nextRule, isUrl: true) ?? []
                nextUrl = nextList.first(where: { $0 != baseUrl }) ?? ""
            } else {
                nextUrl = ""
            }
            Log.info("目录第 \(pageCount) 页，累计 \(chapters.count) 章")
        }

        if chapters.isEmpty { throw EngineError.emptyList("目录") }
        if reverse { chapters.reverse() }

        // 去重
        var seen = Set<String>()
        var unique: [BookChapter] = []
        for chapter in chapters {
            let key = chapter.title + "|" + chapter.url
            if seen.contains(key) { continue }
            seen.insert(key)
            unique.append(chapter)
        }
        for (index, _) in unique.enumerated() { unique[index].index = index }
        return unique
    }

    private func nextChapterUrl(book: Book, chapter: BookChapter) -> String? {
        let chapters = Storage.loadChapters(book.bookUrl)
        return chapters.first { $0.index == chapter.index + 1 }?.url
    }

    // MARK: - 正文

    func loadContent(_ book: Book, chapter: BookChapter) async throws -> String {
        let rule = source.ruleContent ?? ContentRule()
        let baseUrl = chapter.baseUrl.isEmpty ? book.bookUrl : chapter.baseUrl
        var nextUrl = chapter.url.isEmpty ? baseUrl : chapter.url
        var visited = Set<String>()
        var pieces: [String] = []
        var pages = 0

        while !nextUrl.isEmpty && !visited.contains(nextUrl) && pages < 20 {
            visited.insert(nextUrl)
            pages += 1
            let response = try await fetch(nextUrl, baseUrl: baseUrl, book: book, chapter: chapter)
            let effectiveBase = response.url.absoluteString
            let analyzer = AnalyzeRule(source: source, book: book, chapter: chapter)
            analyzer.baseUrl = effectiveBase
            analyzer.redirectUrl = effectiveBase
            analyzer.nextChapterUrl = nextChapterUrl(book: book, chapter: chapter)
            analyzer.setContent(response.text, baseUrl: effectiveBase)

            let raw = analyzer.getString(rule.content)
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if pages == 1 { throw EngineError.emptyContent }
            } else {
                pieces.append(raw)
            }

            if let nextRule = rule.nextContentUrl, !nextRule.isEmpty {
                let list = analyzer.getStringList(nextRule, isUrl: true) ?? []
                nextUrl = list.first(where: { $0 != effectiveBase }) ?? ""
            } else {
                nextUrl = ""
            }
        }

        var content = pieces.joined(separator: "\n")
        if let replace = rule.replaceRegex, !replace.isEmpty {
            let analyzer = AnalyzeRule(source: source, book: book, chapter: chapter)
            analyzer.baseUrl = chapter.baseUrl
            content = analyzer.getString(replace, content)
        }
        let text = content.contains("<") ? TextCleaner.htmlToPlain(content) : TextCleaner.normalize(content)
        if text.isEmpty { throw EngineError.emptyContent }
        Log.info("正文 \(chapter.title) 共 \(text.count) 字")
        return text
    }
}
