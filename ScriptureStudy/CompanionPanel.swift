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

struct CompanionPanel: View {

    @EnvironmentObject var myBible:       MyBibleService
    @EnvironmentObject var notesManager:  NotesManager
    @EnvironmentObject var bmapsService:  BMapsService

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
    @State private var commentaryModule:  MyBibleModule?
    @State private var isLoading         = false
    @State private var syncedVerse:       Int               = 0
    @State private var syncScrollVerse:    Int               = 0

    // Strong's
    @State private var verseNoteIDs:      [UUID]            = []
    @State private var noteSearchText:    String            = ""
    @State private var selectedVerseNote: Note?              = nil
    @State private var crossRefGroups:    [MyBibleService.CrossRefGroup] = []
    @State private var crossRefIsLoading: Bool              = false
    @State private var crossRefTarget:    MyBibleService.CrossRefEntry? = nil
    @State private var xrefBook:          Int?              = nil  // override for cross-ref navigation
    @State private var xrefChapter:       Int?              = nil
    @State private var xrefVerse:         Int               = 0    // verse to highlight in cross-ref passage
    // Live-filtered so deletions reflect immediately
    private var verseNotes: [Note] { notesManager.notes.filter { verseNoteIDs.contains($0.id) } }
    @State private var strongsNumber:    String            = ""
    @State private var strongsEntry:     StrongsEntry?     = nil
    @State private var strongsIsLoading: Bool              = false

    // Dictionary / clipboard
    @State private var dictWord:         String            = ""
    @State private var dictDefinition:   String?           = nil
    @State private var dictIsLoading:    Bool              = false
    @State private var encycWord:        String            = ""
    @State private var encycDefinition:  String?           = nil
    @State private var encycIsLoading:   Bool              = false
    @State private var pbCount:          Int               = 0

    var selectedWebSite: BibleWebSite {
        bibleWebSites.first { $0.id == companionWebSiteID } ?? bibleWebSites[0]
    }

