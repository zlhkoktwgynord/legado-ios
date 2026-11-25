import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum Route: Hashable {
    case detail(Book)
    case searchBook(SearchBook)
    case reader(Book, Int)
    case sourceDetail(BookSource)
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: Int = 0

    var body: some View {
        TabView(selection: $tab) {
            BookshelfView(selectedTab: $tab)
                .tabItem { Label("书架", systemImage: "books.vertical") }
                .tag(0)
            DiscoverView()
                .tabItem { Label("发现", systemImage: "safari") }
                .tag(1)
        }
    }
}

/// 统一的路由出口
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .detail(let book):
            BookDetailView(book: book)
        case .searchBook(let searchBook):
            BookDetailView(searchBook: searchBook)
        case .reader(let book, let index):
            ReaderView(book: book, startIndex: index)
        case .sourceDetail(let source):
            SourceDetailView(source: source)
        }
    }
}
