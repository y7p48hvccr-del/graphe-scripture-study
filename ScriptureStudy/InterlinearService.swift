//
//  InterlinearService.swift
//  ScriptureStudy
//
//  Scans the modules folder for interlinear Bible modules and parses
//  their word-by-word verse data for display in InterlinearView.
//

import Foundation
import SQLite3

// MARK: - Data models

struct InterlinearToken: Identifiable {
    let id            = UUID()
    let english:      String   // English word(s) — may be empty
    let original:     String   // Greek or Hebrew word
    let strongsNum:   String   // e.g. "G1063" or "H7225"
    let morphology:   String   // e.g. "CONJ", "V-AAI-3S" (NT only)
}

struct InterlinearVerse: Identifiable {
    let id       = UUID()
    let verse:   Int
    let tokens:  [InterlinearToken]
}

struct InterlinearModule: Identifiable, Hashable {
    let id:          String   // file path
    let name:        String
    let filePath:    String
    let isRTL:       Bool     // true for Hebrew
    let strongsPrefix: String // "G" or "H"
}

// MARK: - Service

@MainActor
class InterlinearService: ObservableObject {

    @Published var modules:     [InterlinearModule] = []
    @Published var selectedOT:  InterlinearModule?  = nil
    @Published var selectedNT:  InterlinearModule?  = nil
    @Published var isLoaded:    Bool                = false

    func loadIfNeeded() {
        guard !isLoaded else { return }
        guard let folder = UserDefaults.standard.string(forKey: "modulesFolder"),
              !folder.isEmpty else { return }
        scan(in: URL(fileURLWithPath: folder))
    }

    func fetchVerses(module: InterlinearModule, bookNumber: Int, chapter: Int) async -> [InterlinearVerse] {
        let path   = module.filePath
        let isRTL  = module.isRTL
        let prefix = module.strongsPrefix
        return await Task.detached(priority: .userInitiated) {
            InterlinearService.readVerses(dbPath: path, book: bookNumber,
                                           chapter: chapter, isRTL: isRTL, prefix: prefix)
        }.value
    }

    // MARK: - Scanning

    private func scan(in dir: URL) {
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(at: dir,
                                                   includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles]) else { return }
            // Collect URLs synchronously before entering async context
            let allURLs = enumerator.compactMap { $0 as? URL }
            let sqliteURLs = allURLs.filter {
                ["sqlite3","sqlite","db"].contains($0.pathExtension.lowercased())
            }
            var found: [InterlinearModule] = []
            for url in sqliteURLs {
                if let m = InterlinearService.inspectModule(at: url.path) { found.append(m) }
            }
            await MainActor.run { [found] in
                self.modules = found
                self.selectedOT = found.first(where: { $0.isRTL })
                self.selectedNT = found.first(where: { !$0.isRTL })
                self.isLoaded   = true
                print("[InterlinearService] Found \(found.count) interlinear modules")
            }
        }
    }

    private nonisolated static func inspectModule(at path: String) -> InterlinearModule? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        // Must have verses table
        var hasVerses = false
        if let stmt = prepare(db, "SELECT name FROM sqlite_master WHERE type='table' AND name='verses'") {
            hasVerses = sqlite3_step(stmt) == SQLITE_ROW
            sqlite3_finalize(stmt)
        }
        guard hasVerses else { return nil }

        // Read info
        var info: [String: String] = [:]
        if let stmt = prepare(db, "SELECT name, value FROM info") {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let k = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let v = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                info[k] = v
            }
            sqlite3_finalize(stmt)
        }

        // Must have strong_numbers=true AND hyperlink_languages (multi-language = interlinear)
        guard info["strong_numbers"] == "true",
              let hyperlink = info["hyperlink_languages"],
              hyperlink.contains("/") else { return nil }

        // Must NOT be a lexicon (is_strong = true means it's a dictionary not a Bible)
        if info["is_strong"] == "true" { return nil }

        let isRTL    = info["right_to_left"] == "true"
        let prefix   = isRTL ? "H" : "G"
        let name     = info["description"] ?? URL(fileURLWithPath: path).lastPathComponent

        return InterlinearModule(
            id:            path,
            name:          name,
            filePath:      path,
            isRTL:         isRTL,
            strongsPrefix: prefix
        )
    }

    // MARK: - Verse reading

    private nonisolated static func readVerses(dbPath: String, book: Int, chapter: Int,
                                    isRTL: Bool, prefix: String) -> [InterlinearVerse] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        guard let stmt = prepare(db, "SELECT verse, text FROM verses WHERE book_number=? AND chapter=? ORDER BY verse") else { return [] }
        sqlite3_bind_int(stmt, 1, Int32(book))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        defer { sqlite3_finalize(stmt) }

        var result: [InterlinearVerse] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let verseNum = Int(sqlite3_column_int(stmt, 0))
            let text     = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let tokens   = isRTL ? parseOT(text, prefix: prefix) : parseNT(text, prefix: prefix)
            result.append(InterlinearVerse(verse: verseNum, tokens: tokens))
        }
        return result
    }

    // MARK: - NT parser (iESVTH format)
    // English_words <n>Greek</n><S>number</S><m>morphology</m>

    private nonisolated static func parseNT(_ text: String, prefix: String) -> [InterlinearToken] {
        var tokens: [InterlinearToken] = []
        // Regex: optional english before <n>, greek inside <n>, S number, optional m morph
        let pattern = try! NSRegularExpression(
            pattern: #"([^<]*?)<n>([^<]*)</n><S>(\d+)</S>(?:<m>([^<]*)</m>)?"#)
        let ns = text as NSString
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            func sub(_ i: Int) -> String {
                m.range(at: i).location != NSNotFound
                    ? ns.substring(with: m.range(at: i)).trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
            }
            let eng   = sub(1).trimmingCharacters(in: CharacterSet(charactersIn: "\u{201C}\u{201D}\""))
            let greek = sub(2)
            let snum  = prefix + sub(3)
            let morph = sub(4)
            guard !greek.isEmpty else { continue }
            tokens.append(InterlinearToken(english: eng, original: greek,
                                            strongsNum: snum, morphology: morph))
        }
        // Capture any trailing English text after last token
        return tokens
    }

    // MARK: - OT parser (IHOT format)
    // Hebrew_word <S>number</S>English_words

    private nonisolated static func parseOT(_ text: String, prefix: String) -> [InterlinearToken] {
        var tokens: [InterlinearToken] = []
        let pattern = try! NSRegularExpression(
            pattern: #"(\S+)\s+<S>(\d+)</S>((?:(?!\S+\s+<S>).)*)"#)
        let ns = text as NSString
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            func sub(_ i: Int) -> String {
                m.range(at: i).location != NSNotFound
                    ? ns.substring(with: m.range(at: i)).trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
            }
            let hebrew = sub(1)
            let snum   = prefix + sub(2)
            let eng    = sub(3)
            guard !hebrew.isEmpty else { continue }
            tokens.append(InterlinearToken(english: eng, original: hebrew,
                                            strongsNum: snum, morphology: ""))
        }
        return tokens
    }

    // MARK: - SQLite helper

    private nonisolated static func prepare(_ db: OpaquePointer?, _ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }
}
