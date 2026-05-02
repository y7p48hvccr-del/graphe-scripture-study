import Foundation
import SQLite3

struct ChapterLoadResult {
    let verses: [MyBibleVerse]
    let rawVerseTexts: [Int: String]
}

enum ModuleContentService {
    static func bookNumber(forName name: String, in module: MyBibleModule) -> Int? {
        let nameLower = name.lowercased()
        let moduleMatch: Int? = GrapheRuntimeStorage.withOpenDatabase(at: module.filePath) { db in
            if let statement = GrapheRuntimeStorage.query(db: db, sql: "SELECT book_number, short_name, long_name FROM books") {
                var matches: [(Int, Int)] = []
                while sqlite3_step(statement) == SQLITE_ROW {
                    let bookNumber = Int(sqlite3_column_int(statement, 0))
                    let shortName = sqlite3_column_text(statement, 1).map { String(cString: $0) }?.lowercased() ?? ""
                    let longName = sqlite3_column_text(statement, 2).map { String(cString: $0) }?.lowercased() ?? ""
                    if longName == nameLower {
                        matches.append((bookNumber, 3))
                    } else if shortName == nameLower {
                        matches.append((bookNumber, 2))
                    } else if longName.hasPrefix(nameLower) || nameLower.hasPrefix(longName) {
                        matches.append((bookNumber, 1))
                    }
                }
                sqlite3_finalize(statement)
                return matches.max(by: { $0.1 < $1.1 })?.0
            }
            return nil
        } ?? nil

        return moduleMatch ?? ScriptureBookCatalog.bookNumber(forName: nameLower)
    }

    static func availableBooks(in module: MyBibleModule) -> [Int] {
        GrapheRuntimeStorage.withOpenDatabase(at: module.filePath) { db in
            var books: [Int] = []
            if let statement = GrapheRuntimeStorage.query(db: db, sql: "SELECT DISTINCT book_number FROM verses ORDER BY book_number") {
                while sqlite3_step(statement) == SQLITE_ROW {
                    books.append(Int(sqlite3_column_int(statement, 0)))
                }
                sqlite3_finalize(statement)
            }
            return books
        } ?? []
    }

