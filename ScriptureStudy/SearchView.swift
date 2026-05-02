import SwiftUI
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

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
    @State private var scope           = SearchScope.bible
    @State private var searchMode      = SearchMode.global
    @State private var queryKind       = SearchQueryKind.word
    @State private var results         = [SearchResult]()
    @State private var isSearching     = false
    @State private var debounceTimer:  Timer?
    @State private var includeInflections = false
    @State private var selectedResultID: SearchResult.ID?
    @State private var previewVerses: [MyBibleVerse] = []
    @State private var previewCommentaryEntries: [CommentaryEntry] = []
    @State private var previewNote: Note?
    @State private var isLoadingPreview = false
    @State private var selectedSearchLanguages: Set<String> = []
    @State private var scopeHitCounts: [SearchScope: Int] = [:]
    @State private var searchRunID = UUID()
    @State private var languageFilterText = ""

    // Module filters
    @State private var selectedBibleIDs:      Set<String> = []
    @State private var selectedInterlinearIDs: Set<String> = []
    @State private var selectedStrongsIDs: Set<String> = []
    @State private var selectedCommentaryIDs: Set<String> = []
    @State private var selectedCrossReferenceIDs: Set<String> = []
    @State private var selectedEncyclopediaIDs: Set<String> = []
    @State private var selectedLexiconIDs: Set<String> = []
    @State private var selectedDictionaryIDs: Set<String> = []
    @State private var bibleModuleFilterText = ""
    @State private var interlinearModuleFilterText = ""
    @State private var strongsModuleFilterText = ""
    @State private var commentaryModuleFilterText = ""
    @State private var crossReferenceModuleFilterText = ""
    @State private var encyclopediaModuleFilterText = ""
    @State private var lexiconModuleFilterText = ""
    @State private var dictionaryModuleFilterText = ""
    @State private var allBibleModules: [MyBibleModule] = []
    @State private var allInterlinearModules: [MyBibleModule] = []
    @State private var allStrongsModules: [MyBibleModule] = []
    @State private var allCommentaryModules: [MyBibleModule] = []
    @State private var allCrossReferenceModules: [MyBibleModule] = []
    @State private var allEncyclopediaModules: [MyBibleModule] = []
    @State private var allLexiconModules: [MyBibleModule] = []
    @State private var allDictionaryModules: [MyBibleModule] = []
    @State private var searchLanguagesCatalog: [LanguageInfo] = []
    @State private var filteredBibleModuleCache: [MyBibleModule] = []
    @State private var filteredInterlinearModuleCache: [MyBibleModule] = []
    @State private var filteredStrongsModuleCache: [MyBibleModule] = []
    @State private var filteredCommentaryModuleCache: [MyBibleModule] = []
    @State private var filteredCrossReferenceModuleCache: [MyBibleModule] = []
    @State private var filteredEncyclopediaModuleCache: [MyBibleModule] = []
    @State private var filteredLexiconModuleCache: [MyBibleModule] = []
    @State private var filteredDictionaryModuleCache: [MyBibleModule] = []

    // Bible/Commentary scope filters
    @State private var testament:    Testament = .both
    @State private var bookFilter:   Int       = 0     // 0 = all books

    // Notes scope filters
    @State private var notesFrom:    Date?
    @State private var notesTo:      Date?

    var bibleModules:      [MyBibleModule] { filteredBibleModuleCache }
    var interlinearModules: [MyBibleModule] { filteredInterlinearModuleCache }
    var strongsModules: [MyBibleModule] { filteredStrongsModuleCache }
    var commentaryModules: [MyBibleModule] { filteredCommentaryModuleCache }
    var crossReferenceModules: [MyBibleModule] { filteredCrossReferenceModuleCache }
    var encyclopediaModules: [MyBibleModule] { filteredEncyclopediaModuleCache }
    var lexiconModules: [MyBibleModule] { filteredLexiconModuleCache }
    var dictionaryModules: [MyBibleModule] { filteredDictionaryModuleCache }
    var filteredBibleModules: [MyBibleModule] { filterModules(bibleModules, matching: bibleModuleFilterText) }
    var filteredInterlinearModules: [MyBibleModule] { filterModules(interlinearModules, matching: interlinearModuleFilterText) }
    var filteredStrongsModules: [MyBibleModule] { filterModules(strongsModules, matching: strongsModuleFilterText) }
    var filteredCommentaryModules: [MyBibleModule] { filterModules(commentaryModules, matching: commentaryModuleFilterText) }
    var filteredCrossReferenceModules: [MyBibleModule] { filterModules(crossReferenceModules, matching: crossReferenceModuleFilterText) }
    var filteredEncyclopediaModules: [MyBibleModule] { filterModules(encyclopediaModules, matching: encyclopediaModuleFilterText) }
    var filteredLexiconModules: [MyBibleModule] { filterModules(lexiconModules, matching: lexiconModuleFilterText) }
    var filteredDictionaryModules: [MyBibleModule] { filterModules(dictionaryModules, matching: dictionaryModuleFilterText) }
    var visibleSearchScopes: [SearchScope] { SearchScope.allCases.filter { $0 != .crossReferences } }
    var availableSearchLanguages: [LanguageInfo] {
        switch scope {
        case .bible:
            return orderedSearchLanguages(languageInfos(from: allBibleModules.map(\.language)))
        case .interlinear:
            return []
        case .strongs:
            return orderedSearchLanguages(languageInfos(from: allStrongsModules.map(\.language)))
        case .commentary:
            return orderedSearchLanguages(languageInfos(from: allCommentaryModules.map(\.language)))
        case .crossReferences:
            return orderedSearchLanguages(languageInfos(from: allCrossReferenceModules.map(\.language)))
        case .encyclopedias:
            return orderedSearchLanguages(languageInfos(from: allEncyclopediaModules.map(\.language)))
        case .lexicons:
            return orderedSearchLanguages(languageInfos(from: allLexiconModules.map(\.language)))
        case .dictionaries:
            return orderedSearchLanguages(languageInfos(from: allDictionaryModules.map(\.language)))
        case .notes:
            return searchLanguagesCatalog
        }
    }
    var filteredAvailableSearchLanguages: [LanguageInfo] {
        let trimmed = languageFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return availableSearchLanguages }
        let needle = trimmed.lowercased()
        return availableSearchLanguages.filter { language in
            language.displayName.lowercased().contains(needle) ||
            language.code.lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topScopeBar
            Divider()
            workspaceBody
        }
        .background(theme.background)
        .onChange(of: results.map(\.id)) {
            if let selectedResultID,
               results.contains(where: { $0.id == selectedResultID }) {
                return
            }
            selectedResultID = results.first?.id
        }
        .onAppear {
            if scope == .crossReferences {
                scope = .bible
            }
            refreshSearchInventory()
        }
        .onChange(of: selectedSearchLanguages) {
            applySelectedLanguageFilters()
        }
        .task(id: selectedResultID) {
            await loadPreview()
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(searchPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                    .onSubmit { runSearch() }
                    .onChange(of: query) { scheduleSearch() }
                if !query.isEmpty {
                    Button { query = ""; results = [] } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.background.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(filigreeAccent.opacity(0.20), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !activeSearchLanguages.isEmpty {
                HStack(spacing: 8) {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(activeSearchLanguages, id: \.code) { language in
                            HStack(spacing: 4) {
                                Text(language.flag)
                                Text(language.code.uppercased())
                                    .font(.caption2.weight(.semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(filigreeAccent.opacity(0.10))
                            .clipShape(Capsule())
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private var searchPlaceholder: String {
        switch queryKind {
        case .word:
            return "Search exact word…"
        case .phrase:
            return "Search exact phrase…"
        case .strongs:
            return "Search Strong's number… e.g. G25 or H157"
        }
    }

    // MARK: - Scope picker

    private var topScopeBar: some View {
        scopePicker
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(theme.background)
    }

    private var scopePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleSearchScopes, id: \.self) { item in
                    let isActive = scope == item
                    Button {
                        selectScope(item)
                    } label: {
                        scopePillLabel(for: item)
                    }
                    .frame(width: 164, height: 58)
                    .background(scopePillBackground(isActive: isActive))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(scopeBorderColor(isActive: isActive), lineWidth: scopeBorderWidth(isActive: isActive))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: isActive ? Color.black.opacity(0.10) : .clear, radius: 8, x: 0, y: 4)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .defaultScrollAnchor(.center)
    }

    private func selectScope(_ item: SearchScope) {
        scope = item
        if item == .strongs {
            queryKind = .strongs
        }
        syncSearchLanguagesIfNeeded()
        applySelectedLanguageFilters()
        runSearch()
    }

    private func scopeBorderColor(isActive: Bool) -> Color {
        isActive ? filigreeAccent.opacity(0.78) : filigreeAccent.opacity(0.42)
    }

    private func scopeBorderWidth(isActive: Bool) -> CGFloat {
        isActive ? 1.4 : 1.0
    }

    private func scopePillBackground(isActive: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: isActive
                            ? [filigreeAccent.opacity(0.32), filigreeAccent.opacity(0.12)]
                            : [filigreeAccent.opacity(0.12), Color.secondary.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(isActive ? 0.16 : 0.08))
                .padding(1)
        }
    }

    @ViewBuilder
    private func scopePillLabel(for item: SearchScope) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text(item.rawValue)
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(scope == item ? theme.text : filigreeAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if !query.isEmpty, scopeHasHits(item) {
                    Circle()
                        .fill(scope == item ? filigreeAccent : filigreeAccent.opacity(0.92))
                        .frame(width: 6, height: 6)
                }
            }
            Text(scopeHistoricSubtitle(for: item))
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(filigreeAccent.opacity(0.80))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity)
    }

    private func scopeHistoricSubtitle(for scope: SearchScope) -> String {
        switch scope {
        case .bible:
            return "SCRIPTURE"
        case .interlinear:
            return "ORIGINAL TEXTS"
        case .strongs:
            return "WORD STUDY"
        case .commentary:
            return "COMMENTARY"
        case .crossReferences:
            return "REFERENCES"
        case .encyclopedias:
            return "HISTORICAL"
        case .lexicons:
            return "LEXICON"
        case .dictionaries:
            return "DEFINITIONS"
        case .notes:
            return "JOURNAL"
        }
    }

    // MARK: - Filter panel

    private var filterPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                filterSectionCard(title: "Search") {
                    searchBar
                }

                filterSectionCard(title: "Query Type") {
                    Picker("", selection: $queryKind) {
                        ForEach(SearchQueryKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .onChange(of: queryKind) {
                        if queryKind != .word {
                            includeInflections = false
                        }
                        if queryKind == .strongs, scope == .bible {
                            scope = .interlinear
                        }
                        runSearch()
                    }
                }

                filterSectionCard(title: "At a Glance") {
                    filterStatsPanel
                }

                if queryKind == .word {
                    filterSectionCard(title: "Word Matching") {
                        Toggle("Include inflections (e.g. loved, loves)", isOn: $includeInflections)
                            .font(.caption)
                    }
                }

                filterSectionCard(title: "Result Order") {
                    Picker("Result Order", selection: $searchMode) {
                        ForEach(SearchMode.allCases, id: \.self) { mode in
                            Text(searchModeLabel(for: mode)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }

                if scope == .bible || scope == .interlinear {
                    filterSectionCard(title: "Testament") {
                        Picker("Testament", selection: $testament) {
                            Text("Both").tag(Testament.both)
                            Text("Old").tag(Testament.ot)
                            Text("New").tag(Testament.nt)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                    }
                }

                if scope == .bible || scope == .interlinear {
                    filterSectionCard(title: "Book") {
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

                if scope == .notes {
                    filterSectionCard(title: "Notes Date Range") {
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
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(theme.background)
    }

    private func filterModules(_ modules: [MyBibleModule], matching text: String) -> [MyBibleModule] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return modules }
        let needle = trimmed.lowercased()
        return modules.filter { module in
            module.name.lowercased().contains(needle) ||
            module.language.lowercased().contains(needle)
        }
    }

    private func displayedModules(_ modules: [MyBibleModule], filterText: String) -> [MyBibleModule] {
        let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Array(modules.prefix(250))
        }
        return Array(modules.prefix(1000))
    }

    private func normalizedLanguageCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func languageFilteredModules(_ modules: [MyBibleModule]) -> [MyBibleModule] {
        modules.filter { module in
            selectedSearchLanguages.contains { myBible.moduleMatchesLanguageFilter(module, languageCode: $0) }
        }
    }

    private func refreshSearchInventory() {
        let visibleBibleModules = myBible.availableVisibleModules(ofTypes: [.bible])
        allInterlinearModules = visibleBibleModules.filter { myBible.isInterlinearModule($0) }
        allBibleModules = visibleBibleModules.filter {
            !myBible.isInterlinearModule($0) && myBible.supportsCapability("passageLookup", for: $0)
        }
        allStrongsModules = myBible.availableVisibleModules(ofTypes: [.strongs], requiring: "articleLookup")
        allCommentaryModules = myBible.availableVisibleModules(ofTypes: [.commentary], requiring: "commentaryLookup")
        allCrossReferenceModules = myBible.availableVisibleModules(ofTypes: [.crossRef, .crossRefNative], requiring: "crossReferenceLookup")
        allEncyclopediaModules = myBible.availableVisibleModules(ofTypes: [.encyclopedia], requiring: "articleLookup")
        allLexiconModules = allStrongsModules
        allDictionaryModules = myBible.availableVisibleModules(ofTypes: [.dictionary], requiring: "articleLookup")

        let searchableModules = myBible.visibleModules.filter {
            [.bible, .commentary, .dictionary, .encyclopedia].contains($0.type) && myBible.isRuntimeReady($0)
        }
        var codes = Set(searchableModules.map { normalizedLanguageCode($0.language) }).subtracting(["", "all"])
        for module in searchableModules where myBible.isInterlinearModule(module) {
            codes.formUnion(myBible.interlinearLinkedLanguages(for: module).map { normalizedLanguageCode($0) })
        }

        searchLanguagesCatalog = orderedSearchLanguages(codes.map(LanguageInfo.from))

        syncSearchLanguagesIfNeeded()
        applySelectedLanguageFilters()
    }

    private func languageInfos(from codes: [String]) -> [LanguageInfo] {
        let normalizedCodes = Set(codes.map(normalizedLanguageCode)).subtracting(["", "all"])
        return normalizedCodes.map(LanguageInfo.from)
    }

    private func orderedSearchLanguages(_ languages: [LanguageInfo]) -> [LanguageInfo] {
        let majorLanguageCodes = LanguageInfo.regionMap.first(where: { $0.name == "Major Languages" })?.codes ?? []
        let deduplicated = Dictionary(uniqueKeysWithValues: languages.map { ($0.code, $0) })
        return deduplicated.values.sorted { lhs, rhs in
            let lhsPriority = languagePriority(for: lhs.code, majorLanguageCodes: majorLanguageCodes)
            let rhsPriority = languagePriority(for: rhs.code, majorLanguageCodes: majorLanguageCodes)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func languagePriority(for code: String, majorLanguageCodes: Set<String>) -> Int {
        if code == "en" || code == "eng" {
            return 0
        }
        if majorLanguageCodes.contains(code) {
            return 1
        }
        return 2
    }

    private var pinnedEnglishLanguage: LanguageInfo? {
        filteredAvailableSearchLanguages.first {
            let code = normalizedLanguageCode($0.code)
            return code == "en" || code == "eng"
        }
    }

    private var scrollableSearchLanguages: [LanguageInfo] {
        filteredAvailableSearchLanguages.filter {
            let code = normalizedLanguageCode($0.code)
            return code != "en" && code != "eng"
        }
    }

    private func applySelectedLanguageFilters() {
        filteredInterlinearModuleCache = allInterlinearModules

        guard !selectedSearchLanguages.isEmpty else {
            filteredBibleModuleCache = []
            filteredStrongsModuleCache = []
            filteredCommentaryModuleCache = []
            filteredCrossReferenceModuleCache = []
            filteredEncyclopediaModuleCache = []
            filteredLexiconModuleCache = []
            filteredDictionaryModuleCache = []
            return
        }

        filteredBibleModuleCache = languageFilteredModules(allBibleModules)
        filteredStrongsModuleCache = languageFilteredModules(allStrongsModules)
        filteredCommentaryModuleCache = languageFilteredModules(allCommentaryModules)
        filteredCrossReferenceModuleCache = languageFilteredModules(allCrossReferenceModules)
        filteredEncyclopediaModuleCache = languageFilteredModules(allEncyclopediaModules)
        filteredLexiconModuleCache = languageFilteredModules(allLexiconModules)
        filteredDictionaryModuleCache = languageFilteredModules(allDictionaryModules)
    }

    private var effectiveSelectedBibleIDs: Set<String> {
        let available = Set(bibleModules.map(\.filePath))
        let selected = selectedBibleIDs.intersection(available)
        return effectiveSelection(
            explicit: selected,
            available: available,
            preferred: myBible.selectedBible?.filePath
        )
    }

    private var effectiveSelectedInterlinearIDs: Set<String> {
        let available = Set(interlinearModules.map(\.filePath))
        let selected = selectedInterlinearIDs.intersection(available)
        return selected.isEmpty ? available : selected
    }

    private var effectiveSelectedStrongsIDs: Set<String> {
        let available = Set(strongsModules.map(\.filePath))
        let selected = selectedStrongsIDs.intersection(available)
        return effectiveSelection(
            explicit: selected,
            available: available,
            preferred: myBible.selectedStrongs?.filePath
        )
    }

    private var effectiveSelectedCommentaryIDs: Set<String> {
        let available = Set(commentaryModules.map(\.filePath))
        let selected = selectedCommentaryIDs.intersection(available)
        return effectiveSelection(
            explicit: selected,
            available: available,
            preferred: myBible.selectedCommentary?.filePath
        )
    }

    private var effectiveSelectedCrossReferenceIDs: Set<String> {
        let available = Set(crossReferenceModules.map(\.filePath))
        let selected = selectedCrossReferenceIDs.intersection(available)
        return effectiveSelection(
            explicit: selected,
            available: available,
            preferred: myBible.selectedCrossRef?.filePath
        )
    }

    private var effectiveSelectedEncyclopediaIDs: Set<String> {
        let available = Set(encyclopediaModules.map(\.filePath))
        let selected = selectedEncyclopediaIDs.intersection(available)
        return effectiveSelection(
            explicit: selected,
            available: available,
            preferred: myBible.selectedEncyclopedia?.filePath
        )
    }

    private var effectiveSelectedLexiconIDs: Set<String> {
        let available = Set(lexiconModules.map(\.filePath))
        let selected = selectedLexiconIDs.intersection(available)
        return effectiveSelection(
            explicit: selected,
            available: available,
            preferred: myBible.selectedStrongs?.filePath
        )
    }

    private var effectiveSelectedDictionaryIDs: Set<String> {
        let available = Set(dictionaryModules.map(\.filePath))
        let selected = selectedDictionaryIDs.intersection(available)
        return effectiveSelection(
            explicit: selected,
            available: available,
            preferred: myBible.selectedDictionary?.filePath
        )
    }

    private func effectiveSelection(
        explicit: Set<String>,
        available: Set<String>,
        preferred: String?
    ) -> Set<String> {
        if !explicit.isEmpty {
            return explicit
        }
        if let preferred, available.contains(preferred) {
            return [preferred]
        }
        return available
    }

    private var activeSearchLanguages: [LanguageInfo] {
        availableSearchLanguages.filter { selectedSearchLanguages.contains($0.code) }
    }

    private var currentModulePanelTitle: String {
        switch scope {
        case .bible:
            return "BIBLE MODULES"
        case .interlinear:
            return "INTERLINEAR MODULES"
        case .strongs:
            return "STRONG'S MODULES"
        case .commentary:
            return "COMMENTARY MODULES"
        case .crossReferences:
            return "CROSS-REFERENCE MODULES"
        case .encyclopedias:
            return "ENCYCLOPEDIA MODULES"
        case .lexicons:
            return "LEXICON MODULES"
        case .dictionaries:
            return "DICTIONARY MODULES"
        case .notes:
            return "MODULES"
        }
    }

    private var currentModulePanelSubtitle: String {
        switch scope {
        case .bible:
            return "Choose Bible versions for this search."
        case .interlinear:
            return "Choose interlinears for Strong's or lexical search."
        case .strongs:
            return "Choose Strong's resources for lexical lookup."
        case .commentary:
            return "Choose commentary sources for this search."
        case .crossReferences:
            return "Choose cross-reference sources for this search."
        case .encyclopedias:
            return "Choose encyclopedia sources for this search."
        case .lexicons:
            return "Choose lexicon sources for this search."
        case .dictionaries:
            return "Choose dictionary sources for this search."
        case .notes:
            return "Notes search does not use modules."
        }
    }

    private var currentModuleFilterPlaceholder: String {
        switch scope {
        case .bible:
            return "Filter Bible versions"
        case .interlinear:
            return "Filter interlinears"
        case .strongs:
            return "Filter Strong's resources"
        case .commentary:
            return "Filter commentaries"
        case .crossReferences:
            return "Filter cross-references"
        case .encyclopedias:
            return "Filter encyclopedias"
        case .lexicons:
            return "Filter lexicons"
        case .dictionaries:
            return "Filter dictionaries"
        case .notes:
            return ""
        }
    }

    private var currentModuleEmptyMessage: String {
        switch scope {
        case .bible:
            return "No Bible versions match the active language or module filter."
        case .interlinear:
            return "No interlinears match the active language or module filter."
        case .strongs:
            return "No Strong's resources match the active language or module filter."
        case .commentary:
            return "No commentaries match the active language or module filter."
        case .crossReferences:
            return "No cross-reference modules match the active language or module filter."
        case .encyclopedias:
            return "No encyclopedias match the active language or module filter."
        case .lexicons:
            return "No lexicons match the active language or module filter."
        case .dictionaries:
            return "No dictionaries match the active language or module filter."
        case .notes:
            return "Notes search does not use module filters."
        }
    }

    private var currentModuleFilterText: String {
        switch scope {
        case .bible:
            return bibleModuleFilterText
        case .interlinear:
            return interlinearModuleFilterText
        case .strongs:
            return strongsModuleFilterText
        case .commentary:
            return commentaryModuleFilterText
        case .crossReferences:
            return crossReferenceModuleFilterText
        case .encyclopedias:
            return encyclopediaModuleFilterText
        case .lexicons:
            return lexiconModuleFilterText
        case .dictionaries:
            return dictionaryModuleFilterText
        case .notes:
            return ""
        }
    }

    private var currentModuleFilterBinding: Binding<String>? {
        switch scope {
        case .bible:
            return $bibleModuleFilterText
        case .interlinear:
            return $interlinearModuleFilterText
        case .strongs:
            return $strongsModuleFilterText
        case .commentary:
            return $commentaryModuleFilterText
        case .crossReferences:
            return $crossReferenceModuleFilterText
        case .encyclopedias:
            return $encyclopediaModuleFilterText
        case .lexicons:
            return $lexiconModuleFilterText
        case .dictionaries:
            return $dictionaryModuleFilterText
        case .notes:
            return nil
        }
    }

    private var currentModulePanelModules: [MyBibleModule] {
        switch scope {
        case .bible:
            return filteredBibleModules
        case .interlinear:
            return allInterlinearModules
        case .strongs:
            return filteredStrongsModules
        case .commentary:
            return filteredCommentaryModules
        case .crossReferences:
            return filteredCrossReferenceModules
        case .encyclopedias:
            return filteredEncyclopediaModules
        case .lexicons:
            return filteredLexiconModules
        case .dictionaries:
            return filteredDictionaryModules
        case .notes:
            return []
        }
    }

    private var currentModulePanelDisplayedModules: [MyBibleModule] {
        displayedModules(currentModulePanelModules, filterText: currentModuleFilterText)
    }

    private var currentModulePanelSelectedIDs: Set<String> {
        switch scope {
        case .bible:
            return effectiveSelectedBibleIDs
        case .interlinear:
            return effectiveSelectedInterlinearIDs
        case .strongs:
            return effectiveSelectedStrongsIDs
        case .commentary:
            return effectiveSelectedCommentaryIDs
        case .crossReferences:
            return effectiveSelectedCrossReferenceIDs
        case .encyclopedias:
            return effectiveSelectedEncyclopediaIDs
        case .lexicons:
            return effectiveSelectedLexiconIDs
        case .dictionaries:
            return effectiveSelectedDictionaryIDs
        case .notes:
            return []
        }
    }

    private var currentModulePanelTotalCount: Int {
        currentModulePanelModules.count
    }

    private func syncSearchLanguagesIfNeeded() {
        let availableCodes = Set(availableSearchLanguages.map(\.code))
        selectedSearchLanguages = selectedSearchLanguages.intersection(availableCodes)

        guard !availableCodes.isEmpty else {
            selectedSearchLanguages = []
            return
        }

        if selectedSearchLanguages.isEmpty {
            if availableCodes.contains("en") {
                selectedSearchLanguages = ["en"]
            } else if let bibleLanguage = myBible.selectedBible.map({ normalizedLanguageCode($0.language) }),
                      availableCodes.contains(bibleLanguage) {
                selectedSearchLanguages = [bibleLanguage]
            } else if let first = availableSearchLanguages.first?.code {
                selectedSearchLanguages = [first]
            }
        }

        selectedBibleIDs = selectedBibleIDs.intersection(Set(bibleModules.map(\.filePath)))
        selectedInterlinearIDs = selectedInterlinearIDs.intersection(Set(interlinearModules.map(\.filePath)))
        selectedStrongsIDs = selectedStrongsIDs.intersection(Set(strongsModules.map(\.filePath)))
        selectedCommentaryIDs = selectedCommentaryIDs.intersection(Set(commentaryModules.map(\.filePath)))
        selectedCrossReferenceIDs = selectedCrossReferenceIDs.intersection(Set(crossReferenceModules.map(\.filePath)))
        selectedEncyclopediaIDs = selectedEncyclopediaIDs.intersection(Set(encyclopediaModules.map(\.filePath)))
        selectedLexiconIDs = selectedLexiconIDs.intersection(Set(lexiconModules.map(\.filePath)))
        selectedDictionaryIDs = selectedDictionaryIDs.intersection(Set(dictionaryModules.map(\.filePath)))
    }

    @ViewBuilder
    private var languageFilterPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SEARCH LANGUAGES")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(scope == .interlinear ? "Interlinear search always uses all visible interlinears." : "Choose one language.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if scope == .interlinear {
                filterHint("Language filtering is disabled in Interlinear. All \(allInterlinearModules.count) interlinears stay available.")
            } else {
                moduleFilterField("Search languages", text: $languageFilterText)
                if let english = pinnedEnglishLanguage {
                    searchLanguageRow(english, pinned: true)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(scrollableSearchLanguages, id: \.code) { language in
                            searchLanguageRow(language, pinned: false)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func searchLanguageRow(_ language: LanguageInfo, pinned: Bool) -> some View {
        Button {
            toggleSearchLanguage(language.code)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selectedSearchLanguages.contains(language.code) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedSearchLanguages.contains(language.code) ? filigreeAccent : .secondary)
                VStack(alignment: .leading, spacing: 0) {
                    if pinned {
                        Text("ENGLISH")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(filigreeAccent)
                    }
                    Text(language.flag)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(language.displayName)
                        .font(.caption)
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(language.code.uppercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(selectedSearchLanguages.contains(language.code) ? filigreeAccent.opacity(0.10) : Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var moduleRailPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text(currentModulePanelTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if scope != .notes {
                    HStack(spacing: 8) {
                        moduleActionButton(title: "Current") {
                            resetCurrentModuleSelection()
                        }

                        moduleActionButton(title: "Select All") {
                            selectAllCurrentModules()
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if let filterBinding = currentModuleFilterBinding {
                moduleFilterField(currentModuleFilterPlaceholder, text: filterBinding)
                    .padding(.horizontal, 12)
            }

            if currentModulePanelModules.isEmpty {
                filterHint(currentModuleEmptyMessage)
                    .padding(.horizontal, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(currentModulePanelDisplayedModules) { module in
                            Button {
                                toggleCurrentModule(module)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: currentModulePanelSelectedIDs.contains(module.filePath) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(currentModulePanelSelectedIDs.contains(module.filePath) ? filigreeAccent : .secondary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(LanguageInfo.from(code: module.language).flag)
                                        Text(module.name)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(theme.text)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)

                                        Text(LanguageInfo.from(code: module.language).displayName)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(currentModulePanelSelectedIDs.contains(module.filePath) ? filigreeAccent.opacity(0.10) : Color.secondary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }

                if currentModulePanelTotalCount > currentModulePanelDisplayedModules.count {
                    let remaining = currentModulePanelTotalCount - currentModulePanelDisplayedModules.count
                    let message = currentModuleFilterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Showing first \(currentModulePanelDisplayedModules.count) modules. Refine to narrow the remaining \(remaining)."
                        : "Showing first \(currentModulePanelDisplayedModules.count) matches. Refine further to narrow the remaining \(remaining)."
                    filterHint(message)
                        .padding(.horizontal, 12)
                }
            }

            Spacer()
        }
        .background(theme.background)
    }

    @ViewBuilder
    private func moduleActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(filigreeAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(filigreeAccent.opacity(0.12))
            .overlay(
                Capsule()
                    .stroke(filigreeAccent.opacity(0.38), lineWidth: 1)
            )
            .clipShape(Capsule())
            .buttonStyle(.plain)
    }

    private func toggleSearchLanguage(_ code: String) {
        guard scope != .interlinear else { return }
        let normalized = normalizedLanguageCode(code)
        if selectedSearchLanguages.contains(normalized) {
            return
        } else {
            selectedSearchLanguages = [normalized]
        }

        applySelectedLanguageFilters()
        selectedBibleIDs = selectedBibleIDs.intersection(Set(bibleModules.map(\.filePath)))
        selectedInterlinearIDs = selectedInterlinearIDs.intersection(Set(interlinearModules.map(\.filePath)))
        selectedCommentaryIDs = selectedCommentaryIDs.intersection(Set(commentaryModules.map(\.filePath)))
        selectedStrongsIDs = selectedStrongsIDs.intersection(Set(strongsModules.map(\.filePath)))
        selectedCrossReferenceIDs = selectedCrossReferenceIDs.intersection(Set(crossReferenceModules.map(\.filePath)))
        selectedEncyclopediaIDs = selectedEncyclopediaIDs.intersection(Set(encyclopediaModules.map(\.filePath)))
        selectedLexiconIDs = selectedLexiconIDs.intersection(Set(lexiconModules.map(\.filePath)))
        selectedDictionaryIDs = selectedDictionaryIDs.intersection(Set(dictionaryModules.map(\.filePath)))
    }

    @ViewBuilder
    private func filterSectionHeader(title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func moduleSelectionList(
        modules: [MyBibleModule],
        selectedIDs: Set<String>,
        onToggle: @escaping (MyBibleModule) -> Void,
        totalCount: Int,
        filterText: String
    ) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(modules) { module in
                    Button {
                        onToggle(module)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedIDs.contains(module.filePath) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(selectedIDs.contains(module.filePath) ? filigreeAccent : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(module.name)
                                    .font(.caption)
                                    .foregroundStyle(theme.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(LanguageInfo.from(code: module.language).label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minHeight: 120, idealHeight: 220, maxHeight: 260)

        if totalCount > modules.count {
            let remaining = totalCount - modules.count
            let message = filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Showing first \(modules.count) modules. Refine the filter to narrow the remaining \(remaining)."
                : "Showing first \(modules.count) matches. Refine further to narrow the remaining \(remaining)."
            filterHint(message)
        }
    }

    private func toggleBibleModule(_ module: MyBibleModule) {
        if selectedBibleIDs.contains(module.filePath) {
            selectedBibleIDs.remove(module.filePath)
        } else {
            selectedBibleIDs.insert(module.filePath)
        }
    }

    private func toggleInterlinearModule(_ module: MyBibleModule) {
        if selectedInterlinearIDs.contains(module.filePath) {
            selectedInterlinearIDs.remove(module.filePath)
        } else {
            selectedInterlinearIDs.insert(module.filePath)
        }
    }

    private func toggleCommentaryModule(_ module: MyBibleModule) {
        if selectedCommentaryIDs.contains(module.filePath) {
            selectedCommentaryIDs.remove(module.filePath)
        } else {
            selectedCommentaryIDs.insert(module.filePath)
        }
    }

    private func toggleCurrentModule(_ module: MyBibleModule) {
        switch scope {
        case .bible:
            toggleBibleModule(module)
        case .interlinear:
            toggleInterlinearModule(module)
        case .strongs:
            toggleSetMembership(&selectedStrongsIDs, value: module.filePath)
        case .commentary:
            toggleCommentaryModule(module)
        case .crossReferences:
            toggleSetMembership(&selectedCrossReferenceIDs, value: module.filePath)
        case .encyclopedias:
            toggleSetMembership(&selectedEncyclopediaIDs, value: module.filePath)
        case .lexicons:
            toggleSetMembership(&selectedLexiconIDs, value: module.filePath)
        case .dictionaries:
            toggleSetMembership(&selectedDictionaryIDs, value: module.filePath)
        case .notes:
            break
        }
    }

    private func selectAllCurrentModules() {
        let allIDs = Set(currentModulePanelModules.map(\.filePath))
        switch scope {
        case .bible:
            selectedBibleIDs = allIDs
        case .interlinear:
            selectedInterlinearIDs = allIDs
        case .strongs:
            selectedStrongsIDs = allIDs
        case .commentary:
            selectedCommentaryIDs = allIDs
        case .crossReferences:
            selectedCrossReferenceIDs = allIDs
        case .encyclopedias:
            selectedEncyclopediaIDs = allIDs
        case .lexicons:
            selectedLexiconIDs = allIDs
        case .dictionaries:
            selectedDictionaryIDs = allIDs
        case .notes:
            break
        }
    }

    private func resetCurrentModuleSelection() {
        switch scope {
        case .bible:
            selectedBibleIDs = []
        case .interlinear:
            selectedInterlinearIDs = []
        case .strongs:
            selectedStrongsIDs = []
        case .commentary:
            selectedCommentaryIDs = []
        case .crossReferences:
            selectedCrossReferenceIDs = []
        case .encyclopedias:
            selectedEncyclopediaIDs = []
        case .lexicons:
            selectedLexiconIDs = []
        case .dictionaries:
            selectedDictionaryIDs = []
        case .notes:
            break
        }
    }

    private func toggleSetMembership(_ set: inout Set<String>, value: String) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    @ViewBuilder
    private func moduleFilterField(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .font(.caption)
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func searchModeLabel(for mode: SearchMode) -> String {
        switch mode {
        case .global:
            return "Balanced"
        case .bibleFirst:
            return "Bible First"
        case .referenceFirst:
            return "References First"
        case .commentaryFirst:
            return "Commentary First"
        }
    }

    @ViewBuilder
    private func filterHint(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Result area

    private var workspaceBody: some View {
        HSplitView {
            resultsPane
                .frame(minWidth: 320, idealWidth: 400, maxWidth: 540)

            previewPane
                .frame(minWidth: 320, idealWidth: 400, maxWidth: 540)

            filterSidebar
                .frame(minWidth: 760, idealWidth: 900, maxWidth: 1040, alignment: .leading)
        }
    }

    private var resultsPane: some View {
        VStack(spacing: 0) {
            paneHeader(
                title: "Results",
                subtitle: resultsSummaryText,
                icon: "text.magnifyingglass"
            )
            Divider()
            resultArea
        }
        .background(theme.background)
    }

    private var previewPane: some View {
        VStack(spacing: 0) {
            paneHeader(
                title: "Preview",
                subtitle: selectedResult?.moduleName ?? "Inspect a selected result",
                icon: "doc.text.magnifyingglass"
            )
            Divider()

            if let result = selectedResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.reference)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(filigreeAccent)
                                Text(result.type.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if result.route != nil {
                                Button("Open") { navigate(to: result) }
                                    .buttonStyle(.borderedProminent)
                                    .tint(filigreeAccentFill)
                            }
                        }

                        previewMetadata(for: result)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Excerpt")
                                .font(.headline)
                            Text(result.snippet)
                                .font(.body)
                                .foregroundStyle(theme.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        previewContent(for: result)
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "rectangle.and.text.magnifyingglass")
                        .font(.system(size: 42))
                        .foregroundStyle(.quaternary)
                    Text("Select a result to inspect it here")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .background(theme.background)
    }

    private var filterSidebar: some View {
        HStack(spacing: 12) {
            filterPanel
                .frame(minWidth: 350, idealWidth: 400, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(sidebarPanelCard)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(sidebarPanelStroke)
            moduleRailPanel
                .frame(minWidth: 165, idealWidth: 178, maxWidth: 190, maxHeight: .infinity, alignment: .topLeading)
                .background(sidebarPanelCard)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(sidebarPanelStroke)
            languageFilterPanel
                .frame(minWidth: 150, idealWidth: 162, maxWidth: 174, maxHeight: .infinity, alignment: .topLeading)
                .background(sidebarPanelCard)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(sidebarPanelStroke)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(10)
        .background(theme.background)
    }

    private var filterStatsPanel: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
            statCard(title: "Scope", value: scope.rawValue)
            statCard(title: "Results", value: "\(results.count)")
            statCard(title: "Modules", value: "\(currentModulePanelTotalCount)")
            statCard(title: "Language", value: activeLanguageSummary)
        }
    }

    private var activeLanguageSummary: String {
        if scope == .interlinear {
            return "Global"
        }
        return activeSearchLanguages.first?.displayName ?? "None"
    }

    private var sidebarPanelCard: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(theme.background)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(filigreeAccent.opacity(0.72), lineWidth: 1.45)
            )
            .shadow(color: filigreeAccent.opacity(0.08), radius: 8, x: 0, y: 3)
    }

    private var sidebarPanelStroke: some View {
        RoundedRectangle(cornerRadius: 18)
            .stroke(filigreeAccent.opacity(0.82), lineWidth: 1.5)
    }

    @ViewBuilder
    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func filterSectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.055))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func paneHeader(title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(filigreeAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func previewMetadata(for result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details")
                .font(.headline)

            previewMetadataRow(label: "Source", value: result.moduleName)
            previewMetadataRow(label: "Kind", value: result.type.rawValue)

            if let modulePath = result.modulePath, !modulePath.isEmpty {
                previewMetadataRow(label: "Module Path", value: modulePath)
            }

            if let lookupQuery = result.lookupQuery, !lookupQuery.isEmpty {
                previewMetadataRow(label: "Lookup", value: lookupQuery)
            }

            if result.chapter > 0 {
                let verseText = result.verse > 0 ? ":\(result.verse)" : ""
                previewMetadataRow(label: "Location", value: "\(result.bookNumber) \(result.chapter)\(verseText)")
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func previewMetadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(theme.text)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func previewContent(for result: SearchResult) -> some View {
        if isLoadingPreview {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading context…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            switch result.type {
            case .bible:
                if !previewVerseWindow(for: result).isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Verse Context")
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(previewVerseWindow(for: result)) { verse in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(verse.verse)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(verse.verse == result.verse ? filigreeAccent : .secondary)
                                        .frame(width: 26, alignment: .leading)
                                    Text(verse.text)
                                        .font(.body)
                                        .foregroundStyle(theme.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(10)
                                .background(verse.verse == result.verse ? filigreeAccent.opacity(0.10) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(4)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    EmptyView()
                }

            case .commentary:
                if !previewCommentaryWindow(for: result).isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Commentary Context")
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(previewCommentaryWindow(for: result)) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(commentaryReference(for: entry))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(entryMatchesResultVerse(entry, result: result) ? filigreeAccent : .secondary)
                                    Text(entry.text)
                                        .font(.body)
                                        .foregroundStyle(theme.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(12)
                                .background(entryMatchesResultVerse(entry, result: result) ? filigreeAccent.opacity(0.10) : Color.secondary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                } else {
                    EmptyView()
                }

            case .notes:
                if let note = previewNote {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Note")
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 8) {
                            if !note.verseReference.isEmpty {
                                previewMetadataRow(label: "Reference", value: note.verseReference)
                            }
                            previewMetadataRow(label: "Updated", value: note.formattedDate)
                            Text(note.plainTextContent)
                                .font(.body)
                                .foregroundStyle(theme.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    EmptyView()
                }

            case .reference:
                if let lookupQuery = result.lookupQuery, !lookupQuery.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Lookup Target")
                            .font(.headline)
                        previewMetadataRow(label: "Query", value: lookupQuery)
                    }
                    .padding(14)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    EmptyView()
                }
            }
        }
    }

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
                Text(searchHelpText)
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
                ForEach(sectionOrder, id: \.self) { type in
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
                                           filigreeAccent: filigreeAccent, theme: theme,
                                           isSelected: selectedResultID == result.id)
                                .onTapGesture {
                                    selectedResultID = result.id
                                }
                                .onTapGesture(count: 2) {
                                    selectedResultID = result.id
                                    navigate(to: result)
                                }
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var selectedResult: SearchResult? {
        guard let selectedResultID else { return nil }
        return results.first(where: { $0.id == selectedResultID })
    }

    private var resultsSummaryText: String {
        if query.isEmpty {
            return "Search across Bible, notes, commentary, and references"
        }
        if isSearching {
            return "Searching \(scope.rawValue.lowercased()) for \"\(query)\""
        }
        return "\(results.count) result\(results.count == 1 ? "" : "s") for \"\(query)\""
    }

    private func previewVerseWindow(for result: SearchResult) -> [MyBibleVerse] {
        guard result.verse > 0 else { return previewVerses.prefix(5).map { $0 } }
        return previewVerses.filter { abs($0.verse - result.verse) <= 2 }
    }

    private func previewCommentaryWindow(for result: SearchResult) -> [CommentaryEntry] {
        let matched = previewCommentaryEntries.filter { entryMatchesResultVerse($0, result: result) }
        if !matched.isEmpty {
            return matched
        }
        return Array(previewCommentaryEntries.prefix(3))
    }

    private func entryMatchesResultVerse(_ entry: CommentaryEntry, result: SearchResult) -> Bool {
        guard result.verse > 0 else {
            return entry.chapterFrom == result.chapter
        }
        return entry.chapterFrom == result.chapter && result.verse >= entry.verseFrom && result.verse <= entry.verseTo
    }

    private func commentaryReference(for entry: CommentaryEntry) -> String {
        let book = myBibleBookNumbers[entry.bookNumber] ?? "\(entry.bookNumber)"
        if entry.verseFrom == entry.verseTo {
            return "\(book) \(entry.chapterFrom):\(entry.verseFrom)"
        }
        return "\(book) \(entry.chapterFrom):\(entry.verseFrom)-\(entry.verseTo)"
    }

    private func moduleForPreview(path: String?) -> MyBibleModule? {
        guard let path else { return nil }
        return myBible.visibleModules.first(where: { $0.filePath == path })
    }

    @MainActor
    private func resetPreviewState() {
        previewVerses = []
        previewCommentaryEntries = []
        previewNote = nil
        isLoadingPreview = false
    }

    private func loadPreview() async {
        guard let result = selectedResult else {
            await MainActor.run { resetPreviewState() }
            return
        }

        await MainActor.run {
            previewVerses = []
            previewCommentaryEntries = []
            previewNote = nil
            isLoadingPreview = true
        }

        switch result.type {
        case .bible:
            if let module = moduleForPreview(path: result.modulePath) {
                let verses = await myBible.fetchVerses(module: module, bookNumber: result.bookNumber, chapter: result.chapter)
                await MainActor.run {
                    previewVerses = verses
                    isLoadingPreview = false
                }
            } else {
                await MainActor.run { isLoadingPreview = false }
            }

        case .commentary:
            if let module = moduleForPreview(path: result.modulePath) {
                let entries = await myBible.fetchCommentaryEntries(module: module, bookNumber: result.bookNumber, chapter: result.chapter)
                await MainActor.run {
                    previewCommentaryEntries = entries
                    isLoadingPreview = false
                }
            } else {
                await MainActor.run { isLoadingPreview = false }
            }

        case .notes:
            await MainActor.run {
                previewNote = notesManager.notes.first(where: { $0.id == result.noteID })
                isLoadingPreview = false
            }

        case .reference:
            await MainActor.run {
                isLoadingPreview = false
            }
        }
    }

    // MARK: - Query parsing

    /// Returns the actual search string (strips quotes for display/matching)
    private var effectiveQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// True if user wrapped query in quotes = exact phrase
    private var isExactPhrase: Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return (q.hasPrefix("\"") && q.hasSuffix("\"")) ||
               (q.hasPrefix("\u{201C}") && q.hasSuffix("\u{201D}"))
    }

    private var searchHelpText: String {
        switch queryKind {
        case .word:
            return includeInflections
                ? "Word mode is broadened to include forms like loved and loves."
                : "Word mode matches the exact word by default. Use filters to include inflections."
        case .phrase:
            return "Phrase mode matches the phrase exactly in order, without needing quotes."
        case .strongs:
            return "Strong's mode finds every Bible verse where a number like G25 or H157 appears."
        }
    }

    // MARK: - Search scheduling

    private func scheduleSearch() {
        debounceTimer?.invalidate()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            scopeHitCounts = [:]
            return
        }
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in runSearch() }
    }

    // MARK: - Run search

    private func runSearch() {
        let q = effectiveQuery
        guard !q.isEmpty else {
            results = []
            scopeHitCounts = [:]
            return
        }
        let request = SearchRequest(
            query: q,
            queryKind: queryKind,
            scope: scope,
            mode: searchMode,
            testament: testament,
            bookFilter: bookFilter,
            exact: queryKind == .phrase || isExactPhrase,
            includeInflections: includeInflections,
            notesFrom: notesFrom,
            notesTo: notesTo,
            selectedBiblePaths: effectiveSelectedBibleIDs,
            selectedInterlinearPaths: effectiveSelectedInterlinearIDs,
            selectedStrongsPaths: effectiveSelectedStrongsIDs,
            selectedCommentaryPaths: effectiveSelectedCommentaryIDs,
            selectedCrossReferencePaths: effectiveSelectedCrossReferenceIDs,
            selectedEncyclopediaPaths: effectiveSelectedEncyclopediaIDs,
            selectedLexiconPaths: effectiveSelectedLexiconIDs,
            selectedDictionaryPaths: effectiveSelectedDictionaryIDs
        )
        let context = SearchExecutionContext(
            visibleModules: myBible.visibleModules,
            catalogRecordsByPath: myBible.catalogRecordsByPath,
            selectedBible: myBible.selectedBible,
            selectedStrongs: myBible.selectedStrongs,
            selectedCommentary: myBible.selectedCommentary,
            selectedDictionary: myBible.selectedDictionary,
            selectedEncyclopedia: myBible.selectedEncyclopedia,
            selectedCrossReference: myBible.selectedCrossRef,
            moduleUsageScoresByPath: ModuleUsageStore.usageScoresByPath(),
            notes: notesManager.notes
        )
        let runID = UUID()
        searchRunID = runID

        isSearching = true
        results     = []
        scopeHitCounts = [:]

        DispatchQueue.global(qos: .userInitiated).async {
            let found = SearchCoordinator.performSearch(request: request, context: context)

            DispatchQueue.main.async {
                guard self.searchRunID == runID else { return }
                self.results    = found
                self.isSearching = false
            }
        }

        let probeScopes = visibleSearchScopes
        DispatchQueue.global(qos: .utility).async {
            let probe = SearchCoordinator.performScopeProbe(
                request: request,
                context: context,
                scopes: probeScopes
            )

            DispatchQueue.main.async {
                guard self.searchRunID == runID else { return }
                self.scopeHitCounts = probe
            }
        }
    }

    private func scopeHasHits(_ scope: SearchScope) -> Bool {
        (scopeHitCounts[scope] ?? 0) > 0
    }

    // MARK: - Navigation

    private func navigate(to result: SearchResult) {
        guard let route = result.route else { return }

        switch route {
        case .passage(let request):
            NotificationCenter.default.post(name: .navigateToPassage, object: nil,
                userInfo: request.userInfo)
        case .commentary(let bookNumber, let chapter, let moduleName):
            NotificationCenter.default.post(name: .navigateToCommentary, object: nil,
                userInfo: ["bookNumber": bookNumber, "chapter": chapter,
                           "moduleName": moduleName])
        case .reference(let modulePath, let lookupQuery, let kind):
            NotificationCenter.default.post(name: Notification.Name("switchToBibleTab"), object: nil)
            if kind == .encyclopedia {
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
        case .note(let id):
            notesManager.searchHighlight = effectiveQuery
            notesManager.selectedNote = notesManager.notes.first { $0.id == id }
            NotificationCenter.default.post(name: Notification.Name("switchToNotesTab"), object: nil)
        }
    }

    private var sectionOrder: [SearchResult.ResultType] {
        switch searchMode {
        case .global:
            return [.bible, .reference, .commentary, .notes]
        case .bibleFirst:
            return [.bible, .commentary, .reference, .notes]
        case .referenceFirst:
            return [.reference, .commentary, .bible, .notes]
        case .commentaryFirst:
            return [.commentary, .bible, .reference, .notes]
        }
    }
}

// MARK: - Result Row

struct SearchResultRow: View {
    let result:         SearchResult
    let query:          String
    let filigreeAccent: Color
    let theme:          AppTheme
    let isSelected:     Bool
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
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? filigreeAccent.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? filigreeAccent.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
