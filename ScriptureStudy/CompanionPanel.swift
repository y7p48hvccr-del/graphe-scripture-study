import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#endif

enum CompanionMode: String, CaseIterable {
    case commentary   = "Commentary"
    case strongs      = "Dictionaries"
    case encyclopedia = "Encyclopedia"
    case interlinear  = "Interlinear"
    case notes        = "Notes"
    case timeline     = "Timeline"
    case maps         = "Maps"
    case web          = "Web"
}

/// Which slice of the unified saved list is visible. Active is the
/// default; Archived shows notes the user has tucked away; Trash
/// shows items pending permanent deletion (kept forever until the
/// user empties the Trash).
enum SavedView: String, CaseIterable {
    case active   = "Active"
    case archived = "Archived"
    case trash    = "Trash"
}

/// Filter for the unified Notes tab list. Drives the three pills
/// (All / Notes / Bookmarks) at the top of the list.
enum SavedFilter: String, CaseIterable {
    case all       = "All"
    case notes     = "Notes"
    case bookmarks = "Bookmarks"
}

/// Lightweight identity for a specific verse — used as the Notes tab's
/// optional verse filter when the user wants to see only notes for one
/// passage (via the inline note icon or the popover "Make a Note"
/// action).
struct VerseKey: Equatable {
    let bookNumber: Int
    let chapter:    Int
    let verse:      Int

    var displayTitle: String {
        let bookName = myBibleBookNumbers[bookNumber] ?? "Unknown"
        return "\(bookName) \(chapter):\(verse)"
    }
}

/// Unified list entry — either a Note or a Bookmark, surfaced in a
/// single scrollable list under the Notes tab. Both types are sorted
/// by their mutation date (updatedAt for notes, addedAt for bookmarks).
enum SavedEntry: Identifiable {
    case note(Note)
    case bookmark(Bookmark)

    var id: String {
        switch self {
        case .note(let n):     return "note_\(n.id.uuidString)"
        case .bookmark(let b): return "bookmark_\(b.id.uuidString)"
        }
    }

    var sortDate: Date {
        switch self {
        case .note(let n):     return n.updatedAt
        case .bookmark(let b): return b.addedAt
        }
    }
}

struct CompanionPanel: View {

    @EnvironmentObject var myBible:          MyBibleService
    @EnvironmentObject var notesManager:     NotesManager
    @EnvironmentObject var bmapsService:     BMapsService
    @EnvironmentObject var bookmarksManager: BookmarksManager

    @AppStorage("companionMode")      private var modeRaw:           String = CompanionMode.commentary.rawValue
    @AppStorage("companionBiblePath") private var companionBiblePath: String = ""
    @AppStorage("fontSize")           private var fontSize:           Double = 16
    @AppStorage("fontName")           private var fontName:           String = ""
    @AppStorage("themeID")            private var themeID:            String = "light"
    @AppStorage("filigreeColor")      private var filigreeColor:      Int    = 0
    @AppStorage("companionWebSite")   private var companionWebSiteID: String = "blueletterbible"

    var mode: CompanionMode {
        get { CompanionMode(rawValue: modeRaw) ?? .commentary }
        set { modeRaw = newValue.rawValue }
    }

