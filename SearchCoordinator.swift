import Foundation
import SQLite3

enum SearchCoordinator {
    static func performSearch(
        request: SearchRequest,
        context: SearchExecutionContext,
        stopAfterFirstResult: Bool = false
    ) -> [SearchResult] {
        guard !request.query.isEmpty else { return [] }

        let bibles = resolveBibleModules(request: request, context: context)
        let interlinears = resolveInterlinearModules(request: request, context: context)
        let commentaries = prioritizeSearchModules(context.visibleModules.filter {
            $0.type == .commentary &&
            supportsSearch(modulePath: $0.filePath, requiredCapability: "commentaryLookup", context: context) &&
            request.selectedCommentaryPaths.contains($0.filePath)
        }, preferredPath: context.selectedCommentary?.filePath, context: context).map {
            SearchModuleInfo(path: $0.filePath, name: $0.name, type: $0.type)
        }

        let dictionaries = resolveArticleModules(
            types: [.dictionary],
            selectedPaths: request.selectedDictionaryPaths,
            context: context
        ).map {
            SearchModuleInfo(path: $0.filePath, name: $0.name, type: $0.type)
        }
        let encyclopedias = resolveArticleModules(
            types: [.encyclopedia],
            selectedPaths: request.selectedEncyclopediaPaths,
            context: context
        ).map {
            SearchModuleInfo(path: $0.filePath, name: $0.name, type: $0.type)
        }
        let lexicons = resolveArticleModules(
            types: [.strongs],
            selectedPaths: request.selectedLexiconPaths,
            context: context
        ).map {
            SearchModuleInfo(path: $0.filePath, name: $0.name, type: $0.type)
        }
        let crossReferences = prioritizeSearchModules(context.visibleModules.filter {
            ($0.type == .crossRef || $0.type == .crossRefNative) &&
            supportsSearch(modulePath: $0.filePath, requiredCapability: "crossReferenceLookup", context: context) &&
            request.selectedCrossReferencePaths.contains($0.filePath)
        }, preferredPath: context.selectedCrossReference?.filePath, context: context).map {
            SearchModuleInfo(path: $0.filePath, name: $0.name, type: $0.type)
        }

        var found: [SearchResult] = []

        if request.scope == .bible || request.scope == .interlinear || request.scope == .strongs {
            var seen = Set<String>()
            let targetModules: [SearchModuleInfo]
            switch request.scope {
            case .interlinear, .strongs:
                targetModules = interlinears
            default:
                targetModules = bibles
            }
            let allowBroadBibleFallback = targetModules.count <= 2
            for module in targetModules {
                let matches = BibleSearchAdapter.search(
                    module: module,
                    query: request.query,
                    queryKind: request.queryKind,
                    testament: request.testament,
                    bookFilter: request.bookFilter,
                    exact: request.exact,
                    includeInflections: request.includeInflections,
                    allowFallback: allowBroadBibleFallback || module.path == context.selectedBible?.filePath
                )
                for result in matches {
                    let key = "\(result.moduleName):\(result.bookNumber):\(result.chapter):\(result.verse)"
                    if seen.insert(key).inserted {
                        found.append(result)
                        if stopAfterFirstResult {
                            return finalize(found, mode: request.mode)
                        }
                    }
                }
            }
        }

        if request.scope == .notes {
            if request.queryKind != .strongs {
                found += NotesSearchAdapter.search(
                    context.notes,
                    query: request.query,
                    queryKind: request.queryKind,
                    includeInflections: request.includeInflections,
                    from: request.notesFrom,
                    to: request.notesTo
                )
                if stopAfterFirstResult, !found.isEmpty {
                    return finalize(found, mode: request.mode)
                }
            }
        }

        if request.scope == .commentary {
            if request.queryKind != .strongs {
                for module in commentaries {
                    found += CommentarySearchAdapter.search(
                        module: module,
                        query: request.query,
                        queryKind: request.queryKind,
                        exact: request.exact,
                        includeInflections: request.includeInflections
                    )
                    if stopAfterFirstResult, !found.isEmpty {
                        return finalize(found, mode: request.mode)
                    }
                }
            }
        }

        if request.scope == .dictionaries || request.scope == .encyclopedias || request.scope == .lexicons {
            if request.queryKind != .strongs {
                let targetModules: [SearchModuleInfo]
                switch request.scope {
                case .dictionaries:
                    targetModules = dictionaries
                case .encyclopedias:
                    targetModules = encyclopedias
                case .lexicons:
                    targetModules = lexicons
                default:
                    targetModules = []
                }
                for module in targetModules {
                    found += ReferenceSearchAdapter.search(
                        module: module,
                        query: request.query,
                        queryKind: request.queryKind,
                        exact: request.exact,
                        includeInflections: request.includeInflections
                    )
                    if stopAfterFirstResult, !found.isEmpty {
                        return finalize(found, mode: request.mode)
                    }
                }
            }
        }

        if request.scope == .crossReferences {
            if request.queryKind != .strongs {
                for module in crossReferences {
                    found += CrossReferenceSearchAdapter.search(
                        module: module,
                        query: request.query,
                        queryKind: request.queryKind,
                        testament: request.testament,
                        bookFilter: request.bookFilter,
                        exact: request.exact,
                        includeInflections: request.includeInflections
                    )
                    if stopAfterFirstResult, !found.isEmpty {
                        return finalize(found, mode: request.mode)
                    }
                }
            }
        }

        return finalize(found, mode: request.mode)
    }

