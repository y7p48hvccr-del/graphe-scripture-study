import Foundation

enum AppRuntimeContext {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var testNotesDirectory: URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptureStudyTestHostNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

enum ModulesFolderBookmark {
    private static let udKey = "modulesFolderBookmark"

    static func save(_ url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: udKey)
        } catch {
            // Bookmark creation failed; plain path already saved as sentinel
        }
    }

    static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: udKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        if isStale {
            if url.startAccessingSecurityScopedResource() {
                save(url)
                url.stopAccessingSecurityScopedResource()
            }
        }
        return url
    }

    @discardableResult
    static func withAccess<T>(_ body: (URL) throws -> T) rethrows -> T? {
        guard let url = resolve() else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        return try body(url)
    }
}

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
    case atlas          = "Bible Maps"
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
    /// Translator's gloss notes extracted from the verse's `<n>...</n>`
    /// tags before the tags were stripped. Empty when the verse contains
    /// no footnote markup. Rendered as a single tap-target superscript at
    /// the end of the verse when `showGlossNotes` is enabled.
    var glosses: [String] = []
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

// MARK: - MyBible Service

@MainActor
class MyBibleService: ObservableObject {
    private static let bundledStrongsResourceName = "Merged_Strongs_Dictionary"
    private static let bundledStrongsResourceExtension = "SQLite3"

    @Published var modules:          [MyBibleModule] = []
    @Published var catalogRecordsByPath: [String: ModuleCatalogRecord] = [:]
    @Published var moduleDiagnostics: [ModuleCatalogDiagnostic] = []
    @Published var selectedLanguageFilter: String = UserDefaults.standard.string(forKey: "defaultLanguage") ?? "all" {
        didSet { UserDefaults.standard.set(selectedLanguageFilter, forKey: "defaultLanguage") }
    }
    @Published var hiddenModules:     Set<String>     = []   // file paths of hidden modules
    @Published var selectedBible:      MyBibleModule? { didSet { selectedBiblePath      = selectedBible?.filePath      ?? ""; ModuleUsageStore.recordUse(of: selectedBible) } }
    @Published var selectedStrongs:    MyBibleModule? { didSet { selectedStrongsPath    = selectedStrongs?.filePath    ?? ""; ModuleUsageStore.recordUse(of: selectedStrongs) } }
    @Published var selectedCommentary:    MyBibleModule? { didSet { selectedCommentaryPath  = selectedCommentary?.filePath  ?? ""; ModuleUsageStore.recordUse(of: selectedCommentary) } }
    @Published var selectedDictionary:    MyBibleModule? { didSet { selectedDictionaryPath  = selectedDictionary?.filePath  ?? ""; ModuleUsageStore.recordUse(of: selectedDictionary) } }
    @Published var selectedEncyclopedia:  MyBibleModule? { didSet { selectedEncyclopediaPath = selectedEncyclopedia?.filePath ?? ""; ModuleUsageStore.recordUse(of: selectedEncyclopedia) } }
    @Published var selectedCrossRef:      MyBibleModule? { didSet { selectedCrossRefPath     = selectedCrossRef?.filePath     ?? ""; ModuleUsageStore.recordUse(of: selectedCrossRef) } }
    @Published var selectedDevotional:    MyBibleModule? { didSet { selectedDevotionalPath   = selectedDevotional?.filePath   ?? ""; ModuleUsageStore.recordUse(of: selectedDevotional) } }
    @Published var rawVerseTexts:    [Int: String]    = [:]

