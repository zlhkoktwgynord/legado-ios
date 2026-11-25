import Foundation

/// 把书源里常见的 XPath 规则转换成 CSS 选择器。
/// 只覆盖最常用的写法，无法转换时抛出明确错误，避免静默返回空结果。
enum XPathBridge {

    struct Converted {
        var selector: String
        var lastRule: String
    }

    static func convert(_ xpath: String) throws -> Converted {
        var expr = xpath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expr.isEmpty else { return Converted(selector: "", lastRule: "text") }

        var lastRule = "text"
        // 结尾的 /text() 或 /@attr
        if let range = expr.range(of: "/text\\s*\\(\\s*\\)\\s*$", options: .regularExpression) {
            expr = String(expr[..<range.lowerBound])
            lastRule = "text"
        } else if let range = expr.range(of: "/@([A-Za-z_:][-A-Za-z0-9_:.]*)\\s*$",
                                         options: .regularExpression) {
            let attr = String(expr[range])
                .replacingOccurrences(of: "^/@", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            expr = String(expr[..<range.lowerBound])
            lastRule = attr
        }

        if expr.hasPrefix("(") || expr.contains("|") || expr.contains("following-sibling")
            || expr.contains("preceding-sibling") || expr.contains("count(")
            || expr.contains("position()") || expr.contains("ancestor") {
            throw HTMLAnalyze.RuleError.unsupportedXPath(xpath)
        }

        let steps = tokenize(expr)
        var cssParts: [String] = []
        for step in steps {
            if step.separator == .descendant {
                cssParts.append(" ")
            } else if step.separator == .child {
                cssParts.append(" > ")
            }
            let css = try convertStep(step.text)
            cssParts.append(css)
        }
        var selector = cssParts.joined()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if selector.hasPrefix("> ") {
            selector = String(selector.dropFirst(2))
        }
        return Converted(selector: selector, lastRule: lastRule)
    }

    // MARK: - 分词

    private struct Step {
        enum Separator { case none, child, descendant }
        var separator: Separator
        var text: String
    }

    private static func tokenize(_ expr: String) -> [Step] {
        var steps: [Step] = []
        var current = ""
        var pendingSeparator: Step.Separator = .none
        var depth = 0
        var inQuote: Character?
        let chars = Array(expr)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if let q = inQuote {
                current.append(c)
                if c == q { inQuote = nil }
                i += 1
                continue
            }
            if c == "'" || c == "\"" {
                inQuote = c
                current.append(c)
                i += 1
                continue
            }
            if c == "[" || c == "(" { depth += 1; current.append(c); i += 1; continue }
            if c == "]" || c == ")" { depth = max(0, depth - 1); current.append(c); i += 1; continue }
            if c == "/" && depth == 0 {
                if !current.isEmpty {
                    steps.append(Step(separator: pendingSeparator, text: current))
                    current = ""
                }
                if i + 1 < chars.count && chars[i + 1] == "/" {
                    pendingSeparator = .descendant
                    i += 2
                } else {
                    pendingSeparator = .child
                    i += 1
                }
                continue
            }
            current.append(c)
            i += 1
        }
        if !current.isEmpty {
            steps.append(Step(separator: pendingSeparator, text: current))
        }
        return steps
    }

    // MARK: - 单步转换

    private static func convertStep(_ raw: String) throws -> String {
        var step = raw.trimmingCharacters(in: .whitespaces)
        if step.isEmpty || step == "." { return "" }
        if step == ".." { throw HTMLAnalyze.RuleError.unsupportedXPath(raw) }

        var tag = "*"
        var predicates: [String] = []
        if let bracket = step.firstIndex(of: "[") {
            tag = String(step[step.startIndex..<bracket])
            step = String(step[bracket...])
            var depth = 0
            var buffer = ""
            for ch in step {
                if ch == "[" {
                    depth += 1
                    if depth == 1 { continue }
                } else if ch == "]" {
                    depth -= 1
                    if depth == 0 {
                        predicates.append(buffer)
                        buffer = ""
                        continue
                    }
                }
                buffer.append(ch)
            }
        } else {
            tag = step
        }
        if tag.isEmpty { tag = "*" }

        var css = tag == "*" ? "" : tag
        for predicate in predicates {
            for part in splitAnd(predicate) {
                css += try convertPredicate(part)
            }
        }
        return css
    }