    static func performScopeProbe(
        request: SearchRequest,
        context: SearchExecutionContext,
        scopes: [SearchScope]
    ) -> [SearchScope: Int] {
        var hits: [SearchScope: Int] = [:]
        for scope in scopes {
            let scopedRequest = SearchRequest(
                query: request.query,
                queryKind: request.queryKind,
                scope: scope,
                mode: request.mode,
                testament: request.testament,
                bookFilter: request.bookFilter,
                exact: request.exact,
                includeInflections: request.includeInflections,
                notesFrom: request.notesFrom,
                notesTo: request.notesTo,
                selectedBiblePaths: request.selectedBiblePaths,
                selectedInterlinearPaths: request.selectedInterlinearPaths,
                selectedStrongsPaths: request.selectedStrongsPaths,
                selectedCommentaryPaths: request.selectedCommentaryPaths,
                selectedCrossReferencePaths: request.selectedCrossReferencePaths,
                selectedEncyclopediaPaths: request.selectedEncyclopediaPaths,
                selectedLexiconPaths: request.selectedLexiconPaths,
                selectedDictionaryPaths: request.selectedDictionaryPaths
            )
            let found = performSearch(
                request: scopedRequest,
                context: context,
                stopAfterFirstResult: true
            )
            hits[scope] = found.isEmpty ? 0 : 1
        }
        return hits
    }

    private static func finalize(_ found: [SearchResult], mode: SearchMode) -> [SearchResult] {
        found.sorted { compareResults(lhs: $0, rhs: $1, mode: mode) }
    }

    private static func resolveBibleModules(
        request: SearchRequest,
        context: SearchExecutionContext
    ) -> [SearchModuleInfo] {
        var bibleSet = [String: SearchModuleInfo]()
        if let selected = context.selectedBible,
           context.visibleModules.contains(selected),
           supportsSearch(modulePath: selected.filePath, requiredCapability: "passageLookup", context: context),
           request.selectedBiblePaths.contains(selected.filePath) {
            bibleSet[selected.filePath] = SearchModuleInfo(path: selected.filePath, name: selected.name, type: selected.type)
        }
        for module in context.visibleModules where module.type == .bible {
            if supportsSearch(modulePath: module.filePath, requiredCapability: "passageLookup", context: context),
               request.selectedBiblePaths.contains(module.filePath) {
                bibleSet[module.filePath] = SearchModuleInfo(path: module.filePath, name: module.name, type: module.type)
            }
        }
        return prioritizeSearchModuleInfos(
            Array(bibleSet.values),
            preferredPath: context.selectedBible?.filePath,
            context: context
        )
    }

    private static func resolveInterlinearModules(
        request: SearchRequest,
        context: SearchExecutionContext
    ) -> [SearchModuleInfo] {
        let modules: [SearchModuleInfo] = context.visibleModules.compactMap { module -> SearchModuleInfo? in
            guard module.type == .bible,
                  request.selectedInterlinearPaths.contains(module.filePath),
                  supportsSearch(modulePath: module.filePath, requiredCapability: "passageLookup", context: context),
                  supportsInterlinear(modulePath: module.filePath, context: context)
            else {
                return nil
            }
            return SearchModuleInfo(path: module.filePath, name: module.name, type: module.type)
        }
        return prioritizeSearchModuleInfos(modules, preferredPath: nil, context: context)
    }

    private static func resolveArticleModules(
        types: Set<ModuleType>,
        selectedPaths: Set<String>,
        context: SearchExecutionContext
    ) -> [MyBibleModule] {
        let referenceModules = context.visibleModules.filter { types.contains($0.type) }
        var modules: [MyBibleModule] = []
        if types.contains(.dictionary),
           let dictionary = context.selectedDictionary,
           context.visibleModules.contains(dictionary),
           supportsSearch(modulePath: dictionary.filePath, requiredCapability: "articleLookup", context: context),
           selectedPaths.contains(dictionary.filePath) {
            modules.append(dictionary)
        }
        if types.contains(.encyclopedia),
           let encyclopedia = context.selectedEncyclopedia,
           context.visibleModules.contains(encyclopedia),
           supportsSearch(modulePath: encyclopedia.filePath, requiredCapability: "articleLookup", context: context),
           selectedPaths.contains(encyclopedia.filePath),
           !modules.contains(encyclopedia) {
            modules.append(encyclopedia)
        }
        if types.contains(.strongs),
           let strongs = context.selectedStrongs,
           context.visibleModules.contains(strongs),
           supportsSearch(modulePath: strongs.filePath, requiredCapability: "articleLookup", context: context),
           selectedPaths.contains(strongs.filePath),
           !modules.contains(strongs) {
            modules.append(strongs)
        }
        if modules.isEmpty {
            modules = referenceModules.filter {
                supportsSearch(modulePath: $0.filePath, requiredCapability: "articleLookup", context: context) &&
                selectedPaths.contains($0.filePath)
            }
        }
        return prioritizeSearchModules(modules, preferredPath: preferredPath(for: types, context: context), context: context)
    }

    private static func preferredPath(for types: Set<ModuleType>, context: SearchExecutionContext) -> String? {
        if types.contains(.dictionary) {
            return context.selectedDictionary?.filePath
        }
        if types.contains(.encyclopedia) {
            return context.selectedEncyclopedia?.filePath
        }
        if types.contains(.strongs) {
            return context.selectedStrongs?.filePath
        }
        return nil
    }

