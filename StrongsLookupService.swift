import Foundation
import SQLite3

enum StrongsLookupService {
    static func lookup(
        module: MyBibleModule,
        number: String,
        isOldTestament: Bool = false
    ) async -> StrongsEntry? {
        GrapheRuntimeStorage.withOpenDatabase(at: module.filePath) { db in
            let keys = strongsLookupKeys(for: number, isOldTestament: isOldTestament)
            var foundRow: (String, String, String, String, String, String, String, String)?

            for key in keys {
                let sql = "SELECT topic, lexeme, transliteration, pronunciation, short_definition, definition, COALESCE(expanded_definition, ''), COALESCE(source_flags, 'strong') FROM dictionary WHERE topic = ? LIMIT 1"
                if let statement = GrapheRuntimeStorage.query(db: db, sql: sql) {
                    sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)
                    if sqlite3_step(statement) == SQLITE_ROW {
                        let topic = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? key
                        let lexeme = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
                        let transliteration = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
                        let pronunciation = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                        let shortDefinition = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
                        let rawDefinition = GrapheRuntimeStorage.columnString(statement, 5, path: module.filePath) ?? ""
                        let expandedDefinition = GrapheRuntimeStorage.columnString(statement, 6, path: module.filePath) ?? ""
                        let sourceFlags = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? "strong"
                        sqlite3_finalize(statement)
                        foundRow = (
                            topic,
                            lexeme,
                            transliteration,
                            pronunciation,
                            shortDefinition,
                            rawDefinition,
                            expandedDefinition,
                            sourceFlags
                        )
                        break
                    }
                    sqlite3_finalize(statement)
                }
            }

            guard let (topic, lexeme, transliteration, pronunciation, shortDefinition, rawDefinition, expandedDefinition, sourceFlags) = foundRow else {
                return nil
            }

            let body = parseDefinitionBody(rawDefinition)
            var derivation = extractLabel(body, label: "Derivation")
            var kjv = extractLabel(body, label: "KJV")
            let strongsDefinition = extractLabel(body, label: "Strong's")

            if derivation.isEmpty && kjv.isEmpty && strongsDefinition.isEmpty {
                let parts = body.components(separatedBy: ": - ")
                derivation = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
                kjv = parts.count > 1
                    ? parts[1...].joined(separator: ": - ").trimmingCharacters(in: .whitespaces)
                    : ""
            }

            let references = extractReferencesSection(rawDefinition)
            let cognates = lookupCognates(topic: topic, db: db)

            return StrongsEntry(
                topic: topic,
                lexeme: lexeme,
                transliteration: transliteration,
                pronunciation: pronunciation,
                shortDefinition: shortDefinition,
                derivation: derivation,
                strongsDefinition: strongsDefinition,
                kjv: kjv,
                references: references,
                cognates: cognates,
                expandedDefinition: expandedDefinition,
                sourceFlags: sourceFlags,
                rawDefinition: rawDefinition
            )
        } ?? nil
    }

    static func strongsLookupKeys(for rawNumber: String, isOldTestament: Bool) -> [String] {
        let trimmed = rawNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let uppercased = trimmed.uppercased()
        let firstCharacter = uppercased.first
        let hasPrefix = firstCharacter == "G" || firstCharacter == "H"
        let prefix = hasPrefix ? String(firstCharacter!) : nil
        let body = hasPrefix ? String(uppercased.dropFirst()) : uppercased
        let digits = String(body.prefix { $0.isNumber })
        let suffix = String(body.dropFirst(digits.count))

        func canonicalDigits(_ digits: String) -> String {
            let trimmedDigits = String(digits.drop { $0 == "0" })
            return trimmedDigits.isEmpty ? "0" : trimmedDigits
        }

        var keys: [String] = []
        func appendUnique(_ key: String?) {
            guard let key, !key.isEmpty, !keys.contains(key) else { return }
            keys.append(key)
        }

        if hasPrefix {
            appendUnique(uppercased)
            if !digits.isEmpty {
                appendUnique("\(prefix!)\(canonicalDigits(digits))\(suffix)")
                appendUnique("\(digits)\(suffix)")
                appendUnique("\(canonicalDigits(digits))\(suffix)")
            }
        } else {
            appendUnique(uppercased)
            guard !digits.isEmpty else { return keys }
            let canonical = "\(canonicalDigits(digits))\(suffix)"
            let preferredPrefix = isOldTestament ? "H" : "G"
            let fallbackPrefix = isOldTestament ? "G" : "H"
            appendUnique("\(preferredPrefix)\(canonical)")
            appendUnique("\(fallbackPrefix)\(canonical)")
            appendUnique(canonical)
            appendUnique("\(preferredPrefix)\(digits)\(suffix)")
            appendUnique("\(fallbackPrefix)\(digits)\(suffix)")
        }

        return keys
    }

    static func parseDefinitionBody(_ html: String) -> String {
        var text = html

        if text.contains("<hr>") {
            let sections = text.components(separatedBy: "<hr>")
            if sections.count > 2 {
                text = sections[2...].joined(separator: "\n")
            } else if sections.count == 2 {
                text = sections[1]
            }
        } else {
            if let range = text.range(of: "<p/>") {
                text = String(text[range.upperBound...])
            } else if let range = text.range(of: "<p>") {
                text = String(text[range.upperBound...])
            }
        }

        text = text.replacingOccurrences(of: "<br />", with: "\n")
        text = text.replacingOccurrences(of: "<br/>", with: "\n")

        while let open = text.range(of: "<a "),
              let close = text.range(of: "</a>", range: open.lowerBound..<text.endIndex),
              let tagEnd = text.range(of: ">", range: open.upperBound..<close.lowerBound) {
            let inner = String(text[tagEnd.upperBound..<close.lowerBound])
            text.replaceSubrange(open.lowerBound..<close.upperBound, with: inner)
        }

        let entities: [(String, String)] = [
            ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
            ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}"),
            ("&amp;", "&"), ("&lt;", "<"),
            ("&gt;", ">"), ("&nbsp;", " "),
            ("&mdash;", "\u{2014}"), ("&ndash;", "\u{2013}"),
            ("&#x200E;", ""),
        ]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }

        return StrongsParser.stripAllTags(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractLabel(_ body: String, label: String) -> String {
        let search = label + ": "
        guard let start = body.range(of: search) else { return "" }
        let contentStart = start.upperBound
        let knownLabels = ["Derivation: ", "Strong's: ", "KJV: ", "Usage: ", "See: "]
        var contentEnd = body.endIndex
        for next in knownLabels where next != search {
            if let range = body.range(of: next, range: contentStart..<body.endIndex), range.lowerBound < contentEnd {
                contentEnd = range.lowerBound
            }
        }
        return String(body[contentStart..<contentEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractReferencesSection(_ html: String) -> String {
        let sections = html.components(separatedBy: "<hr>")
        guard sections.count >= 2 else { return "" }
        var text = sections[1]

        text = text.replacingOccurrences(of: "<br />", with: " ")
        text = text.replacingOccurrences(of: "<br/>", with: " ")

        while let open = text.range(of: "<a "),
              let close = text.range(of: "</a>", range: open.lowerBound..<text.endIndex),
              let tagEnd = text.range(of: ">", range: open.upperBound..<close.lowerBound) {
            let inner = String(text[tagEnd.upperBound..<close.lowerBound])
            text.replaceSubrange(open.lowerBound..<close.upperBound, with: inner)
        }

        text = StrongsParser.stripAllTags(text)
        text = text.replacingOccurrences(of: "&#x200E;", with: "")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func lookupCognates(topic: String, db: OpaquePointer?) -> [String] {
        let sql = """
            SELECT strong_number FROM cognate_strong_numbers
            WHERE group_id = (SELECT group_id FROM cognate_strong_numbers WHERE strong_number = ?)
            AND strong_number != ?
            """

        var cognates: [String] = []
        if let statement = GrapheRuntimeStorage.query(db: db, sql: sql) {
            sqlite3_bind_text(statement, 1, (topic as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (topic as NSString).utf8String, -1, nil)
            while sqlite3_step(statement) == SQLITE_ROW {
                if let cognate = sqlite3_column_text(statement, 0).map({ String(cString: $0) }) {
                    cognates.append(cognate)
                }
            }
            sqlite3_finalize(statement)
        }
        return cognates
    }
}
