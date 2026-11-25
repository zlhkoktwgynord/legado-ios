import SwiftUI

struct BookshelfView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedTab: Int

    @State private var refreshing: Set<String> = []
    @State private var toast: String?
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var path = NavigationPath()

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: 16)]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.books.isEmpty {
                    emptyView
                } else {
                    shelf
                }
            }
            .navigationTitle("书架")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                RouteView(route: route)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .overlay(alignment: .bottom) {
                if let toast = toast {
                    Text(toast)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.9))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(.bottom, 18)
                        .transition(.opacity)
                }
            }
            .alert("出错了", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } })) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            EmptyStateView(icon: "books.vertical",
                           title: model.sources.isEmpty ? "还没有书源" : "书架是空的",
                           message: model.sources.isEmpty
                            ? "先去「书源」导入书源，再到「搜索」里找书"
                            : "在「搜索」里找到喜欢的书，加入书架")
            VStack(spacing: 10) {
                Button {
                    selectedTab = model.sources.isEmpty ? 2 : 1
                } label: {
                    Text(model.sources.isEmpty ? "导入书源" : "去搜索")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 80)
        }
    }

    private var shelf: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(model.sortedBooks) { book in
                    NavigationLink(value: Route.reader(book, book.durChapterIndex)) {
                        cell(book)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            openDetail(book)
                        } label: {
                            Label("书籍详情", systemImage: "info.circle")
                        }
                        Button {
                            refresh(book)
                        } label: {
                            Label("刷新目录", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Divider()
                        Button(role: .destructive) {
                            model.removeBook(book)
                        } label: {
                            Label("移出书架", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func cell(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                BookCover(url: book.coverUrl, title: book.name, width: 96, height: 132)
                if refreshing.contains(book.bookUrl) {
                    ProgressView()
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .padding(4)
                } else if let count = newChapterCount(book) {
                    Text("+\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .padding(4)
                }
            }
            .frame(width: 96, height: 132)

            Text(book.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Text(book.durChapterTitle ?? book.author)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: 96, alignment: .leading)
    }

    private func newChapterCount(_ book: Book) -> Int? {
        guard book.totalChapterNum > 0 else { return nil }
        let read = book.durChapterIndex + 1
        let count = book.totalChapterNum - read
        return count > 0 ? count : nil
    }

    private func openDetail(_ book: Book) {
        path.append(Route.detail(book))
    }

    private func refresh(_ book: Book) {
        guard let source = model.source(for: book) else {
            errorMessage = "找不到这本书对应的书源，可能已被删除"
            return
        }
        guard !refreshing.contains(book.bookUrl) else { return }
        refreshing.insert(book.bookUrl)
        Task { @MainActor in
            defer { refreshing.remove(book.bookUrl) }
            do {
                let result = try await BookService.refreshToc(book: book, source: source)
                var updated = book
                updated.totalChapterNum = result.chapters.count
                updated.latestChapterTitle = result.chapters.last?.title
                updated.lastCheckTime = Int64(Date().timeIntervalSince1970 * 1000)
                model.updateBook(updated)
                toast = result.added > 0 ? "已更新，新增 \(result.added) 章" : "已是最新"
                autoHideToast()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func autoHideToast() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}