    private static func prioritizeSearchModules(
        _ modules: [MyBibleModule],
        preferredPath: String?,
        context: SearchExecutionContext
    ) -> [MyBibleModule] {
        modules.sorted { lhs, rhs in
            rank(modulePath: lhs.filePath, preferredPath: preferredPath, context: context) >
                rank(modulePath: rhs.filePath, preferredPath: preferredPath, context: context)
        }
    }

    private static func prioritizeSearchModuleInfos(
        _ modules: [SearchModuleInfo],
        preferredPath: String?,
        context: SearchExecutionContext
    ) -> [SearchModuleInfo] {
        modules.sorted { lhs, rhs in
            rank(modulePath: lhs.path, preferredPath: preferredPath, context: context) >
                rank(modulePath: rhs.path, preferredPath: preferredPath, context: context)
        }
    }

    private static func rank(
        modulePath: String,
        preferredPath: String?,
        context: SearchExecutionContext
    ) -> Int {
        let preferredBonus = modulePath == preferredPath ? 1_000_000 : 0
        let usageScore = context.moduleUsageScoresByPath[modulePath, default: 0]
        return preferredBonus + usageScore
    }

    private static func supportsSearch(
        modulePath: String,
        requiredCapability: String,
        context: SearchExecutionContext
    ) -> Bool {
        guard let record = context.catalogRecordsByPath[modulePath] else {
            return true
        }
        return record.validation.state == .ready &&
            record.metadata.capabilities.contains(requiredCapability)
    }

    private static func supportsInterlinear(
        modulePath: String,
        context: SearchExecutionContext
    ) -> Bool {
        guard let record = context.catalogRecordsByPath[modulePath] else {
            return false
        }
        return record.validation.state == .ready &&
            record.metadata.capabilities.contains("interlinear")
    }

    private static func compareResults(lhs: SearchResult, rhs: SearchResult, mode: SearchMode) -> Bool {
        let leftPriority = modePriority(for: lhs.type, mode: mode)
        let rightPriority = modePriority(for: rhs.type, mode: mode)
        if leftPriority != rightPriority { return leftPriority > rightPriority }
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.type != rhs.type { return lhs.type.rawValue < rhs.type.rawValue }
        if lhs.reference != rhs.reference { return lhs.reference.localizedCaseInsensitiveCompare(rhs.reference) == .orderedAscending }
        return lhs.moduleName.localizedCaseInsensitiveCompare(rhs.moduleName) == .orderedAscending
    }

