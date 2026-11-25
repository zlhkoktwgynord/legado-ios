import Foundation

/// 规则切分：按顶层（括号、引号外）的分隔符切分规则串
enum RuleSplitter {

    struct SplitResult {
        var parts: [String]
        /// 实际命中的分隔符：&& / || / %% / ""（只有一个）
        var separator: String
    }

    static func split(_ rule: String, separators: [String] = ["&&", "||", "%%"]) -> SplitResult {
        var parts: [String] = []
        var current = ""
        var found = ""
        var depth = 0
        var inSingle = false
        var inDouble = false
        let chars = Array(rule)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "'" && !inDouble {
                inSingle.toggle()
                current.append(c)
                i += 1
                continue
            }
            if c == "\"" && !inSingle {
                inDouble.toggle()
                current.append(c)
                i += 1
                continue
            }
            if !inSingle && !inDouble {
                if c == "[" || c == "(" || c == "{" {
                    depth += 1
                } else if c == "]" || c == ")" || c == "}" {
                    depth = max(0, depth - 1)
                }
                if depth == 0 {
                    var matched: String?
                    for sep in separators where i + sep.count <= chars.count {
                        if String(chars[i..<(i + sep.count)]) == sep {
                            matched = sep
                            break
                        }
                    }
                    if let sep = matched {
                        parts.append(current)
                        current = ""
                        if found.isEmpty { found = sep } else if found != sep {
                            // 混用分隔符时以第一个为准，后续按普通文本处理
                            current = sep
                        }
                        i += sep.count
                        continue
                    }
                }
            }
            current.append(c)
            i += 1
        }
        parts.append(current)
        let cleaned = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return SplitResult(parts: cleaned.isEmpty ? [rule] : cleaned, separator: found)
    }

    /// 按 '@' 切分选择器链，但忽略 [] () 和引号内的 '@'
    static func splitSelectors(_ rule: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var inSingle = false
        var inDouble = false
        for c in rule {
            if c == "'" && !inDouble { inSingle.toggle(); current.append(c); continue }
            if c == "\"" && !inSingle { inDouble.toggle(); current.append(c); continue }
            if !inSingle && !inDouble {
                if c == "[" || c == "(" { depth += 1 }
                else if c == "]" || c == ")" { depth = max(0, depth - 1) }
                else if c == "@" && depth == 0 {
                    parts.append(current)
                    current = ""
                    continue
                }
            }
            current.append(c)
        }
        parts.append(current)
        // 第一个元素通常是前导的空片段
        return parts.filter { !$0.isEmpty }
    }

    /// 把 `{{ js }}` 找出来（含嵌套花括号的简单平衡处理）
    static func innerJS(_ text: String) -> [(range: Range<String.Index>, js: String)] {
        var result: [(Range<String.Index>, String)] = []
        var searchStart = text.startIndex
        while let open = text.range(of: "{{", range: searchStart..<text.endIndex) {
            var depth = 0
            var idx = open.lowerBound
            var end: String.Index?
            while idx < text.endIndex {
                if text[idx...].hasPrefix("{{") {
                    depth += 1
                    idx = text.index(idx, offsetBy: 2)
                    continue
                }
                if text[idx...].hasPrefix("}}") {
                    depth -= 1
                    if depth == 0 {
                        end = idx
                        break
                    }
                    idx = text.index(idx, offsetBy: 2)
                    continue
                }
                idx = text.index(after: idx)
            }
            guard let close = end else { break }
            let inner = String(text[text.index(open.lowerBound, offsetBy: 2)..<close])
            result.append((open.lowerBound..<text.index(close, offsetBy: 2), inner))
            searchStart = text.index(close, offsetBy: 2)
        }
        return result
    }
}
