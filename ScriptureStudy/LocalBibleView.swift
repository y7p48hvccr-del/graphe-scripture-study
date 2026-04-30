import SwiftUI
struct LocalBibleView: View {

    @EnvironmentObject var myBible:          MyBibleService
    @EnvironmentObject var notesManager:      NotesManager
    @EnvironmentObject var bookmarksManager:  BookmarksManager
    @EnvironmentObject var bmapsService:      BMapsService
    @AppStorage("autoSummaryEnabled")   private var autoSummaryEnabled:  Bool = true
    @AppStorage("strongsFlashEnabled")   private var strongsFlashEnabled: Bool = true
    @AppStorage("strongsOnlyFilter")      private var strongsOnly:          Bool = false
    @AppStorage("showStatusHints")        private var showStatusHints:    Bool = true
    @AppStorage("showGlossNotes")         private var showGlossNotes:     Bool = true
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

    // MARK: - Navigation history (session only)
    @State private var historyStack: [(book: Int, chapter: Int, verse: Int)] = []
    @State private var historyIndex: Int = -1
    @State private var suppressHistoryPush: Bool = false
    @State private var scrollToTopTrigger: UUID = UUID()

    private var canGoBack:    Bool { historyIndex > 0 }
    private var canGoForward: Bool { historyIndex < historyStack.count - 1 }

    var selectedBookName: String { myBibleBookNumbers[selectedBookNumber] ?? "Unknown" }

    var strongsModules: [MyBibleModule] {
        myBible.modules.filter { $0.type == .strongs }
    }

    // Verse numbers that have ACTIVE notes in this chapter. Archived
    // and trashed notes are excluded so the inline blue note icon in
    // the gutter correctly disappears when its last active note is
    // moved to Trash.
    var annotatedVerses: Set<Int> {
        Set(notesManager.notes.filter {
            !$0.isArchived &&
            $0.deletedAt == nil &&
            $0.bookNumber == selectedBookNumber &&
            $0.chapterNumber == selectedChapter &&
            !$0.verseNumbers.isEmpty
        }.flatMap { $0.verseNumbers })
    }

    // Verse numbers that have bookmarks in this chapter
    var bookmarkedVerseNumbers: Set<Int> {
        bookmarksManager.bookmarkedVerses(
            book: selectedBookNumber,
            chapter: selectedChapter)
    }

    // Pre-computed once per chapter — avoids calling notes(forBook:chapter:verse:)
    // inside the ForEach on every scroll frame. Excludes archived and
    // trashed notes.
    var linkedNotesMap: [Int: [Note]] {
        let chapterNotes = notesManager.notes.filter {
            !$0.isArchived &&
            $0.deletedAt == nil &&
            $0.bookNumber == selectedBookNumber &&
            $0.chapterNumber == selectedChapter
        }
        var map: [Int: [Note]] = [:]
        for note in chapterNotes {
            for v in note.verseNumbers {
                map[v, default: []].append(note)
            }
        }
        return map
    }

