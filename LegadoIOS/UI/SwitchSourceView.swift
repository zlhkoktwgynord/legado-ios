import SwiftUI

/// 换源：用别的书源找同名书，保留阅读进度
struct SwitchSourceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let book: Book
    let onSwitched: (Book) -> Void

    @State private var results: [SearchBook] = []
    @State private var searching = true
    @State private var switchingId: String?
    @State private var error: String?

    private var candidates: [SearchBook] {
        results.filter { item in
            item.name == book.name || item.name.contains(book.name)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("《\(book.name)》").font(.subheadline)
                        Spacer()
                        if searching { ProgressView().scaleEffect(0.7) }
                    }
                    Text("当前书源：\(book.originName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let error = error {
                    Section { ErrorBanner(message: error) }
                }

                Section {
                    if candidates.isEmpty {
                        if searching {
                            LoadingRow(text: "正在其他书源里找…")
                        } else {
                            Text("其他书源没有找到这本书")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(candidates) { item in
                            Button {
                                performSwitch(item)
                            } label: {
                                HStack(spacing: 10) {
                                    BookCover(url: item.coverUrl, title: item.name,
                                              width: 40, height: 54, radius: 4)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name).font(.subheadline).lineLimit(1)
                                        Text("\(item.originName) · \(item.author)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if switchingId == item.id {
                                        ProgressView().scaleEffect(0.7)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(switchingId != nil)
                        }
                    }
                } header: {
                    Text("可替换的书源（\(candidates.count)）")
                } footer: {
                    Text("替换后会重新拉目录，并按章节标题恢复阅读进度。")
                }
            }
            .navigationTitle("换源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await search() }
        }
    }

    private func search() async {
        guard !model.enabledSources.isEmpty else {
            searching = false
            error = "没有启用的书源"
            return
        }
        for await result in model.search(keyword: book.name) {
            if Task.isCancelled { break }
            for item in result.books where item.name == book.name {
                if !results.contains(where: { $0.id == item.id }) {
                    results.append(item)
                }
            }
        }
        searching = false
    }

    private func performSwitch(_ item: SearchBook) {
        guard let source = model.source(for: item) else {
            error = "找不到这个书源"
            return
        }
        switchingId = item.id
        Task { @MainActor in
            do {
                let updated = try await model.switchSource(book: book, to: item, source: source)
                onSwitched(updated)
                dismiss()
            } catch {
                self.error = "换源失败：\(error.localizedDescription)"
                switchingId = nil
            }
        }
    }
}