    // Persisted selection paths
    var selectedBiblePath:        String { get { UserDefaults.standard.string(forKey: "selectedBiblePath")        ?? "" } set { UserDefaults.standard.set(newValue, forKey: "selectedBiblePath") } }
    var selectedStrongsPath:      String { get { UserDefaults.standard.string(forKey: "selectedStrongsPath")      ?? "" } set { UserDefaults.standard.set(newValue, forKey: "selectedStrongsPath") } }
    var selectedDictionaryPath:   String { get { UserDefaults.standard.string(forKey: "selectedDictionaryPath")   ?? "" } set { UserDefaults.standard.set(newValue, forKey: "selectedDictionaryPath") } }
    var selectedCommentaryPath:   String { get { UserDefaults.standard.string(forKey: "selectedCommentaryPath")   ?? "" } set { UserDefaults.standard.set(newValue, forKey: "selectedCommentaryPath") } }
    var selectedEncyclopediaPath: String { get { UserDefaults.standard.string(forKey: "selectedEncyclopediaPath") ?? "" } set { UserDefaults.standard.set(newValue, forKey: "selectedEncyclopediaPath") } }
    var selectedCrossRefPath:     String { get { UserDefaults.standard.string(forKey: "selectedCrossRefPath")     ?? "" } set { UserDefaults.standard.set(newValue, forKey: "selectedCrossRefPath") } }
    var selectedDevotionalPath:   String { get { UserDefaults.standard.string(forKey: "selectedDevotionalPath")   ?? "" } set { UserDefaults.standard.set(newValue, forKey: "selectedDevotionalPath") } }
    @Published var verses:           [MyBibleVerse]  = []
    @Published var commentaryEntries:[CommentaryEntry] = []
    @Published var dictionaryEntries:[DictionaryEntry] = []
    @Published var isLoading         = false
    @Published var errorMessage:     String?
    @Published var currentPassage:   String  = ""
    @Published var currentBookNumber: Int     = 0
    @Published var currentChapter:    Int     = 0

    var currentPassageState: BiblePassageState? {
        guard currentBookNumber > 0, currentChapter > 0, !currentPassage.isEmpty else {
            return nil
        }
        return BiblePassageState(
            title: currentPassage,
            bookNumber: currentBookNumber,
            chapter: currentChapter
        )
    }

    @Published var modulesFolder:    String = "" {
        didSet {
            UserDefaults.standard.set(modulesFolder, forKey: "modulesFolder")
            guard !AppRuntimeContext.isRunningTests else { return }
            startFolderAccess()
            Task { await scanModules() }
        }
    }

    /// Holds the actively-accessed folder URL for the lifetime of the service.
    /// All sqlite3_open_v2 calls on files inside this folder are covered while this is non-nil.
    private var folderAccessURL: URL?

    /// Resolve the security-scoped bookmark and begin access, replacing any previous token.
    private func startFolderAccess() {
        folderAccessURL?.stopAccessingSecurityScopedResource()
        folderAccessURL = nil
        guard let url = ModulesFolderBookmark.resolve() else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        folderAccessURL = url
    }

    deinit {
        folderAccessURL?.stopAccessingSecurityScopedResource()
    }

