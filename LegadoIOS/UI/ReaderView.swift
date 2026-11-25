import SwiftUI
import UIKit

/// 阅读器：仿「阅读」原版的翻页阅读 + 覆盖翻页动画
struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let book: Book

    @State private var currentIndex: Int
    @State private var chapters: [BookChapter] = []
    @State private var content: String = ""
    @State private var attributed: NSAttributedString?
    @State private var pages: [NSRange] = []
    @State private var pageIndex: Int = 0
    @State private var loading = false
    @State private var error: String?
    @State private var showChrome = true
    @State private var showChapterList = false
    @State private var showStyle = false
    @State private var jumpToLastPage = false
    @State private var pageSize: CGSize = .zero
    @State private var overlayRange: NSRange?
    @State private var overlayX: CGFloat = 0
    @State private var batteryLevel: Float = -1

    init(book: Book, startIndex: Int) {
        self.book = book
        _currentIndex = State(initialValue: max(0, startIndex))
    }

    private var theme: ReaderTheme { model.readerConfig.theme }
    private var config: ReaderConfig { model.readerConfig }
    private var textColor: Color { Color(hex: theme.textHex) }

    var body: some View {
        GeometryReader { geo in
            let width = max(120, geo.size.width - CGFloat(config.padding) * 2)
            let height = max(160, geo.size.height - 92)

            ZStack(alignment: .bottom) {
                Color(hex: theme.backgroundHex).ignoresSafeArea()

                pageLayer
                    .frame(width: width, height: height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .gesture(tapGesture(width: width))
                    .simultaneousGesture(swipeGesture)

                footer
                    .padding(.horizontal, CGFloat(config.padding))
                    .padding(.bottom, 4)

                if showChrome {
                    chrome
                }
            }
            .onAppear {
                pageSize = CGSize(width: width, height: height)
                UIDevice.current.isBatteryMonitoringEnabled = true
                batteryLevel = UIDevice.current.batteryLevel
                prepare()
            }
            .onChange(of: width) { newValue in
                pageSize = CGSize(width: newValue, height: height)
                rebuild()
            }
            .onChange(of: config) { _ in rebuild() }
        }
        .statusBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear { saveProgress() }
        .fullScreenCover(isPresented: $showChapterList) {
            ChapterListPage(book: book,
                            chapters: chapters,
                            currentIndex: currentIndex,
                            onSelect: { index in
                                showChapterList = false
                                load(index: index)
                            },
                            onClose: { showChapterList = false })
        }
        .sheet(isPresented: $showStyle) {
            ReaderStylePanel()
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 页面

    private var pageLayer: some View {
        ZStack(alignment: .topLeading) {
            if loading && content.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error, content.isEmpty {
                VStack(spacing: 12) {
                    ErrorBanner(message: error)
                    Button("重试") { loadContent(index: currentIndex) }
                }
                .padding()
            } else if let attributed = attributed, pages.indices.contains(pageIndex) {
                PageTextView(attributed: attributed, range: pages[pageIndex])
                if let overlay = overlayRange {
                    PageTextView(attributed: attributed, range: overlay)
                        .offset(x: overlayX)
                }
            }
        }
        .clipped()
    }

    private func tapGesture(width: CGFloat) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let x = value.location.x
                if x < width * 0.32 {
                    previousPage()
                } else if x > width * 0.68 {
                    nextPage()
                } else {
                    withAnimation(.easeInOut(duration: 0.18)) { showChrome.toggle() }
                }
            }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 50, abs(dx) > abs(value.translation.height) else { return }
                if dx < 0 { nextPage() } else { previousPage() }
            }
    }

    // MARK: - 底部状态条（电量 / 时间 / 页码 / 进度）

    private var footer: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 6) {
                Text(batteryText)
                Text(timeText(context.date))
                Spacer()
                if !pages.isEmpty {
                    Text("\(pageIndex + 1)/\(pages.count)")
                    Text(progressText)
                }
            }
            .font(.system(size: 10))
            .foregroundColor(textColor.opacity(0.5))
        }
    }

    private var batteryText: String {
        guard batteryLevel >= 0 else { return "--%" }
        return "\(Int(batteryLevel * 100))%"
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - 工具栏

    private var chrome: some View {
        VStack {
            topBar
            Spacer()
            bottomBar
        }
        .transition(.opacity)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                saveProgress()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
            }
            Text(chapterTitle)
                .font(.system(size: 15))
                .lineLimit(1)
            Spacer()
            Text(book.originName)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .foregroundColor(textColor)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color(hex: theme.backgroundHex).opacity(0.97))
        .overlay(alignment: .bottom) { Divider().opacity(0.25) }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    load(index: currentIndex - 1)
                } label: {
                    Text("上一章").font(.system(size: 12))
                }
                .disabled(currentIndex <= 0)

                Slider(value: pageBinding,
                       in: 0...Double(max(pages.count - 1, 1)),
                       step: 1)
                    .tint(textColor.opacity(0.8))
                    .disabled(pages.isEmpty)

                Button {
                    load(index: currentIndex + 1)
                } label: {
                    Text("下一章").font(.system(size: 12))
                }
                .disabled(currentIndex >= chapters.count - 1)
            }

            HStack(spacing: 0) {
                barButton("目录", "list.bullet") { showChapterList = true }
                barButton("界面", "textformat.size") { showStyle = true }
            }
        }
        .foregroundColor(textColor)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(Color(hex: theme.backgroundHex).opacity(0.97))
        .overlay(alignment: .top) { Divider().opacity(0.25) }
    }

    private func barButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17))
                Text(title).font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(textColor)
        }
    }

    private var pageBinding: Binding<Double> {
        Binding(
            get: { Double(pageIndex) },
            set: { value in
                guard !pages.isEmpty else { return }
                pageIndex = min(max(0, Int(value.rounded())), pages.count - 1)
                saveProgress()
            })
    }

    private var chapterTitle: String {
        if chapters.indices.contains(currentIndex) { return chapters[currentIndex].title }
        return book.durChapterTitle ?? book.name
    }

    private var progressText: String {
        guard !pages.isEmpty else { return "" }
        let chapterProgress = Double(pageIndex + 1) / Double(pages.count)
        let total = max(chapters.count, 1)
        let overall = (Double(currentIndex) + chapterProgress) / Double(total)
        return String(format: "%.2f%%", overall * 100)
    }

    // MARK: - 覆盖翻页

    private func nextPage() {
        guard !pages.isEmpty, overlayRange == nil else { return }
        if pageIndex + 1 < pages.count {
            let target = pageIndex + 1
            overlayRange = pages[target]
            overlayX = pageSize.width
            withAnimation(.easeOut(duration: 0.22)) { overlayX = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
                pageIndex = target
                overlayRange = nil
                saveProgress()
            }
        } else if currentIndex + 1 < chapters.count {
            load(index: currentIndex + 1)
        }
    }

    private func previousPage() {
        guard !pages.isEmpty, overlayRange == nil else { return }
        if pageIndex > 0 {
            let target = pageIndex - 1
            let current = pages[pageIndex]
            pageIndex = target
            overlayRange = current
            overlayX = 0
            withAnimation(.easeOut(duration: 0.22)) { overlayX = pageSize.width }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
                overlayRange = nil
                saveProgress()
            }
        } else if currentIndex > 0 {
            load(index: currentIndex - 1, lastPage: true)
        }
    }

    // MARK: - 数据

    private var processedContent: String {
        let rules = model.replaceRules.filter { $0.enabled }
        guard !rules.isEmpty else { return content }
        return TextCleaner.applyReplaceRules(content, rules: rules)
    }

    private func rebuild() {
        guard !content.isEmpty, pageSize.width > 0 else { return }
        let text = processedContent
        attributed = ReaderPaginator.attributedString(text, config: config)
        pages = ReaderPaginator.pages(text, config: config, size: pageSize)
        if jumpToLastPage {
            jumpToLastPage = false
            pageIndex = max(0, pages.count - 1)
        } else if let restored = restoredPageIndex() {
            pageIndex = min(restored, max(0, pages.count - 1))
        } else {
            pageIndex = min(pageIndex, max(0, pages.count - 1))
        }
    }

    private func restoredPageIndex() -> Int? {
        guard currentIndex == book.durChapterIndex, book.durChapterPos > 0,
              pages.count > 1 else { return nil }
        let ratio = Double(book.durChapterPos) / 1000.0
        return Int(ratio * Double(pages.count))
    }

    private func prepare() {
        let cached = Storage.loadChapters(book.bookUrl)
        if !cached.isEmpty {
            chapters = cached
            let index = min(max(0, currentIndex), cached.count - 1)
            loadContent(index: index)
        } else if book.isLocal {
            error = "本地书籍缺少目录，请重新导入"
        } else {
            guard let source = model.source(for: book) else {
                error = "找不到书源"
                return
            }
            loading = true
            Task { @MainActor in
                do {
                    let list = try await BookService.loadToc(book: book, source: source)
                    chapters = list
                    let index = min(max(0, currentIndex), max(0, list.count - 1))
                    loading = false
                    loadContent(index: index)
                } catch {
                    loading = false
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func load(index: Int, lastPage: Bool = false) {
        guard index >= 0, index < chapters.count else { return }
        saveProgress()
        jumpToLastPage = lastPage
        loadContent(index: index)
    }

    private func loadContent(index: Int) {
        currentIndex = index
        pageIndex = 0
        overlayRange = nil
        guard chapters.indices.contains(index) else { return }
        let chapter = chapters[index]

        if let cached = Storage.loadContent(book.bookUrl, index: index) {
            content = cached
            error = nil
            rebuild()
            saveProgress()
            return
        }

        if book.isLocal {
            do {
                content = try BookService.loadLocalContent(book: book, chapter: chapter)
                error = nil
                rebuild()
            } catch {
                self.error = error.localizedDescription
            }
            return
        }

        guard let source = model.source(for: book) else {
            error = "找不到书源"
            return
        }
        loading = true
        content = ""
        Task { @MainActor in
            do {
                let text = try await BookService.loadContent(book: book, chapter: chapter, source: source)
                content = text
                error = nil
                rebuild()
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
            saveProgress()
        }
    }

    private func saveProgress() {
        var updated = book
        updated.durChapterIndex = currentIndex
        updated.durChapterTitle = chapters.indices.contains(currentIndex) ? chapters[currentIndex].title : nil
        updated.durChapterTime = Int64(Date().timeIntervalSince1970 * 1000)
        if !pages.isEmpty {
            updated.durChapterPos = Int(Double(pageIndex) / Double(pages.count) * 1000)
        }
        if model.isOnShelf(book.bookUrl) {
            model.updateBook(updated)
        }
    }
}
