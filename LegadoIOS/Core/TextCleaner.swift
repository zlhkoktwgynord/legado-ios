import Foundation

/// 文本清洗：HTML 转纯文本、实体解码、书名作者规范化
enum TextCleaner {

    private static let blockTags: Set<String> = [
        "p", "div", "br", "h1", "h2", "h3", "h4", "h5", "h6", "li", "tr",
        "section", "article", "blockquote", "pre", "hr", "dd", "dt"
    ]

    /// 正文 HTML 转成适合阅读的纯文本
    static func htmlToPlain(_ html: String) -> String {
        guard !html.isEmpty else { return "" }
        guard let doc = HTMLAnalyze.parseFragment(html) ?? HTMLAnalyze.parse(html) else {
            return stripTags(html)
        }
        if let body = doc.body() {
            _ = try? body.select("script").remove()
            _ = try? body.select("style").remove()
            var builder = ""
            walk(body, into: &builder)
            return normalize(builder)
        }
        return normalize(stripTags(html))
    }

    private static func walk(_ node: Node, into builder: inout String) {
        if let text = node as? TextNode {
            builder += text.getWholeText()
            return
        }
        if let element = node as? Element {
            let tag = element.tagName().lowercased()
            if tag == "br" {
                builder += "\n"
                return
            }
            if tag == "script" || tag == "style" {
                return
            }
            if tag == "img" {
                let alt = (try? element.attr("alt")) ?? ""
                if !alt.isEmpty { builder += "［\(alt)］\n" }
                return
            }
            let isBlock = blockTags.contains(tag)
            if isBlock && !builder.isEmpty && !builder.hasSuffix("\n") {
                builder += "\n"
            }
            for child in element.getChildNodes() {
                walk(child, into: &builder)
            }
            if isBlock { builder += "\n" }
            return
        }
        if let data = node as? DataNode {
            builder += data.getWholeData()
        }
    }

    /// 去掉标签，保留换行
    static func stripTags(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
            with: "",
            options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</(p|div|h[1-6]|li|tr)>", with: "\n",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "",
                                         options: .regularExpression)
        return normalize(decodeEntities(text))
    }

    /// 统一的空白整理
    static func normalize(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")
        text = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        text = text.replacingOccurrences(of: "\u{3000}", with: " ")
        // 去掉行首尾空白
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append(line.trimmingCharacters(in: .whitespaces))
        }
        // 连续空行只保留一个
        var out: [String] = []
        var blankCount = 0
        for line in lines {
            if line.isEmpty {
                blankCount += 1
                if blankCount > 1 { continue }
            } else {
                blankCount = 0
            }
            out.append(line)
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 常见的 HTML 实体解码
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&", let semicolon = text[index...].firstIndex(of: ";"),
               text.distance(from: index, to: semicolon) <= 10 {
                let entity = String(text[text.index(after: index)..<semicolon])
                if let decoded = decode(entity) {
                    result += decoded
                    index = text.index(after: semicolon)
                    continue
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    private static func decode(_ entity: String) -> String? {
        if entity.hasPrefix("#") {
            let body = entity.dropFirst()
            let value: UInt32?
            if body.hasPrefix("x") || body.hasPrefix("X") {
                value = UInt32(body.dropFirst(), radix: 16)
            } else {
                value = UInt32(body)
            }
            if let v = value, let scalar = Unicode.Scalar(v) {
                return String(Character(scalar))
            }
            return nil
        }
        let table: [String: String] = [
            "nbsp": " ", "lt": "<", "gt": ">", "amp": "&", "quot": "\"", "apos": "'",
            "hellip": "…", "mdash": "—", "ndash": "–", "middot": "·", "ldquo": "“",
            "rdquo": "”", "lsquo": "‘", "rsquo": "’", "emsp": " ", "ensp": " ",
            "copy": "©", "reg": "®", "trade": "™", "times": "×", "divide": "÷"
        ]
        return table[entity.lowercased()]
    }

    // MARK: - 书籍信息

    static func cleanBookName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["书名：", "书名:", "名称：", "名称:"] {
            if name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)) }
        }
        name = name.replacingOccurrences(of: "[\\s\\u3000]+", with: " ",
                                          options: .regularExpression)
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanAuthor(_ raw: String) -> String {
        var author = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["作者：", "作者:", "作 者：", "作 者:"] {
            if author.hasPrefix(prefix) { author = String(author.dropFirst(prefix.count)) }
        }
        author = author.replacingOccurrences(of: "[/／|｜].*$", with: "",
                                              options: .regularExpression)
        return author.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func formatWordCount(_ raw: String) -> String {
        let text = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if text.range(of: "万字|千字|字", options: .regularExpression) != nil {
            return text
        }
        if let n = Int(text) {
            if n >= 10000 { return String(format: "%.1f万字", Double(n) / 10000) }
            return "\(n)字"
        }
        return text
    }

    /// 粗略字数统计
    static func wordCount(_ text: String) -> Int {
        var count = 0
        for ch in text.unicodeScalars {
            if ch == " " || ch == "\n" || ch == "\t" { continue }
            count += 1
        }
        return count
    }
}

// MARK: - 日志

enum Log {
    static var enabled = true
    private static let queue = DispatchQueue(label: "legado.log")

    static func info(_ message: String) {
        guard enabled else { return }
        queue.async { print("[信息] \(message)") }
    }

    static func warn(_ message: String) {
        guard enabled else { return }
        queue.async { print("[警告] \(message)") }
    }

    static func error(_ message: String) {
        queue.async { print("[错误] \(message)") }
    }
}
