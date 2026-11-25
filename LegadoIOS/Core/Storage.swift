import Foundation

/// 本地持久化：书源、书架、目录缓存、正文缓存
enum Storage {

    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("LegadoIOS", isDirectory: true)
        ensure(dir)
        return dir
    }

    static var cacheDir: URL {
        let dir = root.appendingPathComponent("cache", isDirectory: true)
        ensure(dir)
        return dir
    }

    private static func ensure(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func fileURL(_ name: String) -> URL {
        root.appendingPathComponent(name)
    }

    static func loadJSON<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        let url = fileURL(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(type, from: data)
    }

    static func saveJSON<T: Encodable>(_ value: T, _ name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: fileURL(name), options: .atomic)
    }

    // MARK: - 目录

    static func chaptersFile(_ bookUrl: String) -> URL {
        fileURL("chapters-\(MD5.hash(bookUrl)).json")
    }

    static func loadChapters(_ bookUrl: String) -> [BookChapter] {
        loadJSON([BookChapter].self, "chapters-\(MD5.hash(bookUrl)).json") ?? []
    }

    static func saveChapters(_ chapters: [BookChapter], bookUrl: String) {
        saveJSON(chapters, "chapters-\(MD5.hash(bookUrl)).json")
    }

    // MARK: - 正文缓存

    static func contentFile(_ bookUrl: String, index: Int) -> URL {
        let dir = cacheDir.appendingPathComponent(MD5.hash(bookUrl), isDirectory: true)
        ensure(dir)
        return dir.appendingPathComponent("\(index).txt")
    }

    static func loadContent(_ bookUrl: String, index: Int) -> String? {
        let url = contentFile(bookUrl, index: index)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveContent(_ text: String, bookUrl: String, index: Int) {
        let url = contentFile(bookUrl, index: index)
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    static func clearContentCache() {
        try? FileManager.default.removeItem(at: cacheDir)
        _ = cacheDir
    }

    // MARK: - 阅读设置

    static func loadReaderConfig() -> ReaderConfig {
        loadJSON(ReaderConfig.self, "reader.json") ?? .default
    }

    static func saveReaderConfig(_ config: ReaderConfig) {
        saveJSON(config, "reader.json")
    }
}

// MARK: - 书源导入

enum SourceImporter {

    /// 支持：JSON 数组、单个 JSON 对象、每行一个 JSON 对象、以及 ### 分隔
    static func parse(_ raw: String) -> [BookSource] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        var candidates: [String] = []
        if text.hasPrefix("[") {
            candidates = [text]
        } else if text.hasPrefix("{") && text.contains("\n") {
            // 可能是多个对象拼接，也可能是格式化的单个对象
            let list = splitJSONObjects(text)
            if list.count > 1 {
                candidates = list
            } else {
                candidates = [text]
            }
        } else {
            candidates = text.components(separatedBy: "###")
                .flatMap { $0.components(separatedBy: "\n") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        var sources: [BookSource] = []
        for candidate in candidates {
            sources.append(contentsOf: decode(candidate))
        }
        // 去重
        var result: [BookSource] = []
        var seen = Set<String>()
        for source in sources where !source.bookSourceUrl.isEmpty {
            if seen.contains(source.bookSourceUrl) { continue }
            seen.insert(source.bookSourceUrl)
            result.append(source)
        }
        return result
    }

    private static func decode(_ text: String) -> [BookSource] {
        guard let data = text.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([BookSource].self, from: data) {
            return list
        }
        if let single = try? decoder.decode(BookSource.self, from: data) {
            return [single]
        }
        // 容错：把单个对象里不规范的注释去掉后再试
        let cleaned = text.replacingOccurrences(of: "//[^\"]*$", with: "",
                                                 options: [.regularExpression])
        if let data2 = cleaned.data(using: .utf8),
           let single = try? decoder.decode(BookSource.self, from: data2) {
            return [single]
        }
        return []
    }

    /// 从拼接文本里按大括号平衡切出多个 JSON 对象
    private static func splitJSONObjects(_ text: String) -> [String] {
        var result: [String] = []
        var depth = 0
        var inString = false
        var escaped = false
        var current = ""
        for ch in text {
            current.append(ch)
            if escaped { escaped = false; continue }
            if ch == "\\" && inString { escaped = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            if inString { continue }
            if ch == "{" { depth += 1 }
            if ch == "}" {
                depth -= 1
                if depth == 0 {
                    result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = ""
                }
            }
        }
        return result
    }
}
