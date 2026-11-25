import SwiftUI

/// 阅读器：仿「阅读」原版的翻页阅读
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
    @State private var showSettings = false
    @State private var jumpToLastPage = false
    @State private var pageSize: CGSize = .zero

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
            let height = max(160, geo.size.height - 96)

            ZStack {
                Color(hex: theme.backgroundHex).ignoresSafeArea()

                pageLayer
                    .frame(width: width, height: height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .gesture(tapGesture(width: width))
                    .simultaneousGesture(swipeGesture)

                pageHeader
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)

                pageFooter
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)

                if showChrome {
                    chrome
                }
            }
            .onAppear {
                pageSize = CGSize(width: width, height: height)
                prepare()
            }
            .onChange(of: width) { newValue in
                pageSize = CGSize(width: newValue, height: height)
                rebuild()
            }
            .onChange(of: config) { _ in
                rebuild()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { saveProgress() }
        .sheet(isPresented: $showChapterList) {
            ChapterPickerView(chapters: chapters, currentIndex: currentIndex) { index in
                showChapterList = false
                load(index: index)
            }
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsView()
        }
    }

    // MARK: - 页面

    @ViewBuilder
    private var pageLayer: some View {
        if loading && content.isEmpty {
            ProgressView()
        } else if let error = error, content.isEmpty {
            VStack(spacing: 12) {
                ErrorBanner(message: error)
                Button("重试") { loadContent(index: currentIndex) }
            }
            .padding()
        } else if let attributed = attributed, pages.indices.contains(pageIndex) {
            PageTextView(attributed: attributed, range: pages[pageIndex])
        } else {
            Color.clear
        }
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

    // MARK: - 顶部 / 底部

    private var chrome: some View {
        VStack {
            topBar
            Spacer()
            bottomBar
        }
        .transition(.opacity)
    }

    private var pageHeader: some View {
        HStack(spacing: 8) {
            Text(chapterTitle)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            Text(book.name)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundColor(textColor.opacity(0.45))
        .padding(.horizontal, CGFloat(config.padding))
        .padding(.top, 10)
    }

    private var pageFooter: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                Text(timeText(context.date))
                Spacer()
                if !pages.isEmpty {
                    Text("\(pageIndex + 1)/\(pages.count)")
                    Text(progressText)
                }
            }
            .font(.system(size: 10))
            .foregroundColor(textColor.opacity(0.45))
            .padding(.horizontal, CGFloat(config.padding))
            .padding(.bottom, 12)
        }
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    load(index: currentIndex - 1)
                } label: {
                    Text("上一章").font(.system(size: 12))
                }
                .disabled(currentIndex <= 0)

                Slider(value: chapterBinding, in: 0...Double(max(chapters.count - 1, 1)), step: 1)
                    .tint(textColor.opacity(0.8))

                Button {
                    load(index: currentIndex + 1)
                } label: {
                    Text("下一章").font(.system(size: 12))
                }
                .disabled(currentIndex >= chapters.count - 1)
            }

            HStack(spacing: 0) {
                barButton("目录", "list.bullet") { showChapterList = true }
                barButton("界面", "textformat.size") { showSettings = true }
                barButton(theme.isDark ? "日间" : "夜间",
                          theme.isDark ? "sun.max" : "moon") {
                    model.readerConfig.theme = theme.isDark ? .paper : .dark
                    model.saveReaderConfig()
                }
                barButton("设置", "gearshape") { showSettings = true }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(Color(hex: theme.backgroundHex).opacity(0.97))
        .overlay(alignment: .top) { Divider().opacity(0.25) }
    }

    private func barButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 16))
                Text(title).font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(textColor)
        }
    }

    private var chapterBinding: Binding<Double> {
        Binding(
            get: { Double(currentIndex) },
            set: { value in
                let index = Int(value.rounded())
                if index != currentIndex { load(index: index) }
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
        return String(format: "%.1f%%", overall * 100)
    }

    // MARK: - 翻页

    private func nextPage() {
        if pageIndex + 1 < pages.count {
            pageIndex += 1
            saveProgress()
        } else if currentIndex + 1 < chapters.count {
            load(index: currentIndex + 1)
        }
    }

    private func previousPage() {
        if pageIndex > 0 {
            pageIndex -= 1
            saveProgress()
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

    /// 打开时按 durChapterPos 恢复页内位置
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

// MARK: - 目录

struct ChapterPickerView: View {
    let chapters: [BookChapter]
    let currentIndex: Int
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ascending = true

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleChapters) { chapter in
                    Button {
                        onSelect(chapter.index)
                        dismiss()
                    } label: {
                        HStack {
                            Text(chapter.title)
                                .font(.subheadline)
                                .foregroundColor(chapter.index == currentIndex ? .accentColor : .primary)
                                .lineLimit(2)
                            Spacer()
                            if chapter.index == currentIndex {
                                Image(systemName: "chevron.left")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(chapter.index == currentIndex
                                       ? Color.accentColor.opacity(0.08) : Color.clear)
                }
            }
            .listStyle(.plain)
            .navigationTitle("目录（\(chapters.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(ascending ? "倒序" : "正序") { ascending.toggle() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var visibleChapters: [BookChapter] {
        ascending ? chapters : Array(chapters.reversed())
    }
}

// MARK: - 排版设置

struct ReaderSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("字体") {
                    Picker("字体", selection: $model.readerConfig.fontFamily) {
                        Text("系统").tag("")
                        Text("宋体").tag("Songti SC")
                        Text("黑体").tag("PingFang SC")
                        Text("楷体").tag("Kaiti SC")
                        Text("圆体").tag("Yuanti SC")
                    }
                    HStack {
                        Text("字间距")
                        Slider(value: $model.readerConfig.letterSpacing, in: 0...3, step: 0.2)
                    }
                }
                Section("字号") {
                    HStack {
                        Image(systemName: "textformat.size.smaller")
                        Slider(value: $model.readerConfig.fontSize, in: 14...30, step: 1)
                        Image(systemName: "textformat.size.larger")
                    }
                    Text("当前 \(Int(model.readerConfig.fontSize))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section("行距") {
                    HStack {
                        Text("行距")
                        Slider(value: $model.readerConfig.lineSpacing, in: 0...20, step: 1)
                    }
                    HStack {
                        Text("段距")
                        Slider(value: $model.readerConfig.paragraphSpacing, in: 2...24, step: 1)
                    }
                }
                Section("排版") {
                    Toggle("段首缩进", isOn: $model.readerConfig.indent)
                    HStack {
                        Text("页边距")
                        Slider(value: $model.readerConfig.padding, in: 8...40, step: 1)
                    }
                }
                Section("主题") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Button {
                                model.readerConfig.theme = theme
                            } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(hex: theme.backgroundHex))
                                        .frame(height: 44)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(model.readerConfig.theme == theme
                                                        ? Color.accentColor
                                                        : Color.secondary.opacity(0.3),
                                                        lineWidth: model.readerConfig.theme == theme ? 2 : 0.5)
                                        )
                                        .overlay(
                                            Text("文")
                                                .foregroundColor(Color(hex: theme.textHex))
                                        )
                                    Text(theme.name)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("排版")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        model.saveReaderConfig()
                        dismiss()
                    }
                }
            }
            .onDisappear { model.saveReaderConfig() }
        }
    }
}