    var theme:          AppTheme { AppTheme.find(themeID) }
    var filigreeAccent:     Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }
    var resolvedFont:   Font {
        guard !fontName.isEmpty
        else { return .system(size: fontSize) }
        return .custom(fontName, size: fontSize)
    }

    let bookNumber: Int
    let chapter:    Int
    let bookName:   String

    @State private var companionVerses:   [MyBibleVerse]    = []
    @State private var companionModule:   MyBibleModule?
    @State private var commentaryEntries: [CommentaryEntry] = []
    // commentaryModule now lives on myBible.selectedCommentary for cross-view access
    private var commentaryModule: MyBibleModule? {
        get { myBible.selectedCommentary }
        nonmutating set { myBible.selectedCommentary = newValue }
    }
    @State private var isLoading         = false
    @State private var syncedVerse:       Int               = 0
    @State private var syncScrollVerse:    Int               = 0

    // Strong's
    @State private var verseNoteIDs:      [UUID]            = []
    @State private var noteSearchText:    String            = ""
    @State private var selectedVerseNoteID: UUID?            = nil
    /// Active filter for the unified Notes tab list: all, notes only,
    /// or bookmarks only. Three filter pills at the top of the Notes
    /// tab let the user switch.
    @State private var savedFilter:       SavedFilter       = .all
    /// When set, the Notes tab list is filtered to notes attached to
    /// this specific verse. Set by the "Make a Note" popover action and
    /// the inline note icon — both post showNotesForVerse. Cleared via
    /// a "Back to all notes" button at the top of the list.
    @State private var verseFilter:       VerseKey?         = nil
    /// Which view of the saved list is shown: Active, Archived, or
    /// Trash. Toggled via the bottom-of-list toggles.
    @State private var savedView:         SavedView         = .active
    /// When true, the Notes tab list is in multi-select mode:
    /// checkboxes beside each row, action bar at bottom with Delete
    /// and (notes-only) Archive. Toggled by the Select/Done button.
    @State private var isSelectMode:      Bool              = false
    /// IDs of the currently-selected items in multi-select mode. String
    /// keys match SavedEntry.id so both note and bookmark selections
    /// coexist in one Set.
    @State private var selectedIDs:       Set<String>       = []
    /// Bulk-delete confirmation dialog state.
    @State private var showBulkDeleteConfirm: Bool          = false
    /// Single-bookmark delete confirmation dialog state (individual
    /// bookmark delete is permanent per design).
    @State private var pendingBookmarkDelete: Bookmark?     = nil
    /// Single-note delete confirmation dialog state (individual note
    /// delete goes to Trash per design, with warning).
    @State private var pendingNoteDelete:     Note?         = nil
    /// Empty Trash confirmation dialog state.
    @State private var showEmptyTrashConfirm: Bool          = false
    @State private var crossRefGroups:    [MyBibleService.CrossRefGroup] = []
    @State private var crossRefIsLoading: Bool              = false
    @State private var crossRefTarget:    MyBibleService.CrossRefEntry? = nil
    @State private var xrefBook:          Int?              = nil  // override for cross-ref navigation
    @State private var xrefChapter:       Int?              = nil
    @State private var xrefVerse:         Int               = 0    // verse to highlight in cross-ref passage
    // Live-filtered so deletions reflect immediately
    private var verseNotes: [Note] { notesManager.notes.filter { verseNoteIDs.contains($0.id) } }
    private var selectedVerseNote: Note? {
        guard let id = selectedVerseNoteID else { return nil }
        return notesManager.notes.first(where: { $0.id == id })
    }
    @State private var strongsNumber:    String            = ""
    @State private var strongsEntry:     StrongsEntry?     = nil
    @State private var strongsIsLoading: Bool              = false
    @State private var selectedStrongsVerseTarget: VerseLinkTarget? = nil
    @State private var strongsBackStack: [String]          = []
    @State private var strongsForwardStack: [String]       = []

    // Dictionary / clipboard
    @State private var dictWord:         String            = ""
    @State private var dictDefinition:   String?           = nil
    @State private var dictIsLoading:    Bool              = false
    @State private var encycWord:        String            = ""
    @State private var encycDefinition:  String?           = nil
    @State private var encycDefinitionHTML: String?        = nil
    @State private var encycIsLoading:   Bool              = false
    @State private var pbCount:          Int               = 0

    var selectedWebSite: BibleWebSite {
        bibleWebSites.first { $0.id == companionWebSiteID } ?? bibleWebSites[0]
    }

    var bibleModules:      [MyBibleModule] { myBible.visibleModules.filter { $0.type == .bible } }
    var commentaryModules: [MyBibleModule] { myBible.visibleModules.filter { $0.type == .commentary && (myBible.selectedLanguageFilter.isEmpty || $0.language.lowercased() == myBible.selectedLanguageFilter) } }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            modeBar
            Divider()
            moduleBar
            Divider()
            contentArea
        }
        .onAppear {
            load()
            #if os(macOS)
            pbCount = NSPasteboard.general.changeCount
            #endif
        }
        .onChange(of: bookNumber) { syncedVerse = 0; syncScrollVerse = 0; verseNoteIDs = []; crossRefGroups = []; xrefBook = nil; xrefChapter = nil; xrefVerse = 0; load() }
        .onChange(of: chapter)    { syncedVerse = 0; syncScrollVerse = 0; verseNoteIDs = []; crossRefGroups = []; xrefBook = nil; xrefChapter = nil; xrefVerse = 0; load() }
        .onChange(of: myBible.selectedDictionary) { _, _ in
                guard !dictWord.isEmpty else { return }
            dictDefinition = nil
            dictIsLoading  = true
            let word    = dictWord
            let service = myBible
            Task {
                let result = await service.lookupDictionaryWord(word: word)
                await MainActor.run {
                    dictWord       = result?.topic ?? word
                    dictDefinition = result?.definition
                    dictIsLoading  = false
                }
            }
        }
        .onChange(of: myBible.selectedEncyclopedia) { _, _ in
                guard !encycWord.isEmpty else { return }
            encycDefinition = nil
            encycDefinitionHTML = nil
            encycIsLoading  = true
            let word    = encycWord
            let service = myBible
            Task {
                let result = await service.lookupLinkedWord(word: word, in: service.selectedEncyclopedia)
                await MainActor.run {
                    encycWord       = result?.topic ?? word
                    encycDefinition = result?.definition
                    encycDefinitionHTML = result?.definition
                    encycIsLoading  = false
                }
            }
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in checkClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("switchCompanionToCommentary"))) { _ in
            modeRaw = CompanionMode.commentary.rawValue
        }
        .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("lookupDictionaryWord"))) { note in
            guard let word = note.userInfo?["word"] as? String else { return }
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            guard clean.count >= 2 else { return }
            dictWord       = clean
            dictDefinition = nil
            dictIsLoading  = true
            modeRaw        = CompanionMode.strongs.rawValue
            let service    = myBible
            Task {
                let result = await service.lookupDictionaryWord(word: clean)
                await MainActor.run {
                    dictWord       = result?.topic ?? clean
                    dictDefinition = result?.definition
                    dictIsLoading  = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("lookupEncyclopediaWord"))) { note in
            guard let word = note.userInfo?["word"] as? String else { return }
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            guard clean.count >= 2 else { return }
            encycWord       = clean
            encycDefinition = nil
            encycDefinitionHTML = nil
            encycIsLoading  = true
            modeRaw         = CompanionMode.encyclopedia.rawValue
            let service     = myBible
            Task {
                let result = await service.lookupLinkedWord(word: clean, in: service.selectedEncyclopedia)
                await MainActor.run {
                    encycWord       = result?.topic ?? clean
                    encycDefinition = result?.definition
                    encycDefinitionHTML = result?.definition
                    encycIsLoading  = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("showNotesForVerse"))) { notification in
            // Triggered by:
            //  - Tapping the inline blue note icon next to a verse
            //  - Tapping "Make a Note" in the verse popover
            // Switches to the Notes tab, sets the verse filter so the
            // list shows only notes for this verse (plus "+ New note"),
            // and clears any previous single-note drill-in.
            guard let bn = notification.userInfo?["bookNumber"] as? Int,
                  let ch = notification.userInfo?["chapter"]    as? Int,
                  let vs = notification.userInfo?["verse"]      as? Int
                  else { return }
            verseFilter       = VerseKey(bookNumber: bn, chapter: ch, verse: vs)
            savedFilter       = .notes
            selectedVerseNoteID = nil
            modeRaw           = CompanionMode.notes.rawValue
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("openNoteInCompanion"))) { notification in
            // Triggered by the popover "Make a Note" action after
            // creating a new note. Opens the note in the Notes-tab
            // drill-in editor without leaving the Bible tab.
            guard let note = notification.userInfo?["note"] as? Note else {
                return
            }
            selectedVerseNoteID = note.id
            savedView         = .active
            verseFilter       = nil
            modeRaw           = CompanionMode.notes.rawValue
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("strongsTapped"))) { note in
            guard let num = note.userInfo?["number"] as? String else { return }
            let bookNum      = note.userInfo?["bookNumber"] as? Int ?? 0
            modeRaw          = CompanionMode.strongs.rawValue
            let isOT = bookNum > 0 ? bookNum < 470 : !num.hasPrefix("G")
            loadStrongs(number: num, isOldTestament: isOT, pushHistory: false, clearForwardHistory: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("verseScrolledIntoView"))) { note in
            // Don't sync scroll if comparison is showing a cross-ref passage
            guard mode == .commentary, xrefBook == nil,
                  let bn = note.userInfo?["bookNumber"] as? Int,
                  let ch = note.userInfo?["chapter"]    as? Int,
                  let vs = note.userInfo?["verse"]      as? Int,
                  bn == bookNumber, ch == chapter else { return }
            syncScrollVerse = vs
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("showPlaceOnMap"))) { note in
            guard let name = note.userInfo?["placeName"] as? String else { return }
            modeRaw = CompanionMode.maps.rawValue
            // Small delay so the Maps tab is mounted before we post the search
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(
                    name: Notification.Name("mapsSearchPlace"),
                    object: nil,
                    userInfo: ["placeName": name]
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("verseSelected"))) { note in
            guard let bn = note.userInfo?["bookNumber"] as? Int,
                  let ch = note.userInfo?["chapter"]    as? Int,
                  let vs = note.userInfo?["verse"]      as? Int,
                  bn == bookNumber, ch == chapter else { return }
            // Tapping a verse in the main panel clears any cross-ref override
            xrefBook = nil; xrefChapter = nil; xrefVerse = 0; crossRefTarget = nil
            syncedVerse = vs
            if vs > 0 {
                crossRefIsLoading = true
                Task { @MainActor in
                    let groups = await myBible.lookupCrossReferences(book: bn, chapter: ch, verse: vs)
                    crossRefGroups    = groups
                    crossRefIsLoading = false
                }
            }
        }
    }


    // MARK: - Dictionary pickers (extracted so Swift can infer generic types)

    private var strongsPicker: some View {
        let modules = myBible.visibleModules.filter { $0.type == .strongs && (myBible.selectedLanguageFilter.isEmpty || $0.language.lowercased() == myBible.selectedLanguageFilter) }
        let label   = myBible.selectedStrongs?.name ?? "None"
        return Menu {
            Button("None") { myBible.selectedStrongs = nil }
            Divider()
            ForEach(modules) { m in
                Button(m.name) { myBible.selectedStrongs = m }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.background)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(theme.background.opacity(0.7))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(theme.background.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .menuStyle(.borderlessButton)
    }

    private var dictionaryPicker: some View {
        let modules = myBible.visibleModules.filter { $0.type == .dictionary && (myBible.selectedLanguageFilter.isEmpty || $0.language.lowercased() == myBible.selectedLanguageFilter) }
        let label   = myBible.selectedDictionary?.name ?? "None"
        return Menu {
            Button("None") { myBible.selectedDictionary = nil }
            Divider()
            ForEach(modules) { m in
                Button(m.name) { myBible.selectedDictionary = m }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.background)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(theme.background.opacity(0.7))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(theme.background.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .menuStyle(.borderlessButton)
    }

    private var encyclopediaPicker: some View {
        let modules = myBible.visibleModules.filter { $0.type == .encyclopedia && (myBible.selectedLanguageFilter.isEmpty || $0.language.lowercased() == myBible.selectedLanguageFilter) }
        let label   = myBible.selectedEncyclopedia?.name ?? "None"
        return Menu {
            Button("None") { myBible.selectedEncyclopedia = nil }
            Divider()
            ForEach(modules) { m in
                Button(m.name) { myBible.selectedEncyclopedia = m }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.background)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(theme.background.opacity(0.7))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(theme.background.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Cross References panel

    private var crossRefPicker: some View {
        let mods = myBible.modules.filter {
            $0.type == .crossRef || $0.type == .crossRefNative
        }
        let label = myBible.selectedCrossRef?.name ?? "None"
        return Menu {
            Button("None") { myBible.selectedCrossRef = nil }
            Divider()
            ForEach(mods) { m in
                Button(m.name) {
                    myBible.selectedCrossRef = m
                    // Reload cross refs for current verse
                    if syncedVerse > 0 {
                        crossRefIsLoading = true
                        let book = bookNumber; let ch = chapter; let vs = syncedVerse
                        Task { @MainActor in
                            let groups = await myBible.lookupCrossReferences(book: book, chapter: ch, verse: vs)
                            crossRefGroups    = groups
                            crossRefIsLoading = false
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(filigreeAccent)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(theme.text.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .menuStyle(.borderlessButton)
    }

    private var crossRefsView: some View {
        Group {
            if myBible.selectedCrossRef == nil {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 36)).foregroundStyle(.quaternary)
                    Text("No cross-reference module selected — go to the Archives tab to install one, then use the picker above to select it")
                        .foregroundStyle(.secondary)
                    Text("Add a cross-reference module to your modules folder.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            } else if crossRefIsLoading {
                VStack { Spacer(); ProgressView("Loading…"); Spacer() }
            } else if crossRefGroups.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 36)).foregroundStyle(.quaternary)
                    Text(syncedVerse > 0
                         ? "No cross-references for this verse"
                         : "Tap a verse number to see cross-references")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Verse header
                        HStack {
                            Text("Cross-references — verse \(syncedVerse)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.background)
                            Spacer()
                            Text("\(crossRefGroups.flatMap(\.references).count) refs")
                                .font(.caption2)
                                .foregroundStyle(theme.background.opacity(0.7))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(filigreeAccentFill)

                        Divider()

                        ForEach(Array(crossRefGroups.enumerated()), id: \.offset) { _, group in
                            VStack(alignment: .leading, spacing: 6) {
                                // Keyword header
                                if let kw = group.keyword, !kw.isEmpty {
                                    let isReciprocal = kw.lowercased() == "reciprocal"
                                    let isRelated    = ["related", "secondary"].contains(kw.lowercased())
                                    if isReciprocal || isRelated { Divider().padding(.vertical, 4) }
                                    Text(kw)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(isRelated || isReciprocal ? .secondary : filigreeAccent)
                                        .padding(.top, isReciprocal || isRelated ? 0 : 10)
                                        .padding(.horizontal, 12)
                                }

                                // Reference chips
                                FlowLayout(hSpacing: 6, vSpacing: 6) {
                                    ForEach(Array(group.references.enumerated()), id: \.offset) { _, ref in
                                        Button {
                                            navigateToCrossRef(ref)
                                        } label: {
                                            Text(ref.display)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(filigreeAccent)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(filigreeAccent.opacity(0.10))
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(filigreeAccent.opacity(0.3), lineWidth: 0.5)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .help("Open \(ref.display) in comparison panel")
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                        }

                        Spacer().frame(height: 20)
                    }
                }
                .background(theme.background)
            }
        }
    }

    private func navigateToCrossRef(_ ref: MyBibleService.CrossRefEntry) {
        if companionModule == nil {
            companionModule = myBible.visibleModules.first(where: { $0.type == .bible })
        }
        xrefBook    = ref.bookNumber
        xrefChapter = ref.chapter
        xrefVerse   = ref.verseStart
        crossRefTarget = ref
        modeRaw = CompanionMode.commentary.rawValue
        load()
    }

    // MARK: - Notes panel

    private var verseNotesView: some View {
        VStack(spacing: 0) {
            if let note = selectedVerseNote {
                // ── Single note view (from verse tap) ──────────────
                HStack {
                    Button {
                        selectedVerseNoteID = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("All Notes")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(filigreeAccent)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        pendingNoteDelete = note
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Move to Trash")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(theme.background)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(noteHeading(note))
                        .font(resolvedFont.weight(.semibold))
                        .foregroundStyle(theme.text)
                    if !note.verseReference.isEmpty {
                        Button {
                            var userInfo: [String: Any] = [
                                "bookNumber": note.bookNumber,
                                "chapter": note.chapterNumber
                            ]
                            if let verse = note.verseNumbers.first {
                                userInfo["verse"] = verse
                            }
                            NotificationCenter.default.post(
                                name: .navigateToPassage,
                                object: nil,
                                userInfo: userInfo
                            )
                        } label: {
                            Text(note.verseReference)
                                .font(.caption)
                                .foregroundStyle(filigreeAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)

                Divider()

                HStack {
                    Label("\(note.wordCount) words", systemImage: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        openNoteInNotes(note)
                    } label: {
                        Label("Open in Notes", systemImage: "square.and.pencil")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(filigreeAccent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.platformWindowBg)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if note.plainTextContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("This note is empty. Open it in Notes to start writing.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            richNoteText(note)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(theme.background)

            } else {
                // ── Unified Notes + Bookmarks list ──────────────────
                // Three filter pills at top (All / Notes / Bookmarks),
                // search bar below, then a single scrollable list.
                // Notes render with their title + preview; bookmarks
                // render as a compact row with the ox-blood bookmark
                // icon and the verse reference.
                HStack(spacing: 6) {
                    ForEach(SavedFilter.allCases, id: \.self) { f in
                        let active = savedFilter == f
                        Button { savedFilter = f } label: {
                            Text(f.rawValue)
                                .font(.system(size: 11, weight: active ? .semibold : .regular))
                                .foregroundStyle(active ? .white : theme.text)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(active ? filigreeAccent : Color.secondary.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    // Select / Done toggle — enters multi-select mode,
                    // showing checkboxes on each row and revealing the
                    // bulk-action bar at the bottom.
                    Button {
                        isSelectMode.toggle()
                        if !isSelectMode { selectedIDs.removeAll() }
                    } label: {
                        Text(isSelectMode ? "Done" : "Select")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(filigreeAccent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("Search \(savedFilter.rawValue.lowercased())...", text: $noteSearchText)
                        .textFieldStyle(.plain).font(.system(size: 12))
                    if !noteSearchText.isEmpty {
                        Button { noteSearchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(theme.background)

                Divider()

                // ── Verse-filter banner ──────────────────────────────
                // When the user taps "Make a Note" in the verse popover
                // or the inline blue note icon, the Notes tab narrows
                // to just that verse's notes. Banner shows the verse
                // reference and a "back to all" action. Creating a new
                // note is ONLY done via the verse popover — this is a
                // read-only filtered view.
                if let vf = verseFilter {
                    HStack(spacing: 8) {
                        Button {
                            verseFilter = nil
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("All")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(filigreeAccent)
                        }
                        .buttonStyle(.plain)

                        Text(vf.displayTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.text)

                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(filigreeAccent.opacity(0.06))

                    Divider()
                }

                let entries = filteredEntries
                if entries.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: savedFilter == .bookmarks ? "bookmark" : "note.text")
                            .font(.system(size: 28)).foregroundStyle(.quaternary)
                        Text(emptyStateText)
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity).background(theme.background)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(entries) { entry in
                                switch entry {
                                case .note(let note):
                                    noteRow(note)
                                case .bookmark(let bm):
                                    bookmarkRow(bm)
                                }
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                    .background(theme.background)
                }

                // ── Bottom bar ────────────────────────────────────────
                // In select mode: Select All, count, Delete, Archive.
                // In normal mode: view toggles (Active/Archived/Trash).
                Divider()
                if isSelectMode {
                    bulkActionBar
                } else {
                    viewToggleBar
                }
            }
        }
        .background(theme.background)
        .confirmationDialog(
            "Move \(selectedIDs.count) item\(selectedIDs.count == 1 ? "" : "s") to Trash?",
            isPresented: $showBulkDeleteConfirm
        ) {
            Button("Move to Trash", role: .destructive) { performBulkDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can restore items from Trash until you empty it.")
        }
        .confirmationDialog(
            "Move note to Trash?",
            isPresented: Binding(
                get: { pendingNoteDelete != nil },
                set: { if !$0 { pendingNoteDelete = nil } })
        ) {
            Button("Move to Trash", role: .destructive) {
                if let n = pendingNoteDelete {
                    notesManager.delete(n)
                    // If the note was currently drilled-in, close back
                    // to the list so the trashed note isn't still shown.
                    if selectedVerseNoteID == n.id {
                        selectedVerseNoteID = nil
                    }
                }
                pendingNoteDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingNoteDelete = nil }
        } message: {
            Text("You can restore this note from Trash until you empty it.")
        }
        .confirmationDialog(
            "Delete this bookmark?",
            isPresented: Binding(
                get: { pendingBookmarkDelete != nil },
                set: { if !$0 { pendingBookmarkDelete = nil } })
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let b = pendingBookmarkDelete { bookmarksManager.delete(b) }
                pendingBookmarkDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingBookmarkDelete = nil }
        } message: {
            Text("This cannot be undone. Individual bookmark removal is permanent.")
        }
        .confirmationDialog(
            "Empty Trash?",
            isPresented: $showEmptyTrashConfirm
        ) {
            Button("Empty Trash", role: .destructive) {
                notesManager.emptyTrash()
                bookmarksManager.emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All items in Trash will be permanently deleted. This cannot be undone.")
        }
    }

    // MARK: - Bottom bars

    /// Shown in multi-select mode. Select All toggle, count, and
    /// action buttons. Archive is only offered when the selection is
    /// notes-only (bookmarks aren't archivable).
    private var bulkActionBar: some View {
        let selectionIsNotesOnly = selectedIDs.allSatisfy { $0.hasPrefix("note_") }
        let hasSelection = !selectedIDs.isEmpty
        return HStack(spacing: 10) {
            Button {
                toggleSelectAll()
            } label: {
                Text(selectedIDs.count == filteredEntries.count && !filteredEntries.isEmpty
                     ? "Deselect All" : "Select All")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(filigreeAccent)
            }
            .buttonStyle(.plain)

            Text("\(selectedIDs.count) selected")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            if selectionIsNotesOnly && hasSelection {
                Button {
                    performBulkArchive()
                } label: {
                    Label("Archive", systemImage: "archivebox")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(filigreeAccent)
                }
                .buttonStyle(.plain)
            }

            Button {
                showBulkDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hasSelection ? .red : Color.red.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(theme.background)
    }

    /// Shown when not in multi-select mode. Lets the user switch
    /// between Active, Archived, and Trash views of the saved list.
    /// Empty Trash button appears only in Trash view.
    private var viewToggleBar: some View {
        HStack(spacing: 8) {
            ForEach(SavedView.allCases, id: \.self) { v in
                let active = savedView == v
                Button {
                    savedView = v
                    // Clear verse filter when navigating away from
                    // Active — it's a concept that only makes sense
                    // for active notes.
                    if v != .active { verseFilter = nil }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: icon(for: v))
                            .font(.system(size: 10))
                        Text(v.rawValue)
                            .font(.system(size: 11, weight: active ? .semibold : .regular))
                    }
                    .foregroundStyle(active ? filigreeAccent : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if savedView == .trash, !filteredEntries.isEmpty {
                Button { showEmptyTrashConfirm = true } label: {
                    Text("Empty Trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(theme.background)
    }

    private func icon(for view: SavedView) -> String {
        switch view {
        case .active:   return "tray"
        case .archived: return "archivebox"
        case .trash:    return "trash"
        }
    }

    // MARK: - Bulk actions

    private func toggleSelectAll() {
        let allIDs = Set(filteredEntries.map { $0.id })
        if selectedIDs == allIDs {
            selectedIDs.removeAll()
        } else {
            selectedIDs = allIDs
        }
    }

    private func performBulkDelete() {
        for entry in filteredEntries where selectedIDs.contains(entry.id) {
            switch entry {
            case .note(let n):
                // Notes: soft-delete (move to Trash).
                notesManager.delete(n)
            case .bookmark(let b):
                // Bookmarks: BULK delete goes to Trash (per design),
                // unlike individual delete which is permanent.
                bookmarksManager.moveToTrash(b)
            }
        }
        selectedIDs.removeAll()
        isSelectMode = false
    }

    private func performBulkArchive() {
        for entry in filteredEntries where selectedIDs.contains(entry.id) {
            if case .note(let n) = entry {
                notesManager.archive(n)
            }
        }
        selectedIDs.removeAll()
        isSelectMode = false
    }

    // MARK: - Saved list rows

    @ViewBuilder
    private func noteRow(_ note: Note) -> some View {
        let entryID = "note_\(note.id.uuidString)"
        HStack(alignment: .top, spacing: 8) {

            // ── Select-mode checkbox ──────────────────────────────────
            if isSelectMode {
                Button {
                    if selectedIDs.contains(entryID) {
                        selectedIDs.remove(entryID)
                    } else {
                        selectedIDs.insert(entryID)
                    }
                } label: {
                    Image(systemName: selectedIDs.contains(entryID)
                          ? "checkmark.circle.fill"
                          : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(selectedIDs.contains(entryID)
                                         ? filigreeAccent : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

            // Blue note icon — matches the inline-next-to-verse-number
            // icon used in the Bible reader itself. Same hue everywhere
            // notes are represented.
            Image(systemName: "note.text")
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.30, green: 0.50, blue: 0.75))
                .padding(.top, 2)

            Button {
                // In select mode, tapping the row toggles selection
                // (tap-to-select is friendlier than "you must hit the
                // checkbox precisely").
                if isSelectMode {
                    if selectedIDs.contains(entryID) {
                        selectedIDs.remove(entryID)
                    } else {
                        selectedIDs.insert(entryID)
                    }
                } else {
                    selectedVerseNoteID = note.id
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(noteHeading(note))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.text).lineLimit(1)
                    let preview = notePreview(note)
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.text.opacity(0.65))
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        if !note.verseReference.isEmpty {
                            Text(note.verseReference)
                                .font(.system(size: 10))
                                .foregroundStyle(filigreeAccent)
                        }
                        Text(note.updatedAt, style: .date)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // ── Trailing actions (differ by view) ─────────────────────
            if !isSelectMode {
                VStack(spacing: 8) {
                    switch savedView {
                    case .active:
                        // Row tap opens the drill-in editor (in the
                        // main row Button above). The old pencil
                        // "Open in Organizer" affordance was removed
                        // 2026-04-21: the CompanionPanel drill-in is
                        // now the single edit surface, so jumping to
                        // Organizer became a confusing alternate path.
                        // If wider editing is ever wanted, add a
                        // maximise affordance inside the drill-in.
                        Button { pendingNoteDelete = note } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.red.opacity(0.6))
                        }.buttonStyle(.plain).help("Move to Trash")
                    case .archived:
                        Button { notesManager.unarchive(note) } label: {
                            Image(systemName: "tray.and.arrow.up")
                                .font(.system(size: 12))
                                .foregroundStyle(filigreeAccent)
                        }.buttonStyle(.plain).help("Unarchive")
                    case .trash:
                        Button { notesManager.restore(note) } label: {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(filigreeAccent)
                        }.buttonStyle(.plain).help("Restore from Trash")
                        Button { notesManager.deletePermanently(note) } label: {
                            Image(systemName: "trash.slash")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.red.opacity(0.8))
                        }.buttonStyle(.plain).help("Delete permanently")
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(theme.background)
        .contextMenu {
            if savedView == .active {
                Button(role: .destructive) {
                    pendingNoteDelete = note
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                Button {
                    notesManager.archive(note)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            } else if savedView == .archived {
                Button {
                    notesManager.unarchive(note)
                } label: {
                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                }
            } else if savedView == .trash {
                Button {
                    notesManager.restore(note)
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                Button(role: .destructive) {
                    notesManager.deletePermanently(note)
                } label: {
                    Label("Delete Permanently", systemImage: "trash.slash")
                }
            }
        }
    }

    @ViewBuilder
    private func bookmarkRow(_ bm: Bookmark) -> some View {
        let entryID = "bookmark_\(bm.id.uuidString)"
        HStack(alignment: .center, spacing: 8) {

            // ── Select-mode checkbox ──────────────────────────────────
            if isSelectMode {
                Button {
                    if selectedIDs.contains(entryID) {
                        selectedIDs.remove(entryID)
                    } else {
                        selectedIDs.insert(entryID)
                    }
                } label: {
                    Image(systemName: selectedIDs.contains(entryID)
                          ? "checkmark.circle.fill"
                          : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(selectedIDs.contains(entryID)
                                         ? filigreeAccent : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Ox-blood bookmark icon — matches the inline-next-to-
            // verse-number icon used in the Bible reader itself.
            Image(systemName: "bookmark.fill")
                .font(.system(size: 11))
                .foregroundStyle(SilkBookmarkRibbonView.silkRed)

            Button {
                if isSelectMode {
                    if selectedIDs.contains(entryID) {
                        selectedIDs.remove(entryID)
                    } else {
                        selectedIDs.insert(entryID)
                    }
                } else {
                    // Navigate the Bible reader to this bookmark's passage.
                    var info: [String: Any] = [
                        "bookNumber": bm.bookNumber,
                        "chapter":    bm.chapterNumber
                    ]
                    if let v = bm.verseNumber { info["verse"] = v }
                    NotificationCenter.default.post(
                        name: .navigateToPassage,
                        object: nil,
                        userInfo: info)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bm.displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.text).lineLimit(1)
                    Text(bm.formattedDate)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // ── Trailing actions (differ by view) ─────────────────────
            if !isSelectMode {
                switch savedView {
                case .active:
                    // Individual bookmark delete is PERMANENT per
                    // design — warning dialog via pendingBookmarkDelete.
                    Button { pendingBookmarkDelete = bm } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Delete bookmark permanently")
                case .archived:
                    EmptyView()   // bookmarks aren't archivable
                case .trash:
                    // In Trash, bookmarks arrived via BULK delete.
                    HStack(spacing: 8) {
                        Button { bookmarksManager.restore(bm) } label: {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(filigreeAccent)
                        }.buttonStyle(.plain).help("Restore from Trash")
                        Button { bookmarksManager.deletePermanently(bm) } label: {
                            Image(systemName: "trash.slash")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.red.opacity(0.8))
                        }.buttonStyle(.plain).help("Delete permanently")
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(theme.background)
        .contextMenu {
            if savedView == .active {
                Button(role: .destructive) {
                    pendingBookmarkDelete = bm
                } label: {
                    Label("Delete Bookmark", systemImage: "trash")
                }
            } else if savedView == .trash {
                Button {
                    bookmarksManager.restore(bm)
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                Button(role: .destructive) {
                    bookmarksManager.deletePermanently(bm)
                } label: {
                    Label("Delete Permanently", systemImage: "trash.slash")
                }
            }
        }
    }

    // MARK: - Saved list data

    /// Empty-state message, tuned to the active filter.
    private var emptyStateText: String {
        let q = noteSearchText.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { return "No results" }
        if let vf = verseFilter {
            return "No notes on \(vf.displayTitle) yet"
        }
        switch savedFilter {
        case .all:       return "Nothing saved yet"
        case .notes:     return "No notes yet"
        case .bookmarks: return "No bookmarks yet"
        }
    }

    /// Unified filtered + sorted list of SavedEntry for the Notes tab.
    /// Respects: savedView (active/archived/trash), savedFilter pill
    /// (all/notes/bookmarks), verseFilter (optional), and the search
    /// text. Archived + deleted notes are only visible in their
    /// respective views.
    private var filteredEntries: [SavedEntry] {
        let q = noteSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        var result: [SavedEntry] = []

        if savedFilter == .all || savedFilter == .notes {
            for n in notesManager.notes {
                // savedView gating
                switch savedView {
                case .active:
                    if n.isArchived || n.deletedAt != nil { continue }
                case .archived:
                    if !n.isArchived || n.deletedAt != nil { continue }
                case .trash:
                    if n.deletedAt == nil { continue }
                }
                // Verse-filter gating (only meaningful in Active view)
                if savedView == .active, let vf = verseFilter {
                    guard n.bookNumber    == vf.bookNumber,
                          n.chapterNumber == vf.chapter,
                          n.verseNumbers.isEmpty || n.verseNumbers.contains(vf.verse)
                          else { continue }
                }
                if q.isEmpty
                   || n.title.lowercased().contains(q)
                   || n.content.lowercased().contains(q)
                   || n.verseReference.lowercased().contains(q) {
                    result.append(.note(n))
                }
            }
        }

        if savedFilter == .all || savedFilter == .bookmarks {
            for b in bookmarksManager.bookmarks {
                // savedView gating (bookmarks have no archive state)
                switch savedView {
                case .active:
                    if b.deletedAt != nil { continue }
                case .archived:
                    continue   // bookmarks aren't archivable
                case .trash:
                    if b.deletedAt == nil { continue }
                }
                if savedView == .active, let vf = verseFilter {
                    guard b.bookNumber    == vf.bookNumber,
                          b.chapterNumber == vf.chapter,
                          b.verseNumber == nil || b.verseNumber == vf.verse
                          else { continue }
                }
                if q.isEmpty
                   || b.displayTitle.lowercased().contains(q) {
                    result.append(.bookmark(b))
                }
            }
        }

        return result.sorted { $0.sortDate > $1.sortDate }
    }

    private func noteHeading(_ note: Note) -> String {
        let first = note.content.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        let clean = first.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        return clean.isEmpty ? note.title : clean
    }

    private func notePreview(_ note: Note) -> String {
        let lines = note.plainTextContent.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { return "" }
        return lines.dropFirst().prefix(3).joined(separator: " ")
    }

    @ViewBuilder
    private func richNoteText(_ note: Note) -> some View {
        #if os(macOS)
        if let richDocument = note.richDocument {
            let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            let attributed = RichNoteEditorBridge.attributedString(from: richDocument, baseFont: font)
            if let swiftAttributed = try? AttributedString(attributed, including: \.appKit) {
                Text(swiftAttributed)
                    .foregroundStyle(theme.text)
            } else {
                Text(note.plainTextContent)
                    .font(resolvedFont)
                    .foregroundStyle(theme.text)
            }
        } else {
            Text(note.plainTextContent)
                .font(resolvedFont)
                .foregroundStyle(theme.text)
        }
        #else
        Text(note.plainTextContent)
            .font(resolvedFont)
            .foregroundStyle(theme.text)
        #endif
    }

    private func openNoteInNotes(_ note: Note) {
        notesManager.selectedNote = note
        NotificationCenter.default.post(
            name: Notification.Name("switchToNotesTab"),
            object: nil
        )
    }

    // MARK: - Clipboard

    private func checkClipboard() {
        #if os(macOS)
        let pb    = NSPasteboard.general
        let count = pb.changeCount
        guard count != pbCount else { return }
        pbCount = count
        guard let raw = pb.string(forType: .string) else { return }

        let first = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                       .components(separatedBy: .whitespaces).first ?? ""
        let clean = first.trimmingCharacters(in: .punctuationCharacters)
        guard clean.count >= 2 else { return }

        let service = myBible

        // Update encyclopedia if that tab is active
        if mode == .encyclopedia {
            encycWord       = clean
            encycDefinition = nil
            encycDefinitionHTML = nil
            encycIsLoading  = true
            Task {
                let result = await service.lookupLinkedWord(word: clean, in: service.selectedEncyclopedia)
                await MainActor.run {
                    encycWord       = result?.topic ?? clean
                    encycDefinition = result?.definition
                    encycDefinitionHTML = result?.definition
                    encycIsLoading  = false
                }
            }
        }

        // Update dictionary in background — do NOT switch mode automatically
        dictWord       = clean
        dictDefinition = nil
        dictIsLoading  = true

        Task {
            let result = await service.lookupDictionaryWord(word: clean)
            await MainActor.run {
                dictWord       = result?.topic ?? clean
                dictDefinition = result?.definition
                dictIsLoading  = false
            }
        }
        #endif
    }

    private var helpPage: String {
        switch mode {
        case .commentary:  return "commentary"
        case .strongs:     return "dictionaries"
        case .encyclopedia: return "dictionaries"
        case .interlinear: return "interlinear"
        case .notes:       return "notes-companion"
        case .timeline:    return "timeline"
        case .maps:        return "maps"
        case .web:         return "web"
        }
    }

    private var helpAnchor: String { "" }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack {
            Text("COMPANION PANEL")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(filigreeAccent.opacity(0.7))
            Spacer()
            #if os(macOS)
            HelpButton(page: "comparison")
            #endif
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(theme.background)
    }

    // MARK: - Mode bar

    private var modeBar: some View {
        HStack(spacing: 0) {
            ForEach(CompanionMode.allCases, id: \.self) { m in
                Button(m.rawValue) { modeRaw = m.rawValue; load() }
                    .font(.caption.weight(mode == m ? .semibold : .regular))
                    .foregroundStyle(mode == m ? filigreeAccent : Color.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(mode == m ? filigreeAccentFill.opacity(0.25) : Color.clear)
                    .buttonStyle(.plain)
            }
            Spacer()
        }
        .background(theme.background)
    }

    // MARK: - Module bar

    private var moduleBar: some View {
        HStack {
            Group {
                switch mode {
                case .commentary:
                    Picker("", selection: Binding(
                        get: { myBible.selectedCommentary },
                        set: { myBible.selectedCommentary = $0 }
                    )) {
                        Text("Select…").tag(Optional<MyBibleModule>.none)
                        ForEach(commentaryModules) { m in Text(m.name).tag(Optional(m)) }
                    }
                    .labelsHidden().font(.caption)
                    .onChange(of: myBible.selectedCommentary) { load() }
                    .onAppear {
                        if myBible.selectedCommentary == nil {
                            myBible.selectedCommentary = commentaryModules.first
                        }
                    }

                case .strongs:
                    Text("Dictionaries").help("Browse dictionaries and Strong's lexicons").font(.caption).foregroundStyle(.secondary)

                case .encyclopedia:
                    Text("Encyclopedias").help("Browse Bible encyclopedias and handbooks").font(.caption).foregroundStyle(.secondary)

                case .interlinear:
                    Text("Interlinear").font(.caption).foregroundStyle(.secondary)

                case .notes:
                    Text(verseNotes.count == 1 ? "1 note" : "\(verseNotes.count) notes")
                        .font(.caption).foregroundStyle(.secondary)

                case .timeline:
                    Text("Biblical Timeline").font(.caption).foregroundStyle(.secondary)

                case .maps:
                    Text(bmapsService.isLoaded
                         ? "\(bmapsService.places.count) places · \(bmapsService.maps.count) maps"
                         : "Bible Maps")
                        .font(.caption).foregroundStyle(.secondary)
                        .help(bmapsService.loadedAtlasURL?.path ?? "No atlas module loaded")

                case .web:
                    Picker("", selection: $companionWebSiteID) {
                        ForEach(bibleWebSites) { site in Text(site.name).tag(site.id) }
                    }
                    .labelsHidden().font(.caption)
                }
            }
            Spacer()
            if isLoading { ProgressView().controlSize(.mini) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(theme.background)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch mode {
        case .commentary:  textContentView
        case .strongs:     dictionariesView
        case .encyclopedia: encyclopediaView
        case .interlinear: InterlinearView(bookNumber: bookNumber, chapter: chapter, syncedVerse: syncedVerse)
                               .environmentObject(myBible)
        case .notes:       verseNotesView
        case .timeline:    TimelineView(bookNumber: bookNumber, bookName: bookName)
        case .maps:        BibleMapsView(
                               currentVerseRef: syncedVerse > 0
                                   ? "\(osisBookName(bookNumber)?.capitalized ?? bookName) \(chapter):\(syncedVerse)"
                                   : nil,
                               theme:             theme,
                               filigreeAccent:    filigreeAccent,
                               filigreeAccentFill: filigreeAccentFill,
                               resolvedFont:      resolvedFont
                           )
                           .environmentObject(bmapsService)
        case .web:         webContentView
        }
    }

    // MARK: - Dictionaries panel

    private var dictionariesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Strong's header bar ───────────────────────────────
                sectionBar(title: "Strong's", picker: strongsPicker)
                Divider()

                // Strong's content
                VStack(alignment: .leading, spacing: 10) {
                    if strongsNumber.isEmpty {
                        Text("Tap a Strong's word to look up its definition")
                            .foregroundStyle(theme.secondary).font(resolvedFont)
                    } else {
                        strongsHistoryBar
                    }
                    if !strongsNumber.isEmpty && strongsIsLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if !strongsNumber.isEmpty, let entry = strongsEntry {
                        strongsEntryView(entry)
                    } else if !strongsNumber.isEmpty {
                        Text("No entry found for \(strongsNumber)")
                            .foregroundStyle(theme.secondary).font(resolvedFont)
                    }
                }
                .padding()

                Divider()

                // ── Dictionary header bar ─────────────────────────────
                sectionBar(title: "Dictionary", picker: dictionaryPicker)
                Divider()

                // Dictionary content
                VStack(alignment: .leading, spacing: 8) {
                    if dictWord.isEmpty {
                        Text("Copy any word to look it up here")
                            .foregroundStyle(theme.secondary).font(resolvedFont)
                    } else if dictIsLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if let def = dictDefinition {
                        Text(dictWord.capitalized)
                            .font(resolvedFont.weight(.bold))
                            .foregroundStyle(filigreeAccent)
                        Text(def)
                            .font(resolvedFont).lineSpacing(6)
                            .foregroundStyle(theme.text)
                    } else {
                        Text("No entry found for \"\(dictWord)\"")
                            .foregroundStyle(theme.secondary).font(resolvedFont)
                    }
                }
                .padding()
            }
        }
        .scrollIndicators(.hidden)
        .background(theme.background)
    }

    private var encyclopediaView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionBar(title: "Encyclopedia", picker: encyclopediaPicker)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    if encycWord.isEmpty {
                        Text("Copy any word or name to look it up here")
                            .foregroundStyle(theme.secondary).font(resolvedFont)
                    } else if encycIsLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if let def = encycDefinitionHTML ?? encycDefinition {
                        Text(encycWord.capitalized)
                            .font(resolvedFont.weight(.bold))
                            .foregroundStyle(filigreeAccent)
                        LinkedDefinitionView(
                            html: def,
                            font: resolvedFont,
                            textColor: theme.text,
                            accentColor: filigreeAccent,
                            onVerseTap: { bookNumber, chapter, verse in
                                NotificationCenter.default.post(
                                    name: .navigateToPassage,
                                    object: nil,
                                    userInfo: ["bookNumber": bookNumber, "chapter": chapter, "verse": verse]
                                )
                            },
                            onStrongsTap: { _ in }
                        )
                    } else {
                        Text("No entry found for \"\(encycWord)\"")
                            .foregroundStyle(theme.secondary).font(resolvedFont)
                    }
                }
                .padding()
            }
        }
        .scrollIndicators(.hidden)
        .background(theme.background)
    }

    private func sectionBar(title: String, picker: some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.background)
            Spacer()
            picker
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(filigreeAccentFill)
    }

    @ViewBuilder
    private func strongsEntryView(_ entry: StrongsEntry) -> some View {
        StrongsPopoverWebView(
            html: StrongsCardRenderer.html(for: entry),
            onVerseTap: { target in
                selectedStrongsVerseTarget = target
            },
            onStrongsTap: { tappedNumber in
                loadStrongs(number: tappedNumber, pushHistory: true, clearForwardHistory: true)
            }
        )
        .frame(minHeight: 240, idealHeight: 360)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(filigreeAccent.opacity(0.18), lineWidth: 1)
        )
        .popover(item: $selectedStrongsVerseTarget, arrowEdge: .bottom) { target in
            VersePreviewPopover(
                bookNumber: target.bookNumber,
                chapter: target.chapter,
                verseStart: target.verseStart,
                verseEnd: target.verseEnd,
                accent: filigreeAccent
            )
            .frame(width: 320)
        }
        if !entry.hasExpandedDefinition && !entry.derivation.isEmpty {
            Divider()
            Text("Derivation").font(resolvedFont.weight(.semibold)).foregroundStyle(theme.secondary)
            LinkedDefinitionView(
                html: entry.derivation,
                font: resolvedFont,
                textColor: theme.text,
                accentColor: filigreeAccent,
                onVerseTap: { _, _, _ in },
                onStrongsTap: { _ in }
            )
        }
        if !entry.hasExpandedDefinition && !entry.kjv.isEmpty {
            Divider()
            Text("KJV Usage").font(resolvedFont.weight(.semibold)).foregroundStyle(theme.secondary)
            LinkedDefinitionView(
                html: entry.kjv,
                font: resolvedFont,
                textColor: theme.text,
                accentColor: filigreeAccent,
                onVerseTap: { _, _, _ in },
                onStrongsTap: { _ in }
            )
        }
        if !entry.cognates.isEmpty {
            Divider()
            Text("Cognates").font(resolvedFont.weight(.semibold)).foregroundStyle(theme.secondary)
            HStack(spacing: 6) {
                ForEach(entry.cognates, id: \.self) { cognate in
                    CognateButton(number: cognate, accent: filigreeAccent,
                                  module: myBible.selectedStrongs ?? myBible.selectedDictionary)
                }
                Spacer()
            }
        }
    }

    private var strongsHistoryBar: some View {
        HStack(spacing: 10) {
            Button {
                guard let previous = strongsBackStack.popLast() else { return }
                if !strongsNumber.isEmpty {
                    strongsForwardStack.append(strongsNumber)
                }
                loadStrongs(number: previous, pushHistory: false, clearForwardHistory: false)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(strongsBackStack.isEmpty)
            .opacity(strongsBackStack.isEmpty ? 0.35 : 1)

            Button {
                guard let next = strongsForwardStack.popLast() else { return }
                if !strongsNumber.isEmpty {
                    strongsBackStack.append(strongsNumber)
                }
                loadStrongs(number: next, pushHistory: false, clearForwardHistory: false)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(strongsForwardStack.isEmpty)
            .opacity(strongsForwardStack.isEmpty ? 0.35 : 1)

            Spacer()

            Text(strongsNumber)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondary)
        }
    }

    private func loadStrongs(
        number: String,
        isOldTestament: Bool? = nil,
        pushHistory: Bool = false,
        clearForwardHistory: Bool = true
    ) {
        let normalised = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalised.isEmpty else { return }
        if pushHistory && !strongsNumber.isEmpty && strongsNumber != normalised {
            strongsBackStack.append(strongsNumber)
        }
        strongsNumber = normalised
        strongsEntry = nil
        strongsIsLoading = true
        selectedStrongsVerseTarget = nil
        if clearForwardHistory {
            strongsForwardStack.removeAll()
        }
        guard let module = myBible.selectedStrongs else {
            strongsIsLoading = false
            return
        }
        let isOT = isOldTestament ?? !normalised.uppercased().hasPrefix("G")
        Task {
            let entry = await myBible.lookupStrongs(module: module, number: normalised, isOldTestament: isOT)
            await MainActor.run {
                strongsEntry = entry
                strongsIsLoading = false
            }
        }
    }

    // MARK: - Web panel

    private var webContentView: some View {
        Group {
            if let osisName = osisBookName(bookNumber),
               let url = URL(string: syncedVerse > 0
                    ? selectedWebSite.verseURL(osisName, chapter, syncedVerse)
                    : selectedWebSite.url(osisName, chapter)) {
                #if os(macOS)
                BibleWebView(url: url)
                #else
                WKWebView_Placeholder()
                #endif
            } else {
                VStack { Spacer(); Text("Unable to load page").foregroundStyle(.secondary); Spacer() }
            }
        }
    }

    // MARK: - Text panel

    private var textContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(xrefBook != nil
                     ? "\(myBibleBookNumbers[xrefBook!] ?? bookName) \(xrefChapter ?? chapter)"
                     : "\(bookName) \(chapter)")
                    .font(resolvedFont.bold()).foregroundStyle(theme.text).padding(.bottom, 4)
                if let m = myBible.selectedCommentary {
                    Text(m.name).font(.caption).foregroundStyle(theme.secondary).padding(.bottom, 16)
                }
                commentaryContent
                // Show xref back button when viewing a cross-ref passage
            if xrefBook != nil {
                HStack {
                    Button {
                        xrefBook = nil; xrefChapter = nil; xrefVerse = 0
                        crossRefTarget = nil
                        load()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Back to \(bookName)")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(filigreeAccent)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(filigreeAccent.opacity(0.06))
                Divider()
            }
                if mode == .commentary && commentaryEntries.isEmpty && !isLoading {
                    Text("Select a commentary").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(theme.background)
    }

    private var comparisonContent: some View {
        ScrollViewReader { proxy in
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(companionVerses) { verse in
                    let isSynced = xrefBook != nil ? verse.verse == xrefVerse : verse.verse == syncedVerse
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(verse.verse)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isSynced ? .white : filigreeAccent.opacity(0.7))
                            .frame(minWidth: 20, alignment: .trailing)
                            .padding(.horizontal, 3).padding(.vertical, 2)
                            .background(isSynced ? filigreeAccentFill : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text(verse.text).font(resolvedFont).foregroundStyle(theme.text).lineSpacing(4)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(isSynced ? filigreeAccent.opacity(0.10) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .id(verse.verse)
                }
            }
            .onChange(of: syncedVerse) { _, v in
                if v > 0 && xrefBook == nil { withAnimation { proxy.scrollTo(v, anchor: .center) } }
            }
            .onChange(of: xrefVerse) { _, v in
                if v > 0 { withAnimation { proxy.scrollTo(v, anchor: .center) } }
            }
            .onChange(of: syncScrollVerse) { _, v in
                if v > 0 && xrefBook == nil { proxy.scrollTo(v, anchor: .top) }
            }
        }
    }

    /// Find the best commentary entry for a verse:
    /// Prefers the most specific (smallest range) entry covering the verse.
    /// Falls back to any entry that covers the verse.
    /// Falls back to chapter overview (verseFrom == 0) if nothing else.
    private func bestEntry(for verse: Int) -> CommentaryEntry? {
        let covering = commentaryEntries.filter {
            $0.verseFrom <= verse && verse <= $0.verseTo && $0.verseFrom > 0
        }
        if let specific = covering.min(by: { ($0.verseTo - $0.verseFrom) < ($1.verseTo - $1.verseFrom) }) {
            return specific
        }
        // Fall back to chapter overview entry (verseFrom == 0 covers whole chapter)
        return commentaryEntries.first { $0.verseFrom == 0 } ?? commentaryEntries.first
    }

    private var commentaryContent: some View {
        ScrollViewReader { proxy in
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(commentaryEntries) { entry in
                    let isSynced = syncedVerse > 0 &&
                        entry.verseFrom <= syncedVerse && syncedVerse <= entry.verseTo
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verseRef(entry))
                            .font(.caption.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(isSynced ? filigreeAccentFill : filigreeAccentFill.opacity(0.6))
                            .clipShape(Capsule())
                        Text(entry.text).font(resolvedFont).foregroundStyle(theme.text).lineSpacing(4)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 8)
                    .background(isSynced ? filigreeAccent.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .id(entry.id)
                }
            }
            .onChange(of: commentaryEntries) { _, _ in
                guard syncedVerse > 0,
                      let entry = bestEntry(for: syncedVerse) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    proxy.scrollTo(entry.id, anchor: .top)
                }
            }
            .onChange(of: syncedVerse) { _, v in
                guard v > 0, !commentaryEntries.isEmpty,
                      let entry = bestEntry(for: v) else { return }
                proxy.scrollTo(entry.id, anchor: .top)
            }
        }
    }

    // MARK: - Helpers

    private func load() {
        guard mode != .web && mode != .strongs && mode != .maps else { return }
        isLoading = true
        if false { // comparison mode removed
            guard let module = companionModule else { isLoading = false; return }
            let loadBook = xrefBook    ?? bookNumber
            let loadCh   = xrefChapter ?? chapter
            Task {
                let verses = await myBible.fetchVerses(module: module,
                                                       bookNumber: loadBook, chapter: loadCh)
                await MainActor.run { companionVerses = verses; isLoading = false }
            }
        } else {
            guard let module = myBible.selectedCommentary else { isLoading = false; return }
            Task {
                let entries = await myBible.fetchCommentaryEntries(module: module,
                                                                   bookNumber: bookNumber, chapter: chapter)
                await MainActor.run {
                    commentaryEntries = entries
                    isLoading = false
                }
            }
        }
    }

    private func osisBookName(_ bookNumber: Int) -> String? {
        let map: [Int: String] = [
            10:"genesis",20:"exodus",30:"leviticus",40:"numbers",50:"deuteronomy",
            60:"joshua",70:"judges",80:"ruth",90:"1samuel",100:"2samuel",
            110:"1kings",120:"2kings",130:"1chronicles",140:"2chronicles",
            150:"ezra",160:"nehemiah",190:"esther",220:"job",230:"psalms",
            240:"proverbs",250:"ecclesiastes",260:"songs",290:"isaiah",
            300:"jeremiah",310:"lamentations",330:"ezekiel",340:"daniel",
            350:"hosea",360:"joel",370:"amos",380:"obadiah",390:"jonah",
            400:"micah",410:"nahum",420:"habakkuk",430:"zephaniah",440:"haggai",
            450:"zechariah",460:"malachi",470:"matthew",480:"mark",490:"luke",
            500:"john",510:"acts",520:"romans",530:"1corinthians",540:"2corinthians",
            550:"galatians",560:"ephesians",570:"philippians",580:"colossians",
            590:"1thessalonians",600:"2thessalonians",610:"1timothy",620:"2timothy",
            630:"titus",640:"philemon",650:"hebrews",660:"james",670:"1peter",
            680:"2peter",690:"1john",700:"2john",710:"3john",720:"jude",
            730:"revelation"
        ]
        return map[bookNumber]
    }

    private func verseRef(_ entry: CommentaryEntry) -> String {
        let book = myBibleBookNumbers[entry.bookNumber] ?? ""
        if entry.verseFrom == entry.verseTo { return "\(book) \(entry.chapterFrom):\(entry.verseFrom)" }
        return "\(book) \(entry.chapterFrom):\(entry.verseFrom)–\(entry.verseTo)"
    }
}

// MARK: - Web Sites

struct BibleWebSite: Identifiable {
    let id:       String
    let name:     String
    let url:      (String, Int) -> String
    let verseURL: (String, Int, Int) -> String
}

let bibleWebSites: [BibleWebSite] = [
    BibleWebSite(id: "blueletterbible", name: "Blue Letter Bible",
        url:      { b, ch     in "https://www.blueletterbible.org/niv/\(b)/\(ch)/1/" },
        verseURL: { b, ch, vs in "https://www.blueletterbible.org/niv/\(b)/\(ch)/\(vs)/" }
    ),
    BibleWebSite(id: "biblehub", name: "Biblehub",
        url:      { b, ch     in "https://biblehub.com/\(b)/\(ch)-1.htm" },
        verseURL: { b, ch, vs in "https://biblehub.com/\(b)/\(ch)-\(vs).htm" }
    ),
]

// MARK: - Custom Web Sites

struct CustomWebSite: Identifiable, Codable {
    var id:   UUID   = UUID()
    var name: String
    var url:  String
}

class CustomWebSitesStore: ObservableObject {
    @Published var sites: [CustomWebSite] = []
    init() { load() }
    func load() {
        guard let data    = UserDefaults.standard.data(forKey: "customWebSites"),
              let decoded = try? JSONDecoder().decode([CustomWebSite].self, from: data)
        else { return }
        sites = decoded
    }
    func save() {
        if let data = try? JSONEncoder().encode(sites) {
            UserDefaults.standard.set(data, forKey: "customWebSites")
        }
    }
    func add(_ site: CustomWebSite)   { sites.append(site); save() }
    func delete(at offsets: IndexSet) { sites.remove(atOffsets: offsets); save() }
    func update(_ site: CustomWebSite) {
        if let i = sites.firstIndex(where: { $0.id == site.id }) { sites[i] = site; save() }
    }
}

// MARK: - WKWebView Wrapper

#if !os(macOS)
struct WKWebView_Placeholder: View {
    var body: some View { Color.clear }
}
#endif

#if os(macOS)
struct BibleWebView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let css = ".ad,.ads,.advertisement,.adsbygoogle,[id^='div-gpt-ad'],[class*='google-ad'],[class*='sponsored'],.notification-bar,.cookie-consent,.donate-bar,.blb-banner,.padvertise,.bing-ad,.sectionad{display:none!important}"
        let script = WKUserScript(
            source: "var s=document.createElement('style');s.textContent='\(css)';document.head.appendChild(s);",
            injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"
        wv.load(URLRequest(url: url))
        return wv
    }
    func updateNSView(_ wv: WKWebView, context: Context) {
        if wv.url != url { wv.load(URLRequest(url: url)) }
    }
}
#endif


// MARK: - Cognate Button

struct CognateButton: View {
    let number: String
    let accent:  Color
    let module:  MyBibleModule?

    @EnvironmentObject var myBible: MyBibleService
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover = true
        } label: {
            Text(number)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            StrongsPreviewPopover(number: number, accent: accent, module: module)
                .environmentObject(myBible)
                .frame(width: 300)
        }
    }
}
