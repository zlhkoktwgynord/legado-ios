import Foundation

/// 解析书源里的 URL 规则：
/// `https://a.com/search?q={{key}}&page={{page}},{"method":"POST","body":"...","charset":"gbk"}`
enum AnalyzeURL {

    struct Plan {
        var url: String
        var method: String = "GET"
        var headers: [String: String] = [:]
        var body: Data?
        var charset: String?
        var useWebView: Bool = false
    }

    static func build(ruleUrl rawRule: String,
                      source: BookSource?,
                      book: Book? = nil,
                      chapter: BookChapter? = nil,
                      key: String? = nil,
                      page: Int? = nil,
                      baseUrl: String = "") -> Plan {
        let analyzer = AnalyzeRule(source: source, book: book, chapter: chapter)
        analyzer.baseUrl = baseUrl
        var bindings: [String: Any] = [:]
        if let key = key { bindings["key"] = key }
        if let page = page { bindings["page"] = page }
        analyzer.jsExtraBindings = bindings

        var text = evaluateJSSegments(rawRule, analyzer: analyzer)
        text = replaceMustache(text, analyzer: analyzer)

        // 拆分 URL 与参数 JSON
        var urlPart = text
        var option: [String: Any] = [:]
        if let range = text.range(of: ",\\s*\\{", options: .regularExpression) {
            let jsonStart = text.index(range.lowerBound, offsetBy: 1)
            let jsonText = String(text[jsonStart...])
            if let obj = JSONTool.object(from: jsonText) as? [String: Any] {
                option = obj
                urlPart = String(text[..<range.lowerBound])
            } else {
                // 兼容不规范的 JSON：截取到最后一个 }
                if let end = text.lastIndex(of: "}") {
                    let candidate = String(text[jsonStart...end])
                    if let obj = JSONTool.object(from: candidate) as? [String: Any] {
                        option = obj
                        urlPart = String(text[..<range.lowerBound])
                    }
                }
            }
        }

        var body = option["body"] as? String
        var method = ((option["method"] as? String) ?? "GET").uppercased()
        var charset = option["charset"] as? String
        var headers: [String: String] = [:]
        if let optionHeaders = option["headers"] as? [String: Any] {
            for (k, v) in optionHeaders {
                headers[k] = v as? String ?? "\(v)"
            }
        }

        // URL 里自带的 js 处理
        if let js = option["js"] as? String, !js.isEmpty {
            if let result = analyzer.evalJS(js, result: urlPart) as? String, !result.isEmpty {
                urlPart = result
            }
        }

        var url = URLTool.encode(URLTool.absolute(base: baseUrl, urlPart))
        if !baseUrl.isEmpty {
            url = URLTool.encode(URLTool.absolute(base: baseUrl, url))
        }

        // 站点级 header 与 referer
        var mergedHeaders = URLTool.headers(fromJSON: source?.header)
        for (k, v) in headers { mergedHeaders[k] = v }
        if mergedHeaders["Referer"] == nil && mergedHeaders["referer"] == nil {
            if !baseUrl.isEmpty {
                mergedHeaders["Referer"] = baseUrl
            } else if let sourceUrl = source?.bookSourceUrl, !sourceUrl.isEmpty {
                mergedHeaders["Referer"] = URLTool.origin(sourceUrl)
            }
        }

        var bodyData: Data?
        if let body = body {
            if method != "POST" { method = "POST" }
            if !isJSONBody(body) && !body.contains("Content-Type") {
                if mergedHeaders["Content-Type"] == nil {
                    mergedHeaders["Content-Type"] = "application/x-www-form-urlencoded"
                }
            }
            bodyData = encodeBody(body, charset: charset).data(using: .utf8)
        }

        return Plan(url: url,
                    method: method,
                    headers: mergedHeaders,
                    body: bodyData,
                    charset: charset,
                    useWebView: (option["webView"] as? Bool) ?? false)
    }

    // MARK: - JS 片段

    private static func evaluateJSSegments(_ rule: String, analyzer: AnalyzeRule) -> String {
        guard rule.contains("<js>") || rule.contains("@js:") else { return rule }
        let pattern = "<js>([\\s\\S]*?)</js>|@js:([\\s\\S]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                    options: [.caseInsensitive]) else {
            return rule
        }
        let ns = rule as NSString
        let matches = regex.matches(in: rule, options: [],
                                    range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return rule }
        var result = rule
        for match in matches.reversed() {
            let js: String
            if match.range(at: 2).location != NSNotFound {
                js = ns.substring(with: match.range(at: 2))
            } else {
                js = ns.substring(with: match.range(at: 1))
            }
            let evaluated = AnalyzeRule.jsString(analyzer.evalJS(js, result: nil))
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: evaluated)
            }
        }
        return result
    }

    private static func replaceMustache(_ text: String, analyzer: AnalyzeRule) -> String {
        guard text.contains("{{") else { return text }
        var result = text
        for item in RuleSplitter.innerJS(text).reversed() {
            let expression = item.js.trimmingCharacters(in: .whitespacesAndNewlines)
            let value: String
            if let direct = directValue(expression, analyzer: analyzer) {
                value = direct
            } else {
                value = AnalyzeRule.jsString(analyzer.evalJS(expression, result: nil))
            }
            result.replaceSubrange(item.range, with: value)
        }
        return result
    }

    /// `{{key}}`、`{{page}}` 这类最常见的占位符直接取值，避免依赖 JS 引擎
    private static func directValue(_ expression: String, analyzer: AnalyzeRule) -> String? {
        switch expression {
        case "key", "searchKey", "query":
            return AnalyzeRule.jsString(analyzer.jsExtraBindings["key"])
        case "page", "searchPage":
            return AnalyzeRule.jsString(analyzer.jsExtraBindings["page"])
        case "baseUrl":
            return analyzer.baseUrl
        case "bookName":
            return analyzer.book?.name
        case "title":
            return analyzer.chapter?.title
        default:
            return nil
        }
    }

    // MARK: - 请求体

    private static func isJSONBody(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) && JSONTool.object(from: trimmed) != nil
    }

    /// 表单 body 里对值做 URL 编码，保留 `a=b&c=d` 的结构
    private static func encodeBody(_ body: String, charset: String?) -> String {
        if let charset = charset?.lowercased(), charset == "escape" {
            return body
        }
        if isJSONBody(body) { return body }
        let pairs = body.split(separator: "&", omittingEmptySubsequences: false)
        let encoded = pairs.map { pair -> String in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts.first ?? "")
            if parts.count == 1 {
                return URLTool.encodeQueryValue(decodeIfNeeded(key))
            }
            let value = String(parts[1])
            return URLTool.encodeQueryValue(decodeIfNeeded(key)) + "=" +
                URLTool.encodeQueryValue(decodeIfNeeded(value))
        }
        return encoded.joined(separator: "&")
    }

    private static func decodeIfNeeded(_ value: String) -> String {
        value.removingPercentEncoding ?? value
    }
}