    private static func modePriority(for type: SearchResult.ResultType, mode: SearchMode) -> Int {
        switch mode {
        case .global:
            switch type {
            case .bible: return 4
            case .reference: return 3
            case .commentary: return 2
            case .notes: return 1
            }
        case .bibleFirst:
            switch type {
            case .bible: return 4
            case .commentary: return 3
            case .reference: return 2
            case .notes: return 1
            }
        case .referenceFirst:
            switch type {
            case .reference: return 4
            case .commentary: return 3
            case .bible: return 2
            case .notes: return 1
            }
        case .commentaryFirst:
            switch type {
            case .commentary: return 4
            case .bible: return 3
            case .reference: return 2
            case .notes: return 1
            }
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum BibleSearchAdapter {
    static func search(
        module: SearchModuleInfo,
        query: String,
        queryKind: SearchQueryKind,
        testament: Testament,
        bookFilter: Int,
        exact: Bool,
        includeInflections: Bool,
        allowFallback: Bool
    ) -> [SearchResult] {
        if module.path.hasSuffix(".graphe") {
            guard allowFallback else { return [] }
            return searchFallback(
                db: SearchAdapterSupport.openDatabase(at: module.path),
                path: module.path,
                query: query,
                queryKind: queryKind,
                moduleName: module.name,
                testament: testament,
                bookFilter: bookFilter,
                exact: exact,
                includeInflections: includeInflections
            )
        }

        return GrapheRuntimeStorage.withOpenDatabase(at: module.path) { db in
            var out: [SearchResult] = []
            let queryPattern = SearchAdapterSupport.sqlCandidatePattern(for: query, kind: queryKind)

            for (lower, upper) in SearchAdapterSupport.ranges(for: testament) {
                let bookClause = bookFilter > 0
                    ? "AND book_number = \(bookFilter)"
                    : "AND book_number BETWEEN \(lower) AND \(upper)"
                let sql = "SELECT book_number, chapter, verse, text FROM verses WHERE text LIKE ? \(bookClause) ORDER BY book_number, chapter, verse LIMIT 300"
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
                sqlite3_bind_text(statement, 1, queryPattern, -1, SQLITE_TRANSIENT)

                while sqlite3_step(statement) == SQLITE_ROW {
                    let book = Int(sqlite3_column_int(statement, 0))
                    let chapter = Int(sqlite3_column_int(statement, 1))
                    let verse = Int(sqlite3_column_int(statement, 2))
                    let raw = GrapheRuntimeStorage.columnString(statement, 3, path: module.path) ?? ""
                    guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let clean = SearchAdapterSupport.cleanText(raw)
                    guard SearchAdapterSupport.matchesVerse(raw: raw, clean: clean, query: query, kind: queryKind, exact: exact, includeInflections: includeInflections) else {
                        continue
                    }
                    let bookName = myBibleBookNumbers[book] ?? "Book \(book)"
                    out.append(
                        .bible(
                            reference: "\(bookName) \(chapter):\(verse)",
                            snippet: makeSnippet(clean, matching: query),
                            moduleName: module.name,
                            bookNumber: book,
                            chapter: chapter,
                            verse: verse,
                            modulePath: module.path,
                            score: SearchAdapterSupport.scoreBibleResult(
                                bookName: bookName,
                                text: clean,
                                query: query,
                                exact: exact || queryKind != .word || !includeInflections
                            )
                        )
                    )
                }
                sqlite3_finalize(statement)
                if bookFilter > 0 { break }
            }

            out.sort { ($0.bookNumber, $0.chapter, $0.verse) < ($1.bookNumber, $1.chapter, $1.verse) }
            return out
        } ?? []
    }

    private static func searchFallback(
        db: OpaquePointer?,
        path: String,
        query: String,
        queryKind: SearchQueryKind,
        moduleName: String,
        testament: Testament,
        bookFilter: Int,
        exact: Bool,
        includeInflections: Bool
    ) -> [SearchResult] {
        guard let db else { return [] }
        var out: [SearchResult] = []

        for (lower, upper) in SearchAdapterSupport.ranges(for: testament) {
            let bookClause = bookFilter > 0
                ? "AND book_number = \(bookFilter)"
                : "AND book_number BETWEEN \(lower) AND \(upper)"
            let sql = "SELECT book_number, chapter, verse, text FROM verses WHERE 1 = 1 \(bookClause) ORDER BY book_number, chapter, verse"

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(statement) }

            while sqlite3_step(statement) == SQLITE_ROW {
                let book = Int(sqlite3_column_int(statement, 0))
                let chapter = Int(sqlite3_column_int(statement, 1))
                let verse = Int(sqlite3_column_int(statement, 2))
                let raw = GrapheRuntimeStorage.columnString(statement, 3, path: path) ?? ""
                let clean = SearchAdapterSupport.cleanText(raw)
                guard !clean.isEmpty,
                      SearchAdapterSupport.matchesVerse(raw: raw, clean: clean, query: query, kind: queryKind, exact: exact, includeInflections: includeInflections)
                else { continue }

                let bookName = myBibleBookNumbers[book] ?? "Book \(book)"
                out.append(
                    .bible(
                        reference: "\(bookName) \(chapter):\(verse)",
                        snippet: makeSnippet(clean, matching: query),
                        moduleName: moduleName,
                        bookNumber: book,
                        chapter: chapter,
                        verse: verse,
                        modulePath: path,
                        score: SearchAdapterSupport.scoreBibleResult(
                            bookName: bookName,
                            text: clean,
                            query: query,
                            exact: exact || queryKind != .word || !includeInflections
                        )
                    )
                )

                if out.count >= 300 { return out }
            }

            if bookFilter > 0 { break }
        }

        return out
    }
}

enum CommentarySearchAdapter {
    static func search(module: SearchModuleInfo, query: String, queryKind: SearchQueryKind, exact: Bool, includeInflections: Bool) -> [SearchResult] {
        if module.path.hasSuffix(".graphe") {
            return searchFallback(path: module.path, query: query, queryKind: queryKind, moduleName: module.name, exact: exact, includeInflections: includeInflections)
        }

        return GrapheRuntimeStorage.withOpenDatabase(at: module.path) { db in
            let sqls = [
                "SELECT book_number, chapter_number_from, verse_number_from, text FROM commentaries WHERE text LIKE ? LIMIT 200",
                "SELECT book_number, chapter, verse, text FROM commentary WHERE text LIKE ? LIMIT 200"
            ]
            var out: [SearchResult] = []

            for sql in sqls {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
                sqlite3_bind_text(statement, 1, "%\(query)%", -1, SQLITE_TRANSIENT)
                while sqlite3_step(statement) == SQLITE_ROW {
                    let book = Int(sqlite3_column_int(statement, 0))
                    let chapter = Int(sqlite3_column_int(statement, 1))
                    let verse = Int(sqlite3_column_int(statement, 2))
                    let raw = GrapheRuntimeStorage.columnString(statement, 3, path: module.path) ?? ""
                    guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let clean = SearchAdapterSupport.cleanText(raw)
                    guard SearchAdapterSupport.matchesText(clean, query: query, kind: queryKind, exact: exact, includeInflections: includeInflections) else { continue }
                    let bookName = myBibleBookNumbers[book] ?? "Book \(book)"
                    out.append(
                        .commentary(
                            reference: "\(bookName) \(chapter):\(verse)",
                            snippet: makeSnippet(clean, matching: query),
                            moduleName: module.name,
                            bookNumber: book,
                            chapter: chapter,
                            verse: verse,
                            modulePath: module.path,
                            score: SearchAdapterSupport.scoreCommentaryResult(
                                bookName: bookName,
                                text: clean,
                                query: query,
                                exact: exact
                            )
                        )
                    )
                }
                sqlite3_finalize(statement)
                if !out.isEmpty { break }
            }

            return out
        } ?? []
    }

    private static func searchFallback(path: String, query: String, queryKind: SearchQueryKind, moduleName: String, exact: Bool, includeInflections: Bool) -> [SearchResult] {
        guard let db = SearchAdapterSupport.openDatabase(at: path) else { return [] }
        defer { sqlite3_close(db) }

        let sqls = [
            "SELECT book_number, chapter_number_from, verse_number_from, text FROM commentaries LIMIT 2000",
            "SELECT book_number, chapter, verse, text FROM commentary LIMIT 2000"
        ]
        var out: [SearchResult] = []

        for sql in sqls {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(statement) }

            while sqlite3_step(statement) == SQLITE_ROW {
                let book = Int(sqlite3_column_int(statement, 0))
                let chapter = Int(sqlite3_column_int(statement, 1))
                let verse = Int(sqlite3_column_int(statement, 2))
                let raw = GrapheRuntimeStorage.columnString(statement, 3, path: path) ?? ""
                let clean = SearchAdapterSupport.cleanText(raw)
                guard !clean.isEmpty,
                      SearchAdapterSupport.matchesText(clean, query: query, kind: queryKind, exact: exact, includeInflections: includeInflections) else { continue }

                let bookName = myBibleBookNumbers[book] ?? "Book \(book)"
                out.append(
                    .commentary(
                        reference: "\(bookName) \(chapter):\(verse)",
                        snippet: makeSnippet(clean, matching: query),
                        moduleName: moduleName,
                        bookNumber: book,
                        chapter: chapter,
                        verse: verse,
                        modulePath: path,
                        score: SearchAdapterSupport.scoreCommentaryResult(
                            bookName: bookName,
                            text: clean,
                            query: query,
                            exact: exact
                        )
                    )
                )
                if out.count >= 200 { return out }
            }

            if !out.isEmpty { break }
        }

        return out
    }
}

enum ReferenceSearchAdapter {
    static func search(module: SearchModuleInfo, query: String, queryKind: SearchQueryKind, exact: Bool, includeInflections: Bool) -> [SearchResult] {
        if module.path.hasSuffix(".graphe") {
            return searchFallback(module: module, query: query, queryKind: queryKind, exact: exact, includeInflections: includeInflections)
        }

        return GrapheRuntimeStorage.withOpenDatabase(at: module.path) { db in
            let referenceKind: SearchResult.ReferenceKind = module.type == .encyclopedia ? .encyclopedia : .dictionary
            let sql = """
            SELECT topic, definition
            FROM dictionary
            WHERE topic LIKE ? OR definition LIKE ?
            ORDER BY CASE WHEN topic LIKE ? THEN 0 ELSE 1 END, topic
            LIMIT 150
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }

            let fuzzyPattern = "%\(query)%"
            let topicPrefixPattern = "\(query)%"
            sqlite3_bind_text(statement, 1, fuzzyPattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, fuzzyPattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, topicPrefixPattern, -1, SQLITE_TRANSIENT)

            var out: [SearchResult] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let topic = GrapheRuntimeStorage.columnString(statement, 0, path: module.path) ?? ""
                let raw = GrapheRuntimeStorage.columnString(statement, 1, path: module.path) ?? ""
                let clean = SearchAdapterSupport.cleanText(raw)
                if !SearchAdapterSupport.matchesText(topic, query: query, kind: queryKind, exact: exact, includeInflections: includeInflections),
                   !SearchAdapterSupport.matchesText(clean, query: query, kind: queryKind, exact: exact, includeInflections: includeInflections) {
                    continue
                }

                let snippetSource = clean.isEmpty ? topic : clean
                out.append(
                    .reference(
                        reference: topic,
                        snippet: makeSnippet(snippetSource, matching: query),
                        moduleName: module.name,
                        modulePath: module.path,
                        lookupQuery: topic,
                        kind: referenceKind,
                        score: SearchAdapterSupport.scoreReferenceResult(topic: topic, body: clean, query: query, exact: exact)
                    )
                )
            }
            return out
        } ?? []
    }

    private static func searchFallback(module: SearchModuleInfo, query: String, queryKind: SearchQueryKind, exact: Bool, includeInflections: Bool) -> [SearchResult] {
        guard let db = SearchAdapterSupport.openDatabase(at: module.path) else { return [] }
        defer { sqlite3_close(db) }

        let referenceKind: SearchResult.ReferenceKind = module.type == .encyclopedia ? .encyclopedia : .dictionary
        let sql = "SELECT topic, definition FROM dictionary LIMIT 4000"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var out: [SearchResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let topic = GrapheRuntimeStorage.columnString(statement, 0, path: module.path) ?? ""
            let raw = GrapheRuntimeStorage.columnString(statement, 1, path: module.path) ?? ""
            let clean = SearchAdapterSupport.cleanText(raw)
            guard SearchAdapterSupport.matchesText(topic, query: query, kind: queryKind, exact: exact, includeInflections: includeInflections) ||
                    SearchAdapterSupport.matchesText(clean, query: query, kind: queryKind, exact: exact, includeInflections: includeInflections) else { continue }

            let snippetSource = clean.isEmpty ? topic : clean
            out.append(
                .reference(
                    reference: topic,
                    snippet: makeSnippet(snippetSource, matching: query),
                    moduleName: module.name,
                    modulePath: module.path,
                    lookupQuery: topic,
                    kind: referenceKind,
                    score: SearchAdapterSupport.scoreReferenceResult(topic: topic, body: clean, query: query, exact: exact)
                )
            )
            if out.count >= 150 { return out }
        }

        return out
    }
}

enum NotesSearchAdapter {
    static func search(_ notes: [Note], query: String, queryKind: SearchQueryKind, includeInflections: Bool, from: Date?, to: Date?) -> [SearchResult] {
        notes.compactMap { note in
            if let from, note.updatedAt < from { return nil }
            if let to {
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: to) ?? to
                if note.updatedAt > endOfDay { return nil }
            }
            let inTitle = SearchAdapterSupport.matchesText(note.displayTitle, query: query, kind: queryKind, exact: false, includeInflections: includeInflections)
            let inContent = SearchAdapterSupport.matchesText(note.content, query: query, kind: queryKind, exact: false, includeInflections: includeInflections)
            guard inTitle || inContent else { return nil }
            let text = inTitle ? note.displayTitle + " " + note.content : note.content
            return SearchResult.note(
                reference: note.displayTitle,
                snippet: makeSnippet(text, matching: query),
                note: note,
                score: SearchAdapterSupport.scoreNoteResult(note: note, query: query)
            )
        }
    }
}

enum CrossReferenceSearchAdapter {
    static func search(
        module: SearchModuleInfo,
        query: String,
        queryKind: SearchQueryKind,
        testament: Testament,
        bookFilter: Int,
        exact: Bool,
        includeInflections: Bool
    ) -> [SearchResult] {
        if module.type == .crossRefNative {
            return searchNative(
                module: module,
                query: query,
                queryKind: queryKind,
                testament: testament,
                bookFilter: bookFilter,
                exact: exact,
                includeInflections: includeInflections
            )
        }

        return searchLegacy(
            module: module,
            query: query,
            queryKind: queryKind,
            testament: testament,
            bookFilter: bookFilter,
            exact: exact,
            includeInflections: includeInflections
        )
    }

    private static func searchNative(
        module: SearchModuleInfo,
        query: String,
        queryKind: SearchQueryKind,
        testament: Testament,
        bookFilter: Int,
        exact: Bool,
        includeInflections: Bool
    ) -> [SearchResult] {
        guard let targetReference = SearchAdapterSupport.parseReferenceQuery(query) else { return [] }

        return GrapheRuntimeStorage.withOpenDatabase(at: module.path) { db in
            let sql = """
            SELECT book, chapter, verse, book_to, chapter_to, verse_to_start, verse_to_end, votes
            FROM cross_references
            WHERE book_to = ? AND chapter_to = ? AND verse_to_start <= ? AND verse_to_end >= ?
            ORDER BY votes DESC, book, chapter, verse
            LIMIT 300
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int(statement, 1, Int32(targetReference.bookNumber))
            sqlite3_bind_int(statement, 2, Int32(targetReference.chapter))
            sqlite3_bind_int(statement, 3, Int32(targetReference.verse))
            sqlite3_bind_int(statement, 4, Int32(targetReference.verse))

            var out: [SearchResult] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let sourceBook = Int(sqlite3_column_int(statement, 0))
                let sourceChapter = Int(sqlite3_column_int(statement, 1))
                let sourceVerse = Int(sqlite3_column_int(statement, 2))
                let targetVerseStart = Int(sqlite3_column_int(statement, 5))
                let targetVerseEnd = Int(sqlite3_column_int(statement, 6))
                let votes = Int(sqlite3_column_int(statement, 7))

                guard SearchAdapterSupport.matchesBookAndTestament(
                    book: sourceBook,
                    testament: testament,
                    bookFilter: bookFilter
                ) else {
                    continue
                }

                let sourceBookName = myBibleBookNumbers[sourceBook] ?? "Book \(sourceBook)"
                let sourceReference = "\(sourceBookName) \(sourceChapter):\(sourceVerse)"
                let targetDisplay = SearchAdapterSupport.referenceDisplay(
                    bookNumber: targetReference.bookNumber,
                    chapter: targetReference.chapter,
                    verseStart: targetVerseStart,
                    verseEnd: targetVerseEnd
                )
                let snippet = "Cross-reference to \(targetDisplay) (\(votes) votes)"
                out.append(
                    .bible(
                        reference: sourceReference,
                        snippet: snippet,
                        moduleName: module.name,
                        bookNumber: sourceBook,
                        chapter: sourceChapter,
                        verse: sourceVerse,
                        modulePath: module.path,
                        score: 520 + min(votes * 10, 80)
                    )
                )
            }
            return out
        } ?? []
    }

