import Foundation
import SQLite3

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
                    guard SearchAdapterSupport.matchesVerse(raw: raw, clean: clean, query: query, kind: queryKind, exact: exact, includeInflections: includeInflections) else { continue }
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
                      SearchAdapterSupport.matchesVerse(raw: raw, clean: clean, query: query, kind: queryKind, exact: exact, includeInflections: includeInflections) else { continue }

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

private enum SearchAdapterSupport {
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
            guard let strongsTag = normalizedStrongsTag(for: query) else { return "%\(query)%" }
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
            return matchesText(clean, query: query, kind: .phrase, exact: exact, includeInflections: includeInflections)
        case .word:
            return matchesText(clean, query: query, kind: .word, exact: exact, includeInflections: includeInflections)
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
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        return db
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
}
