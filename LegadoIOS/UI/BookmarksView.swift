import SwiftUI

/// 某本书的书签列表
struct BookmarksView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let book: Book
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if model.bookmarks(for: book).isEmpty {
                    EmptyStateView(icon: "bookmark",
                                   title: "还没有书签",
                                   message: "阅读时点底部「书签」按钮，就能把当前章节存下来")
                } else {
                    List {
                        ForEach(model.bookmarks(for: book)) { mark in
                            Button {
                                onSelect(mark.chapterIndex)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mark.chapterTitle)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    if !mark.content.isEmpty {
                                        Text(mark.content)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    Text(dateText(mark.createdAt))
                                        .font(.caption2)
                                        .foregroundColor(.secondary.opacity(0.7))
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    if let index = model.bookmarks.firstIndex(where: { $0.id == mark.id }) {
                                        model.bookmarks.remove(at: index)
                                        Storage.saveJSON(model.bookmarks, "bookmarks.json")
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func dateText(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