    private static func searchLegacy(
        module: SearchModuleInfo,
        query: String,
        queryKind: SearchQueryKind,
        testament: Testament,
        bookFilter: Int,
        exact: Bool,
        includeInflections: Bool
    ) -> [SearchResult] {
        let targetReference = SearchAdapterSupport.parseReferenceQuery(query)

        return GrapheRuntimeStorage.withOpenDatabase(at: module.path) { db in
            let useFilteredSQL = targetReference == nil
            let sql: String
            if useFilteredSQL {
                sql = """
                SELECT book_number, chapter_number_from, verse_number_from, text
                FROM commentaries
                WHERE text LIKE ? AND book_number != 'book_number'
                ORDER BY book_number, chapter_number_from, verse_number_from
                LIMIT 400
                """
            } else {
                sql = """
                SELECT book_number, chapter_number_from, verse_number_from, text
                FROM commentaries
                WHERE book_number != 'book_number'
                ORDER BY book_number, chapter_number_from, verse_number_from
                LIMIT 5000
                """
            }

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }

            if useFilteredSQL {
                let pattern = SearchAdapterSupport.sqlCandidatePattern(for: query, kind: queryKind)
                sqlite3_bind_text(statement, 1, pattern, -1, SQLITE_TRANSIENT)
            }

            var out: [SearchResult] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let sourceBook = Int(sqlite3_column_int(statement, 0))
                let sourceChapter = Int(sqlite3_column_int(statement, 1))
                let sourceVerse = Int(sqlite3_column_int(statement, 2))
                let html = GrapheRuntimeStorage.columnString(statement, 3, path: module.path) ?? ""

                guard SearchAdapterSupport.matchesBookAndTestament(
                    book: sourceBook,
                    testament: testament,
                    bookFilter: bookFilter
                ) else {
                    continue
                }

                let groups = parseLegacyCrossRefHTML(html)
                let matchContext = matchLegacyGroups(
                    groups,
                    query: query,
                    queryKind: queryKind,
                    exact: exact,
                    includeInflections: includeInflections,
                    targetReference: targetReference
                )
                guard let matchContext else { continue }

                let sourceBookName = myBibleBookNumbers[sourceBook] ?? "Book \(sourceBook)"
                let sourceReference = "\(sourceBookName) \(sourceChapter):\(sourceVerse)"
                out.append(
                    .bible(
                        reference: sourceReference,
                        snippet: matchContext.snippet,
                        moduleName: module.name,
                        bookNumber: sourceBook,
                        chapter: sourceChapter,
                        verse: sourceVerse,
                        modulePath: module.path,
                        score: matchContext.score
                    )
                )
                if out.count >= 150 { break }
            }
            return out
        } ?? []
    }

    private static func matchLegacyGroups(
        _ groups: [CrossRefGroup],
        query: String,
        queryKind: SearchQueryKind,
        exact: Bool,
        includeInflections: Bool,
        targetReference: SearchAdapterSupport.ParsedReferenceQuery?
    ) -> (snippet: String, score: Int)? {
        for group in groups {
            for reference in group.references {
                if let targetReference,
                   reference.bookNumber == targetReference.bookNumber,
                   reference.chapter == targetReference.chapter,
                   reference.verseStart <= targetReference.verse,
                   reference.verseEnd >= targetReference.verse {
                    let label = group.keyword.map { "\($0): " } ?? ""
                    return (
                        snippet: "\(label)Cross-reference to \(reference.display)",
                        score: 560
                    )
                }

                if SearchAdapterSupport.matchesText(
                    reference.display,
                    query: query,
                    kind: queryKind,
                    exact: exact,
                    includeInflections: includeInflections
                ) {
                    let label = group.keyword.map { "\($0): " } ?? ""
                    return (
                        snippet: "\(label)\(makeSnippet(reference.display, matching: query))",
                        score: SearchAdapterSupport.scoreReferenceResult(
                            topic: reference.display,
                            body: group.keyword ?? "",
                            query: query,
                            exact: exact
                        )
                    )
                }
            }

            if let keyword = group.keyword,
               SearchAdapterSupport.matchesText(
                keyword,
                query: query,
                kind: queryKind,
                exact: exact,
                includeInflections: includeInflections
               ) {
                let references = group.references.prefix(3).map(\.display).joined(separator: ", ")
                return (
                    snippet: "\(keyword): \(references)",
                    score: SearchAdapterSupport.scoreReferenceResult(
                        topic: keyword,
                        body: references,
                        query: query,
                        exact: exact
                    )
                )
            }
        }

        return nil
    }

    private static func parseLegacyCrossRefHTML(_ html: String) -> [CrossRefGroup] {
        let parts = html.components(separatedBy: "<p/>")
        var groups: [CrossRefGroup] = []

        let linkPattern = try? NSRegularExpression(
            pattern: #"<a href='B:(\d+) (\d+):(\d+)(?:-(\d+))?'>(.*?)</a>"#
        )
        let keywordPattern = try? NSRegularExpression(pattern: #"<b>(.*?)</b>"#)

        for part in parts {
            let nsPart = part as NSString
            let fullRange = NSRange(location: 0, length: nsPart.length)

            var keyword: String?
            if let match = keywordPattern?.firstMatch(in: part, range: fullRange) {
                var foundKeyword = nsPart.substring(with: match.range(at: 1))
                if foundKeyword.hasSuffix(":") {
                    foundKeyword = String(foundKeyword.dropLast())
                }
                keyword = foundKeyword
            }

            var references: [CrossRefEntry] = []
            linkPattern?.enumerateMatches(in: part, range: fullRange) { match, _, _ in
                guard let match else { return }
                let book = Int(nsPart.substring(with: match.range(at: 1))) ?? 0
                let chapter = Int(nsPart.substring(with: match.range(at: 2))) ?? 0
                let verseStart = Int(nsPart.substring(with: match.range(at: 3))) ?? 0
                let verseEnd = match.range(at: 4).location != NSNotFound
                    ? Int(nsPart.substring(with: match.range(at: 4))) ?? verseStart
                    : verseStart
                let display = nsPart.substring(with: match.range(at: 5))
                references.append(
                    CrossRefEntry(
                        display: display,
                        bookNumber: book,
                        chapter: chapter,
                        verseStart: verseStart,
                        verseEnd: verseEnd
                    )
                )
            }

            if !references.isEmpty {
                groups.append(CrossRefGroup(keyword: keyword, references: references))
            }
        }

        return groups
    }
}