    init() {
        modulesFolder = UserDefaults.standard.string(forKey: "modulesFolder") ?? ""
        if let paths = UserDefaults.standard.array(forKey: "hiddenModules") as? [String] {
            hiddenModules = Set(paths)
        }
        guard !AppRuntimeContext.isRunningTests else { return }
        // Start folder access immediately so module reads work from the first launch
        startFolderAccess()
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

    func catalogRecord(for module: MyBibleModule) -> ModuleCatalogRecord? {
        catalogRecordsByPath[module.filePath]
    }

    func metadataBlob(for module: MyBibleModule) -> String? {
        catalogRecord(for: module)?.metadataBlob
    }

    func validationReport(for module: MyBibleModule) -> GrapheRuntimeValidationReport? {
        catalogRecord(for: module)?.validation
    }

    func runtimeProfileName(for module: MyBibleModule) -> String? {
        validationReport(for: module)?.matchedProfileName
    }

    func isRuntimeReady(_ module: MyBibleModule) -> Bool {
        validationReport(for: module)?.state == .ready
    }

    func hasStrongsCapability(_ module: MyBibleModule) -> Bool {
        catalogRecord(for: module)?.hasStrongsCapability == true
    }

    func isInterlinearModule(_ module: MyBibleModule) -> Bool {
        if let record = catalogRecord(for: module) {
            return record.metadata.capabilities.contains("interlinear")
        }
        return runtimeInterlinearMetadata(for: module)?.isInterlinear == true
    }

    func moduleMatchesLanguageFilter(_ module: MyBibleModule, languageCode: String) -> Bool {
        let normalized = languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != "all" else { return true }
        if module.language.lowercased() == normalized { return true }
        if let record = catalogRecord(for: module),
           record.metadata.capabilities.contains("interlinear") {
            return Set(record.metadata.linkedLanguages).contains(normalized)
        }
        guard let metadata = runtimeInterlinearMetadata(for: module), metadata.isInterlinear else {
            return false
        }
        return metadata.languages.contains(normalized)
    }

    func interlinearLinkedLanguages(for module: MyBibleModule) -> Set<String> {
        if let record = catalogRecord(for: module),
           record.metadata.capabilities.contains("interlinear") {
            return Set(record.metadata.linkedLanguages)
        }
        return runtimeInterlinearMetadata(for: module)?.languages ?? []
    }

    private func runtimeInterlinearMetadata(for module: MyBibleModule) -> (isInterlinear: Bool, languages: Set<String>)? {
        guard isRuntimeReady(module),
              let inspection = GrapheRuntimeStorage.inspectModule(at: module.filePath)
        else {
            return nil
        }

        let hyperlinkLanguages = inspection.info["hyperlink_languages"]?
            .lowercased()
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []

        let isInterlinear =
            inspection.tables.contains("verses") &&
            inspection.info["strong_numbers"]?.lowercased() == "true" &&
            inspection.info["is_strong"]?.lowercased() != "true" &&
            hyperlinkLanguages.contains { !$0.isEmpty }

        return (isInterlinear, Set(hyperlinkLanguages))
    }

    func supportsCapability(_ capability: String, for module: MyBibleModule) -> Bool {
        guard let record = catalogRecord(for: module) else {
            return false
        }
        return record.validation.state == .ready && record.metadata.capabilities.contains(capability)
    }

    func availableVisibleModules(
        ofTypes types: [ModuleType],
        requiring capability: String? = nil
    ) -> [MyBibleModule] {
        let allowedTypes = Set(types)
        return visibleModules.filter { module in
            guard allowedTypes.contains(module.type), isRuntimeReady(module) else {
                return false
            }
            if let capability {
                return supportsCapability(capability, for: module)
            }
            return true
        }
    }

    func diagnostic(forModulePath path: String) -> ModuleCatalogDiagnostic? {
        moduleDiagnostics.first(where: { $0.filePath == path })
    }

    var latestDiagnosticSummary: String? {
        guard let diagnostic = moduleDiagnostics.first else { return nil }
        let filename = URL(fileURLWithPath: diagnostic.filePath).lastPathComponent
        return "\(filename): \(diagnostic.reason)"
    }

    private func normalizedModuleTitle(for module: MyBibleModule) -> String {
        let description = module.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty {
            return description
        }

        let name = module.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }

        return URL(fileURLWithPath: module.filePath)
            .deletingPathExtension()
            .lastPathComponent
    }

    private func normalizedModules(_ modules: [MyBibleModule]) -> [MyBibleModule] {
        modules.map { module in
            MyBibleModule(
                name: normalizedModuleTitle(for: module),
                description: module.description,
                language: module.language,
                type: module.type,
                filePath: module.filePath
            )
        }
    }

    private var bundledCanonicalStrongsPath: String? {
        Bundle.main.path(
            forResource: Self.bundledStrongsResourceName,
            ofType: Self.bundledStrongsResourceExtension
        )
    }

    // MARK: - Scan folder for modules

