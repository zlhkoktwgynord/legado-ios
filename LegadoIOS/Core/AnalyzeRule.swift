import Foundation

/// 书源规则解析核心，对应 Legado 的 AnalyzeRule + AnalyzeByJSoup / JsonPath / Regex / JS
final class AnalyzeRule {

    enum Mode {
        case css, json, xpath, js
    }

    // MARK: - 上下文

    var source: BookSource?
    var book: Book?
    var chapter: BookChapter?
    var baseUrl: String = ""
    var redirectUrl: String = ""
    var nextChapterUrl: String?
    var isFromBookInfo: Bool = false
    /// 额外注入给 JS 的变量（如 key、page）
    var jsExtraBindings: [String: Any] = [:]

    private(set) var content: Any?
    private var documentCache: Document?
    private var documentDirty = true
    private var jsonCache: Any?
    private var jsonParsed = false
    private var variableMap: [String: String] = [:]

    init(source: BookSource? = nil, book: Book? = nil, chapter: BookChapter? = nil) {
        self.source = source
        self.book = book
        self.chapter = chapter
        if let v = book?.variable { variableMap = Self.parseVariables(v) }
        if let v = chapter?.variable { variableMap.merge(Self.parseVariables(v)) { _, b in b } }
    }

    @discardableResult
    func setContent(_ content: Any?, baseUrl: String? = nil) -> AnalyzeRule {
        self.content = content
        if let baseUrl = baseUrl, !baseUrl.isEmpty { self.baseUrl = baseUrl }
        documentDirty = true
        documentCache = nil
        jsonParsed = false
        jsonCache = nil
        return self
    }

    var sourceKey: String { source?.bookSourceUrl ?? "" }

    // MARK: - 对外接口

