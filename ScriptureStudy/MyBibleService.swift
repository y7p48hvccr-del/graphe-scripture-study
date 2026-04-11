import Foundation
import SQLite3

// MARK: - Module Types

enum ModuleType: String, CaseIterable {
    case bible          = "Bible"
    case commentary     = "Commentary"
    case crossRef       = "Cross-References"
    case crossRefNative = "Cross-References (Native)"
    case devotional     = "Devotional"
    case readingPlan    = "Reading Plan"
    case strongs        = "Strong's"
    case dictionary     = "Dictionary"
    case encyclopedia   = "Encyclopedia"
    case subheadings    = "Subheadings"
    case wordIndex      = "Word Index"
    case unknown        = "Other"
}

// MARK: - Module

struct MyBibleModule: Identifiable, Hashable {
    let id          = UUID()
    let name:        String
    let description: String
    let language:    String
    let type:        ModuleType
    let filePath:    String

    static func == (lhs: MyBibleModule, rhs: MyBibleModule) -> Bool { lhs.filePath == rhs.filePath }
    func hash(into hasher: inout Hasher) { hasher.combine(filePath) }
}

// MARK: - Verse

struct MyBibleVerse: Identifiable, Equatable {
    let id      = UUID()
    let book:    Int
    let chapter: Int
    let verse:   Int
    let text:    String
}

// MARK: - Commentary Entry

struct CommentaryEntry: Identifiable, Equatable {
    let id          = UUID()
    let bookNumber:  Int
    let chapterFrom: Int
    let verseFrom:   Int
    let chapterTo:   Int
    let verseTo:     Int
    let text:        String