    func scanModules() async {
        guard !modulesFolder.isEmpty else { return }
        await MainActor.run { isLoading = true; errorMessage = nil }

        guard let folderURL = folderAccessURL else {
            await MainActor.run {
                errorMessage = "Modules folder is no longer accessible. Please re-select it."
                isLoading = false
            }
            return
        }

        let scanResult: ModuleCatalogScanResult
        do {
            scanResult = try await ModuleCatalogService.scanModules(
                folderURL: folderURL,
                bundledCanonicalStrongsPath: bundledCanonicalStrongsPath
            )
        } catch ModuleCatalogScanError.unreadableFolder {
            await MainActor.run {
                errorMessage = "Could not read folder. Please select it again."
                isLoading = false
            }
            return
        } catch {
            await MainActor.run {
                errorMessage = "Module scan failed: \(error.localizedDescription)"
                isLoading = false
            }
            return
        }

        catalogRecordsByPath = scanResult.recordsByPath
        moduleDiagnostics = scanResult.diagnostics
        hiddenModules.formUnion(scanResult.hiddenModulePaths)
        modules = normalizedModules(scanResult.modules)
        if modules.isEmpty, let latestDiagnosticSummary {
            errorMessage = latestDiagnosticSummary
        }

        let savedPaths = ModuleSelectionPaths(
            biblePath: selectedBiblePath,
            strongsPath: selectedStrongsPath,
            dictionaryPath: selectedDictionaryPath,
            commentaryPath: selectedCommentaryPath,
            encyclopediaPath: selectedEncyclopediaPath,
            crossRefPath: selectedCrossRefPath,
            devotionalPath: selectedDevotionalPath
        )
        let currentPaths = ModuleSelectionPaths(
            biblePath: selectedBible?.filePath ?? "",
            strongsPath: selectedStrongs?.filePath ?? "",
            dictionaryPath: selectedDictionary?.filePath ?? "",
            commentaryPath: selectedCommentary?.filePath ?? "",
            encyclopediaPath: selectedEncyclopedia?.filePath ?? "",
            crossRefPath: selectedCrossRef?.filePath ?? "",
            devotionalPath: selectedDevotional?.filePath ?? ""
        )
        let resolvedSelections = ModuleCatalogService.resolveSelections(
            modules: modules,
            savedPaths: savedPaths,
            currentPaths: currentPaths,
            bundledCanonicalStrongsPath: bundledCanonicalStrongsPath
        )

        selectedBible = resolvedSelections.bible
        selectedStrongs = resolvedSelections.strongs
        selectedDictionary = resolvedSelections.dictionary
        selectedCommentary = resolvedSelections.commentary
        selectedEncyclopedia = resolvedSelections.encyclopedia
        selectedCrossRef = resolvedSelections.crossRef
        selectedDevotional = resolvedSelections.devotional

        isLoading = false
    }

    // MARK: - Load Bible chapter


    // Load verses for a module without affecting main state (used by ComparisonPanelView)
    func loadChapterVerses(module: MyBibleModule, bookNumber: Int, chapter: Int) async -> [MyBibleVerse] {
        await ModuleContentService.loadChapterVerses(module: module, bookNumber: bookNumber, chapter: chapter)
    }

    func loadChapter(module: MyBibleModule, bookNumber: Int, chapter: Int) async {
        isLoading = true
        errorMessage = nil
        verses = []

        let result = await ModuleContentService.loadChapter(module: module, bookNumber: bookNumber, chapter: chapter)
        verses = result.verses
        rawVerseTexts = result.rawVerseTexts
        print("[MyBible] verses set: count=\(result.verses.count) first=\(result.verses.first?.text.prefix(40) ?? "nil")")

        if verses.isEmpty {
            errorMessage = "No verses found for this chapter."
        } else {
            let passageState = PassageNavigationResolver.makePassageState(
                bookNumber: bookNumber,
                chapter: chapter,
                fallbackTitle: module.name
            )
            currentPassage = passageState.title
            currentBookNumber = passageState.bookNumber
            currentChapter = passageState.chapter
            NotificationCenter.default.post(
                name: .biblePassageChanged,
                object: nil,
                userInfo: passageState.userInfo
            )
        }

        isLoading = false
    }

    // MARK: - Load Commentary

    func loadCommentary(module: MyBibleModule, bookNumber: Int, chapter: Int) async {
        commentaryEntries = await ModuleContentService.loadCommentaryEntries(
            module: module,
            bookNumber: bookNumber,
            chapter: chapter
        )
    }

    // MARK: - Search Dictionary

    func searchDictionary(module: MyBibleModule, query searchTerm: String) async {
        dictionaryEntries = await ModuleContentService.searchDictionaryEntries(
            module: module,
            searchTerm: searchTerm
        )
    }

    // MARK: - Get available books in a Bible module

    // MARK: - Look up book number by name in a specific module

    @MainActor
    func bookNumber(forName name: String, in module: MyBibleModule) -> Int? {
        ModuleContentService.bookNumber(forName: name, in: module)
    }

    func availableBooks(in module: MyBibleModule) -> [Int] {
        ModuleContentService.availableBooks(in: module)
    }

    // MARK: - Get chapter count for a book

    func chapterCount(module: MyBibleModule, bookNumber: Int) -> Int {
        ModuleContentService.chapterCount(module: module, bookNumber: bookNumber)
    }

