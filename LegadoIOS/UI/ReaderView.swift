import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let book: Book
    @State private var currentIndex: Int
    @State private var chapters: [BookChapter] = []
    @State private var content: String = ""
    @State private var loading = false
    @State private var error: String?
    @State private var showToolbar = true
    @State private var showChapterList = false
    @State private var showSettings = false
    @State private var speaking = false

    init(book: Book, startIndex: Int) {
        self.book = book
        _currentIndex = State(initialValue: max(0, startIndex))
    }

    private var theme: ReaderTheme { model.readerConfig.theme }
    private var config: ReaderConfig { model.readerConfig }

    var body: some View {
        ZStack {
            Color(hex: theme.backgroundHex).ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 1).id("top")
                        if loading && content.isEmpty {
                            LoadingRow().padding(.top, 40)
                        } else if let error = error, content.isEmpty {
                            errorView(error)
                        } else {
                            chapterBody
                        }
                        footer
                    }
                    .padding(.horizontal, CGFloat(config.padding))
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
                .onChange(of: currentIndex) { _ in
                    proxy.scrollTo("top", anchor: .top)
                }
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showToolbar.toggle() }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            guard abs(dx) > 70, abs(dx) > abs(dy) * 1.5 else { return }
                            if dx < 0 {
                                load(index: currentIndex + 1)
                            } else {
                                load(index: currentIndex - 1)
                            }
                        }
                )
            }

            if showToolbar {
                overlays
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { prepare() }
        .onDisappear {
            saveProgress()
            SpeechManager.shared.stop()
        }
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

    // MARK: - 正文

    private var chapterBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(chapterTitle)
                .font(titleFont)
                .foregroundColor(Color(hex: theme.textHex))
                .padding(.bottom, 14)

            if let error = error, !content.isEmpty {
                ErrorBanner(message: error).padding(.bottom, 10)
            }

            LazyVStack(alignment: .leading, spacing: CGFloat(config.paragraphSpacing)) {
                ForEach(paragraphs.indices, id: \.self) { index in
                    Text(paragraphs[index])
                        .font(bodyFont)
                        .tracking(CGFloat(config.letterSpacing))
                        .lineSpacing(CGFloat(config.lineSpacing))
                        .foregroundColor(Color(hex: theme.textHex))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// 应用替换净化后的正文
    private var processedContent: String {
        let rules = model.replaceRules.filter { $0.enabled }
        guard !rules.isEmpty else { return content }
        return TextCleaner.applyReplaceRules(content, rules: rules)
    }

    private var bodyFont: Font {
        if config.fontFamily.isEmpty {
            return .system(size: CGFloat(config.fontSize))
        }
        return .custom(config.fontFamily, size: CGFloat(config.fontSize))
    }

    private var titleFont: Font {
        if config.fontFamily.isEmpty {
            return .system(size: CGFloat(config.fontSize) + 3, weight: .semibold)
        }
        return .custom(config.fontFamily, size: CGFloat(config.fontSize) + 3)
    }

    private var paragraphs: [String] {
        processedContent
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                if config.indent && !line.hasPrefix("　　") {
                    return "　　" + line
                }
                return line
            }
    }

    private var chapterTitle: String {
        if chapters.indices.contains(currentIndex) { return chapters[currentIndex].title }
        return book.durChapterTitle ?? book.name
    }

    private var footer: some View {
        VStack(spacing: 14) {
            if loading && !content.isEmpty {
                ProgressView()
            }
            HStack(spacing: 12) {
                Button {
                    load(index: currentIndex - 1)
                } label: {
                    Text("上一章").frame(maxWidth: .infinity)
                }
                .disabled(currentIndex <= 0)

                Button {
                    load(index: currentIndex + 1)
                } label: {
                    Text("下一章").frame(maxWidth: .infinity)
                }
                .disabled(currentIndex >= chapters.count - 1)
            }
            .font(.footnote)
            .buttonStyle(.bordered)
            .padding(.top, 20)

            Text("第 \(currentIndex + 1) / \(max(chapters.count, 1)) 章")
                .font(.caption2)
                .foregroundColor(Color(hex: theme.textHex).opacity(0.5))
                .padding(.top, 4)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ErrorBanner(message: message)
            Button("重试") { loadContent(index: currentIndex, force: true) }
        }
        .padding(.top, 30)
    }

    // MARK: - 覆盖层

    private var overlays: some View {
        VStack {
            topBar
            Spacer()
            bottomBar
        }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(book.name).font(.footnote).lineLimit(1)
                Text(chapterTitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                showChapterList = true
            } label: {
                Image(systemName: "list.bullet")
            }
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                barButton(icon: "list.bullet.rectangle", title: "目录") {
                    showChapterList = true
                }
                barButton(icon: speaking ? "speaker.wave.2.fill" : "speaker.wave.2", title: "朗读") {
                    toggleSpeech()
                }
                barButton(icon: "textformat.size", title: "排版") {
                    showSettings = true
                }
            }
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func barButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17))
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.primary)
        }
    }

    private func toggleSpeech() {
        if speaking {
            SpeechManager.shared.stop()
            speaking = false
        } else {
            guard !content.isEmpty else { return }
            speaking = true
            SpeechManager.shared.speak(content) {
                speaking = false
            }
        }
    }

    // MARK: - 数据

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

    private func load(index: Int) {
        guard index >= 0, index < chapters.count else { return }
        saveProgress(index: index)
        loadContent(index: index)
    }

    private func loadContent(index: Int, force: Bool = false) {
        currentIndex = index
        guard chapters.indices.contains(index) else { return }
        let chapter = chapters[index]
        if !force, let cached = Storage.loadContent(book.bookUrl, index: index) {
            content = cached
            error = nil
            saveProgress()
            return
        }
        if book.isLocal {
            do {
                content = try BookService.loadLocalContent(book: book, chapter: chapter)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
            saveProgress()
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
                let text = try await BookService.loadContent(book: book, chapter: chapter,
                                                             source: source, force: force)
                content = text
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
            saveProgress()
        }
    }

    private func saveProgress(index: Int? = nil) {
        var updated = book
        let idx = index ?? currentIndex
        updated.durChapterIndex = idx
        updated.durChapterTitle = chapters.indices.contains(idx) ? chapters[idx].title : nil
        updated.durChapterTime = Int64(Date().timeIntervalSince1970 * 1000)
        if model.isOnShelf(book.bookUrl) {
            model.updateBook(updated)
        }
    }
}

// MARK: - 目录选择

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
                    Slider(value: $model.readerConfig.lineSpacing, in: 0...20, step: 1)
                    Text("段落间隔 \(Int(model.readerConfig.paragraphSpacing))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $model.readerConfig.paragraphSpacing, in: 2...24, step: 1)
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
                                                        ? Color.accentColor : Color.secondary.opacity(0.3),
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