    static func == (lhs: CommentaryEntry, rhs: CommentaryEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Dictionary Entry

struct DictionaryEntry: Identifiable, Hashable {
    let id         = UUID()
    let topic:     String
    let definition: String
}

// MARK: - MyBible Book Number Map

let myBibleBookNumbers: [Int: String] = [
    10:"Genesis", 20:"Exodus", 30:"Leviticus", 40:"Numbers", 50:"Deuteronomy",
    60:"Joshua", 70:"Judges", 80:"Ruth", 90:"1 Samuel", 100:"2 Samuel",
    110:"1 Kings", 120:"2 Kings", 130:"1 Chronicles", 140:"2 Chronicles",
    150:"Ezra", 160:"Nehemiah", 190:"Esther", 220:"Job", 230:"Psalms",
    240:"Proverbs", 250:"Ecclesiastes", 260:"Song of Solomon", 290:"Isaiah",
    300:"Jeremiah", 310:"Lamentations", 330:"Ezekiel", 340:"Daniel",
    350:"Hosea", 360:"Joel", 370:"Amos", 380:"Obadiah", 390:"Jonah",
    400:"Micah", 410:"Nahum", 420:"Habakkuk", 430:"Zephaniah", 440:"Haggai",
    450:"Zechariah", 460:"Malachi",
    470:"Matthew", 480:"Mark", 490:"Luke", 500:"John", 510:"Acts",
    520:"Romans", 530:"1 Corinthians", 540:"2 Corinthians", 550:"Galatians",
    560:"Ephesians", 570:"Philippians", 580:"Colossians",
    590:"1 Thessalonians", 600:"2 Thessalonians",
    610:"1 Timothy", 620:"2 Timothy", 630:"Titus", 640:"Philemon",
    650:"Hebrews", 660:"James", 670:"1 Peter", 680:"2 Peter",
    690:"1 John", 700:"2 John", 710:"3 John", 720:"Jude", 730:"Revelation"
]

let myBibleBookOrder: [Int] = myBibleBookNumbers.keys.sorted()

// MARK: - MyBible Service

@MainActor
class MyBibleService: ObservableObject {

    @Published var modules:          [MyBibleModule] = []
    @Published var hiddenModules:     Set<String>     = []   // file paths of hidden modules
    @Published var selectedBible:      MyBibleModule? { didSet { selectedBiblePath      = selectedBible?.filePath      ?? "" } }
    @Published var selectedStrongs:    MyBibleModule? { didSet { selectedStrongsPath    = selectedStrongs?.filePath    ?? "" } }
    @Published var selectedDictionary:    MyBibleModule?
    @Published var selectedEncyclopedia:  MyBibleModule?
    @Published var selectedCrossRef:      MyBibleModule?
    @Published var selectedDevotional:  MyBibleModule? { didSet { selectedDictionaryPath = selectedDictionary?.filePath ?? "" } }
    @Published var rawVerseTexts:    [Int: String]    = [:]

    // Persisted selection paths
    var selectedBiblePath:      String { get { UserDefaults.standard.string(forKey: "selectedBiblePath") ?? "" }      set { UserDefaults.standard.set(newValue, forKey: "selectedBiblePath") } }
    var selectedStrongsPath:    String { get { UserDefaults.standard.string(forKey: "selectedStrongsPath") ?? "" }    set { UserDefaults.standard.set(newValue, forKey: "selectedStrongsPath") } }
    var selectedDictionaryPath: String { get { UserDefaults.standard.string(forKey: "selectedDictionaryPath") ?? "" } set { UserDefaults.standard.set(newValue, forKey: "selectedDictionaryPath") } }
    @Published var verses:           [MyBibleVerse]  = []
    @Published var commentaryEntries:[CommentaryEntry] = []
    @Published var dictionaryEntries:[DictionaryEntry] = []
    @Published var isLoading         = false
    @Published var errorMessage:     String?
    @Published var currentPassage:   String  = ""
    @Published var currentBookNumber: Int     = 0
    @Published var currentChapter:    Int     = 0

    @Published var modulesFolder:    String = "" {
        didSet {
            UserDefaults.standard.set(modulesFolder, forKey: "modulesFolder")
            Task { await scanModules() }
        }
    }

    init() {
        modulesFolder = UserDefaults.standard.string(forKey: "modulesFolder") ?? ""
        if let paths = UserDefaults.standard.array(forKey: "hiddenModules") as? [String] {
            hiddenModules = Set(paths)
        }
        if !modulesFolder.isEmpty {
            Task { await scanModules() }
        }
    }

    // MARK: - Module visibility

    func toggleHidden(_ module: MyBibleModule) {
        if hiddenModules.contains(module.filePath) {
            hiddenModules.remove(module.filePath)
        } else {
            hiddenModules.insert(module.filePath)
        }
        UserDefaults.standard.set(Array(hiddenModules), forKey: "hiddenModules")
    }

    func saveHiddenModules() {
        UserDefaults.standard.set(Array(hiddenModules), forKey: "hiddenModules")
    }

    var visibleModules: [MyBibleModule] {
        modules.filter { !hiddenModules.contains($0.filePath) }
    }

    // MARK: - Scan folder for modules

    func scanModules() async {
        guard !modulesFolder.isEmpty else { return }
        await MainActor.run { isLoading = true; errorMessage = nil }

        let fm  = FileManager.default
        let url = URL(fileURLWithPath: modulesFolder)

        // Recursive scan — find SQLite files in subfolders too
        var sqliteFiles: [URL] = []
        if let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let allURLs = enumerator.compactMap { $0 as? URL }
            sqliteFiles = allURLs.filter {
                ["sqlite3","sqlite","db"].contains($0.pathExtension.lowercased())
            }
        } else {
            errorMessage = "Could not read folder. Please select it again."
            isLoading = false
            return
        }

        var found: [MyBibleModule] = []
        for file in sqliteFiles {
            if let module = await inspectModule(at: file.path) {
                found.append(module)
            }
        }

        modules = found.sorted { $0.name < $1.name }

        // Restore saved selections, fall back to first available
        let bPath = selectedBiblePath
        let sPath = selectedStrongsPath
        let dPath = selectedDictionaryPath

        if !bPath.isEmpty, let m = modules.first(where: { $0.filePath == bPath }) {
            selectedBible = m
        } else if selectedBible == nil {
            selectedBible = modules.first(where: { $0.type == .bible })
        }
        if !sPath.isEmpty, let m = modules.first(where: { $0.filePath == sPath }) {
            selectedStrongs = m
        } else if selectedStrongs == nil {
            selectedStrongs = modules.first(where: { $0.type == .strongs })
        }
        // Auto-select devotional
        if selectedDevotional == nil {
            selectedDevotional = modules.first(where: { $0.type == .devotional })
        }
        // Auto-select encyclopedia
        if selectedEncyclopedia == nil {
            selectedEncyclopedia = modules.first(where: { $0.type == .encyclopedia })
        }
        // Auto-select cross-reference module (prefer native format)
        if selectedCrossRef == nil {
            selectedCrossRef = modules.first(where: { $0.type == .crossRefNative })
                            ?? modules.first(where: { $0.type == .crossRef })
        }
        if !dPath.isEmpty, let m = modules.first(where: { $0.filePath == dPath }) {
            selectedDictionary = m
        } else if selectedDictionary == nil {
            selectedDictionary = modules.first(where: { $0.type == .dictionary })
        }

        isLoading = false
    }

    // MARK: - Inspect a SQLite3 file to determine module type

    private func inspectModule(at path: String) async -> MyBibleModule? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        // Read info table
        var info: [String: String] = [:]
        if let stmt = query(db: db, sql: "SELECT name, value FROM info") {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let keyPtr = sqlite3_column_text(stmt, 0),
                      let valPtr = sqlite3_column_text(stmt, 1) else { continue }
                let key = String(cString: keyPtr)
                let val = String(cString: valPtr)
                info[key] = val
            }
            sqlite3_finalize(stmt)
        }

        // Determine type from tables present + is_strong flag
        let tables      = getTableNames(db: db)
        let isStrongs   = info["is_strong"]?.lowercased() == "true"
        let isFootnotes = info["is_footnotes"]?.lowercased() == "true"
        let desc        = (info["description"] ?? "").lowercased()
        let filename    = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        let isCrossRef  = tables.contains("commentaries") &&
            (isFootnotes ||
             desc.contains("treasury") || desc.contains("cross ref") ||
             desc.contains("cross-ref") || desc.contains("tsk") ||
             desc.contains("footnote") || desc.contains("cross-reference") ||
             filename.contains(".crossreferences.") || filename.contains("-x."))
        let isNativeCrossRef = tables.contains("cross_references")
        let isDevotional     = tables.contains("devotions")
        let isReadingPlan    = tables.contains("reading_plan")
        let isSubheadings    = tables.contains("subheadings")
        let isWordIndex      = (tables.contains("words") || tables.contains("words_processing"))
                               && !tables.contains("dictionary")
                               && !tables.contains("verses")
        let encyclopaediaKeywords = ["encyclop", "handbook", "companion to the bible",
                                     "isbe", "easton", "hastings", "smith's bible",
                                     "unger", "zondervan", "naves", "nave's"]
        let isEncyclopedia   = tables.contains("dictionary") && !isStrongs &&
                               encyclopaediaKeywords.contains(where: { desc.contains($0) || filename.contains($0) })
        let type: ModuleType
        if tables.contains("verses")               { type = .bible }
        else if isDevotional                       { type = .devotional }
        else if isReadingPlan                      { type = .readingPlan }
        else if isNativeCrossRef                   { type = .crossRefNative }
        else if isCrossRef                         { type = .crossRef }
        else if isSubheadings                      { type = .subheadings }
        else if isWordIndex                        { type = .wordIndex }
        else if tables.contains("commentaries")    { type = .commentary }
        else if tables.contains("dictionary") && isStrongs      { type = .strongs }
        else if isEncyclopedia                     { type = .encyclopedia }
        else if tables.contains("dictionary")      { type = .dictionary }
        else { type = .unknown }