    // MARK: - Lookup Strong\'s number in dictionary module

    // Sync lookup for use in views
    func lookupStrongs(_ number: String) -> StrongsEntry? { nil }  // placeholder — async lookup used in CompanionPanel

    func lookupStrongs(module: MyBibleModule, number: String, isOldTestament: Bool = false) async -> StrongsEntry? {
        await StrongsLookupService.lookup(module: module, number: number, isOldTestament: isOldTestament)
    }

    // MARK: - Navigate to a passage from a reference string e.g. "Genesis 1" or "Genesis 1:3"

    func navigate(to reference: String) {
        guard let request = PassageNavigationResolver.resolveRequest(from: reference) else { return }
        NotificationCenter.default.post(name: .navigateToPassage, object: nil, userInfo: request.userInfo)
    }

    func navigate(toBook bookNumber: Int, chapter: Int) {
        NotificationCenter.default.post(
            name: .navigateToPassage, object: nil,
            userInfo: ["bookNumber": bookNumber, "chapter": chapter]
        )
    }


    // MARK: - Companion panel helpers

    func fetchVerses(module: MyBibleModule, bookNumber: Int, chapter: Int) async -> [MyBibleVerse] {
        await ModuleContentService.fetchVerses(module: module, bookNumber: bookNumber, chapter: chapter)
    }

    func fetchCommentaryEntries(module: MyBibleModule, bookNumber: Int, chapter: Int) async -> [CommentaryEntry] {
        await ModuleContentService.fetchCommentaryEntries(module: module, bookNumber: bookNumber, chapter: chapter)
    }




    // MARK: - General dictionary word lookup (for Webster etc)

    func lookupDictionaryWord(word: String) async -> (topic: String, definition: String)? {
        return await lookupWord(word: word, in: selectedDictionary, fallbackType: .dictionary)
    }

    func lookupWord(word: String, in module: MyBibleModule?) async -> (topic: String, definition: String)? {
        return await lookupWord(word: word, in: module, fallbackType: nil)
    }

    func lookupLinkedWord(word: String, in module: MyBibleModule?) async -> (topic: String, definition: String)? {
        return await lookupWord(word: word, in: module, fallbackType: nil, preservingMarkup: true)
    }

    private func lookupWord(word: String, in module: MyBibleModule?, fallbackType: ModuleType?, preservingMarkup: Bool = false) async -> (topic: String, definition: String)? {
        let dicts = ModuleLookupResolver.resolveLookupModules(
            preferredModule: module,
            fallbackType: fallbackType,
            visibleModules: visibleModules
        )
        guard !dicts.isEmpty else { return nil }

        for module in dicts {
            if let match = await ModuleContentService.lookupWord(
                word: word,
                in: module,
                preservingMarkup: preservingMarkup
            ) {
                return match
            }
        }
        return nil
    }


    // MARK: - Cross References

    // Called from main actor — captures module, then dispatches off-actor
    func lookupCrossReferences(book: Int, chapter: Int, verse: Int) async -> [CrossRefGroup] {
        guard let module = selectedCrossRef else { return [] }
        return await ModuleContentService.lookupCrossReferences(
            module: module,
            book: book,
            chapter: chapter,
            verse: verse
        )
    }


    // MARK: - Devotional
    func fetchDevotionalEntry(day: Int) async -> DevotionalEntry? {
        guard let module = selectedDevotional else { return nil }
        return await ModuleContentService.fetchDevotionalEntry(module: module, day: day)
    }

    // Total days in a devotional module
    func devotionalDayCount() async -> Int {
        guard let module = selectedDevotional else { return 365 }
        return await ModuleContentService.devotionalDayCount(module: module)
    }

    // MARK: - Reading plan
    //
    // Used by both OrganizerView and DevotionalView. `PlanEntry` is the
    // resolved daily entry from a reading-plan module's `reading_plan`
    // table: which book and chapter/verse range to read on day N of the plan.

    /// Loads the reading plan entry for a given day (1–365ish) from a
    /// reading-plan module. Returns nil if the module has no entry for that
    /// day or the file can't be opened.
    func loadPlanEntry(day: Int, from module: MyBibleModule) async -> PlanEntry? {
        await ModuleContentService.loadPlanEntry(day: day, from: module)
    }
}