private enum SearchAdapterSupport {
    struct ParsedReferenceQuery {
        let bookNumber: Int
        let chapter: Int
        let verse: Int
    }

    static func ranges(for testament: Testament) -> [(Int, Int)] {
        switch testament {
        case .ot: return [(10, 469)]
        case .nt: return [(470, 999)]
        case .both: return [(10, 469), (470, 999)]
        }
    }

    static func scoreBibleResult(bookName: String, text: String, query: String, exact: Bool) -> Int {
        scoreTextMatch(title: bookName, body: text, query: query, exact: exact, base: 500)
    }

    static func sqlCandidatePattern(for query: String, kind: SearchQueryKind) -> String {
        switch kind {
        case .strongs:
            guard let strongsTag = normalizedStrongsTag(for: query) else {
                return "%\(query)%"
            }
            return "%\(strongsTag)%"
        case .word, .phrase:
            return "%\(query)%"
        }
    }

    static func matchesVerse(
        raw: String,
        clean: String,
        query: String,
        kind: SearchQueryKind,
        exact: Bool,
        includeInflections: Bool
    ) -> Bool {
        switch kind {
        case .strongs:
            guard let strongsTag = normalizedStrongsTag(for: query) else { return false }
            return raw.localizedCaseInsensitiveContains(strongsTag)
        case .phrase:
            return clean.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .contains(query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
        case .word:
            if includeInflections {
                return clean.localizedCaseInsensitiveContains(query)
            }
            return wholeWordMatch(in: clean, query: query)
        }
    }

    static func matchesText(
        _ text: String,
        query: String,
        kind: SearchQueryKind,
        exact: Bool,
        includeInflections: Bool
    ) -> Bool {
        switch kind {
        case .strongs:
            return false
        case .phrase:
            let normalizedText = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return normalizedText.contains(normalizedQuery)
        case .word:
            if includeInflections {
                return text.localizedCaseInsensitiveContains(query)
            }
            return wholeWordMatch(in: text, query: query)
        }
    }

    static func normalizedStrongsTag(for query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let prefix = trimmed.first, prefix == "G" || prefix == "H" else { return nil }
        let digits = trimmed.dropFirst().filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return "<S>\(digits)</S>"
    }

    static func wholeWordMatch(in text: String, query: String) -> Bool {
        let normalizedText = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !normalizedQuery.isEmpty else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: normalizedQuery)
        let pattern = "(?i)(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: (normalizedText as NSString).length)
        return regex.firstMatch(in: normalizedText, range: range) != nil
    }