    var bibleModules:      [MyBibleModule] { myBible.visibleModules.filter { $0.type == .bible } }
    var commentaryModules: [MyBibleModule] { myBible.visibleModules.filter { $0.type == .commentary } }

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
        .background(theme.background)
        .foregroundStyle(theme.text)
        .environment(\.colorScheme, themeID == "charcoal" ? .dark : .light)
        .onAppear {
            load()
            #if os(macOS)
            pbCount = NSPasteboard.general.changeCount
            #endif
        }
        .onChange(of: bookNumber) { _ in syncedVerse = 0; syncScrollVerse = 0; verseNoteIDs = []; crossRefGroups = []; xrefBook = nil; xrefChapter = nil; xrefVerse = 0; load() }
        .onChange(of: chapter)    { _ in syncedVerse = 0; syncScrollVerse = 0; verseNoteIDs = []; crossRefGroups = []; xrefBook = nil; xrefChapter = nil; xrefVerse = 0; load() }
        .onChange(of: myBible.selectedDictionary) { _ in
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
        .onChange(of: myBible.selectedEncyclopedia) { _ in
            guard !encycWord.isEmpty else { return }
            encycDefinition = nil
            encycIsLoading  = true
            let word    = encycWord
            let service = myBible
            Task {
                let result = await service.lookupWord(word: word, in: service.selectedEncyclopedia)
                await MainActor.run {
                    encycWord       = result?.topic ?? word
                    encycDefinition = result?.definition
                    encycIsLoading  = false
                }
            }
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            checkClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("showVerseNotes"))) { notification in
            guard let notes = notification.userInfo?["notes"] as? [Note],
                  let first = notes.first else { return }
            selectedVerseNote = first
            modeRaw           = CompanionMode.notes.rawValue
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("strongsTapped"))) { note in
            guard let num = note.userInfo?["number"] as? String else { return }
            let bookNum      = note.userInfo?["bookNumber"] as? Int ?? 0
            strongsNumber    = num
            strongsEntry     = nil
            strongsIsLoading = true
            modeRaw          = CompanionMode.strongs.rawValue
            guard let module = myBible.selectedStrongs else { strongsIsLoading = false; return }
            let isOT = bookNum > 0 ? bookNum < 470 : !num.hasPrefix("G")
            Task {
                let entry = await myBible.lookupStrongs(module: module, number: num, isOldTestament: isOT)
                await MainActor.run { strongsEntry = entry; strongsIsLoading = false }
            }
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
            if syncedVerse > 0 { load() }
            // Switch to Commentary so there's always something to read.
            // Cross-refs load in background and are ready when user switches to Notes.
            if vs > 0 {
                crossRefIsLoading = true
                modeRaw = CompanionMode.commentary.rawValue
                Task {
                    let groups = await myBible.lookupCrossReferences(book: bn, chapter: ch, verse: vs)
                    await MainActor.run {
                        crossRefGroups    = groups
                        crossRefIsLoading = false
                    }
                }
            }
        }
    }


    // MARK: - Dictionary pickers (extracted so Swift can infer generic types)

    private var strongsPicker: some View {
        let modules = myBible.visibleModules.filter { $0.type == .strongs }
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
        let modules = myBible.visibleModules.filter { $0.type == .dictionary }
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
        let modules = myBible.visibleModules.filter { $0.type == .encyclopedia }
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
                        Task {
                            let groups = await myBible.lookupCrossReferences(book: book, chapter: ch, verse: vs)
                            await MainActor.run {
                                crossRefGroups    = groups
                                crossRefIsLoading = false
                            }
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
                        selectedVerseNote = nil
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
                        notesManager.delete(note)
                        selectedVerseNote = nil
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Delete note")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(theme.background)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(noteHeading(note))
                        .font(resolvedFont.weight(.semibold))
                        .foregroundStyle(theme.text)
                    if !note.verseReference.isEmpty {
                        Text(note.verseReference)
                            .font(.caption)
                            .foregroundStyle(filigreeAccent)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)

                Divider()

                ScrollView {
                    Text(note.content.isEmpty ? "Empty note" : note.content)
                        .font(resolvedFont)
                        .foregroundStyle(note.content.isEmpty ? theme.text.opacity(0.4) : theme.text)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(theme.background)

            } else {
                // ── All notes list with search ──────────────────────
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("Search notes...", text: $noteSearchText)
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

                let notes = filteredNotes
                if notes.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "note.text")
                            .font(.system(size: 28)).foregroundStyle(.quaternary)
                        Text(noteSearchText.isEmpty ? "No notes yet" : "No results")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity).background(theme.background)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(notes) { note in
                                HStack(alignment: .top, spacing: 8) {
                                    Button {
                                        selectedVerseNote = note
                                    } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(noteHeading(note))
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(theme.text).lineLimit(1)
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
                                            let preview = notePreview(note)
                                            if !preview.isEmpty {
                                                Text(preview)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(theme.text.opacity(0.65))
                                                    .lineLimit(2)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)

                                    VStack(spacing: 8) {
                                        if note.bookNumber > 0 {
                                            Button {
                                                // Open in Organizer editor
                                                NotificationCenter.default.post(
                                                    name: Notification.Name("noteCreatedFromVerse"),
                                                    object: nil,
                                                    userInfo: ["note": note])
                                            } label: {
                                                Image(systemName: "square.and.pencil")
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(filigreeAccent)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Open in Organizer editor")
                                        }
                                        Button { notesManager.delete(note) } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.red.opacity(0.6))
                                        }.buttonStyle(.plain).help("Delete note")
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(theme.background)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        notesManager.delete(note)
                                    } label: {
                                        Label("Delete Note", systemImage: "trash")
                                    }
                                }
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                    .background(theme.background)
                }
            }
        }
        .background(theme.background)
    }

    private var filteredNotes: [Note] {
        let all = notesManager.notes.sorted { $0.updatedAt > $1.updatedAt }
        let q = noteSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.title.lowercased().contains(q) ||
            $0.content.lowercased().contains(q) ||
            $0.verseReference.lowercased().contains(q)
        }
    }

    private func noteHeading(_ note: Note) -> String {
        let first = note.content.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        let clean = first.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        return clean.isEmpty ? note.title : clean
    }

    private func notePreview(_ note: Note) -> String {
        let lines = note.content.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { return "" }
        return lines.dropFirst().prefix(3).joined(separator: " ")
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
            encycIsLoading  = true
            Task {
                let result = await service.lookupWord(word: clean, in: service.selectedEncyclopedia)
                await MainActor.run {
                    encycWord       = result?.topic ?? clean
                    encycDefinition = result?.definition
                    encycIsLoading  = false
                }
            }
        }

        // Always update dictionary/strongs
        dictWord       = clean
        dictDefinition = nil
        dictIsLoading  = true
        modeRaw        = CompanionMode.strongs.rawValue

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
                    Picker("", selection: $commentaryModule) {
                        Text("Select…").tag(Optional<MyBibleModule>.none)
                        ForEach(commentaryModules) { m in Text(m.name).tag(Optional(m)) }
                    }
                    .labelsHidden().font(.caption)
                    .onChange(of: commentaryModule) { _ in load() }
                    .onAppear {
                        if commentaryModule == nil { commentaryModule = commentaryModules.first }
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
                    } else if strongsIsLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if let entry = strongsEntry {
                        strongsEntryView(entry)
                    } else {
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
                    } else if let def = encycDefinition {
                        Text(encycWord.capitalized)
                            .font(resolvedFont.weight(.bold))
                            .foregroundStyle(filigreeAccent)
                        Text(def)
                            .font(resolvedFont).lineSpacing(6)
                            .foregroundStyle(theme.text)
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
        // Header: number + lexeme
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(strongsNumber)
                .font(resolvedFont.weight(.bold)).foregroundStyle(filigreeAccent)
            if !entry.lexeme.isEmpty {
                Text(entry.lexeme).font(resolvedFont).foregroundStyle(theme.text)
            }
            Spacer()
        }
        // Transliteration / pronunciation
        if !entry.transliteration.isEmpty || !entry.pronunciation.isEmpty {
            Text([entry.transliteration, entry.pronunciation]
                    .filter { !$0.isEmpty }.joined(separator: "  ·  "))
                .font(resolvedFont.italic()).foregroundStyle(theme.secondary)
        }
        // Cross-references (ETCBC#, TWOT, GK, Greek/Hebrew equivalents)
        if !entry.references.isEmpty {
            Divider()
            Text(entry.references)
                .font(.system(size: CGFloat(fontSize) * 0.85))
                .foregroundStyle(theme.secondary)
                .lineSpacing(4)
        }
        Divider()
        // Strong's definition — prefer strongsDefinition, fall back to shortDefinition
        let definition = entry.strongsDefinition.isEmpty ? entry.shortDefinition : entry.strongsDefinition
        if !definition.isEmpty {
            Text("Strong's").font(resolvedFont.weight(.semibold)).foregroundStyle(theme.secondary)
            Text(definition).font(resolvedFont).lineSpacing(6).foregroundStyle(theme.text)
        }
        if !entry.derivation.isEmpty {
            Divider()
            Text("Derivation").font(resolvedFont.weight(.semibold)).foregroundStyle(theme.secondary)
            Text(entry.derivation).font(resolvedFont).lineSpacing(5).foregroundStyle(theme.text)
        }
        if !entry.kjv.isEmpty {
            Divider()
            Text("KJV Usage").font(resolvedFont.weight(.semibold)).foregroundStyle(theme.secondary)
            Text(entry.kjv).font(resolvedFont).lineSpacing(5).foregroundStyle(theme.text)
        }
        if !entry.cognates.isEmpty {
            Divider()
            Text("Cognates").font(resolvedFont.weight(.semibold)).foregroundStyle(theme.secondary)
            Text(entry.cognates.joined(separator: ", "))
                .font(resolvedFont).foregroundStyle(theme.secondary)
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
                if let m = commentaryModule {
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
            .onChange(of: syncedVerse) { v in
                if v > 0 && xrefBook == nil { withAnimation { proxy.scrollTo(v, anchor: .center) } }
            }
            .onChange(of: xrefVerse) { v in
                if v > 0 { withAnimation { proxy.scrollTo(v, anchor: .center) } }
            }
            .onChange(of: syncScrollVerse) { v in
                if v > 0 && xrefBook == nil { proxy.scrollTo(v, anchor: .top) }
            }
        }
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
                    .id(entry.verseFrom)
                }
            }
            .onChange(of: commentaryEntries) { _ in
                guard syncedVerse > 0,
                      let entry = commentaryEntries.first(where: {
                          $0.verseFrom <= syncedVerse && syncedVerse <= $0.verseTo
                      }) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation { proxy.scrollTo(entry.verseFrom, anchor: .top) }
                }
            }
            .onChange(of: syncedVerse) { v in
                guard v > 0, !commentaryEntries.isEmpty,
                      let entry = commentaryEntries.first(where: {
                          $0.verseFrom <= v && v <= $0.verseTo
                      }) else { return }
                withAnimation { proxy.scrollTo(entry.verseFrom, anchor: .top) }
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
            guard let module = commentaryModule else { isLoading = false; return }
            Task {
                let entries = await myBible.fetchCommentaryEntries(module: module,
                                                                   bookNumber: bookNumber, chapter: chapter)
                await MainActor.run { commentaryEntries = entries; isLoading = false }
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