    func getString(_ rule: String?, _ mContent: Any? = nil, isUrl: Bool = false) -> String {
        guard let rule = rule, !rule.trimmingCharacters(in: .whitespaces).isEmpty else {
            return isUrl ? baseUrl : ""
        }
        var result: Any? = mContent ?? content
        for part in splitSourceRule(rule) {
            applyPut(part)
            guard let current = result else { break }
            let resolved = part.resolved(analyze: self, result: current)
            if !resolved.rule.isEmpty {
                result = evaluateStringValue(resolved.rule, mode: part.mode, content: current)
            }
            if let pattern = resolved.pattern, !pattern.isEmpty {
                result = applyRegex(pattern,
                                    replacement: resolved.replacement,
                                    first: resolved.replaceFirst,
                                    to: stringValue(result))
            }
        }
        var text = stringValue(result)
        if text.contains("&") { text = TextCleaner.decodeEntities(text) }
        if isUrl {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return baseUrl }
            let base = redirectUrl.isEmpty ? baseUrl : redirectUrl
            return URLTool.absolute(base: base, trimmed)
        }
        return text
    }

    func getStringList(_ rule: String?, isUrl: Bool = false) -> [String]? {
        guard let rule = rule, !rule.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var result: [String] = []
        var current: Any? = content
        for part in splitSourceRule(rule) {
            applyPut(part)
            guard let value = current else { break }
            let resolved = part.resolved(analyze: self, result: value)
            if !resolved.rule.isEmpty {
                result = evaluateStrings(resolved.rule, mode: part.mode, content: value)
            }
            if let pattern = resolved.pattern, !pattern.isEmpty {
                result = result.map {
                    applyRegex(pattern, replacement: resolved.replacement,
                               first: resolved.replaceFirst, to: $0)
                }
            }
            current = result
        }
        if isUrl {
            let base = redirectUrl.isEmpty ? baseUrl : redirectUrl
            var urls: [String] = []
            for item in result {
                let url = URLTool.absolute(base: base, item)
                if !url.isEmpty && !urls.contains(url) { urls.append(url) }
            }
            return urls
        }
        return result
    }

    /// 取元素列表，用于书籍列表 / 目录列表
    func getElements(_ rule: String?, _ mContent: Any? = nil) -> [Any] {
        guard let rule = rule, !rule.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var current: Any? = mContent ?? content
        var output: [Any] = []
        for part in splitSourceRule(rule) {
            applyPut(part)
            guard let value = current else { break }
            let resolved = part.resolved(analyze: self, result: value)
            guard !resolved.rule.isEmpty else { continue }
            output = evaluateElements(resolved.rule, mode: part.mode, content: value)
            current = output
        }
        return output
    }

    // MARK: - 求值

    private func evaluateStringValue(_ rule: String, mode: Mode, content: Any) -> Any? {
        switch mode {
        case .css:
            let list = htmlStrings(rule, content: content)
            return list.isEmpty ? nil : list
        case .xpath:
            return evaluateXPath(rule, content: content) { selector, lastRule in
                htmlStrings(lastRule == "text" ? selector : "\(selector)@\(lastRule)",
                            content: content)
            }
        case .json:
            let values = JSONPath.query(rule, root: jsonRoot(content))
            return values.isEmpty ? nil : values
        case .js:
            return evalJS(rule, result: content)
        }
    }

    private func evaluateStrings(_ rule: String, mode: Mode, content: Any) -> [String] {
        switch mode {
        case .css:
            return htmlStrings(rule, content: content)
        case .xpath:
            return evaluateXPath(rule, content: content) { selector, lastRule in
                htmlStrings(lastRule == "text" ? selector : "\(selector)@\(lastRule)",
                            content: content)
            }
        case .json:
            return JSONPath.query(rule, root: jsonRoot(content)).flatMap(flattenStrings)
        case .js:
            let value = evalJS(rule, result: content)
            return flattenStrings(value)
        }
    }

    private func evaluateElements(_ rule: String, mode: Mode, content: Any) -> [Any] {
        switch mode {
        case .css:
            return htmlElements(rule, content: content).map { $0 as Any }
        case .xpath:
            return evaluateXPath(rule, content: content) { selector, _ in
                htmlElements(selector, content: content).map { (try? $0.outerHtml()) ?? "" }
            }.map { $0 as Any }
        case .json:
            return JSONPath.query(rule, root: jsonRoot(content))
        case .js:
            let value = evalJS(rule, result: content)
            if let array = value as? [Any] { return array }
            if let value = value { return [value] }
            return []
        }
    }

    private func evaluateXPath(_ rule: String, content: Any,
                               extract: (String, String) -> [String]) -> [String] {
        do {
            let converted = try XPathBridge.convert(rule)
            return extract(converted.selector, converted.lastRule)
        } catch {
            Log.warn("XPath 规则无法转换：\(rule)")
            return []
        }
    }

    // MARK: - HTML

    private var document: Document? {
        if !documentDirty, let doc = documentCache { return doc }
        documentDirty = false
        guard let html = content as? String else {
            documentCache = nil
            return nil
        }
        documentCache = HTMLAnalyze.parse(html, baseUrl: baseUrl)
        return documentCache
    }

    private func htmlStrings(_ rule: String, content: Any) -> [String] {
        if let element = content as? Element {
            return HTMLAnalyze.strings(rule, in: element)
        }
        if let list = content as? [Any] {
            return list.flatMap { htmlStrings(rule, content: $0) }
        }
        if let text = content as? String, let doc = document {
            _ = text
            return HTMLAnalyze.strings(rule, in: doc)
        }
        return []
    }

    private func htmlElements(_ rule: String, content: Any) -> [Element] {
        if let element = content as? Element {
            return HTMLAnalyze.elements(rule, in: element)
        }
        if let list = content as? [Any] {
            return list.flatMap { htmlElements(rule, content: $0) }
        }
        if content is String, let doc = document {
            return HTMLAnalyze.elements(rule, in: doc)
        }
        return []
    }

    // MARK: - JSON

    private func jsonRoot(_ content: Any) -> Any {
        if let text = content as? String {
            if !jsonParsed {
                jsonParsed = true
                jsonCache = JSONTool.object(from: text)
            }
            return jsonCache ?? [:]
        }
        return content
    }

    func isJSONContent() -> Bool {
        guard let text = content as? String else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return false }
        return JSONTool.object(from: trimmed) != nil
    }

    // MARK: - JS

    func evalJS(_ js: String, result: Any? = nil) -> Any? {
        self.resultForJS = result
        defer { self.resultForJS = nil }
        let context = JSEngine.Context(rule: self, bindings: jsExtraBindings)
        return JSEngine.shared.evaluate(js, context: context)
    }

    fileprivate var resultForJS: Any?

    var resultObject: Any {
        Self.jsValue(resultForJS)
    }

    var jsBookObject: [String: Any] {
        guard let book = book else { return [:] }
        return [
            "name": book.name,
            "author": book.author,
            "bookUrl": book.bookUrl,
            "tocUrl": book.tocUrl,
            "origin": book.origin,
            "originName": book.originName,
            "kind": book.kind ?? "",
            "intro": book.intro ?? "",
            "coverUrl": book.coverUrl ?? "",
            "latestChapterTitle": book.latestChapterTitle ?? "",
            "durChapterIndex": book.durChapterIndex,
            "totalChapterNum": book.totalChapterNum,
            "variable": book.variable ?? ""
        ]
    }

    var jsSourceObject: [String: Any] {
        guard let source = source else { return [:] }
        return [
            "bookSourceName": source.bookSourceName,
            "bookSourceUrl": source.bookSourceUrl,
            "bookSourceGroup": source.bookSourceGroup ?? "",
            "bookSourceType": source.bookSourceType,
            "header": source.header ?? "",
            "searchUrl": source.searchUrl ?? ""
        ]
    }

    var chapterObject: [String: Any] {
        guard let chapter = chapter else { return [:] }
        return [
            "title": chapter.title,
            "url": chapter.url,
            "index": chapter.index,
            "baseUrl": chapter.baseUrl,
            "bookUrl": chapter.bookUrl
        ]
    }

    var allVariables: [String: String] { variableMap }

    static func jsValue(_ value: Any?) -> Any {
        guard let value = value else { return NSNull() }
        switch value {
        case let s as String: return s
        case let n as Int: return n
        case let d as Double: return d
        case let b as Bool: return b
        case let e as Element: return (try? e.outerHtml()) ?? ""
        case let arr as [Any]:
            return arr.map { jsValue($0) }
        case let dict as [String: Any]:
            var out: [String: Any] = [:]
            for (k, v) in dict { out[k] = jsValue(v) }
            return out
        default:
            return "\(value)"
        }
    }

    // MARK: - 变量

    func variable(_ key: String) -> String {
        if key == "bookName" { return book?.name ?? "" }
        if key == "title" { return chapter?.title ?? "" }
        return variableMap[key] ?? ""
    }

    func setVariable(_ key: String, _ value: String) {
        variableMap[key] = value
    }

    static func parseVariables(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var out: [String: String] = [:]
        for (k, v) in dict {
            if let s = v as? String { out[k] = s } else { out[k] = "\(v)" }
        }
        return out
    }

    // MARK: - 同步请求（供 JS 使用）

    func fetchSync(_ url: String) -> String {
        fetchSyncData(url).map { DataDecoder.decode(data: $0) } ?? ""
    }

    func fetchSyncData(_ url: String) -> Data? {
        var headers: [String: String] = [:]
        if let source = source {
            headers = URLTool.headers(fromJSON: source.header)
        }
        if headers["Referer"] == nil, !baseUrl.isEmpty {
            headers["Referer"] = baseUrl
        }
        let request = HTTPRequest(url: URLTool.encode(url), headers: headers, timeout: 20)
        var data: Data?
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached { [request] in
            defer { semaphore.signal() }
            data = try? await HTTPClient.shared.send(request).data
        }
        if semaphore.wait(timeout: .now() + 25) == .timedOut { return nil }
        return data
    }

    // MARK: - 规则切分与执行

    private static let jsPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "<js>([\\s\\S]*?)</js>|@js:([\\s\\S]*)",
                                 options: [.caseInsensitive])
    }()

    func splitSourceRule(_ ruleStr: String) -> [SourceRule] {
        guard !ruleStr.isEmpty else { return [] }
        var parts: [SourceRule] = []
        let ns = ruleStr as NSString
        let matches = Self.jsPattern.matches(in: ruleStr, options: [],
                                             range: NSRange(location: 0, length: ns.length))
        var start = 0
        for match in matches {
            if match.range.location > start {
                let text = ns.substring(with: NSRange(location: start,
                                                      length: match.range.location - start))
                    .trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { parts.append(SourceRule(text, mode: .css)) }
            }
            let group2 = match.range(at: 2)
            let js: String
            if group2.location != NSNotFound {
                js = ns.substring(with: group2)
            } else {
                js = ns.substring(with: match.range(at: 1))
            }
            parts.append(SourceRule(js, mode: .js))
            start = match.range.location + match.range.length
        }
        if start < ns.length {
            let text = ns.substring(from: start).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { parts.append(SourceRule(text, mode: .css)) }
        }
        if parts.isEmpty { parts.append(SourceRule(ruleStr, mode: .css)) }
        return parts
    }

    private func applyPut(_ rule: SourceRule) {
        for (key, value) in rule.putMap {
            setVariable(key, getString(value))
        }
    }

    private func stringValue(_ value: Any?) -> String {
        guard let value = value else { return "" }
        switch value {
        case let s as String: return s
        case let e as Element: return (try? e.outerHtml()) ?? ""
        case let arr as [Any]:
            if arr.count == 1 { return stringValue(arr[0]) }
            return arr.map { stringValue($0) }.joined(separator: "\n")
        case let d as [String: Any]: return JSONTool.string(from: d)
        case let n as NSNumber: return n.stringValue
        default: return "\(value)"
        }
    }

    private func flattenStrings(_ value: Any?) -> [String] {
        guard let value = value else { return [] }
        if let arr = value as? [Any] { return arr.flatMap(flattenStrings) }
        if let s = value as? String { return s.split(separator: "\n").map(String.init) }
        return ["\(value)"]
    }

    private func applyRegex(_ pattern: String, replacement: String,
                            first: Bool, to input: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return input
        }
        let range = NSRange(input.startIndex..., in: input)
        if first {
            guard let match = regex.firstMatch(in: input, options: [], range: range) else {
                return ""
            }
            let matched = (input as NSString).substring(with: match.range)
            return regex.stringByReplacingMatches(
                in: matched,
                options: [],
                range: NSRange(location: 0, length: (matched as NSString).length),
                withTemplate: replacement)
        }
        return regex.stringByReplacingMatches(in: input, options: [], range: range,
                                              withTemplate: replacement)
    }
}

