import SwiftUI

/// 全屏目录页（仿原版：章节名 + 字数，当前章节高亮，底部定位与上下章）
struct ChapterListPage: View {
    let book: Book
    let chapters: [BookChapter]
    let currentIndex: Int
    let onSelect: (Int) -> Void
    let onClose: () -> Void

    @State private var highlight: Int = 0

    init(book: Book, chapters: [BookChapter], currentIndex: Int,
         onSelect: @escaping (Int) -> Void, onClose: @escaping () -> Void) {
        self.book = book
        self.chapters = chapters
        self.currentIndex = currentIndex
        self.onSelect = onSelect
        self.onClose = onClose
        _highlight = State(initialValue: currentIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            bottomBar
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
            }
            Text(book.name)
                .font(.headline)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(chapters) { chapter in
                    Button {
                        highlight = chapter.index
                        onSelect(chapter.index)
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chapter.title)
                                    .font(.system(size: 16))
                                    .foregroundColor(chapter.index == currentIndex ? .red : .primary)
                                    .lineLimit(2)
                                if let words = chapter.wordCount, !words.isEmpty {
                                    Text(words)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if chapter.index == currentIndex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .id(chapter.index)
                }
            }
            .listStyle(.plain)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    proxy.scrollTo(currentIndex, anchor: .center)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text(positionText)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()
            Button {
                guard currentIndex > 0 else { return }
                onSelect(currentIndex - 1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 16, weight: .semibold))
            }
            .disabled(currentIndex <= 0)

            Button {
                guard currentIndex < chapters.count - 1 else { return }
                onSelect(currentIndex + 1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
            }
            .disabled(currentIndex >= chapters.count - 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Divider() }
    }

    private var positionText: String {
        let title = chapters.indices.contains(currentIndex) ? chapters[currentIndex].title : ""
        return "\(title)(\(currentIndex + 1)/\(chapters.count))"
    }
}