        let name = info["description"]
            ?? info["name"]
            ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let language = info["language"] ?? "en"

        return MyBibleModule(
            name:        name,
            description: name,
            language:    language,
            type:        type,
            filePath:    path
        )
    }

    nonisolated private func getTableNames(db: OpaquePointer?) -> [String] {
        var tables: [String] = []
        if let stmt = query(db: db, sql: "SELECT name FROM sqlite_master WHERE type='table'") {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let ptr = sqlite3_column_text(stmt, 0) else { continue }
                tables.append(String(cString: ptr))
            }
            sqlite3_finalize(stmt)
        }
        return tables
    }

    // MARK: - Load Bible chapter


    // Load verses for a module without affecting main state (used by ComparisonPanelView)
    func loadChapterVerses(module: MyBibleModule, bookNumber: Int, chapter: Int) async -> [MyBibleVerse] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }
        let sql = "SELECT book_number, chapter, verse, text FROM verses WHERE book_number = ? AND chapter = ? ORDER BY verse"
        guard let stmt = query(db: db, sql: sql) else { return [] }
        sqlite3_bind_int(stmt, 1, Int32(bookNumber))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        var results: [MyBibleVerse] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let ptr = sqlite3_column_text(stmt, 3) else { continue }
            let raw = String(cString: ptr)
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            results.append(MyBibleVerse(
                book:    Int(sqlite3_column_int(stmt, 0)),
                chapter: Int(sqlite3_column_int(stmt, 1)),
                verse:   Int(sqlite3_column_int(stmt, 2)),
                text:    raw  // return raw text — callers strip as needed
            ))
        }
        sqlite3_finalize(stmt)
        return results
    }

    func loadChapter(module: MyBibleModule, bookNumber: Int, chapter: Int) async {
        isLoading = true
        errorMessage = nil
        verses = []

        var db: OpaquePointer?
        guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            errorMessage = "Could not open module file."
            isLoading = false
            return
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT book_number, chapter, verse, text FROM verses WHERE book_number = ? AND chapter = ? ORDER BY verse"
        if let stmt = query(db: db, sql: sql) {
            sqlite3_bind_int(stmt, 1, Int32(bookNumber))
            sqlite3_bind_int(stmt, 2, Int32(chapter))
            var results: [MyBibleVerse] = []
            var rawTexts: [Int: String] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let raw  = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
                // Skip empty verses (The Message and some other translations
                // group multiple traditional verses into one row)
                guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let vnum = Int(sqlite3_column_int(stmt, 2))
                rawTexts[vnum] = raw
                results.append(MyBibleVerse(
                    book:    Int(sqlite3_column_int(stmt, 0)),
                    chapter: Int(sqlite3_column_int(stmt, 1)),
                    verse:   vnum,
                    text:    stripStrongsAndTags(raw)
                ))
            }
            sqlite3_finalize(stmt)
            verses       = results
            rawVerseTexts = rawTexts
            print("[MyBible] verses set: count=\(results.count) first=\(results.first?.text.prefix(40) ?? "nil")")
        }

        if verses.isEmpty {
            errorMessage = "No verses found for this chapter."
        } else {
            let bookName   = myBibleBookNumbers[bookNumber] ?? module.name
            currentPassage    = "\(bookName) \(chapter)"
            currentBookNumber = bookNumber
            currentChapter    = chapter
            NotificationCenter.default.post(
                name: Notification.Name("biblePassageChanged"),
                object: nil,
                userInfo: ["bookNumber": bookNumber, "chapter": chapter]
            )
        }

        isLoading = false
    }

    // MARK: - Load Commentary

    func loadCommentary(module: MyBibleModule, bookNumber: Int, chapter: Int) async {
        commentaryEntries = []
        var db: OpaquePointer?
        guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT book_number, chapter_number_from, verse_number_from,
                   chapter_number_to, verse_number_to, text
            FROM commentaries
            WHERE book_number = ? AND chapter_number_from = ?
            ORDER BY verse_number_from
            """
        if let stmt = query(db: db, sql: sql) {
            sqlite3_bind_int(stmt, 1, Int32(bookNumber))
            sqlite3_bind_int(stmt, 2, Int32(chapter))
            var results: [CommentaryEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let text = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
                results.append(CommentaryEntry(
                    bookNumber:  Int(sqlite3_column_int(stmt, 0)),
                    chapterFrom: Int(sqlite3_column_int(stmt, 1)),
                    verseFrom:   Int(sqlite3_column_int(stmt, 2)),
                    chapterTo:   Int(sqlite3_column_int(stmt, 3)),
                    verseTo:     Int(sqlite3_column_int(stmt, 4)),
                    text:        stripTags(text)
                ))
            }
            sqlite3_finalize(stmt)
            commentaryEntries = results
        }
    }

    // MARK: - Search Dictionary

    func searchDictionary(module: MyBibleModule, query searchTerm: String) async {
        dictionaryEntries = []
        var db: OpaquePointer?
        guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }

        let sql = searchTerm.isEmpty
            ? "SELECT topic, definition FROM dictionary ORDER BY topic LIMIT 100"
            : "SELECT topic, definition FROM dictionary WHERE topic LIKE ? ORDER BY topic LIMIT 100"

        if let stmt = query(db: db, sql: sql) {
            if !searchTerm.isEmpty {
                let pattern = "%\(searchTerm)%"
                sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
            }
            var results: [DictionaryEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let topic = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let def   = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                results.append(DictionaryEntry(topic: topic, definition: stripTags(def)))
            }
            sqlite3_finalize(stmt)
            dictionaryEntries = results
        }
    }

    // MARK: - Helpers

    nonisolated private func query(db: OpaquePointer?, sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    /// Strip basic HTML tags from MyBible text
    private func stripTags(_ input: String) -> String {
        var result = input
        // Remove <pb> page break markers
        result = result.replacingOccurrences(of: "<pb/>", with: "\n")
        // Remove all other HTML tags
        while let start = result.range(of: "<"),
              let end   = result.range(of: ">", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound...end.lowerBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Get available books in a Bible module

    // MARK: - Look up book number by name in a specific module

    /// Searches the module's books table for a matching book number.
    /// Falls back to the standard MyBible hardcoded numbers if no books table exists.
    @MainActor
    func bookNumber(forName name: String, in module: MyBibleModule) -> Int? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        let nameLower = name.lowercased()

        // Try books table first (long_name and short_name)
        if let stmt = query(db: db, sql: "SELECT book_number, short_name, long_name FROM books") {
            var matches: [(Int, Int)] = [] // (bookNum, matchQuality)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let bn        = Int(sqlite3_column_int(stmt, 0))
                let shortName = sqlite3_column_text(stmt, 1).map { String(cString: $0) }?.lowercased() ?? ""
                let longName  = sqlite3_column_text(stmt, 2).map { String(cString: $0) }?.lowercased() ?? ""
                if longName == nameLower { matches.append((bn, 3)) }
                else if shortName == nameLower { matches.append((bn, 2)) }
                else if longName.hasPrefix(nameLower) || nameLower.hasPrefix(longName) { matches.append((bn, 1)) }
            }
            sqlite3_finalize(stmt)
            if let best = matches.max(by: { $0.1 < $1.1 }) { return best.0 }
        }
        return nil
    }

    func availableBooks(in module: MyBibleModule) -> [Int] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        var books: [Int] = []
        if let stmt = query(db: db, sql: "SELECT DISTINCT book_number FROM verses ORDER BY book_number") {
            while sqlite3_step(stmt) == SQLITE_ROW {
                books.append(Int(sqlite3_column_int(stmt, 0)))
            }
            sqlite3_finalize(stmt)
        }
        return books
    }

    // MARK: - Get chapter count for a book

    func chapterCount(module: MyBibleModule, bookNumber: Int) -> Int {
        var db: OpaquePointer?
        guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return 1 }
        defer { sqlite3_close(db) }

        var count = 1
        if let stmt = query(db: db, sql: "SELECT MAX(chapter) FROM verses WHERE book_number = ?") {
            sqlite3_bind_int(stmt, 1, Int32(bookNumber))
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }
        return max(count, 1)
    }

    // MARK: - Lookup Strong\'s number in dictionary module

    // Sync lookup for use in views
    func lookupStrongs(_ number: String) -> StrongsEntry? { nil }  // placeholder — async lookup used in CompanionPanel

    // Book number to OSIS code for timeline
    static func bookNumberToOsisCode(_ n: Int) -> String {
        // MyBible uses multiples of 10: Genesis=10, Exodus=20 ... Revelation=660
        let map: [Int: String] = [
            10:"GEN", 20:"EXO", 30:"LEV", 40:"NUM", 50:"DEU",
            60:"JOS", 70:"JDG", 80:"RUT", 90:"1SA", 100:"2SA",
            110:"1KI", 120:"2KI", 130:"1CH", 140:"2CH", 150:"EZR",
            160:"NEH", 170:"EST", 180:"JOB", 190:"PSA", 220:"PRO",
            230:"ECC", 240:"SNG", 250:"ISA", 260:"JER", 270:"LAM",
            280:"EZK", 290:"DAN", 300:"HOS", 310:"JOL", 320:"AMO",
            330:"OBA", 340:"JON", 350:"MIC", 360:"NAH", 370:"HAB",
            380:"ZEP", 390:"HAG", 400:"ZEC", 410:"MAL",
            470:"MAT", 480:"MRK", 490:"LUK", 500:"JHN", 510:"ACT",
            520:"ROM", 530:"1CO", 540:"2CO", 550:"GAL", 560:"EPH",
            570:"PHP", 580:"COL", 590:"1TH", 600:"2TH", 610:"1TI",
            620:"2TI", 630:"TIT", 640:"PHM", 650:"HEB", 660:"JAS",
            670:"1PE", 680:"2PE", 690:"1JN", 700:"2JN", 710:"3JN",
            720:"JUD", 730:"REV"
        ]
        return map[n] ?? ""
    }

    func lookupStrongs(module: MyBibleModule, number: String, isOldTestament: Bool = false) async -> StrongsEntry? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        let digits    = String(number.drop(while: { !$0.isNumber }))
        let prefix    = number.first.map(String.init) ?? ""
        let hasPrefix = prefix == "G" || prefix == "H"
        var keys      = [number, digits]
        if !hasPrefix {
            // No prefix — use book context to prefer Hebrew (OT) or Greek (NT)
            if isOldTestament {
                keys += ["H" + digits, "G" + digits]
            } else {
                keys += ["G" + digits, "H" + digits]
            }
        }

        var foundRow: (String, String, String, String, String, String)?

        for key in keys {
            let sql = "SELECT topic, lexeme, transliteration, pronunciation, short_definition, definition FROM dictionary WHERE topic = ? LIMIT 1"
            if let stmt = query(db: db, sql: sql) {
                sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let t  = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? key
                    let l  = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                    let tr = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                    let pr = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
                    let sd = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
                    let df = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
                    sqlite3_finalize(stmt)
                    foundRow = (t, l, tr, pr, sd, df)
                    break
                }
                sqlite3_finalize(stmt)
            }
        }

        guard let (topic, lexeme, translit, pronunc, shortDef, rawDef) = foundRow else { return nil }

        let body  = parseDefinitionBody(rawDef)

        // Try labelled extraction first (ETCBC+ format has explicit Bold labels)
        var derivation = extractLabel(body, label: "Derivation")
        var kjv        = extractLabel(body, label: "KJV")
        let strongs    = extractLabel(body, label: "Strong\'s")

        // If labelled extraction found nothing, fall back to ": - " split (standard Strong's format)
        if derivation.isEmpty && kjv.isEmpty && strongs.isEmpty {
            let parts  = body.components(separatedBy: ": - ")
            derivation = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
            kjv        = parts.count > 1
                ? parts[1...].joined(separator: ": - ").trimmingCharacters(in: .whitespaces)
                : ""
        }

        // Extract cross-reference section (section 1 in ETCBC+ format — between first and second <hr>)
        let references = extractReferencesSection(rawDef)

        // Fetch cognates
        var cognates: [String] = []
        let cogSql = """
            SELECT strong_number FROM cognate_strong_numbers
            WHERE group_id = (SELECT group_id FROM cognate_strong_numbers WHERE strong_number = ?)
            AND strong_number != ?
            """
        if let stmt = query(db: db, sql: cogSql) {
            sqlite3_bind_text(stmt, 1, (topic as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (topic as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }) {
                    cognates.append(c)
                }
            }
            sqlite3_finalize(stmt)
        }

        return StrongsEntry(
            topic:             topic,
            lexeme:            lexeme,
            transliteration:   translit,
            pronunciation:     pronunc,
            shortDefinition:   shortDef,
            derivation:        derivation,
            strongsDefinition: strongs,
            kjv:               kjv,
            references:        references,
            cognates:          cognates
        )
    }

    /// Parse the raw HTML definition into (derivation, kjv) strings.
    /// Handles two formats:
    ///   ETCBC: sections separated by <hr>, body is section 2+
    ///   Standard: header before <p/>, body follows
    private func parseDefinitionBody(_ html: String) -> String {
        var text = html

        if text.contains("<hr>") {
            // ETCBC format: split on <hr>, skip sections 0 and 1
            let sections = text.components(separatedBy: "<hr>")
            guard sections.count > 2 else { return "" }
            text = sections[2...].joined(separator: "\n")
        } else {
            // Standard format: skip everything before <p/>
            if let r = text.range(of: "<p/>") { text = String(text[r.upperBound...]) }
            else if let r = text.range(of: "<p>") { text = String(text[r.upperBound...]) }
        }

        // Convert <br /> and <br/> to newline so labels stay on separate lines
        text = text.replacingOccurrences(of: "<br />", with: "\n")
        text = text.replacingOccurrences(of: "<br/>",  with: "\n")

        // Replace <a href=...>TEXT</a> with TEXT
        while let open  = text.range(of: "<a "),
              let close = text.range(of: "</a>", range: open.lowerBound..<text.endIndex),
              let tagEnd = text.range(of: ">", range: open.upperBound..<close.lowerBound) {
            let inner = String(text[tagEnd.upperBound..<close.lowerBound])
            text.replaceSubrange(open.lowerBound..<text.index(close.upperBound, offsetBy: 0), with: inner)
        }

        // Decode HTML entities
        let entities: [(String, String)] = [
            ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
            ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}"),
            ("&amp;",   "&"),        ("&lt;",    "<"),
            ("&gt;",    ">"),        ("&nbsp;",  " "),
            ("&mdash;", "\u{2014}"), ("&ndash;", "\u{2013}"),
            ("&#x200E;", ""),         // left-to-right mark
        ]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }

        return StrongsParser.stripAllTags(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract a labelled section from a body string, e.g. "Derivation: text\nKJV: other"
    private func extractLabel(_ body: String, label: String) -> String {
        let search = label + ": "
        guard let start = body.range(of: search) else { return "" }
        let contentStart = start.upperBound
        // Find where next label begins
        let knownLabels = ["Derivation: ", "Strong\'s: ", "KJV: ", "Usage: ", "See: "]
        var contentEnd = body.endIndex
        for next in knownLabels where next != search {
            if let r = body.range(of: next, range: contentStart..<body.endIndex) {
                if r.lowerBound < contentEnd { contentEnd = r.lowerBound }
            }
        }
        return String(body[contentStart..<contentEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract the cross-reference section (section 1 between first and second <hr> in ETCBC+ format).
    /// Returns a cleaned string like "[Heb] ETCBC: אֱלֹהִים (subs|god(s)) TWOT: 93c GK: H466 Greek: θεός..."
    private func extractReferencesSection(_ html: String) -> String {
        let sections = html.components(separatedBy: "<hr>")
        guard sections.count >= 2 else { return "" }
        var text = sections[1]

        // Convert <br /> to space
        text = text.replacingOccurrences(of: "<br />", with: " ")
        text = text.replacingOccurrences(of: "<br/>",  with: " ")

        // Replace links with their text content
        while let open  = text.range(of: "<a "),
              let close = text.range(of: "</a>", range: open.lowerBound..<text.endIndex),
              let tagEnd = text.range(of: ">", range: open.upperBound..<close.lowerBound) {
            let inner = String(text[tagEnd.upperBound..<close.lowerBound])
            text.replaceSubrange(open.lowerBound..<text.index(close.upperBound, offsetBy: 0), with: inner)
        }

        // Strip remaining tags
        text = StrongsParser.stripAllTags(text)

        // Decode entities
        text = text.replacingOccurrences(of: "&#x200E;", with: "")
        text = text.replacingOccurrences(of: "&amp;",    with: "&")

        // Normalise whitespace
        text = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Navigate to a passage from a reference string e.g. "Genesis 1" or "Genesis 1:3"

    func navigate(to reference: String) {
        let withoutVerse = reference.components(separatedBy: ":").first ?? reference
        let parts        = withoutVerse.trimmingCharacters(in: .whitespaces)
                                       .components(separatedBy: " ")
        guard let chapterStr = parts.last,
              let chapter    = Int(chapterStr) else { return }
        let bookName = parts.dropLast().joined(separator: " ")
        guard let bookNum = myBibleBookNumbers
                .first(where: { $0.value == bookName })?.key else { return }
        NotificationCenter.default.post(
            name: .navigateToPassage, object: nil,
            userInfo: ["bookNumber": bookNum, "chapter": chapter]
        )
    }

    func navigate(toBook bookNumber: Int, chapter: Int) {
        NotificationCenter.default.post(
            name: .navigateToPassage, object: nil,
            userInfo: ["bookNumber": bookNumber, "chapter": chapter]
        )
    }


    // MARK: - Companion panel helpers

    func fetchVerses(module: MyBibleModule, bookNumber: Int, chapter: Int) async -> [MyBibleVerse] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
        else { return [] }
        defer { sqlite3_close(db) }
        let sql  = "SELECT book_number, chapter, verse, text FROM verses WHERE book_number = ? AND chapter = ? ORDER BY verse"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookNumber))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        var results = [MyBibleVerse]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let raw = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            results.append(MyBibleVerse(
                book:    Int(sqlite3_column_int(stmt, 0)),
                chapter: Int(sqlite3_column_int(stmt, 1)),
                verse:   Int(sqlite3_column_int(stmt, 2)),
                text:    stripStrongsAndTags(raw)
            ))
        }
        return results
    }

    func fetchCommentaryEntries(module: MyBibleModule, bookNumber: Int, chapter: Int) async -> [CommentaryEntry] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
        else { return [] }
        defer { sqlite3_close(db) }
        let sql = """
            SELECT book_number, chapter_number_from, verse_number_from,
                   chapter_number_to, verse_number_to, text
            FROM commentaries
            WHERE book_number = ? AND chapter_number_from = ?
            ORDER BY verse_number_from
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookNumber))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        var results = [CommentaryEntry]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let raw       = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
            let verseFrom = Int(sqlite3_column_int(stmt, 2))
            var verseTo   = Int(sqlite3_column_int(stmt, 4))
            // verseTo == 0 means the commentary covers through the end of the chapter,
            // or is a chapter-level entry. Treat it as covering all verses (999 = any verse matches).
            if verseTo == 0 { verseTo = verseFrom == 0 ? 999 : verseFrom }
            results.append(CommentaryEntry(
                bookNumber:  Int(sqlite3_column_int(stmt, 0)),
                chapterFrom: Int(sqlite3_column_int(stmt, 1)),
                verseFrom:   verseFrom,
                chapterTo:   Int(sqlite3_column_int(stmt, 3)),
                verseTo:     verseTo,
                text:        StrongsParser.stripAllTags(raw)
            ))
        }
        return results
    }

    private func stripStrongsAndTags(_ raw: String) -> String {
        var t = raw
        // Strip <S>number</S> Strong's tags and their numeric content
        while let o = t.range(of: "<S>"),
              let c = t.range(of: "</S>", range: o.lowerBound..<t.endIndex) {
            t.removeSubrange(o.lowerBound..<c.upperBound)
        }
        // Strip <WG...> and <WH...> prefix Strong's numbers
        for prefix in ["<WG", "<WH"] {
            while let r = t.range(of: prefix),
                  let end = t.range(of: ">", range: r.upperBound..<t.endIndex) {
                t.removeSubrange(r.lowerBound...end.lowerBound)
            }
        }
        // Strip all remaining HTML/markup tags
        return StrongsParser.stripAllTags(t)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }




    // MARK: - General dictionary word lookup (for Webster etc)

    func lookupDictionaryWord(word: String) async -> (topic: String, definition: String)? {
        return await lookupWord(word: word, in: selectedDictionary, fallbackType: .dictionary)
    }

    func lookupWord(word: String, in module: MyBibleModule?) async -> (topic: String, definition: String)? {
        return await lookupWord(word: word, in: module, fallbackType: nil)
    }

    private func lookupWord(word: String, in module: MyBibleModule?, fallbackType: ModuleType?) async -> (topic: String, definition: String)? {
        let dicts: [MyBibleModule]
        if let selected = module {
            dicts = [selected]
        } else if let ft = fallbackType {
            dicts = visibleModules.filter { $0.type == ft }
        } else {
            return nil
        }
        guard !dicts.isEmpty else { return nil }

        let candidates = [word, word.capitalized, word.lowercased(), word.uppercased()]

        for module in dicts {
            var db: OpaquePointer?
            guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { continue }
            defer { sqlite3_close(db) }

            for candidate in candidates {
                let sql = "SELECT topic, definition FROM dictionary WHERE topic = ? LIMIT 1"
                if let stmt = query(db: db, sql: sql) {
                    sqlite3_bind_text(stmt, 1, (candidate as NSString).utf8String, -1, nil)
                    if sqlite3_step(stmt) == SQLITE_ROW,
                       let topicPtr = sqlite3_column_text(stmt, 0),
                       let defPtr   = sqlite3_column_text(stmt, 1) {
                        let topic = String(cString: topicPtr)
                        let raw   = String(cString: defPtr)
                        sqlite3_finalize(stmt)
                        let clean = raw
                            .replacingOccurrences(of: "<p/>",  with: "\n\n")
                            .replacingOccurrences(of: "<p />", with: "\n\n")
                            .replacingOccurrences(of: "<br/>", with: "\n")
                            .replacingOccurrences(of: "<br />", with: "\n")
                            .replacingOccurrences(of: "<br>",  with: "\n")
                        // Strip remaining HTML tags
                        let stripped: String
                        if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
                            stripped = regex.stringByReplacingMatches(
                                in: clean,
                                range: NSRange(clean.startIndex..., in: clean),
                                withTemplate: "")
                        } else {
                            stripped = clean
                        }
                        let result = stripped
                            .replacingOccurrences(of: "&amp;",  with: "&")
                            .replacingOccurrences(of: "&lt;",   with: "<")
                            .replacingOccurrences(of: "&gt;",   with: ">")
                            .replacingOccurrences(of: "&nbsp;", with: " ")
                            .replacingOccurrences(of: "&#160;", with: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return (topic: topic, definition: result)
                    }
                    sqlite3_finalize(stmt)
                }
            }
        }
        return nil
    }


    // MARK: - Cross References

    struct CrossRefGroup {
        let keyword:    String?
        let references: [CrossRefEntry]
    }

    struct CrossRefEntry {
        let display:    String
        let bookNumber: Int
        let chapter:    Int
        let verseStart: Int
        let verseEnd:   Int
    }

    // Called from main actor — captures module, then dispatches off-actor
    func lookupCrossReferences(book: Int, chapter: Int, verse: Int) async -> [CrossRefGroup] {
        guard let module = selectedCrossRef else { return [] }
        return await lookupCrossReferencesOffActor(module: module, book: book, chapter: chapter, verse: verse)
    }

    nonisolated private func lookupCrossReferencesOffActor(module: MyBibleModule, book: Int, chapter: Int, verse: Int) async -> [CrossRefGroup] {
        if module.type == .crossRefNative {
            return await lookupNativeCrossReferences(module: module, book: book, chapter: chapter, verse: verse)
        }
        return await Task.detached(priority: .userInitiated) {
            var db: OpaquePointer?
            guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
            else { return [] }
            defer { sqlite3_close(db) }

            var groups: [CrossRefGroup] = []
            if let stmt = self.query(db: db, sql:
                "SELECT text FROM commentaries WHERE book_number=? AND chapter_number_from=? AND verse_number_from=? AND book_number != 'book_number' LIMIT 1") {
                sqlite3_bind_int(stmt, 1, Int32(book))
                sqlite3_bind_int(stmt, 2, Int32(chapter))
                sqlite3_bind_int(stmt, 3, Int32(verse))
                if sqlite3_step(stmt) == SQLITE_ROW,
                   let raw = sqlite3_column_text(stmt, 0) {
                    let html = String(cString: raw)
                    groups = self.parseCrossRefHTML(html)
                }
                sqlite3_finalize(stmt)
            }
            return groups
        }.value
    }


    nonisolated private func lookupNativeCrossReferences(module: MyBibleModule, book: Int, chapter: Int, verse: Int) async -> [CrossRefGroup] {
        return await Task.detached(priority: .userInitiated) {
            var db: OpaquePointer?
            guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
            else { return [] }
            defer { sqlite3_close(db) }

            var high:   [CrossRefEntry] = []
            var medium: [CrossRefEntry] = []
            var low:    [CrossRefEntry] = []

            if let stmt = self.query(db: db, sql:
                "SELECT book_to, chapter_to, verse_to_start, verse_to_end, votes FROM cross_references WHERE book=? AND chapter=? AND verse=? ORDER BY votes DESC") {
                sqlite3_bind_int(stmt, 1, Int32(book))
                sqlite3_bind_int(stmt, 2, Int32(chapter))
                sqlite3_bind_int(stmt, 3, Int32(verse))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let bookTo  = Int(sqlite3_column_int(stmt, 0))
                    let chTo    = Int(sqlite3_column_int(stmt, 1))
                    let vsStart = Int(sqlite3_column_int(stmt, 2))
                    let vsEnd   = Int(sqlite3_column_int(stmt, 3))
                    let votes   = Int(sqlite3_column_int(stmt, 4))

                    let bookName = myBibleBookNumbers[bookTo] ?? "\(bookTo)"
                    let display  = vsEnd > 0 && vsEnd != vsStart
                        ? "\(bookName) \(chTo):\(vsStart)-\(vsEnd)"
                        : "\(bookName) \(chTo):\(vsStart)"
                    let entry = CrossRefEntry(display: display, bookNumber: bookTo,
                                             chapter: chTo, verseStart: vsStart,
                                             verseEnd: vsEnd > 0 ? vsEnd : vsStart)

                    if votes >= 3      { high.append(entry) }
                    else if votes >= 1 { medium.append(entry) }
                    else               { low.append(entry) }
                }
                sqlite3_finalize(stmt)
            }

            var groups: [CrossRefGroup] = []
            if !high.isEmpty   { groups.append(CrossRefGroup(keyword: "Primary",   references: high)) }
            if !medium.isEmpty { groups.append(CrossRefGroup(keyword: "Secondary", references: medium)) }
            if !low.isEmpty    { groups.append(CrossRefGroup(keyword: "Related",   references: low)) }
            return groups
        }.value
    }

    nonisolated private func parseCrossRefHTML(_ html: String) -> [CrossRefGroup] {
        // Split into groups on <p/>
        let parts = html.components(separatedBy: "<p/>")
        var groups: [CrossRefGroup] = []

        let linkPattern = try? NSRegularExpression(
            pattern: #"<a href='B:(\d+) (\d+):(\d+)(?:-(\d+))?'>(.*?)</a>"#)
        let kwPattern   = try? NSRegularExpression(pattern: #"<b>(.*?)</b>"#)

        for part in parts {
            let ns = part as NSString
            let fullRange = NSRange(location: 0, length: ns.length)

            // Extract keyword
            var keyword: String? = nil
            if let m = kwPattern?.firstMatch(in: part, range: fullRange) {
                var kw = ns.substring(with: m.range(at: 1))
                if kw.hasSuffix(":") { kw = String(kw.dropLast()) }
                keyword = kw
            }

            // Extract references
            var refs: [CrossRefEntry] = []
            linkPattern?.enumerateMatches(in: part, range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let book    = Int(ns.substring(with: match.range(at: 1))) ?? 0
                let ch      = Int(ns.substring(with: match.range(at: 2))) ?? 0
                let vsStart = Int(ns.substring(with: match.range(at: 3))) ?? 0
                let vsEnd   = match.range(at: 4).location != NSNotFound
                              ? Int(ns.substring(with: match.range(at: 4))) ?? vsStart
                              : vsStart
                let display = ns.substring(with: match.range(at: 5))
                refs.append(CrossRefEntry(display: display, bookNumber: book,
                                          chapter: ch, verseStart: vsStart, verseEnd: vsEnd))
            }

            if !refs.isEmpty {
                groups.append(CrossRefGroup(keyword: keyword, references: refs))
            }
        }
        return groups
    }


    // MARK: - Devotional

    struct DevotionalEntry {
        let day:      Int
        let title:    String   // first line stripped of HTML
        let html:     String   // full raw HTML for rendering
    }

    func fetchDevotionalEntry(day: Int) async -> DevotionalEntry? {
        guard let module = selectedDevotional else { return nil }
        return await Task.detached(priority: .userInitiated) {
            var db: OpaquePointer?
            guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
            else { return nil }
            defer { sqlite3_close(db) }

            if let stmt = self.query(db: db, sql:
                "SELECT devotion FROM devotions WHERE day=? LIMIT 1") {
                sqlite3_bind_int(stmt, 1, Int32(day))
                if sqlite3_step(stmt) == SQLITE_ROW,
                   let raw = sqlite3_column_text(stmt, 0) {
                    let html = String(cString: raw)
                    sqlite3_finalize(stmt)
                    let title = Self.extractDevotionalTitle(html)
                    return DevotionalEntry(day: day, title: title, html: html)
                }
                sqlite3_finalize(stmt)
            }
            return nil
        }.value
    }

    nonisolated static func extractDevotionalTitle(_ html: String) -> String {
        // First segment before <p> or <p/> is the title/verse heading
        let parts = html.components(separatedBy: "<p")
        let first  = parts.first ?? html
        // Strip all HTML tags
        let clean  = first.replacingOccurrences(of: "<[^>]+>",
                         with: "", options: .regularExpression)
        // Decode common HTML entities
        return clean
            .replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
            .replacingOccurrences(of: "&rdquo;", with: "\u{201D}")
            .replacingOccurrences(of: "&nbsp;",  with: " ")
            .replacingOccurrences(of: "&amp;",   with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Total days in a devotional module
    func devotionalDayCount() async -> Int {
        guard let module = selectedDevotional else { return 365 }
        return await Task.detached(priority: .userInitiated) {
            var db: OpaquePointer?
            guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
            else { return 365 }
            defer { sqlite3_close(db) }
            if let stmt = self.query(db: db, sql: "SELECT MAX(day) FROM devotions") {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let count = Int(sqlite3_column_int(stmt, 0))
                    sqlite3_finalize(stmt)
                    return count
                }
                sqlite3_finalize(stmt)
            }
            return 365
        }.value
    }


}