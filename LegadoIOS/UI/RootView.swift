import SwiftUI

enum Route: Hashable {
    case detail(Book)
    case searchBook(SearchBook)
    case sourceDetail(BookSource)
}

/// 阅读器以全屏方式弹出（不走导航栈，避免右滑把阅读页 pop 掉，也方便隐藏状态栏）
struct ReadingTarget: Identifiable {
    var book: Book
    var index: Int

    var id: String { "\(book.bookUrl)#\(index)" }
}

extension View {
    func readerCover(_ target: Binding<ReadingTarget?>) -> some View {
        fullScreenCover(item: target) { item in
            ReaderView(book: item.book, startIndex: item.index)
        }
    }
}

/// 主界面外壳：照搬安卓版「阅读」
/// 五页横向分页（书架 / 发现 / 订阅 / 阅读记录 / 我的）
/// + 底部 48pt 悬浮毛玻璃导航栏（5 个 23pt 图标 + 切换时闪现的 52×40 指示器）
/// + 右下角 48pt 圆形搜索按钮
/// 主界面底栏的显隐状态：二级页面（详情/阅读/设置）里要收起来
@MainActor
final class HomeChrome: ObservableObject {
    /// 当前压在主界面之上的页面层数
    @Published var depth = 0

    var barHidden: Bool { depth > 0 }
}

/// 二级页面出现时把底栏收起来
struct HidesHomeBar: ViewModifier {
    @EnvironmentObject private var chrome: HomeChrome

    func body(content: Content) -> some View {
        content
            .onAppear { chrome.depth += 1 }
            .onDisappear { chrome.depth = max(0, chrome.depth - 1) }
    }
}

extension View {
    func hidesHomeBar() -> some View { modifier(HidesHomeBar()) }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var chrome: HomeChrome
    @Environment(\.colorScheme) private var scheme

    @State private var tab: Int = RootView.initialTab
    @State private var showSearch: Bool = RootView.debugOpensSearch
    @State private var indicatorTab = 0
    @State private var indicatorOpacity: Double = 0
    @State private var fadeToken = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            LegadoTheme.background(scheme)
                .ignoresSafeArea()

            TabView(selection: $tab) {
                BookshelfView(onSearch: { showSearch = true })
                    .tag(0)
                DiscoverView()
                    .tag(1)
                RssView()
                    .tag(2)
                ReadRecordView()
                    .tag(3)
                MyConfigView()
                    .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)

            bottomBar
                .opacity(chrome.depth > 0 ? 0 : 1)
                .allowsHitTesting(chrome.depth == 0)
                .animation(.easeOut(duration: 0.15), value: chrome.depth)
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchView()
        }
    }

    // MARK: - 底部悬浮导航

    private var bottomBar: some View {
        HStack(spacing: 10) {
            GlassSurface(cornerRadius: 24) {
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(HomeTab.allCases, id: \.rawValue) { item in
                            Button {
                                select(item.rawValue)
                            } label: {
                                Image(systemName: tab == item.rawValue ? item.selectedIcon : item.icon)
                                    .font(.system(size: 23, weight: .regular))
                                    .foregroundColor(tab == item.rawValue
                                                     ? LegadoTheme.accent
                                                     : LegadoTheme.secondaryText(scheme).opacity(0.85))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)

                    GeometryReader { geo in
                        let itemWidth = geo.size.width / CGFloat(HomeTab.allCases.count)
                        Capsule()
                            .fill(LegadoTheme.accent.opacity(0.16))
                            .frame(width: 52, height: 40)
                            .offset(x: itemWidth * CGFloat(indicatorTab) + (itemWidth - 52) / 2,
                                    y: 4)
                            .opacity(indicatorOpacity)
                    }
                    .allowsHitTesting(false)
                }
                .frame(height: 48)
            }
            .frame(height: 48)

            Button {
                showSearch = true
            } label: {
                GlassSurface(cornerRadius: 24) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(LegadoTheme.secondaryText(scheme).opacity(0.9))
                        .frame(width: 48, height: 48)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func select(_ value: Int) {
        withAnimation(.easeOut(duration: 0.18)) { tab = value }
        indicatorTab = value
        fadeToken += 1
        let token = fadeToken
        withAnimation(.interpolatingSpring(stiffness: 380, damping: 22)) {
            indicatorOpacity = 1
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 780_000_000)
            guard token == fadeToken else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                indicatorOpacity = 0
            }
        }
    }

    // MARK: - 调试入口（截图流水线用）

    private static var initialTab: Int {
        switch ProcessInfo.processInfo.environment["LEGADO_SCREEN"] {
        case "explore": return 1
        case "rss": return 2
        case "stats": return 3
        case "mine": return 4
        default: return 0
        }
    }

    private static var debugOpensSearch: Bool {
        ProcessInfo.processInfo.environment["LEGADO_SCREEN"] == "search"
    }
}

enum HomeTab: Int, CaseIterable {
    case shelf, discover, rss, stats, mine

    var title: String {
        switch self {
        case .shelf: return "书架"
        case .discover: return "发现"
        case .rss: return "订阅"
        case .stats: return "阅读记录"
        case .mine: return "我的"
        }
    }

    var icon: String {
        switch self {
        case .shelf: return "books.vertical"
        case .discover: return "safari"
        case .rss: return "dot.radiowaves.left.and.right"
        case .stats: return "chart.bar"
        case .mine: return "person"
        }
    }

    var selectedIcon: String {
        switch self {
        case .shelf: return "books.vertical.fill"
        case .discover: return "safari.fill"
        case .rss: return "dot.radiowaves.left.and.right"
        case .stats: return "chart.bar.fill"
        case .mine: return "person.fill"
        }
    }
}

/// 统一的路由出口
struct RouteView: View {
    let route: Route

    var body: some View {
        content
            .hidesHomeBar()
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .detail(let book):
            BookDetailView(book: book)
        case .searchBook(let searchBook):
            BookDetailView(searchBook: searchBook)
        case .sourceDetail(let source):
            SourceDetailView(source: source)
        }
    }
}
