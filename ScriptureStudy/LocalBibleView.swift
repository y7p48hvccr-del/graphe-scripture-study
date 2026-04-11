import SwiftUI
struct LocalBibleView: View {

    @EnvironmentObject var myBible:          MyBibleService
    @EnvironmentObject var notesManager:      NotesManager
    @EnvironmentObject var bookmarksManager:  BookmarksManager
    @EnvironmentObject var bmapsService:      BMapsService
    @AppStorage("autoSummaryEnabled")   private var autoSummaryEnabled:  Bool = true
    @AppStorage("strongsFlashEnabled")   private var strongsFlashEnabled: Bool = true
    @AppStorage("showStatusHints")        private var showStatusHints:    Bool = true
    @EnvironmentObject var ollama:            OllamaService

    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("fontName") private var fontName:  String = ""
    @AppStorage("themeID")       private var themeID:      String = "light"
    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    var theme: AppTheme { AppTheme.find(themeID) }
    var filigreeAccent:     Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }
    var resolvedFont: Font {
        guard !fontName.isEmpty else { return .system(size: fontSize) }
        if !fontName.isEmpty {
            return .custom(fontName, size: fontSize)
        }
        return .system(size: fontSize)  // font not installed, use system
    }

    @AppStorage("lastBookNumber") private var selectedBookNumber = 470
    @AppStorage("lastChapter")    private var selectedChapter    = 1
    @State private var availableBooks:     [Int] = []
    @State private var chapterCount        = 28
    @State private var selectedVerse:      Int     = 0   // 0 = none selected
    @State private var isNavigatingToPassage: Bool = false
    @State private var showCompanion:      Bool    = true
    @State private var showComparison:     Bool    = false
    @State private var toastMessage:      String  = ""
    @State private var toastVisible:      Bool    = false
    @State private var toastIsProgress:   Bool    = false
    @State private var toastTimer:        Timer?
    @State private var scrollOffset:      CGFloat       = 0
    @State private var verseFrames:       [Int: CGFloat] = [:]

    var selectedBookName: String { myBibleBookNumbers[selectedBookNumber] ?? "Unknown" }

    var strongsModules: [MyBibleModule] {
        myBible.modules.filter { $0.type == .strongs }
    }

    // Verse numbers that have notes in this chapter
    var annotatedVerses: Set<Int> {
        Set(notesManager.notes.filter {
            $0.bookNumber == selectedBookNumber &&
            $0.chapterNumber == selectedChapter &&
            !$0.verseNumbers.isEmpty
        }.flatMap { $0.verseNumbers })
    }

    var body: some View {
        readingColumn
        .onAppear { loadAvailableBooks(); Task { await loadChapter() } }
        .onChange(of: myBible.selectedBible) { _ in
            loadAvailableBooks()
            Task { await loadChapter() }
        }
        .onChange(of: myBible.modules) { _ in
            // Modules just finished scanning — reload books if we have a Bible now
            if !myBible.modules.isEmpty {
                loadAvailableBooks()
                if !availableBooks.isEmpty { Task { await loadChapter() } }
            }
        }


        .onReceive(NotificationCenter.default.publisher(for: .navigateToPassage)) { note in
            guard let bn = note.userInfo?["bookNumber"] as? Int,
                  let ch = note.userInfo?["chapter"]    as? Int else { return }

            // Switch to the requested Bible module if specified
            if let moduleName = note.userInfo?["moduleName"] as? String {
                let match = myBible.modules.first(where: {
                    $0.type == .bible && $0.name == moduleName
                })
                if let match = match {
                    myBible.selectedBible = match
                }
            }

            // Refresh available books first so the book guard doesn't reset our target
            if let bible = myBible.selectedBible {
                availableBooks = myBible.availableBooks(in: bible)
            }

            // Set flag to prevent onAppear from resetting our target book
            isNavigatingToPassage = true

            // Navigate to book/chapter
            selectedBookNumber = bn
            selectedChapter    = ch
            updateChapterCount()

            // Highlight the specific verse if provided
            let targetVerse = note.userInfo?["verse"] as? Int ?? 0
            Task {
                await loadChapter()
                if targetVerse > 0 {
                    selectedVerse = targetVerse
                    NotificationCenter.default.post(
                        name: Notification.Name("verseSelected"),
                        object: nil,
                        userInfo: ["bookNumber": bn, "chapter": ch, "verse": targetVerse])

                }
                isNavigatingToPassage = false
            }
        }
    }

    // MARK: - Reading column (full width)

    private var readingColumn: some View {
        VStack(spacing: 0) {
            pickerBar
            Divider()
            Group {
                if myBible.selectedBible == nil          { noModulePrompt }
                else if myBible.isLoading                { loadingView }
                else if let error = myBible.errorMessage { errorView(error) }
                else if myBible.verses.isEmpty           { emptyPrompt }
                else                                     { readingAreaWithCompanion }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.background)
    }

    // MARK: - Picker bar (above Bible text)

    private var pickerBar: some View {
        HStack(spacing: 12) {
            // Bible picker — custom fixed-width button with popover list
            BiblePickerButton(
                modules: myBible.visibleModules.filter { $0.type == .bible },
                selected: Binding(
                    get: { myBible.selectedBible },
                    set: { newVal in
                        myBible.selectedBible = newVal
                        loadAvailableBooks()
                        Task { await loadChapter() }
                    }
                ),
                accent: filigreeAccent,
                textColor: theme.text
            )

            Divider().frame(height: 16)

            // Book picker
            Menu {
                ForEach(availableBooks, id: \.self) { bn in
                    Button(myBibleBookNumbers[bn] ?? "\(bn)") {
                        selectedBookNumber = bn
                    }
                }
            } label: {
                pickerLabel(selectedBookName, icon: "book.pages")
            .help("Choose book")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .onChange(of: selectedBookNumber) { _ in
                guard !isNavigatingToPassage else { return }
                selectedChapter = 1; updateChapterCount(); selectedVerse = 0
                Task { await loadChapter() }
            }

            Divider().frame(height: 16)

            // Chapter picker
            Menu {
                ForEach(1...max(chapterCount, 1), id: \.self) { ch in
                    Button("Chapter \(ch)") { selectedChapter = ch }
                }
            } label: {
                pickerLabel("Chapter \(selectedChapter)", icon: "list.number")
            .help("Choose chapter")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .onChange(of: selectedChapter) { _ in
                guard !isNavigatingToPassage else { return }
                selectedVerse = 0
                Task { await loadChapter() }
            }

            Spacer()

            // Comparison toggle
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showComparison.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text("Compare")
                        .font(.system(size: 11))
                        .foregroundStyle(showComparison ? filigreeAccent : Color.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(showComparison ? filigreeAccent : Color.secondary)
                    Image(systemName: showComparison ? "rectangle.split.1x2.fill" : "rectangle.split.1x2")
                        .font(.system(size: 13))
                        .foregroundStyle(showComparison ? filigreeAccent : Color.secondary)
                }
            }
            .buttonStyle(.plain)
            .help(showComparison ? "Hide comparison panel" : "Open comparison panel")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(theme.background)
    }

    private func pickerLabel(_ title: String, icon: String, fixedWidth: CGFloat? = nil) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(filigreeAccent)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: fixedWidth, alignment: .leading)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(filigreeAccent)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(theme.text.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Sidebar toggle tab

    // MARK: - Chapter view


    private var statusBar: some View {
        Group {
            if selectedVerse > 0 {
                HStack {
                    Text("Verse \(selectedVerse) selected")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("tap again to deselect  ·  long-press to add note")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(Color.platformWindowBg.opacity(0.95))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedVerse)
    }

    private var chapterView: some View {
        ZStack(alignment: .topTrailing) {
            // Hidden dependency on notes so view refreshes when notes change
            let _ = notesManager.notes.count
            // ── Reading scroll view ──
            ScrollViewReader { proxy in
            ScrollView {
                ScrollOffsetReader()
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(selectedBookName) \(selectedChapter)")
                            .font(.title.weight(.bold))
                            .foregroundStyle(theme.text)
                        if let bible = myBible.selectedBible {
                            Text(bible.name).font(.caption).foregroundStyle(theme.secondary)
                        }
                    }
                    .padding(.bottom, 20)

                    ForEach(myBible.verses) { verse in
                        let _ = annotatedVerses // observe changes
                        let isSelected  = selectedVerse == verse.verse
                        let hasNote     = annotatedVerses.contains(verse.verse)
                        let linkedNotes = notesManager.notes(
                            forBook: selectedBookNumber,
                            chapter: selectedChapter,
                            verse:   verse.verse
                        )
                        VerseWithStrongsView(
                            verse:         verse,
                            rawText:       myBible.rawVerseTexts[verse.verse] ?? verse.text,
                            strongsModule: myBible.selectedStrongs,
                            isSelected:    isSelected,
                            hasNote:       hasNote,
                            linkedNotes:   linkedNotes,
                            onTapVerseNum: {
                                selectedVerse = (selectedVerse == verse.verse) ? 0 : verse.verse
                                let bn = selectedBookNumber
                                let ch = selectedChapter
                                let sv = selectedVerse
                                NotificationCenter.default.post(
                                    name: Notification.Name("verseSelected"),
                                    object: nil,
                                    userInfo: ["bookNumber": bn, "chapter": ch, "verse": sv]
                                )
                            },
                            onLongPressVerseNum: {
                                createNoteForVerse(verse.verse)
                            }
                        )
                        .environmentObject(myBible)
                        .environmentObject(notesManager)
                        .environmentObject(bmapsService)
                        .padding(.bottom, 14)
                        .verseAnchor(verse.verse)
                        .id(verse.verse)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 12)
            }
            .coordinateSpace(name: "scrollCoordinate")
            .scrollIndicators(.hidden)
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                scrollOffset = offset
                broadcastTopVerse()
            }
            .onPreferenceChange(VerseFrameKey.self) { frames in
                verseFrames = frames
                broadcastTopVerse()
            }

            .onChange(of: selectedVerse) { v in
                if v > 0 { proxy.scrollTo(v, anchor: .top) }
            }
            } // end ScrollViewReader

            // ── Bookmark ribbon — thin, Kindle-style ──
            let isBookmarked = bookmarksManager.isBookmarked(
                book: selectedBookNumber, chapter: selectedChapter)

            Button {
                bookmarksManager.toggle(book: selectedBookNumber, chapter: selectedChapter)
            } label: {
                BookmarkRibbon()
                    .fill(isBookmarked
                          ? Color.red
                          : Color.gray.opacity(0.12))
                    .overlay(
                        BookmarkRibbon()
                            .stroke(isBookmarked
                                    ? Color.red.opacity(0.7)
                                    : Color.gray.opacity(0.25),
                                    lineWidth: 0.75)
                    )
                    .contentShape(BookmarkRibbon())
                    .frame(width: 16, height: 34)
                    .animation(.easeInOut(duration: 0.15), value: isBookmarked)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .padding(.trailing, 22)
            .help(isBookmarked ? "Remove bookmark" : "Bookmark this chapter")
        }
    }

    // MARK: - Full reading area with optional companion panel

    private var readingAreaWithCompanion: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Bible text + optional bottom comparison
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        chapterView
                        if showStatusHints { VStack { Spacer(); statusBar } }
                    }
                    if showComparison {
                        Divider()
                        ComparisonPanelView(
                            bookNumber:  selectedBookNumber,
                            chapter:     selectedChapter,
                            syncedVerse: selectedVerse,
                            onClose: { withAnimation(.easeInOut(duration: 0.25)) { showComparison = false } }
                        )
                        .frame(height: geo.size.height * 0.50)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(width: showCompanion ? geo.size.width / 2 : geo.size.width)

                if showCompanion {
                    Divider()
                    CompanionPanel(
                        bookNumber: selectedBookNumber,
                        chapter:    selectedChapter,
                        bookName:   selectedBookName
                    )
                    .frame(width: geo.size.width / 2)
                    .transition(.move(edge: .trailing))
                }
            }
        }
    }


    // MARK: - Empty states

    private var noModulePrompt: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "book.closed").font(.system(size: 48)).foregroundStyle(.quaternary)
            Text("No Bible module selected.\nGo to the Archives tab to add your modules.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) { Spacer(); ProgressView("Loading…"); Spacer() }
    }

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "book.closed").font(.system(size: 48)).foregroundStyle(.quaternary)
            Text("Select a book and chapter,\nthen tap Load Chapter.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
            Button("Try Again") { Task { await loadChapter() } }.buttonStyle(.bordered)
            Spacer()
        }
    }

    // MARK: - Actions

    private func createNoteForVerse(_ verseNum: Int) {
        let note = notesManager.createNote(
            bookNumber: selectedBookNumber,
            chapter:    selectedChapter,
            verses:     [verseNum]
        )
        // Open in Organizer editor via notification — stay on Bible tab
        NotificationCenter.default.post(
            name: Notification.Name("noteCreatedFromVerse"),
            object: nil,
            userInfo: ["note": note]
        )
    }

    private func createNoteForSelection() {
        guard selectedVerse > 0 else { return }
        let sortedVerses = [selectedVerse]
        let note = notesManager.createNote(
            bookNumber: selectedBookNumber,
            chapter:    selectedChapter,
            verses:     sortedVerses
        )
        selectedVerse = 0
        // Switch to Notes tab and open the new note
        NotificationCenter.default.post(
            name: .navigateToNote, object: nil,
            userInfo: ["noteID": note.id]
        )
        // Brief delay to let Notes tab respond before switching
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: Notification.Name("switchToNotesTab"), object: nil)
        }
    }



    private func broadcastTopVerse() {
        guard let topVerse = ScrollSyncManager.topVisibleVerse(
            scrollOffset: scrollOffset,
            verseFrames:  verseFrames
        ) else { return }
        NotificationCenter.default.post(
            name: Notification.Name("verseScrolledIntoView"),
            object: nil,
            userInfo: [
                "bookNumber": selectedBookNumber,
                "chapter":    selectedChapter,
                "verse":      topVerse
            ]
        )
    }

    private func loadAvailableBooks() {
        guard let bible = myBible.selectedBible else { return }
        availableBooks = myBible.availableBooks(in: bible)
        // Don't reset selectedBookNumber if we're navigating to a specific passage
        if !isNavigatingToPassage,
           !availableBooks.contains(selectedBookNumber),
           let first = availableBooks.first {
            selectedBookNumber = first
        }
        updateChapterCount()
    }

    private func updateChapterCount() {
        guard let bible = myBible.selectedBible else { return }
        chapterCount = myBible.chapterCount(module: bible, bookNumber: selectedBookNumber)
        if selectedChapter > chapterCount { selectedChapter = 1 }
    }

    private func showToast(_ message: String, isProgress: Bool, autoDismiss: Double = 0) {
        toastTimer?.invalidate()
        toastMessage    = message
        toastIsProgress = isProgress
        withAnimation { toastVisible = true }
        if autoDismiss > 0 {
            toastTimer = Timer.scheduledTimer(withTimeInterval: autoDismiss, repeats: false) { _ in
                withAnimation { self.toastVisible = false }
            }
        }
    }


    private func loadChapter() async {
        guard let bible = myBible.selectedBible else { return }
        verseFrames = [:]   // reset on new chapter
        await myBible.loadChapter(module: bible, bookNumber: selectedBookNumber, chapter: selectedChapter)

        // Flash Strong's words once per session if enabled
        if strongsFlashEnabled,
           myBible.selectedStrongs != nil,
           !myBible.verses.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NotificationCenter.default.post(name: Notification.Name("strongsFlashOn"), object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    NotificationCenter.default.post(name: Notification.Name("strongsFlashOff"), object: nil)
                }
            }
        }

        // Generate AI summary in background if enabled and Ollama/Claude available
        if autoSummaryEnabled && (ollama.ollamaReady || AnthropicService.shared.isConfigured) && !myBible.verses.isEmpty {
            let passage  = myBible.currentPassage
            let texts    = myBible.verses.map { "v\($0.verse): \($0.text)" }.joined(separator: "\n")
            if selectedChapter == 1 {
                // Chapter 1 — generate full book overview + chapter summary
                let book = selectedBookName
                Task { await ollama.generateBookAndChapterSummary(
                    bookName: book, passage: passage, verseTexts: texts) }
            } else {
                Task { await ollama.generateSummary(passage: passage, verseTexts: texts) }
            }
        }
    }
}
