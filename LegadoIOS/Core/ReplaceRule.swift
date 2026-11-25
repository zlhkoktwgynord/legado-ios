import Foundation

/// 替换净化规则：按顺序对正文做正则/文本替换
struct ReplaceRule: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var pattern: String = ""
    var replacement: String = ""
    /// true = 按正则处理，false = 纯文本替换
    var isRegex: Bool = true
    var enabled: Bool = true
}

extension TextCleaner {

    static func applyReplaceRules(_ text: String, rules: [ReplaceRule]) -> String {
        guard !text.isEmpty, !rules.isEmpty else { return text }
        var result = text
        for rule in rules where rule.enabled && !rule.pattern.isEmpty {
            if rule.isRegex {
                guard let regex = try? NSRegularExpression(pattern: rule.pattern,
                                                            options: [.caseInsensitive]) else {
                    continue
                }
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range,
                                                        withTemplate: rule.replacement)
            } else {
                result = result.replacingOccurrences(of: rule.pattern, with: rule.replacement)
            }
        }
        return result
    }

    /// 内置的几条常用净化规则，方便新用户直接用
    static func defaultReplaceRules() -> [ReplaceRule] {
        [
            ReplaceRule(name: "去掉广告尾巴",
                        pattern: "\\n?[^\\n]{0,30}(本章未完|请记住本站|手机用户请浏览|最新章节|加入书签|投推荐票)[^\\n]*",
                        replacement: "",
                        isRegex: true,
                        enabled: true),
            ReplaceRule(name: "去掉网址",
                        pattern: "(https?://|www\\.)[^\\s，。；]+",
                        replacement: "",
                        isRegex: true,
                        enabled: true)
        ]
    }
}