    static func scoreCommentaryResult(bookName: String, text: String, query: String, exact: Bool) -> Int {
        scoreTextMatch(title: bookName, body: text, query: query, exact: exact, base: 400)
    }

    static func scoreReferenceResult(topic: String, body: String, query: String, exact: Bool) -> Int {
        scoreTextMatch(title: topic, body: body, query: query, exact: exact, base: 450)
    }

    static func scoreNoteResult(note: Note, query: String) -> Int {
        scoreTextMatch(title: note.displayTitle, body: note.content, query: query, exact: false, base: 350)
    }

    static func scoreTextMatch(
        title: String,
        body: String,
        query: String,
        exact: Bool,
        base: Int
    ) -> Int {
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedTitle = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedBody = body.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        var score = base
        if normalizedTitle == normalizedQuery {
            score += 140
        } else if normalizedTitle.hasPrefix(normalizedQuery) {
            score += 90
        } else if normalizedTitle.contains(normalizedQuery) {
            score += 55
        }

        if normalizedBody.contains(normalizedQuery) {
            score += exact ? 45 : 30
            if let range = normalizedBody.range(of: normalizedQuery) {
                let distance = normalizedBody.distance(from: normalizedBody.startIndex, to: range.lowerBound)
                score += max(0, 40 - min(distance / 12, 40))
            }
        }

        score += max(0, 30 - min(body.count / 80, 30))
        return score
    }