    private static func splitAnd(_ predicate: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuote: Character?
        let chars = Array(predicate)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if let q = inQuote {
                current.append(c)
                if c == q { inQuote = nil }
                i += 1
                continue
            }
            if c == "'" || c == "\"" { inQuote = c; current.append(c); i += 1; continue }
            if chars[i...].starts(with: Array(" and ")) {
                parts.append(current)
                current = ""
                i += 5
                continue
            }
            current.append(c)
            i += 1
        }
        if !current.isEmpty { parts.append(current) }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func convertPredicate(_ predicate: String) throws -> String {
        let p = predicate.trimmingCharacters(in: .whitespaces)

        // 纯数字索引：[1] / [last()]
        if let n = Int(p) {
            return ":nth-of-type(\(n))"
        }
        if p == "last()" {
            return ":last-of-type"
        }

        // @class='x' / @id='x'
        if let (attr, value) = attributeEquality(p) {
            if attr == "class" {
                if value.split(separator: " ").count == 1 && value.rangeOfCharacter(
                    from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
                        .inverted) == nil {
                    return ".\(value)"
                }
                return "[class=\"\(value)\"]"
            }
            if attr == "id" {
                return "#\(value)"
            }
            return "[\(attr)=\"\(value)\"]"
        }

        // contains(@class,'x') / contains(@href,'x') / contains(text(),'x')
        if let (target, value) = containsFunction(p) {
            if target == "class" { return ".\(value)" }
            if target == "text()" { return ":contains(\(value))" }
            return "[\(target)*=\"\(value)\"]"
        }

        // starts-with(@href,'x')
        if let (target, value) = startsWithFunction(p) {
            return "[\(target)^=\"\(value)\"]"
        }

        throw HTMLAnalyze.RuleError.unsupportedXPath("[\(p)]")
    }

    private static func attributeEquality(_ p: String) -> (String, String)? {
        guard p.hasPrefix("@") else { return nil }
        let pattern = "^@([-A-Za-z0-9_:.]+)\\s*=\\s*(['\"])(.*?)\\2$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: p, options: [],
                                            range: NSRange(p.startIndex..., in: p)),
              match.numberOfRanges == 4,
              let attrRange = Range(match.range(at: 1), in: p),
              let valueRange = Range(match.range(at: 3), in: p) else { return nil }
        return (String(p[attrRange]), String(p[valueRange]))
    }

    private static func containsFunction(_ p: String) -> (String, String)? {
        let pattern = "^contains\\(\\s*@?([-A-Za-z0-9_:.()]+)\\s*,\\s*(['\"])(.*?)\\2\\s*\\)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: p, options: [],
                                            range: NSRange(p.startIndex..., in: p)),
              match.numberOfRanges == 4,
              let t = Range(match.range(at: 1), in: p),
              let v = Range(match.range(at: 3), in: p) else { return nil }
        return (String(p[t]), String(p[v]))
    }

    private static func startsWithFunction(_ p: String) -> (String, String)? {
        let pattern = "^starts-with\\(\\s*@?([-A-Za-z0-9_:.]+)\\s*,\\s*(['\"])(.*?)\\2\\s*\\)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: p, options: [],
                                            range: NSRange(p.startIndex..., in: p)),
              match.numberOfRanges == 4,
              let t = Range(match.range(at: 1), in: p),
              let v = Range(match.range(at: 3), in: p) else { return nil }
        return (String(p[t]), String(p[v]))
    }
}