    static func chapterCount(module: MyBibleModule, bookNumber: Int) -> Int {
        let count = GrapheRuntimeStorage.withOpenDatabase(at: module.filePath) { db in
            var count = 1
            if let statement = GrapheRuntimeStorage.query(db: db, sql: "SELECT MAX(chapter) FROM verses WHERE book_number = ?") {
                sqlite3_bind_int(statement, 1, Int32(bookNumber))
                if sqlite3_step(statement) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(statement, 0))
                }
                sqlite3_finalize(statement)
            }
            return count
        } ?? 1
        return max(count, 1)
    }

    static func loadChapterVerses(module: MyBibleModule, bookNumber: Int, chapter: Int) async -> [MyBibleVerse] {
        GrapheRuntimeStorage.withOpenDatabase(at: module.filePath) { db in
            let sql = "SELECT book_number, chapter, verse, text FROM verses WHERE book_number = ? AND chapter = ? ORDER BY verse"
            guard let statement = GrapheRuntimeStorage.query(db: db, sql: sql) else { return [] }
            sqlite3_bind_int(statement, 1, Int32(bookNumber))
            sqlite3_bind_int(statement, 2, Int32(chapter))

            var results: [MyBibleVerse] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let raw = GrapheRuntimeStorage.columnString(statement, 3, path: module.filePath),
                      !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    continue
                }
                results.append(
                    MyBibleVerse(
                        book: Int(sqlite3_column_int(statement, 0)),
                        chapter: Int(sqlite3_column_int(statement, 1)),
                        verse: Int(sqlite3_column_int(statement, 2)),
                        text: raw
                    )
                )
            }
            sqlite3_finalize(statement)
            return results
        } ?? []
    }

    static func loadChapter(module: MyBibleModule, bookNumber: Int, chapter: Int) async -> ChapterLoadResult {
        GrapheRuntimeStorage.withOpenDatabase(at: module.filePath) { db in
            let sql = "SELECT book_number, chapter, verse, text FROM verses WHERE book_number = ? AND chapter = ? ORDER BY verse"
            guard let statement = GrapheRuntimeStorage.query(db: db, sql: sql) else {
                return ChapterLoadResult(verses: [], rawVerseTexts: [:])
            }
            sqlite3_bind_int(statement, 1, Int32(bookNumber))
            sqlite3_bind_int(statement, 2, Int32(chapter))

            var verses: [MyBibleVerse] = []
            var rawVerseTexts: [Int: String] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                let raw = GrapheRuntimeStorage.columnString(statement, 3, path: module.filePath) ?? ""
                guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                let verseNumber = Int(sqlite3_column_int(statement, 2))
                rawVerseTexts[verseNumber] = raw
                let (cleanText, notes) = stripStrongsAndTagsCapturingNotes(raw)
                verses.append(
                    MyBibleVerse(
                        book: Int(sqlite3_column_int(statement, 0)),
                        chapter: Int(sqlite3_column_int(statement, 1)),
                        verse: verseNumber,
                        text: cleanText,
                        glosses: notes
                    )
                )
            }
            sqlite3_finalize(statement)
            return ChapterLoadResult(verses: verses, rawVerseTexts: rawVerseTexts)
        } ?? ChapterLoadResult(verses: [], rawVerseTexts: [:])
    }

    static func loadCommentaryEntries(module: MyBibleModule, bookNumber: Int, chapter: Int) async -> [CommentaryEntry] {
        GrapheRuntimeStorage.withOpenDatabase(at: module.filePath) { db in
            let sql = """
                SELECT book_number, chapter_number_from, verse_number_from,
                       chapter_number_to, verse_number_to, text
                FROM commentaries
                WHERE book_number = ? AND chapter_number_from = ?
                ORDER BY verse_number_from
                """
            guard let statement = GrapheRuntimeStorage.query(db: db, sql: sql) else { return [] }
            sqlite3_bind_int(statement, 1, Int32(bookNumber))
            sqlite3_bind_int(statement, 2, Int32(chapter))

            var results: [CommentaryEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let rawText = GrapheRuntimeStorage.columnString(statement, 5, path: module.filePath) ?? ""
                let verseFrom = Int(sqlite3_column_int(statement, 2))
                var verseTo = Int(sqlite3_column_int(statement, 4))
                if verseTo == 0 { verseTo = verseFrom == 0 ? 999 : verseFrom }
                results.append(
                    CommentaryEntry(
                        bookNumber: Int(sqlite3_column_int(statement, 0)),
                        chapterFrom: Int(sqlite3_column_int(statement, 1)),
                        verseFrom: verseFrom,
                        chapterTo: Int(sqlite3_column_int(statement, 3)),
                        verseTo: verseTo,
                        text: stripTags(rawText)
                    )
                )
            }
            sqlite3_finalize(statement)
            return results
        } ?? []
    }

    static func searchDictionaryEntries(module: MyBibleModule, searchTerm: String) async -> [DictionaryEntry] {
        GrapheRuntimeStorage.withOpenDatabase(at: module.filePath) { db in
            let sql = searchTerm.isEmpty
                ? "SELECT topic, definition FROM dictionary ORDER BY topic LIMIT 100"
                : "SELECT topic, definition FROM dictionary WHERE topic LIKE ? ORDER BY topic LIMIT 100"
            guard let statement = GrapheRuntimeStorage.query(db: db, sql: sql) else { return [] }
            if !searchTerm.isEmpty {
                let pattern = "%\(searchTerm)%"
                sqlite3_bind_text(statement, 1, (pattern as NSString).utf8String, -1, nil)
            }

            var results: [DictionaryEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let topic = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
                let definition = GrapheRuntimeStorage.columnString(statement, 1, path: module.filePath) ?? ""
                results.append(DictionaryEntry(topic: topic, definition: definition))
            }
            sqlite3_finalize(statement)
            return results
        } ?? []
    }

    static func lookupWord(word: String, in module: MyBibleModule, preservingMarkup: Bool = false) async -> (topic: String, definition: String)? {
        let candidates = [word, word.capitalized, word.lowercased(), word.uppercased()]

        return GrapheRuntimeStorage.withOpenDatabase(at: module.filePath) { db in
            for candidate in candidates {
                let sql = "SELECT topic, definition FROM dictionary WHERE topic = ? LIMIT 1"
                if let statement = GrapheRuntimeStorage.query(db: db, sql: sql) {
                    sqlite3_bind_text(statement, 1, (candidate as NSString).utf8String, -1, nil)
                    if sqlite3_step(statement) == SQLITE_ROW,
                       let topicPointer = sqlite3_column_text(statement, 0) {
                        let topic = String(cString: topicPointer)
                        let raw = GrapheRuntimeStorage.columnString(statement, 1, path: module.filePath) ?? ""
                        sqlite3_finalize(statement)
                        let clean = raw
                            .replacingOccurrences(of: "&amp;", with: "&")
                            .replacingOccurrences(of: "&lt;", with: "<")
                            .replacingOccurrences(of: "&gt;", with: ">")
                            .replacingOccurrences(of: "&nbsp;", with: " ")
                            .replacingOccurrences(of: "&#160;", with: " ")
                        let definition: String
                        if preservingMarkup {
                            definition = clean.trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            let blockFormatted = clean
                                .replacingOccurrences(of: "<p/>", with: "\n\n")
                                .replacingOccurrences(of: "<p />", with: "\n\n")
                                .replacingOccurrences(of: "<br/>", with: "\n")
                                .replacingOccurrences(of: "<br />", with: "\n")
                                .replacingOccurrences(of: "<br>", with: "\n")
                            let stripped: String
                            if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
                                stripped = regex.stringByReplacingMatches(
                                    in: blockFormatted,
                                    range: NSRange(blockFormatted.startIndex..., in: blockFormatted),
                                    withTemplate: ""
                                )
                            } else {
                                stripped = blockFormatted
                            }
                            definition = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        return (topic: topic, definition: definition)
                    }
                    sqlite3_finalize(statement)
                }
            }
            return nil
        } ?? nil
    }

    static func fetchVerses(module: MyBibleModule, bookNumber: Int, chapter: Int) async -> [MyBibleVerse] {
        await Task.detached(priority: .userInitiated) {
            await loadChapter(module: module, bookNumber: bookNumber, chapter: chapter).verses
        }.value
    }

    static func fetchCommentaryEntries(module: MyBibleModule, bookNumber: Int, chapter: Int) async -> [CommentaryEntry] {
        await Task.detached(priority: .userInitiated) {
            await loadCommentaryEntries(module: module, bookNumber: bookNumber, chapter: chapter)
        }.value
    }

    static func lookupCrossReferences(
        module: MyBibleModule,
        book: Int,
        chapter: Int,
        verse: Int
    ) async -> [CrossRefGroup] {
        if module.type == .crossRefNative {
            return await lookupNativeCrossReferences(module: module, book: book, chapter: chapter, verse: verse)
        }

        return await Task.detached(priority: .userInitiated) {
            GrapheRuntimeStorage.withOpenDatabase(at: module.filePath) { db in
                var groups: [CrossRefGroup] = []
                if let statement = GrapheRuntimeStorage.query(
                    db: db,
                    sql: "SELECT text FROM commentaries WHERE book_number=? AND chapter_number_from=? AND verse_number_from=? AND book_number != 'book_number' LIMIT 1"
                ) {
                    sqlite3_bind_int(statement, 1, Int32(book))
                    sqlite3_bind_int(statement, 2, Int32(chapter))
                    sqlite3_bind_int(statement, 3, Int32(verse))
                    if sqlite3_step(statement) == SQLITE_ROW {
                        let html = GrapheRuntimeStorage.columnString(statement, 0, path: module.filePath) ?? ""
                        if !html.isEmpty {
                            groups = parseCrossRefHTML(html)
                        }
                    }
                    sqlite3_finalize(statement)
                }
                return groups
            } ?? []
        }.value
    }

    static func fetchDevotionalEntry(module: MyBibleModule, day: Int) async -> DevotionalEntry? {
        await Task.detached(priority: .userInitiated) { () -> DevotionalEntry? in
            GrapheRuntimeStorage.withOpenDatabase(at: module.filePath) { db in
                if let statement = GrapheRuntimeStorage.query(db: db, sql: "SELECT devotion FROM devotions WHERE day=? LIMIT 1") {
                    sqlite3_bind_int(statement, 1, Int32(day))
                    if sqlite3_step(statement) == SQLITE_ROW {
                        let html = GrapheRuntimeStorage.columnString(statement, 0, path: module.filePath) ?? ""
                        sqlite3_finalize(statement)
                        if !html.isEmpty {
                            let title = extractDevotionalTitle(html)
                            return DevotionalEntry(day: day, title: title, html: html)
                        }
                    }
                    sqlite3_finalize(statement)
                }
                return nil
            } ?? nil
        }.value
    }

    static func devotionalDayCount(module: MyBibleModule) async -> Int {
        await Task.detached(priority: .userInitiated) {
            GrapheRuntimeStorage.withOpenDatabase(at: module.filePath) { db in
                if let statement = GrapheRuntimeStorage.query(db: db, sql: "SELECT MAX(day) FROM devotions") {
                    if sqlite3_step(statement) == SQLITE_ROW {
                        let count = Int(sqlite3_column_int(statement, 0))
                        sqlite3_finalize(statement)
                        return count
                    }
                    sqlite3_finalize(statement)
                }
                return 365
            } ?? 365
        }.value
    }

    static func loadPlanEntry(day: Int, from module: MyBibleModule) async -> PlanEntry? {
        await Task.detached(priority: .userInitiated) {
            GrapheRuntimeStorage.withOpenDatabase(at: module.filePath) { db in
                let sql = "SELECT book_number, start_chapter, start_verse, end_chapter, end_verse FROM reading_plan WHERE day=? AND book_number != 'day' LIMIT 1"
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
                sqlite3_bind_int(statement, 1, Int32(day))
                guard sqlite3_step(statement) == SQLITE_ROW else {
                    sqlite3_finalize(statement)
                    return nil
                }

                let bookNumber = Int(sqlite3_column_int(statement, 0))
                let startChapter = Int(sqlite3_column_int(statement, 1))
                let startVerse = sqlite3_column_type(statement, 2) != SQLITE_NULL ? Int(sqlite3_column_int(statement, 2)) : nil
                let endChapter = sqlite3_column_type(statement, 3) != SQLITE_NULL ? Int(sqlite3_column_int(statement, 3)) : nil
                let endVerse = sqlite3_column_type(statement, 4) != SQLITE_NULL ? Int(sqlite3_column_int(statement, 4)) : nil
                sqlite3_finalize(statement)

                let bookName = myBibleBookNumbers[bookNumber] ?? "\(bookNumber)"
                var displayText = "\(bookName) \(startChapter)"
                if let startVerse {
                    displayText += ":\(startVerse)"
                }
                if let endChapter, let endVerse {
                    displayText += " – \(bookName) \(endChapter):\(endVerse)"
                }

                return PlanEntry(
                    bookNumber: bookNumber,
                    startChapter: startChapter,
                    startVerse: startVerse,
                    endChapter: endChapter,
                    endVerse: endVerse,
                    displayText: displayText
                )
            } ?? nil
        }.value
    }

    private static func stripTags(_ input: String) -> String {
        var result = input.replacingOccurrences(of: "<pb/>", with: "\n")
        while let start = result.range(of: "<"),
              let end = result.range(of: ">", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound...end.lowerBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripStrongsAndTagsCapturingNotes(_ raw: String) -> (text: String, notes: [String]) {
        var text = raw
        var notes: [String] = []
        while let open = text.range(of: "<n>"),
              let close = text.range(of: "</n>", range: open.lowerBound..<text.endIndex) {
            let inner = String(text[open.upperBound..<close.lowerBound])
            let clean = StrongsParser.stripAllTags(inner)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                notes.append(clean)
            }
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        while let open = text.range(of: "<S>"),
              let close = text.range(of: "</S>", range: open.lowerBound..<text.endIndex) {
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        for prefix in ["<WG", "<WH"] {
            while let range = text.range(of: prefix),
                  let end = text.range(of: ">", range: range.upperBound..<text.endIndex) {
                text.removeSubrange(range.lowerBound...end.lowerBound)
            }
        }
        let cleaned = StrongsParser.stripAllTags(text)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, notes)
    }

    private static func lookupNativeCrossReferences(
        module: MyBibleModule,
        book: Int,
        chapter: Int,
        verse: Int
    ) async -> [CrossRefGroup] {
        await Task.detached(priority: .userInitiated) {
            GrapheRuntimeStorage.withOpenDatabase(at: module.filePath) { db in
                var high: [CrossRefEntry] = []
                var medium: [CrossRefEntry] = []
                var low: [CrossRefEntry] = []

                if let statement = GrapheRuntimeStorage.query(
                    db: db,
                    sql: "SELECT book_to, chapter_to, verse_to_start, verse_to_end, votes FROM cross_references WHERE book=? AND chapter=? AND verse=? ORDER BY votes DESC"
                ) {
                    sqlite3_bind_int(statement, 1, Int32(book))
                    sqlite3_bind_int(statement, 2, Int32(chapter))
                    sqlite3_bind_int(statement, 3, Int32(verse))

                    while sqlite3_step(statement) == SQLITE_ROW {
                        let bookTo = Int(sqlite3_column_int(statement, 0))
                        let chapterTo = Int(sqlite3_column_int(statement, 1))
                        let verseStart = Int(sqlite3_column_int(statement, 2))
                        let verseEnd = Int(sqlite3_column_int(statement, 3))
                        let votes = Int(sqlite3_column_int(statement, 4))

                        let bookName = myBibleBookNumbers[bookTo] ?? "\(bookTo)"
                        let display = verseEnd > 0 && verseEnd != verseStart
                            ? "\(bookName) \(chapterTo):\(verseStart)-\(verseEnd)"
                            : "\(bookName) \(chapterTo):\(verseStart)"
                        let entry = CrossRefEntry(
                            display: display,
                            bookNumber: bookTo,
                            chapter: chapterTo,
                            verseStart: verseStart,
                            verseEnd: verseEnd > 0 ? verseEnd : verseStart
                        )

                        if votes >= 3 {
                            high.append(entry)
                        } else if votes >= 1 {
                            medium.append(entry)
                        } else {
                            low.append(entry)
                        }
                    }
                    sqlite3_finalize(statement)
                }

                var groups: [CrossRefGroup] = []
                if !high.isEmpty { groups.append(CrossRefGroup(keyword: "Primary", references: high)) }
                if !medium.isEmpty { groups.append(CrossRefGroup(keyword: "Secondary", references: medium)) }
                if !low.isEmpty { groups.append(CrossRefGroup(keyword: "Related", references: low)) }
                return groups
            } ?? []
        }.value
    }

    private static func parseCrossRefHTML(_ html: String) -> [CrossRefGroup] {
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

    private static func extractDevotionalTitle(_ html: String) -> String {
        let parts = html.components(separatedBy: "<p")
        let first = parts.first ?? html
        let clean = first.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return clean
            .replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
            .replacingOccurrences(of: "&rdquo;", with: "\u{201D}")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
