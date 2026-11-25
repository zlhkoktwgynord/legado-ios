import Foundation

/// 本地 TXT 书籍的导入与读取
enum LocalBookImporter {

    struct Imported {
        var book: Book
        var chapters: [BookChapter]
    }

    enum ImportError: LocalizedError {
        case empty
        case unsupported

        var errorDescription: String? {
            switch self {
            case .empty: return "文件内容为空"
            case .unsupported: return "无法识别文件编码"
            }
        }
    }

    // MARK: - 导入

    static func load(data: Data, fileName: String) throws -> Imported {
        guard !data.isEmpty else { throw ImportError.empty }
        let text = DataDecoder.decode(data: data)
        guard !text.isEmpty else { throw ImportError.unsupported }

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let id = String(MD5.hash(normalized).prefix(12))
        Storage.saveBookText(normalized, id: id)

        var book = Book()
        book.bookUrl = Book.localUrl(id: id)
        book.name = cleanTitle(fileName)
        book.author = "本地"
        book.origin = "local"
        book.originName = "本地"
        book.intro = "本地 TXT 文件"
        book.type = 0
        book.canUpdate = false

        let parsed = splitChapters(normalized)
        var chapters: [BookChapter] = []
        for (index, item) in parsed.enumerated() {
            var chapter = BookChapter()
            chapter.bookUrl = book.bookUrl
            chapter.url = book.bookUrl
            chapter.title = item.title
            chapter.index = index
            chapter.start = Int64(item.start)
            chapter.end = Int64(item.end)
            chapter.baseUrl = ""
            chapters.append(chapter)
        }
        book.totalChapterNum = chapters.count
        book.latestChapterTitle = chapters.last?.title
        return Imported(book: book, chapters: chapters)
    }

    static func content(book: Book, chapter: BookChapter) throws -> String {
        guard let text = Storage.loadBookText(id: Book.localId(from: book.bookUrl)) else {
            throw ImportError.empty
        }
        let ns = text as NSString
        let start = max(0, min(Int(chapter.start ?? 0), ns.length))
        let end = max(start, min(Int(chapter.end ?? Int64(ns.length)), ns.length))
        let raw = ns.substring(with: NSRange(location: start, length: end - start))
        let body = TextCleaner.normalize(raw)
        // 去掉章节标题那一行
        let lines = body.components(separatedBy: "\n")
        if let first = lines.first, first.contains(chapter.title) {
            return lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return body
    }

    // MARK: - 分章

    private static let chapterPattern: NSRegularExpression = {
        let pattern = "^[ \\t\\u3000]*(第[0-9零一二三四五六七八九十百千万两]{1,10}[章节回卷集篇部][^\\n]{0,40}" +
            "|序章[^\\n]{0,30}|楔子[^\\n]{0,30}|引子[^\\n]{0,30}|前言[^\\n]{0,30}" +
            "|后记[^\\n]{0,30}|尾声[^\\n]{0,30}|番外[^\\n]{0,30})$"
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }()

    struct ChapterRange {
        var title: String
        var start: Int   // UTF-16 偏移
        var end: Int
    }

    static func splitChapters(_ text: String) -> [ChapterRange] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let matches = chapterPattern.matches(in: text, options: [], range: full)

        if matches.count < 2 {
            return [ChapterRange(title: "正文", start: 0, end: ns.length)]
        }

        var ranges: [ChapterRange] = []
        // 第一个章节标题之前的内容单独成章
        if matches[0].range.location > 50 {
            ranges.append(ChapterRange(title: "前言", start: 0, end: matches[0].range.location))
        }
        for (index, match) in matches.enumerated() {
            let start = match.range.location
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let rawTitle = ns.substring(with: match.range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = rawTitle.isEmpty ? "第 \(index + 1) 章" : rawTitle
            ranges.append(ChapterRange(title: title, start: start, end: end))
        }
        return ranges
    }

    private static func cleanTitle(_ fileName: String) -> String {
        var name = (fileName as NSString).deletingPathExtension
        name = name.replacingOccurrences(of: "[_\\-]+", with: " ", options: .regularExpression)
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "本地书籍" : name
    }
}