    static func cleanText(_ raw: String) -> String {
        var text = raw
        while let open = text.range(of: "<S>"),
              let close = text.range(of: "</S>", range: open.lowerBound..<text.endIndex) {
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return decodeHTMLEntities(StrongsParser.stripAllTags(text))
    }

    static func openDatabase(at path: String) -> OpaquePointer? {
        GrapheRuntimeStorage.openDatabase(at: path)
    }

    static func decodeHTMLEntities(_ input: String) -> String {
        var value = input
        let namedEntities: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'"
        ]
        for (entity, replacement) in namedEntities {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }

        let pattern = #"&#(x?[0-9A-Fa-f]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let nsValue = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length)).reversed()
        var result = value

        for match in matches {
            let token = nsValue.substring(with: match.range(at: 1))
            let scalarValue: UInt32?
            if token.lowercased().hasPrefix("x") {
                scalarValue = UInt32(token.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(token, radix: 10)
            }

            guard let scalarValue, let scalar = UnicodeScalar(scalarValue), let range = Range(match.range, in: result) else {
                continue
            }
            result.replaceSubrange(range, with: String(scalar))
        }

        return result
    }

    static func parseReferenceQuery(_ query: String) -> ParsedReferenceQuery? {
        let pattern = #"^\s*((?:[1-3]\s*)?[A-Za-z][A-Za-z.\s]+?)\s+(\d+):(\d+)(?:[-–](\d+))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsQuery = query as NSString
        let range = NSRange(location: 0, length: nsQuery.length)
        guard let match = regex.firstMatch(in: query, range: range) else { return nil }

        let bookName = nsQuery.substring(with: match.range(at: 1))
        guard let bookNumber = ScriptureBookCatalog.bookNumber(forName: bookName) else { return nil }
        let chapter = Int(nsQuery.substring(with: match.range(at: 2))) ?? 0
        let verse = Int(nsQuery.substring(with: match.range(at: 3))) ?? 0
        guard chapter > 0, verse > 0 else { return nil }
        return ParsedReferenceQuery(bookNumber: bookNumber, chapter: chapter, verse: verse)
    }

    static func matchesBookAndTestament(book: Int, testament: Testament, bookFilter: Int) -> Bool {
        if bookFilter > 0 {
            return book == bookFilter
        }
        return ranges(for: testament).contains { lower, upper in
            book >= lower && book <= upper
        }
    }

    static func referenceDisplay(bookNumber: Int, chapter: Int, verseStart: Int, verseEnd: Int) -> String {
        let bookName = myBibleBookNumbers[bookNumber] ?? "Book \(bookNumber)"
        if verseEnd > verseStart {
            return "\(bookName) \(chapter):\(verseStart)-\(verseEnd)"
        }
        return "\(bookName) \(chapter):\(verseStart)"
    }
}
