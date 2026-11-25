import Foundation

/// 用 SwiftSoup 实现 Legado 的默认（CSS / 标签）规则
enum HTMLAnalyze {

    enum RuleError: LocalizedError {
        case unsupportedXPath(String)
        case badRule(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedXPath(let r): return "暂不支持的 XPath 规则：\(r)"
            case .badRule(let r): return "规则有误：\(r)"
            }
        }
    }

    // MARK: - 解析

    static func parse(_ html: String, baseUrl: String = "") -> Document? {
        (try? Parser.parse(html, baseUrl)) ?? (try? parseHTML(html, baseUrl))
    }

    static func parseFragment(_ html: String, baseUrl: String = "") -> Document? {
        try? parseBodyFragment(html, baseUrl)
    }

    // MARK: - 取元素

    /// 取一组元素（规则里的每一段都当选择器）
    static func elements(_ rule: String, in root: Element) -> [Element] {
        let split = RuleSplitter.split(rule)
        var collected: [[Element]] = []
        for part in split.parts {
            let segments = RuleSplitter.splitSelectors(part)
            guard !segments.isEmpty else { continue }
            var current: [Element] = [root]
            for segment in segments {
                let (selector, indexes, exclude) = splitIndex(segment)
                var next: [Element] = []
                for el in current {
                    next.append(contentsOf: select(selector, in: el))
                }
                current = applyIndex(next, indexes: indexes, exclude: exclude)
            }
            if !current.isEmpty { collected.append(current) }
            if split.separator == "||" && !collected.isEmpty { break }
        }
        return merge(collected, separator: split.separator)
    }

    /// 取文本（完整规则：最后一段是 text/html/@attr 这类取值方式）
    static func strings(_ rule: String, in root: Element) -> [String] {
        let split = RuleSplitter.split(rule)
        var collected: [[String]] = []
        for part in split.parts {
            let result = strings(part: part, in: root)
            if !result.isEmpty { collected.append(result) }
            if split.separator == "||" && !collected.isEmpty { break }
        }
        return merge(collected, separator: split.separator)
    }

    static func string(_ rule: String, in root: Element) -> String? {
        let list = strings(rule, in: root)
        if list.isEmpty { return nil }
        return list.joined(separator: "\n")
    }

    private static func strings(part: String, in root: Element) -> [String] {
        var segments = RuleSplitter.splitSelectors(part)
        guard !segments.isEmpty else { return [] }
        var lastRule = "text"
        if segments.count > 1 || part.hasPrefix("@") {
            lastRule = segments.removeLast().trimmingCharacters(in: .whitespaces)
        }
        // 规则可能只是 "@text"
        if segments.isEmpty { segments = [""] }

        var current: [Element] = [root]
        for segment in segments {
            let (selector, indexes, exclude) = splitIndex(segment)
            var next: [Element] = []
            for el in current {
                next.append(contentsOf: select(selector, in: el))
            }
            current = applyIndex(next, indexes: indexes, exclude: exclude)
        }
        return extract(current, rule: lastRule)
    }


    /// 兼容阅读的 ElementsSingle 简写：class.xxx / tag.xxx / id.xxx / text.xxx / children
    static func select(_ selector: String, in element: Element) -> [Element] {
        let trimmed = selector.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return [element] }
        if trimmed.lowercased() == "children" {
            return element.children().array()
        }
        if let dot = trimmed.firstIndex(of: ".") {
            let prefix = String(trimmed[trimmed.startIndex..<dot]).lowercased()
            let argument = String(trimmed[trimmed.index(after: dot)...])
            switch prefix {
            case "class":
                return ((try? element.getElementsByClass(argument))?.array()) ?? []
            case "tag":
                return ((try? element.getElementsByTag(argument))?.array()) ?? []
            case "id":
                return ((try? element.select("#\(argument)"))?.array()) ?? []
            case "text":
                return ((try? element.getElementsContainingOwnText(argument))?.array()) ?? []
            default:
                break
            }
        }
        return ((try? element.select(trimmed))?.array()) ?? []
    }

    // MARK: - 取值

    private static func extract(_ elements: [Element], rule: String) -> [String] {
        var out: [String] = []
        switch rule {
        case "text":
            for el in elements {
                let text = ((try? el.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { out.append(text) }
            }
        case "textNodes":
            for el in elements {
                var lines: [String] = []
                for node in el.getChildNodes() {
                    if let textNode = node as? TextNode {
                        let t = textNode.getWholeText()
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { lines.append(t) }
                    }
                }
                if !lines.isEmpty { out.append(lines.joined(separator: "\n")) }
            }
        case "ownText":
            for el in elements {
                let t = el.ownText().trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { out.append(t) }
            }
        case "html":
            for el in elements {
                guard let copy = el.copy() as? Element else { continue }
                _ = try? copy.select("script").remove()
                _ = try? copy.select("style").remove()
                let html = ((try? copy.outerHtml()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !html.isEmpty { out.append(html) }
            }
        case "all":
            for el in elements {
                let html = (try? el.outerHtml()) ?? ""
                if !html.isEmpty { out.append(html) }
            }
        default:
            for el in elements {
                let value = ((try? el.attr(rule)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty && !out.contains(value) { out.append(value) }
            }
        }
        return out
    }

    // MARK: - 索引

    /// 解析 `div.book.0`、`div.book!0`、`div.book[-1]`、`div.book[0:3]` 里的索引
    static func splitIndex(_ raw: String) -> (selector: String, indexes: [Int]?, exclude: Bool) {
        let s = raw.trimmingCharacters(in: .whitespaces)
        // [..] 写法
        if s.hasSuffix("]"), let open = s.lastIndex(of: "[") {
            let inner = String(s[s.index(after: open)..<s.index(before: s.endIndex)])
            let selector = String(s[..<open])
            if let indexes = parseIndexList(inner) {
                return (selector, indexes, inner.trimmingCharacters(in: .whitespaces).hasPrefix("!"))
            }
        }
        // .N / !N 写法
        var idx = s.endIndex
        var digitsStart = idx
        while digitsStart > s.startIndex {
            let prev = s.index(before: digitsStart)
            let ch = s[prev]
            if ch.isNumber { digitsStart = prev } else { break }
        }
        idx = digitsStart
        if idx > s.startIndex && idx < s.endIndex {
            let prev = s.index(before: idx)
            let sep = s[prev]
            if sep == "." || sep == "!" {
                let numberPart = String(s[idx...])
                if let n = Int(numberPart) {
                    let selector = String(s[..<prev])
                    return (selector, [n], sep == "!")
                }
            }
        }
        return (s, nil, false)
    }

    static func parseIndexList(_ inner: String) -> [Int]? {
        var text = inner.trimmingCharacters(in: .whitespaces)
        var exclude = false
        if text.hasPrefix("!") {
            exclude = true
            text.removeFirst()
        }
        guard !text.isEmpty else { return nil }
        var result: [Int] = []
        for token in text.split(separator: ",") {
            let part = token.trimmingCharacters(in: .whitespaces)
            if part.contains(":") {
                let pieces = part.split(separator: ":", omittingEmptySubsequences: false)
                guard pieces.count >= 2 else { return nil }
                let start = Int(pieces[0].trimmingCharacters(in: .whitespaces))
                let end = Int(pieces[1].trimmingCharacters(in: .whitespaces))
                let step = pieces.count > 2 ? Int(pieces[2].trimmingCharacters(in: .whitespaces)) : 1
                if let start = start, let end = end, let step = step, step != 0 {
                    var i = start
                    if step > 0 {
                        while i <= end { result.append(i); i += step }
                    } else {
                        while i >= end { result.append(i); i += step }
                    }
                }
            } else if let n = Int(part) {
                result.append(n)
            } else {
                return nil
            }
        }
        _ = exclude
        return result.isEmpty ? nil : result
    }

    static func applyIndex(_ elements: [Element], indexes: [Int]?, exclude: Bool) -> [Element] {
        guard let indexes = indexes, !elements.isEmpty else { return elements }
        let count = elements.count
        var picked = Set<Int>()
        for raw in indexes {
            let i = raw < 0 ? count + raw : raw
            if i >= 0 && i < count { picked.insert(i) }
        }
        if exclude {
            return elements.enumerated().filter { !picked.contains($0.offset) }.map { $0.element }
        }
        return elements.enumerated().filter { picked.contains($0.offset) }.map { $0.element }
    }

    private static func merge<T>(_ lists: [[T]], separator: String) -> [T] {
        guard !lists.isEmpty else { return [] }
        if separator == "%%" {
            var out: [T] = []
            let maxCount = lists.map { $0.count }.max() ?? 0
            for i in 0..<maxCount {
                for list in lists where i < list.count {
                    out.append(list[i])
                }
            }
            return out
        }
        return lists.flatMap { $0 }
    }
}
