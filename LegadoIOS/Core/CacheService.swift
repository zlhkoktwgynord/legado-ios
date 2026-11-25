import Foundation

/// 整本缓存下载（离线阅读）
enum CacheService {

    static func cachedCount(_ book: Book) -> Int {
        let total = book.totalChapterNum
        guard total > 0 else { return 0 }
        var count = 0
        for index in 0..<total where Storage.loadContent(book.bookUrl, index: index) != nil {
            count += 1
        }
        return count
    }

    /// 下载缺失章节，返回已缓存章节数
    @discardableResult
    static func downloadAll(book: Book,
                            source: BookSource,
                            chapters: [BookChapter],
                            progress: @escaping @Sendable (Int, Int) -> Void) async -> Int {
        let total = chapters.count
        guard total > 0 else { return 0 }
        var completed = 0
        var pending: [BookChapter] = []
        for chapter in chapters {
            if Storage.loadContent(book.bookUrl, index: chapter.index) != nil {
                completed += 1
                progress(completed, total)
            } else {
                pending.append(chapter)
            }
        }
        if pending.isEmpty { return completed }

        let limit = 3
        await withTaskGroup(of: Bool.self) { group in
            var iterator = pending.makeIterator()
            var running = 0
            while let chapter = iterator.next() {
                group.addTask {
                    do {
                        _ = try await BookService.loadContent(book: book,
                                                              chapter: chapter,
                                                              source: source)
                        return true
                    } catch {
                        Log.warn("缓存失败 \(chapter.title): \(error.localizedDescription)")
                        return false
                    }
                }
                running += 1
                if running >= limit {
                    _ = await group.next()
                    running -= 1
                    completed += 1
                    progress(completed, total)
                }
            }
            for await _ in group {
                completed += 1
                progress(completed, total)
            }
        }
        return completed
    }
}