// MARK: - 单段规则

struct SourceRule {
    struct Resolved {
        var rule: String
        var pattern: String?
        var replacement: String = ""
        var replaceFirst: Bool = false
    }

    var mode: AnalyzeRule.Mode
    var raw: String
    var putMap: [String: String] = [:]

    init(_ raw: String, mode: AnalyzeRule.Mode) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var m = mode
        // 解析 @put:{...}
        if let putRegex = try? NSRegularExpression(
            pattern: "@put:(\\{[^}]+?\\})", options: [.caseInsensitive]) {
            let ns = text as NSString
            let matches = putRegex.matches(in: text, options: [],
                                           range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                let json = ns.substring(with: match.range(at: 1))
                if let dict = JSONTool.object(from: json) as? [String: Any] {
                    for (k, v) in dict {
                        putMap[k] = v as? String ?? "\(v)"
                    }
                }
                if let range = Range(match.range, in: text) {
                    text.removeSubrange(range)
                }
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if m != .js {
            let lower = text.lowercased()
            if lower.hasPrefix("@css:") {
                text = String(text.dropFirst(5))
                m = .css
            } else if text.hasPrefix("@@") {
                text = String(text.dropFirst(2))
                m = .css
            } else if lower.hasPrefix("@xpath:") {
                text = String(text.dropFirst(7))
                m = .xpath
            } else if lower.hasPrefix("@json:") {
                text = String(text.dropFirst(6))
                m = .json
            } else if text.hasPrefix("$.") || text.hasPrefix("$[") {
                m = .json
            } else if text.hasPrefix("/") && !text.hasPrefix("//") == false {
                m = .xpath
            } else if text.hasPrefix("/") {
                m = .xpath
            }
        }
        self.mode = m
        self.raw = text.trimmingCharacters(in: .whitespaces)
    }

    func resolved(analyze: AnalyzeRule, result: Any?) -> Resolved {
        var text = raw
        // {{ js }}
        let inner = RuleSplitter.innerJS(text)
        for item in inner.reversed() {
            let value = analyze.evalJS(item.js, result: result)
            text.replaceSubrange(item.range, with: AnalyzeRule.jsString(value))
        }
        // @get:{key}
        if text.contains("@get:") {
            let regex = try? NSRegularExpression(pattern: "@get:\\{([^}]+?)\\}",
                                                 options: [.caseInsensitive])
            if let regex = regex {
                let ns = text as NSString
                let matches = regex.matches(in: text, options: [],
                                            range: NSRange(location: 0, length: ns.length))
                for match in matches.reversed() {
                    let key = ns.substring(with: match.range(at: 1))
                    let value = analyze.variable(key)
                    if let range = Range(match.range, in: text) {
                        text.replaceSubrange(range, with: value)
                    }
                }
            }
        }
        // $1 $2 这类占位符：只有结果是列表时才替换
        if let list = result as? [Any], text.contains("$") {
            let regex = try? NSRegularExpression(pattern: "\\$(\\d{1,2})", options: [])
            if let regex = regex {
                let ns = text as NSString
                let matches = regex.matches(in: text, options: [],
                                            range: NSRange(location: 0, length: ns.length))
                for match in matches.reversed() {
                    let index = Int(ns.substring(with: match.range(at: 1))) ?? -1
                    if index >= 0 && index < list.count {
                        let value = AnalyzeRule.jsString(list[index])
                        if let range = Range(match.range, in: text) {
                            text.replaceSubrange(range, with: value)
                        }
                    }
                }
            }
        }
        let segments = text.components(separatedBy: "##")
        return Resolved(
            rule: segments.indices.contains(0) ? segments[0].trimmingCharacters(in: .whitespaces) : "",
            pattern: segments.count > 1 ? segments[1] : nil,
            replacement: segments.count > 2 ? segments[2] : "",
            replaceFirst: segments.count > 3
        )
    }
}

extension AnalyzeRule {
    static func jsString(_ value: Any?) -> String {
        guard let value = value else { return "" }
        if let s = value as? String { return s }
        if let d = value as? Double {
            if d.truncatingRemainder(dividingBy: 1) == 0 { return String(format: "%.0f", d) }
            return "\(d)"
        }
        return "\(value)"
    }
}
