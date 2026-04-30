import SwiftUI
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SearchScope: String, CaseIterable {
    case all        = "All"
    case bible      = "Bible"
    case notes      = "Notes"
    case commentary = "Commentary"
    case reference  = "References"
}

enum Testament { case ot, nt, both }

struct SearchView: View {

    @EnvironmentObject var myBible:      MyBibleService
    @EnvironmentObject var notesManager: NotesManager

    @AppStorage("themeID")       private var themeID:      String = "light"
    @AppStorage("filigreeColor") private var filigreeColor: Int   = 0
    var theme: AppTheme { AppTheme.find(themeID) }
    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }

    // Search state
    @State private var query           = ""
    @State private var scope           = SearchScope.all
    @State private var results         = [SearchResult]()
    @State private var isSearching     = false
    @State private var debounceTimer:  Timer?
    @State private var showFilters     = false

    // Module filters
    @State private var selectedBibleIDs:      Set<String> = []   // empty = all
    @State private var selectedCommentaryIDs: Set<String> = []   // empty = all

    // Bible/Commentary scope filters
    @State private var testament:    Testament = .both
    @State private var bookFilter:   Int       = 0     // 0 = all books

    // Notes scope filters
    @State private var notesFrom:    Date?
    @State private var notesTo:      Date?

    var bibleModules:      [MyBibleModule] { myBible.visibleModules.filter { $0.type == .bible } }
    var commentaryModules: [MyBibleModule] { myBible.visibleModules.filter { $0.type == .commentary } }
    var referenceModules:  [MyBibleModule] { myBible.visibleModules.filter { $0.type == .dictionary || $0.type == .encyclopedia } }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            scopePicker
            Divider()

            if showFilters {
                filterPanel
                Divider()
            }

            resultArea
        }
        .background(theme.background)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search… use \"quotes\" for exact phrases", text: $query)
                .textFieldStyle(.plain)
                .onSubmit { runSearch() }
                .onChange(of: query) { scheduleSearch() }
            if !query.isEmpty {
                Button { query = ""; results = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFilters.toggle() }
            } label: {
                Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .foregroundStyle(showFilters ? filigreeAccent : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Show search filters")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(theme.background)
    }

    // MARK: - Scope picker

    private var scopePicker: some View {
        Picker("Scope", selection: $scope) {
            ForEach(SearchScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .tint(filigreeAccentFill)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(theme.background)
        .onChange(of: scope) { runSearch() }
    }

    // MARK: - Filter panel

    private var filterPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                // Bible module checkboxes
                if scope == .all || scope == .bible, !bibleModules.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BIBLE VERSIONS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(bibleModules) { module in
                            Toggle(module.name, isOn: Binding(
                                get: { selectedBibleIDs.isEmpty || selectedBibleIDs.contains(module.filePath) },
                                set: { on in
                                    if selectedBibleIDs.isEmpty {
                                        // All were selected — deselect all except this one
                                        selectedBibleIDs = Set(bibleModules.map(\.filePath))
                                    }
                                    if on { selectedBibleIDs.insert(module.filePath) }
                                    else  { selectedBibleIDs.remove(module.filePath) }
                                    if selectedBibleIDs.count == bibleModules.count { selectedBibleIDs = [] }
                                }
                            ))
                            .font(.caption)
                        }
                    }
                }

                // Commentary module checkboxes
                if scope == .all || scope == .commentary, !commentaryModules.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COMMENTARIES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(commentaryModules) { module in
                            Toggle(module.name, isOn: Binding(
                                get: { selectedCommentaryIDs.isEmpty || selectedCommentaryIDs.contains(module.filePath) },
                                set: { on in
                                    if selectedCommentaryIDs.isEmpty {
                                        selectedCommentaryIDs = Set(commentaryModules.map(\.filePath))
                                    }
                                    if on { selectedCommentaryIDs.insert(module.filePath) }
                                    else  { selectedCommentaryIDs.remove(module.filePath) }
                                    if selectedCommentaryIDs.count == commentaryModules.count { selectedCommentaryIDs = [] }
                                }
                            ))
                            .font(.caption)
                        }
                    }
                }

                // Testament filter
                if scope == .all || scope == .bible {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TESTAMENT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach([("Both", Testament.both), ("Old", .ot), ("New", .nt)], id: \.0) { label, t in
                                Button(label) { testament = t }
                                    .font(.caption)
                                    .foregroundStyle(testament == t ? Color.primary : filigreeAccent)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(testament == t ? filigreeAccentFill : filigreeAccent.opacity(0.12))
                                    .clipShape(Capsule())
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Book filter
                if scope == .all || scope == .bible {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BOOK").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Picker("Book", selection: $bookFilter) {
                            Text("All books").tag(0)
                            ForEach(myBibleBookOrder, id: \.self) { bn in
                                Text(myBibleBookNumbers[bn] ?? "\(bn)").tag(bn)
                            }
                        }
                        .labelsHidden()
                        .font(.caption)
                    }
                }

                // Notes date range
                if scope == .all || scope == .notes {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES DATE RANGE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        HStack {
                            Text("From").font(.caption).foregroundStyle(.secondary)
                            DatePicker("", selection: Binding(
                                get: { notesFrom ?? Date.distantPast },
                                set: { notesFrom = $0 }
                            ), displayedComponents: .date)
                            .labelsHidden().controlSize(.small)
                            if notesFrom != nil {
                                Button("Clear") { notesFrom = nil }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Text("To").font(.caption).foregroundStyle(.secondary)
                            DatePicker("", selection: Binding(
                                get: { notesTo ?? Date() },
                                set: { notesTo = $0 }
                            ), displayedComponents: .date)
                            .labelsHidden().controlSize(.small)
                            if notesTo != nil {
                                Button("Clear") { notesTo = nil }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Button("Apply Filters") { runSearch() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(filigreeAccentFill)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .frame(maxHeight: 280)
        .background(theme.background)
    }

    // MARK: - Result area

    @ViewBuilder
    private var resultArea: some View {
        if isSearching {
            VStack { Spacer(); ProgressView("Searching…"); Spacer() }
        } else if query.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "magnifyingglass").font(.system(size: 44)).foregroundStyle(.quaternary)
                Text("Search your Bible, notes,\ncommentary, and references")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Text("Wrap phrases in \u{201C}quotes\u{201D} for exact matching.\nUse filters to narrow Bible versions or books.")
                    .font(.caption).multilineTextAlignment(.center).foregroundStyle(.tertiary)
                    .padding(.horizontal)
                Spacer()
            }
        } else if results.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "magnifyingglass").font(.system(size: 44)).foregroundStyle(.quaternary)
                Text("No results for \"\(query)\"").foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let grouped = Dictionary(grouping: results, by: \.type)
                ForEach([SearchResult.ResultType.bible, .notes, .commentary, .reference], id: \.self) { type in
                    if let group = grouped[type], !group.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: type.icon).font(.caption)
                            Text(type.rawValue).font(.caption.weight(.semibold))
                            Text("(\(group.count))").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .foregroundStyle(filigreeAccent)
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)

                        ForEach(group) { result in
                            SearchResultRow(result: result, query: effectiveQuery,
                                           filigreeAccent: filigreeAccent, theme: theme)
                                .onTapGesture { navigate(to: result) }
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Query parsing

    /// Returns the actual search string (strips quotes for display/matching)
    private var effectiveQuery: String {
        query.trimmingCharacters(in: .whitespaces)
             .trimmingCharacters(in: CharacterSet(charactersIn: "\u{201C}\u{201D}\""))
    }

    /// True if user wrapped query in quotes = exact phrase
    private var isExactPhrase: Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return (q.hasPrefix("\"") && q.hasSuffix("\"")) ||
               (q.hasPrefix("\u{201C}") && q.hasSuffix("\u{201D}"))
    }

    // MARK: - Search scheduling

    private func scheduleSearch() {
        debounceTimer?.invalidate()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in runSearch() }
    }

    // MARK: - Run search

    private func runSearch() {
        let q = effectiveQuery
        guard !q.isEmpty else { results = []; return }

        struct ModuleInfo { let path: String; let name: String }

        // Capture MainActor data
        var bibleSet = [String: ModuleInfo]()
        if let sel = myBible.selectedBible,
           myBible.visibleModules.contains(sel) {
            bibleSet[sel.filePath] = ModuleInfo(path: sel.filePath, name: sel.name)
        }
        for m in myBible.visibleModules where m.type == .bible {
            if selectedBibleIDs.isEmpty || selectedBibleIDs.contains(m.filePath) {
                bibleSet[m.filePath] = ModuleInfo(path: m.filePath, name: m.name)
            }
        }
        let bibles = Array(bibleSet.values)

        let commentaries = myBible.visibleModules.filter {
            $0.type == .commentary &&
            (selectedCommentaryIDs.isEmpty || selectedCommentaryIDs.contains($0.filePath))
        }.map { ModuleInfo(path: $0.filePath, name: $0.name) }

        let references = selectedReferenceModules().map {
            ModuleInfo(path: $0.filePath, name: $0.name)
        }

        let capturedNotes   = notesManager.notes
        let capturedScope   = scope
        let capturedTest    = testament
        let capturedBook    = bookFilter
        let capturedFrom    = notesFrom
        let capturedTo      = notesTo
        let exact           = isExactPhrase

        isSearching = true
        results     = []

        DispatchQueue.global(qos: .userInitiated).async {
            var found = [SearchResult]()

            if capturedScope == .all || capturedScope == .bible {
                var seen = Set<String>()
                let allowBroadBibleFallback = !selectedBibleIDs.isEmpty || bibles.count <= 2
                for module in bibles {
                    let matches = searchBible(path: module.path, query: q,
                                             moduleName: module.name,
                                             testament: capturedTest,
                                             bookFilter: capturedBook,
                                             exact: exact,
                                             allowFallback: allowBroadBibleFallback || module.path == myBible.selectedBible?.filePath)
                    for r in matches {
                        let key = "\(r.moduleName):\(r.bookNumber):\(r.chapter):\(r.verse)"
                        if seen.insert(key).inserted { found.append(r) }
                    }
                }
            }

            if capturedScope == .all || capturedScope == .notes {
                found += searchNotes(capturedNotes, query: q,
                                     from: capturedFrom, to: capturedTo)
            }

            if capturedScope == .all || capturedScope == .commentary {
                for module in commentaries {
                    found += searchCommentary(path: module.path, query: q,
                                             moduleName: module.name, exact: exact)
                }
            }

            if capturedScope == .all || capturedScope == .reference {
                for module in references {
                    found += searchReference(path: module.path, query: q,
                                             moduleName: module.name, exact: exact)
                }
            }

            DispatchQueue.main.async {
                self.results    = found
                self.isSearching = false
            }
        }
    }

    // MARK: - Bible search

    private func searchBible(path: String, query: String, moduleName: String,
                             testament: Testament, bookFilter: Int, exact: Bool,
                             allowFallback: Bool) -> [SearchResult] {
        if path.hasSuffix(".graphe") {
            guard allowFallback else { return [] }
            return searchBibleFallback(
                db: openDatabase(at: path),
                path: path,
                query: query,
                moduleName: moduleName,
                testament: testament,
                bookFilter: bookFilter,
                exact: exact
            )
        }

        var out = [SearchResult]()
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return out }
        defer { sqlite3_close(db) }

        let ranges: [(Int, Int)]
        switch testament {
        case .ot:   ranges = [(10, 469)]
        case .nt:   ranges = [(470, 999)]
        case .both: ranges = [(10, 469), (470, 999)]
        }

        for (lo, hi) in ranges {
            let bookClause = bookFilter > 0
                ? "AND book_number = \(bookFilter)"
                : "AND book_number BETWEEN \(lo) AND \(hi)"

            let sql = "SELECT book_number, chapter, verse, text FROM verses WHERE text LIKE ? \(bookClause) ORDER BY book_number, chapter, verse LIMIT 300"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            sqlite3_bind_text(stmt, 1, "%\(query)%", -1, SQLITE_TRANSIENT)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let book    = Int(sqlite3_column_int(stmt, 0))
                let chapter = Int(sqlite3_column_int(stmt, 1))
                let verse   = Int(sqlite3_column_int(stmt, 2))
                let raw     = columnString(stmt, index: 3, filePath: path) ?? ""
                guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let clean    = cleanText(raw)
                // For exact phrase — verify after stripping markup
                if exact && !clean.localizedCaseInsensitiveContains(query) { continue }
                let bookName = myBibleBookNumbers[book] ?? "Book \(book)"
                out.append(SearchResult(type: .bible,
                    reference: "\(bookName) \(chapter):\(verse)",
                    snippet: makeSnippet(clean, matching: query),
                    moduleName: moduleName,
                    bookNumber: book, chapter: chapter, verse: verse, noteID: nil,
                    modulePath: path, lookupQuery: nil, referenceKind: nil))
            }
            sqlite3_finalize(stmt)
            if bookFilter > 0 { break }  // single book, no need to run second range
        }

        out.sort { ($0.bookNumber, $0.chapter, $0.verse) < ($1.bookNumber, $1.chapter, $1.verse) }
        return out
    }

    private func searchBibleFallback(db: OpaquePointer?,
                                     path: String,
                                     query: String,
                                     moduleName: String,
                                     testament: Testament,
                                     bookFilter: Int,
                                     exact: Bool) -> [SearchResult] {
        guard let db else { return [] }
        var out = [SearchResult]()

        let ranges: [(Int, Int)]
        switch testament {
        case .ot:   ranges = [(10, 469)]
        case .nt:   ranges = [(470, 999)]
        case .both: ranges = [(10, 469), (470, 999)]
        }

        for (lo, hi) in ranges {
            let bookClause = bookFilter > 0
                ? "AND book_number = \(bookFilter)"
                : "AND book_number BETWEEN \(lo) AND \(hi)"
            let sql = "SELECT book_number, chapter, verse, text FROM verses WHERE 1 = 1 \(bookClause) ORDER BY book_number, chapter, verse"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                let book = Int(sqlite3_column_int(stmt, 0))
                let chapter = Int(sqlite3_column_int(stmt, 1))
                let verse = Int(sqlite3_column_int(stmt, 2))
                let raw = columnString(stmt, index: 3, filePath: path) ?? ""
                let clean = cleanText(raw)
                guard !clean.isEmpty,
                      clean.localizedCaseInsensitiveContains(query) else { continue }
                if exact && !clean.localizedCaseInsensitiveContains(query) { continue }

                let bookName = myBibleBookNumbers[book] ?? "Book \(book)"
                out.append(SearchResult(
                    type: .bible,
                    reference: "\(bookName) \(chapter):\(verse)",
                    snippet: makeSnippet(clean, matching: query),
                    moduleName: moduleName,
                    bookNumber: book,
                    chapter: chapter,
                    verse: verse,
                    noteID: nil,
                    modulePath: path,
                    lookupQuery: nil,
                    referenceKind: nil
                ))

                if out.count >= 300 { return out }
            }

            if bookFilter > 0 { break }
        }

        return out
    }

    // MARK: - Commentary search

    private func searchCommentary(path: String, query: String,
                                   moduleName: String, exact: Bool) -> [SearchResult] {
        if path.hasSuffix(".graphe") {
            return searchCommentaryFallback(path: path, query: query, moduleName: moduleName, exact: exact)
        }

        var out = [SearchResult]()
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return out }
        defer { sqlite3_close(db) }
        let sqls = [
            "SELECT book_number, chapter_number_from, verse_number_from, text FROM commentaries WHERE text LIKE ? LIMIT 200",
            "SELECT book_number, chapter, verse, text FROM commentary WHERE text LIKE ? LIMIT 200",
        ]
        for sql in sqls {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                sqlite3_finalize(stmt); continue
            }
            sqlite3_bind_text(stmt, 1, "%\(query)%", -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let book    = Int(sqlite3_column_int(stmt, 0))
                let chapter = Int(sqlite3_column_int(stmt, 1))
                let verse   = Int(sqlite3_column_int(stmt, 2))
                let raw     = columnString(stmt, index: 3, filePath: path) ?? ""
                guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let clean    = cleanText(raw)
                if exact && !clean.localizedCaseInsensitiveContains(query) { continue }
                let bookName = myBibleBookNumbers[book] ?? "Book \(book)"
                out.append(SearchResult(type: .commentary,
                    reference: "\(bookName) \(chapter):\(verse)",
                    snippet: makeSnippet(clean, matching: query),
                    moduleName: moduleName,
                    bookNumber: book, chapter: chapter, verse: verse, noteID: nil,
                    modulePath: path, lookupQuery: nil, referenceKind: nil))
            }
            sqlite3_finalize(stmt)
            if !out.isEmpty { break }
        }
        return out
    }

    private func searchReference(path: String, query: String,
                                 moduleName: String, exact: Bool) -> [SearchResult] {
        if path.hasSuffix(".graphe") {
            return searchReferenceFallback(path: path, query: query, moduleName: moduleName, exact: exact)
        }

        var out = [SearchResult]()
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return out }
        defer { sqlite3_close(db) }

        let moduleType = myBible.visibleModules.first(where: { $0.filePath == path })?.type
        let referenceKind: SearchResult.ReferenceKind = moduleType == .encyclopedia ? .encyclopedia : .dictionary
        let sql = """
        SELECT topic, definition
        FROM dictionary
        WHERE topic LIKE ? OR definition LIKE ?
        ORDER BY CASE WHEN topic LIKE ? THEN 0 ELSE 1 END, topic
        LIMIT 150
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }

        let fuzzyPattern = "%\(query)%"
        let topicPrefixPattern = "\(query)%"
        sqlite3_bind_text(stmt, 1, fuzzyPattern, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, fuzzyPattern, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, topicPrefixPattern, -1, SQLITE_TRANSIENT)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let topic = columnString(stmt, index: 0, filePath: path) ?? ""
            let raw = columnString(stmt, index: 1, filePath: path) ?? ""
            let clean = cleanText(raw)
            if exact,
               !topic.localizedCaseInsensitiveContains(query),
               !clean.localizedCaseInsensitiveContains(query) {
                continue
            }

            let snippetSource = clean.isEmpty ? topic : clean
            out.append(SearchResult(
                type: .reference,
                reference: topic,
                snippet: makeSnippet(snippetSource, matching: query),
                moduleName: moduleName,
                bookNumber: 0,
                chapter: 0,
                verse: 0,
                noteID: nil,
                modulePath: path,
                lookupQuery: topic,
                referenceKind: referenceKind
            ))
        }

        return out
    }

    private func searchCommentaryFallback(path: String, query: String,
                                          moduleName: String, exact: Bool) -> [SearchResult] {
        guard let db = openDatabase(at: path) else { return [] }
        defer { sqlite3_close(db) }

        let sqls = [
            "SELECT book_number, chapter_number_from, verse_number_from, text FROM commentaries LIMIT 2000",
            "SELECT book_number, chapter, verse, text FROM commentary LIMIT 2000",
        ]
        var out = [SearchResult]()

        for sql in sqls {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                sqlite3_finalize(stmt)
                continue
            }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                let book = Int(sqlite3_column_int(stmt, 0))
                let chapter = Int(sqlite3_column_int(stmt, 1))
                let verse = Int(sqlite3_column_int(stmt, 2))
                let raw = columnString(stmt, index: 3, filePath: path) ?? ""
                let clean = cleanText(raw)
                guard !clean.isEmpty,
                      clean.localizedCaseInsensitiveContains(query) else { continue }
                if exact && !clean.localizedCaseInsensitiveContains(query) { continue }

                let bookName = myBibleBookNumbers[book] ?? "Book \(book)"
                out.append(SearchResult(
                    type: .commentary,
                    reference: "\(bookName) \(chapter):\(verse)",
                    snippet: makeSnippet(clean, matching: query),
                    moduleName: moduleName,
                    bookNumber: book,
                    chapter: chapter,
                    verse: verse,
                    noteID: nil,
                    modulePath: path,
                    lookupQuery: nil,
                    referenceKind: nil
                ))
                if out.count >= 200 { return out }
            }

            if !out.isEmpty { break }
        }

        return out
    }

    private func searchReferenceFallback(path: String, query: String,
                                         moduleName: String, exact: Bool) -> [SearchResult] {
        guard let db = openDatabase(at: path) else { return [] }
        defer { sqlite3_close(db) }

        let moduleType = myBible.visibleModules.first(where: { $0.filePath == path })?.type
        let referenceKind: SearchResult.ReferenceKind = moduleType == .encyclopedia ? .encyclopedia : .dictionary
        let sql = "SELECT topic, definition FROM dictionary LIMIT 4000"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var out = [SearchResult]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let topic = columnString(stmt, index: 0, filePath: path) ?? ""
            let raw = columnString(stmt, index: 1, filePath: path) ?? ""
            let clean = cleanText(raw)
            guard topic.localizedCaseInsensitiveContains(query) || clean.localizedCaseInsensitiveContains(query) else {
                continue
            }
            if exact &&
                !topic.localizedCaseInsensitiveContains(query) &&
                !clean.localizedCaseInsensitiveContains(query) {
                continue
            }

            let snippetSource = clean.isEmpty ? topic : clean
            out.append(SearchResult(
                type: .reference,
                reference: topic,
                snippet: makeSnippet(snippetSource, matching: query),
                moduleName: moduleName,
                bookNumber: 0,
                chapter: 0,
                verse: 0,
                noteID: nil,
                modulePath: path,
                lookupQuery: topic,
                referenceKind: referenceKind
            ))

            if out.count >= 150 { return out }
        }

        return out
    }

    // MARK: - Notes search

    private func searchNotes(_ notes: [Note], query: String,
                              from: Date?, to: Date?) -> [SearchResult] {
        notes.compactMap { note in
            // Date range filter
            if let f = from, note.updatedAt < f { return nil }
            if let t = to {
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: t) ?? t
                if note.updatedAt > endOfDay { return nil }
            }
            let inTitle   = note.displayTitle.localizedCaseInsensitiveContains(query)
            let inContent = note.content.localizedCaseInsensitiveContains(query)
            guard inTitle || inContent else { return nil }
            let text = inTitle ? note.displayTitle + " " + note.content : note.content
            return SearchResult(type: .notes, reference: note.displayTitle,
                snippet: makeSnippet(text, matching: query),
                moduleName: "Notes",
                bookNumber: note.bookNumber, chapter: note.chapterNumber,
                verse: 0, noteID: note.id,
                modulePath: nil, lookupQuery: nil, referenceKind: nil)
        }
    }

    private func selectedReferenceModules() -> [MyBibleModule] {
        var modules: [MyBibleModule] = []
        if let dictionary = myBible.selectedDictionary,
           myBible.visibleModules.contains(dictionary) {
            modules.append(dictionary)
        }
        if let encyclopedia = myBible.selectedEncyclopedia,
           myBible.visibleModules.contains(encyclopedia),
           !modules.contains(encyclopedia) {
            modules.append(encyclopedia)
        }
        if modules.isEmpty {
            if let dictionary = referenceModules.first(where: { $0.type == .dictionary }) {
                modules.append(dictionary)
            }
            if let encyclopedia = referenceModules.first(where: { $0.type == .encyclopedia }),
               !modules.contains(encyclopedia) {
                modules.append(encyclopedia)
            }
        }
        return modules
    }

    // MARK: - Text cleaning

    private func cleanText(_ raw: String) -> String {
        var t = raw
        while let o = t.range(of: "<S>"), let c = t.range(of: "</S>", range: o.lowerBound..<t.endIndex) {
            t.removeSubrange(o.lowerBound..<c.upperBound)
        }
        return decodeHTMLEntities(StrongsParser.stripAllTags(t))
    }

    private func openDatabase(at path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        return db
    }

    private func columnString(_ stmt: OpaquePointer?, index: Int32, filePath: String) -> String? {
        let type = sqlite3_column_type(stmt, index)
        switch type {
        case SQLITE_BLOB:
            let length = sqlite3_column_bytes(stmt, index)
            let blob = sqlite3_column_blob(stmt, index)?.assumingMemoryBound(to: UInt8.self)
            return grapheDecrypt(blob, length, filePath: filePath)
        case SQLITE_TEXT:
            if filePath.hasSuffix(".graphe") {
                let length = sqlite3_column_bytes(stmt, index)
                let blob = sqlite3_column_blob(stmt, index)?.assumingMemoryBound(to: UInt8.self)
                return grapheDecrypt(blob, length, filePath: filePath)
            }
            return sqlite3_column_text(stmt, index).map { String(cString: $0) }
        default:
            return nil
        }
    }

    private func decodeHTMLEntities(_ input: String) -> String {
        var s = input
        let namedEntities: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'"
        ]
        for (entity, replacement) in namedEntities {
            s = s.replacingOccurrences(of: entity, with: replacement)
        }

        let pattern = #"&#(x?[0-9A-Fa-f]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let nsString = s as NSString
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: nsString.length)).reversed()
        var result = s

        for match in matches {
            let token = nsString.substring(with: match.range(at: 1))
            let scalarValue: UInt32?
            if token.lowercased().hasPrefix("x") {
                scalarValue = UInt32(token.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(token, radix: 10)
            }

            guard let scalarValue,
                  let scalar = UnicodeScalar(scalarValue) else { continue }
            let replacement = String(scalar)
            let range = Range(match.range, in: result)!
            result.replaceSubrange(range, with: replacement)
        }

        return result
    }

    // MARK: - Navigation

    private func navigate(to result: SearchResult) {
        switch result.type {
        case .bible:
            NotificationCenter.default.post(name: .navigateToPassage, object: nil,
                userInfo: ["bookNumber": result.bookNumber, "chapter": result.chapter,
                           "verse": result.verse, "moduleName": result.moduleName])
        case .commentary:
            NotificationCenter.default.post(name: .navigateToCommentary, object: nil,
                userInfo: ["bookNumber": result.bookNumber, "chapter": result.chapter,
                           "moduleName": result.moduleName])
        case .reference:
            guard let modulePath = result.modulePath,
                  let lookupQuery = result.lookupQuery else { return }
            NotificationCenter.default.post(name: Notification.Name("switchToBibleTab"), object: nil)
            if result.referenceKind == .encyclopedia {
                if let module = myBible.visibleModules.first(where: { $0.filePath == modulePath }) {
                    myBible.selectedEncyclopedia = module
                }
                UserDefaults.standard.set(CompanionMode.encyclopedia.rawValue, forKey: "companionMode")
                NotificationCenter.default.post(
                    name: Notification.Name("lookupEncyclopediaWord"),
                    object: nil,
                    userInfo: ["word": lookupQuery]
                )
            } else {
                if let module = myBible.visibleModules.first(where: { $0.filePath == modulePath }) {
                    myBible.selectedDictionary = module
                }
                UserDefaults.standard.set(CompanionMode.strongs.rawValue, forKey: "companionMode")
                NotificationCenter.default.post(
                    name: Notification.Name("lookupDictionaryWord"),
                    object: nil,
                    userInfo: ["word": lookupQuery]
                )
            }
        case .notes:
            if let id = result.noteID {
                notesManager.searchHighlight = effectiveQuery
                notesManager.selectedNote = notesManager.notes.first { $0.id == id }
                NotificationCenter.default.post(name: Notification.Name("switchToNotesTab"), object: nil)
            }
        }
    }
}

// MARK: - Result Row

struct SearchResultRow: View {
    let result:         SearchResult
    let query:          String
    let filigreeAccent: Color
    let theme:          AppTheme
    @AppStorage("fontSize") private var fontSize: Double = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(result.reference)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(filigreeAccent)
                Spacer()
                if result.type != .notes {
                    Text(result.moduleName)
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            Text(result.snippet)
                .font(.system(size: max(12, fontSize - 2)))
                .foregroundStyle(theme.text)
                .lineLimit(3)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
