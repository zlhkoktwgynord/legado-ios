import SwiftUI

enum Route: Hashable {
    case detail(Book)
    case searchBook(SearchBook)
    case reader(Book, Int)
    case sourceDetail(BookSource)
}

/// 主界面外壳：照搬安卓版「阅读」的布局
/// 五页横向分页（书架 / 发现 / RSS / 阅读统计 / 我的）
/// + 底部悬浮毛玻璃导航栏（图标 + 胶囊指示器）
/// + 右下角圆形搜索按钮 + 左侧抽屉
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    @State private var tab: Int = RootView.initialTab
    @State private var showSearch: Bool = RootView.debugOpensSearch
    @State private var showDrawer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LegadoTheme.background(scheme)
                .ignoresSafeArea()

            TabView(selection: $tab) {
                BookshelfView(onSearch: { showSearch = true },
                              onOpenDrawer: { withAnimation(.easeOut(duration: 0.22)) { showDrawer = true } })
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
        }
        .overlay { drawerLayer }
        .fullScreenCover(isPresented: $showSearch) {
            SearchView()
        }
    }

    // MARK: - 底部悬浮导航

    private var bottomBar: some View {
        HStack(spacing: 10) {
            GlassSurface(cornerRadius: 26) {
                HStack(spacing: 0) {
                    ForEach(HomeTab.allCases, id: \.rawValue) { item in
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { tab = item.rawValue }
                        } label: {
                            ZStack {
                                if tab == item.rawValue {
                                    Capsule()
                                        .fill(LegadoTheme.accent.opacity(0.14))
                                        .frame(width: 52, height: 40)
                                }
                                Image(systemName: item.icon)
                                    .font(.system(size: 19, weight: tab == item.rawValue ? .semibold : .regular))
                                    .foregroundColor(tab == item.rawValue
                                                     ? LegadoTheme.accent
                                                     : LegadoTheme.secondaryText(scheme))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .frame(height: 48)
            }
            .frame(height: 48)

            Button {
                showSearch = true
            } label: {
                GlassSurface(cornerRadius: 24) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(LegadoTheme.primaryText(scheme))
                        .frame(width: 48, height: 48)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    // MARK: - 左侧抽屉

    @ViewBuilder
    private var drawerLayer: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if showDrawer {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) { showDrawer = false }
                        }
                    drawer
                        .frame(width: geo.size.width * 0.66)
                        .transition(.move(edge: .leading))
                }
            }
        }
        .ignoresSafeArea()
    }

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LegadoTheme.accent.opacity(0.16))
                    Image(systemName: "book.fill")
                        .font(.system(size: 18))
                        .foregroundColor(LegadoTheme.accent)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("阅读")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(LegadoTheme.primaryText(scheme))
                    Text(drawerSummary)
                        .font(.system(size: 13))
                        .foregroundColor(LegadoTheme.secondaryText(scheme))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)
            .padding(.bottom, 18)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(HomeTab.allCases, id: \.rawValue) { item in
                        Button {
                            tab = item.rawValue
                            withAnimation(.easeOut(duration: 0.18)) { showDrawer = false }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 18))
                                    .frame(width: 24)
                                Text(item.title)
                                    .font(.system(size: 17, weight: .semibold))
                                Spacer()
                            }
                            .foregroundColor(tab == item.rawValue
                                             ? LegadoTheme.accent
                                             : LegadoTheme.primaryText(scheme))
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Rectangle()
                        .fill(LegadoTheme.divider(scheme))
                        .frame(height: 0.5)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)

                    Button {
                        showDrawer = false
                        showSearch = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18))
                                .frame(width: 24)
                            Text("搜索")
                                .font(.system(size: 16))
                            Spacer()
                        }
                        .foregroundColor(LegadoTheme.secondaryText(scheme))
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 24)
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .ignoresSafeArea()
    }

    private var drawerSummary: String {
        let today = Calendar.current.startOfDay(for: Date())
        let readingToday = model.books.filter { $0.durChapterTime > 0
            && Date(timeIntervalSince1970: Double($0.durChapterTime) / 1000) >= today }.count
        return "书架 \(model.books.count) 本 · 今日在读 \(readingToday) 本"
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
        case .rss: return "RSS"
        case .stats: return "阅读统计"
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