    var body: some View {
        readingColumn
        .onAppear {
            print("[STARTUP] LocalBibleView.onAppear")
            // Beachball fix 2026-04-21: the Bible tab reconstructs on
            // every tab switch back. Skip the expensive chapter/book
            // reload when the current state already matches what the
            // user was viewing. Without this guard, returning from any
            // other tab re-runs loadAvailableBooks + loadChapter (SQL
            // queries + potential AI summary regeneration), producing
            // a 1-3 second beachball for a no-op state.
            let needsBooks = availableBooks.isEmpty
            let needsChapter = myBible.verses.isEmpty
                || myBible.currentBookNumber != selectedBookNumber
                || myBible.currentChapter   != selectedChapter
            if needsBooks {
                loadAvailableBooks()
            }
            if needsChapter {
                Task { await loadChapter() }
            }
        }
        .onChange(of: myBible.selectedBible) { loadAvailableBooks()
            Task { await loadChapter() }
        }
        .onChange(of: myBible.modules) { // Modules just finished scanning — reload books if we have a Bible now
            if !myBible.modules.isEmpty {
                loadAvailableBooks()
                if !availableBooks.isEmpty { Task { await loadChapter() } }
            }
        }


        // Removed: .onReceive(createNoteForVerse). Previously the
        // VerseWithStrongsView popover posted a notification here that
        // this view listened for; SwiftUI's .onReceive accumulated
        // duplicate subscriptions over re-renders, causing one tap to
        // fire N times. Replaced with a direct onAddNote callback.

        .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("dictionaryWordTapped"))) { note in
            guard let word = note.userInfo?["word"] as? String else { return }
            NotificationCenter.default.post(
                name: Notification.Name("lookupDictionaryWord"),
                object: nil,
                userInfo: ["word": word]
            )
        }
        .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("encyclopediaWordTapped"))) { note in
            guard let word = note.userInfo?["word"] as? String else { return }
            NotificationCenter.default.post(
                name: Notification.Name("lookupEncyclopediaWord"),
                object: nil,
                userInfo: ["word": word]
            )
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
                modules: myBible.visibleModules.filter {
                    $0.type == .bible &&
                    (myBible.selectedLanguageFilter == "all" || myBible.selectedLanguageFilter.isEmpty || $0.language.lowercased() == myBible.selectedLanguageFilter) &&
                    (!strongsOnly || myBible.strongsFilePaths.contains($0.filePath))
                },
                selected: Binding(
                    get: { myBible.selectedBible },
                    set: { newVal in
                        myBible.selectedBible = newVal
                        loadAvailableBooks()
                        Task { await loadChapter() }
                    }
                ),
                accent: filigreeAccentFill,
                textColor: theme.text
            )

            // Strong's filter toggle
            Toggle(isOn: $strongsOnly) {
                Text("Strong's")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(filigreeAccentFill)
            .help(strongsOnly ? "Showing Strong's Bibles only" : "Filter to Strong's Bibles only")

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
            .onChange(of: selectedBookNumber) { guard !isNavigatingToPassage else { return }
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
            .onChange(of: selectedChapter) { guard !isNavigatingToPassage else { return }
                selectedVerse = 0
                Task { await loadChapter() }
            }

            Spacer()

            // ── History navigation ──────────────────────────────────
            if !historyStack.isEmpty {
                HStack(spacing: 2) {
                    Button { goBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(canGoBack ? filigreeAccent : Color.secondary.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoBack)
                    .help("Go back")

                    Menu {
                        ForEach(Array(historyStack.enumerated().reversed()), id: \.offset) { idx, entry in
                            Button {
                                navigateToHistoryIndex(idx)
                            } label: {
                                HStack {
                                    if idx == historyIndex {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(historyLabel(entry))
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                            .foregroundStyle(filigreeAccent)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Recent passages")

                    Button { goForward() } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(canGoForward ? filigreeAccent : Color.secondary.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoForward)
                    .help("Go forward")
                }
                .padding(.horizontal, 4)

                Divider().frame(height: 16)
            }


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
                    .id("chapterTop")

                    ForEach(myBible.verses) { verse in
                        let _ = annotatedVerses // observe changes
                        let _ = bookmarkedVerseNumbers  // observe changes
                        let isSelected  = selectedVerse == verse.verse
                        let hasNote     = annotatedVerses.contains(verse.verse)
                        let isVerseBookmarked = bookmarkedVerseNumbers.contains(verse.verse)
                        let linkedNotes = linkedNotesMap[verse.verse] ?? []
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            VerseWithStrongsView(
                                verse:         verse,
                                rawText:       myBible.rawVerseTexts[verse.verse] ?? verse.text,
                                strongsModule: myBible.selectedStrongs,
                                isSelected:    isSelected,
                                hasNote:       hasNote,
                                isBookmarked:  isVerseBookmarked,
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
                                },
                                onToggleBookmark: {
                                    bookmarksManager.toggle(
                                        book:    selectedBookNumber,
                                        chapter: selectedChapter,
                                        verse:   verse.verse)
                                },
                                onAddNote: {
                                    createNoteForVerse(verse.verse)
                                }
                            )
                            .environmentObject(myBible)
                            .environmentObject(notesManager)
                            .environmentObject(bmapsService)

                            // Translator's gloss-note indicator — one per verse.
                            // Tapping shows a popover listing every <n>...</n>
                            // note the translator included for that verse.
                            if showGlossNotes && !verse.glosses.isEmpty {
                                GlossNoteMarker(notes: verse.glosses)
                            }
                        }
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

            .onChange(of: selectedVerse) { _, v in
                if v > 0 { proxy.scrollTo(v, anchor: .top) }
            }
            .onChange(of: scrollToTopTrigger) { let v = historyStack[safe: historyIndex]?.verse ?? 0
                if v > 0 {
                    proxy.scrollTo(v, anchor: .top)
                } else {
                    proxy.scrollTo("chapterTop", anchor: .top)
                }
            }
            } // end ScrollViewReader

            // Kindle-style chapter ribbon removed — verse-level
            // bookmarks with inline ox-blood icons are now the sole
            // bookmark surface in the Bible reader. See the popover
            // "Bookmark Verse" action in VerseWithStrongsView, and
            // the inline icons rendered next to each verse number.
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
        print("[NOTE DEBUG] createNoteForVerse called: book=\(selectedBookNumber) ch=\(selectedChapter) v=\(verseNum)")
        let note = notesManager.createNote(
            bookNumber: selectedBookNumber,
            chapter:    selectedChapter,
            verses:     [verseNum]
        )
        print("[NOTE DEBUG] createNote returned note id=\(note.id) verseRef=\(note.verseReference)")
        print("[NOTE DEBUG] notesManager.notes.count after create = \(notesManager.notes.count)")
        print("[NOTE DEBUG] posting openNoteInCompanion for note \(note.id)")
        NotificationCenter.default.post(
            name: Notification.Name("openNoteInCompanion"),
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
        // Keep current history entry in sync with scroll position
        if historyStack.indices.contains(historyIndex) {
            historyStack[historyIndex].verse = topVerse
        }
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

    // MARK: - History

    private func pushHistory(book: Int, chapter: Int, verse: Int) {
        let entry = (book: book, chapter: chapter, verse: verse)
        // Don't push duplicate of current position
        if let current = historyStack[safe: historyIndex],
           current.book == book && current.chapter == chapter { return }
        // Truncate forward history when navigating to a new location
        if historyIndex < historyStack.count - 1 {
            historyStack = Array(historyStack.prefix(historyIndex + 1))
        }
        historyStack.append(entry)
        // Cap at 50 entries
        if historyStack.count > 50 {
            historyStack.removeFirst()
        }
        historyIndex = historyStack.count - 1
    }

    private func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        navigateToHistoryIndex(historyIndex)
    }

    private func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        navigateToHistoryIndex(historyIndex)
    }

    private func navigateToHistoryIndex(_ idx: Int) {
        guard historyStack.indices.contains(idx) else { return }
        let entry = historyStack[idx]
        historyIndex = idx
        suppressHistoryPush = true
        selectedBookNumber = entry.book
        selectedChapter    = entry.chapter
        selectedVerse      = entry.verse
        updateChapterCount()
        scrollToTopTrigger = UUID()
        Task { await loadChapter() }
    }

    private func historyLabel(_ entry: (book: Int, chapter: Int, verse: Int)) -> String {
        let bookName = myBibleBookNumbers[entry.book] ?? "?"
        if entry.verse > 0 { return "\(bookName) \(entry.chapter):\(entry.verse)" }
        return "\(bookName) \(entry.chapter)"
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
            toastTimer = Timer.scheduledTimer(withTimeInterval: autoDismiss, repeats: false) { _ in withAnimation { self.toastVisible = false }
            }
        }
    }


    private func loadChapter() async {
        guard let bible = myBible.selectedBible else { return }
        verseFrames = [:]   // reset on new chapter
        await myBible.loadChapter(module: bible, bookNumber: selectedBookNumber, chapter: selectedChapter)

        // Record in navigation history
        if !suppressHistoryPush {
            pushHistory(book: selectedBookNumber, chapter: selectedChapter, verse: selectedVerse)
        }
        suppressHistoryPush = false

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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Gloss note marker
//
// Small superscript indicator shown at the end of verses that contain one
// or more translator's notes (extracted from `<n>...</n>` tags). Tapping
// opens a popover listing every note for that verse. Deliberately
// unobtrusive — a single lowercase "n" styled as a superscript in the
// theme's accent colour.

struct GlossNoteMarker: View {
    let notes: [String]

    @AppStorage("themeID")       private var themeID:       String = "light"
    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("fontSize")      private var fontSize:      Double = 16

    private var accent: Color {
        resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID)
    }

    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Text("ⁿ")
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.leading, 3)
                .padding(.trailing, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(notes.count == 1 ? "Translator's note" : "\(notes.count) translator's notes")
        .popover(isPresented: $showingPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 10))
                        .foregroundStyle(accent)
                    Text("TRANSLATOR'S NOTE\(notes.count == 1 ? "" : "S")")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                        .tracking(1.2)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { idx, note in
                        if notes.count > 1 {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(idx + 1).")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                Text(note)
                                    .font(.system(size: 13))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text(note)
                                .font(.system(size: 13))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
            .frame(minWidth: 240, maxWidth: 360)
        }
    }
}
