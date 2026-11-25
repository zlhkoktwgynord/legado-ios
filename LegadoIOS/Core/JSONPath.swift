import Foundation

/// 精简版 JSONPath，覆盖书源里常见的写法：
/// `$.data.list[*].name`、`$..name`、`$.data['x']`、`$.list[0].name`、`$.list[-1]`
enum JSONPath {

    enum Step {
        case key(String)
        case index(Int)
        case wildcard          // .* 或 [*]
        case recursiveKey(String)   // ..name
        case recursiveWildcard      // ..*
    }

    static func query(_ path: String, root: Any) -> [Any] {
        let steps = parse(path)
        var current: [Any] = [root]
        for step in steps {
            var next: [Any] = []
            for node in current {
                next.append(contentsOf: apply(step, to: node))
            }
            current = next
            if current.isEmpty { break }
        }
        return current
    }

    // MARK: - 解析

    static func parse(_ rawPath: String) -> [Step] {
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("$") { path.removeFirst() }
        var steps: [Step] = []
        let chars = Array(path)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "." {
                if i + 1 < chars.count && chars[i + 1] == "." {
                    // 递归
                    i += 2
                    if i < chars.count && chars[i] == "*" {
                        steps.append(.recursiveWildcard)
                        i += 1
                        continue
                    }
                    var name = ""
                    while i < chars.count && (chars[i].isLetter || chars[i].isNumber
                        || chars[i] == "_" || chars[i] == "-" || chars[i] == " ") {
                        name.append(chars[i])
                        i += 1
                    }
                    if !name.isEmpty {
                        steps.append(.recursiveKey(name.trimmingCharacters(in: .whitespaces)))
                    }
                    continue
                }
                i += 1
                if i < chars.count && chars[i] == "*" {
                    steps.append(.wildcard)
                    i += 1
                    continue
                }
                var name = ""
                while i < chars.count && chars[i] != "." && chars[i] != "[" {
                    name.append(chars[i])
                    i += 1
                }
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { steps.append(.key(trimmed)) }
                continue
            }
            if c == "[" {
                var inner = ""
                i += 1
                var inQuote: Character?
                while i < chars.count {
                    let ch = chars[i]
                    if let q = inQuote {
                        if ch == q { inQuote = nil } else { inner.append(ch) }
                        i += 1
                        continue
                    }
                    if ch == "'" || ch == "\"" { inQuote = ch; i += 1; continue }
                    if ch == "]" { i += 1; break }
                    inner.append(ch)
                    i += 1
                }
                let token = inner.trimmingCharacters(in: .whitespaces)
                if token == "*" {
                    steps.append(.wildcard)
                } else if let n = Int(token) {
                    steps.append(.index(n))
                } else if !token.isEmpty {
                    steps.append(.key(token))
                }
                continue
            }
            // 形如 name.xxx 或直接以字段名开头
            var name = ""
            while i < chars.count && chars[i] != "." && chars[i] != "[" {
                name.append(chars[i])
                i += 1
            }
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { steps.append(.key(trimmed)) }
        }
        return steps
    }

    // MARK: - 求值

    private static func apply(_ step: Step, to node: Any) -> [Any] {
        switch step {
        case .key(let k):
            if let dict = DictionaryBox(node) { return dict.value(k).map { [$0] } ?? [] }
            return []
        case .index(let n):
            if let arr = ArrayBox(node) {
                let idx = n < 0 ? arr.count + n : n
                if idx >= 0 && idx < arr.count { return [arr[idx]] }
            }
            return []
        case .wildcard:
            if let arr = ArrayBox(node) { return arr.all }
            if let dict = DictionaryBox(node) { return dict.allValues() }
            return []
        case .recursiveKey(let k):
            var out: [Any] = []
            walk(node) { candidate in
                if let dict = DictionaryBox(candidate), let v = dict.value(k) {
                    out.append(v)
                }
            }
            return out
        case .recursiveWildcard:
            var out: [Any] = []
            walk(node) { candidate in
                if let dict = DictionaryBox(candidate) {
                    out.append(contentsOf: dict.allValues())
                } else if let arr = ArrayBox(candidate) {
                    out.append(contentsOf: arr.all)
                }
            }
            return out
        }
    }

    private static func walk(_ node: Any, visit: (Any) -> Void) {
        visit(node)
        if let arr = ArrayBox(node) {
            for item in arr.all { walk(item, visit: visit) }
        } else if let dict = DictionaryBox(node) {
            for v in dict.allValues() { walk(v, visit: visit) }
        }
    }
}

// MARK: - 类型擦除的访问器

struct DictionaryBox {
    private let dict: [String: Any]

    init?(_ value: Any) {
        if let d = value as? [String: Any] {
            dict = d
        } else if let d = value as? [AnyHashable: Any] {
            var tmp: [String: Any] = [:]
            for (k, v) in d { if let ks = k as? String { tmp[ks] = v } }
            dict = tmp
        } else {
            return nil
        }
    }

    func value(_ key: String) -> Any? {
        if let v = dict[key] { return v }
        // 兼容 key 带空格的规则写法
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        return dict[trimmed]
    }

    func allValues() -> [Any] { Array(dict.values) }
}

struct ArrayBox {
    private let array: [Any]

    init?(_ value: Any) {
        if let a = value as? [Any] { array = a }
        else if let a = value as? [AnyHashable] { array = a.map { $0 as Any } }
        else { return nil }
    }

    var count: Int { array.count }
    subscript(index: Int) -> Any { array[index] }
    var all: [Any] { array }

    func makeIterator() -> IndexingIterator<[Any]> { array.makeIterator() }
}
