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
    let language:    String
    let hyperlinkLanguages: String
    let isRTL:       Bool     // true for Hebrew
    let strongsPrefix: String // "G" or "H"

    var fileStem: String {
        URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
    }

    func supportsLanguage(_ code: String) -> Bool {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != "all" else { return true }
        if language == normalized { return true }
        let parts = hyperlinkLanguages
            .lowercased()
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return parts.contains(normalized)
    }
}

// MARK: - Service

@MainActor
class InterlinearService: ObservableObject {

    // STARTUP DIAGNOSTIC — 2026-04-21
    init() {
        print("[STARTUP] InterlinearService.init()")
    }

    @Published var modules:     [InterlinearModule] = []
    @Published var selectedOT:  InterlinearModule?  = nil
    @Published var selectedNT:  InterlinearModule?  = nil
    @Published var isLoaded:    Bool                = false

    // 2026-04-21: concurrent-load guard. `isLoaded` only flips inside the
    // detached Task's completion block, so without this flag every caller
    // arriving before the first scan finishes races past the guard and
    // kicks off its own scan. @MainActor isolation makes a plain Bool safe.
    private var isLoading: Bool = false

    func loadIfNeeded() {
        guard !AppRuntimeContext.isRunningTests else { return }
        print("[STARTUP] InterlinearService.loadIfNeeded() isLoaded=\(isLoaded) isLoading=\(isLoading)")
        guard !isLoaded, !isLoading else { return }
        print("[InterlinearService] loadIfNeeded called")
        guard let folder = ModulesFolderBookmark.resolve() else {
            print("[InterlinearService] bookmark resolve failed, trying plain path")
            guard let path = UserDefaults.standard.string(forKey: "modulesFolder"),
                  !path.isEmpty else {
                print("[InterlinearService] no modules folder set")
                return
            }
            isLoading = true
            scan(in: URL(fileURLWithPath: path))
            return
        }
        print("[InterlinearService] resolved folder: \(folder.path)")
        guard folder.startAccessingSecurityScopedResource() else {
            print("[InterlinearService] failed to access security scope")
            return
        }
        isLoading = true
        scan(in: folder)
        folder.stopAccessingSecurityScopedResource()
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
                ["sqlite3","sqlite","db","graphe"].contains($0.pathExtension.lowercased())
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
                self.isLoading  = false
                print("[InterlinearService] Found \(found.count) interlinear modules")
            }
        }
    }

    private nonisolated static func inspectModule(at path: String) -> InterlinearModule? {
        GrapheRuntimeStorage.withOpenDatabase(at: path) { db in
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
                    let k = GrapheRuntimeStorage.columnString(stmt, 0, path: path) ?? ""
                    let v = GrapheRuntimeStorage.columnString(stmt, 1, path: path) ?? ""
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

            let isRTL = info["right_to_left"] == "true"
            let prefix = isRTL ? "H" : "G"
            let name = info["description"] ?? URL(fileURLWithPath: path).lastPathComponent
            let language = info["language"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "en"
            let hyperlinkLanguages = info["hyperlink_languages"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            return InterlinearModule(
                id: path,
                name: name,
                filePath: path,
                language: language,
                hyperlinkLanguages: hyperlinkLanguages,
                isRTL: isRTL,
                strongsPrefix: prefix
            )
        } ?? nil
    }

    // MARK: - Verse reading

    private nonisolated static func readVerses(dbPath: String, book: Int, chapter: Int,
                                    isRTL: Bool, prefix: String) -> [InterlinearVerse] {
        GrapheRuntimeStorage.withOpenDatabase(at: dbPath) { db in
            guard let stmt = prepare(db, "SELECT verse, text FROM verses WHERE book_number=? AND chapter=? ORDER BY verse") else { return [] }
            sqlite3_bind_int(stmt, 1, Int32(book))
            sqlite3_bind_int(stmt, 2, Int32(chapter))
            defer { sqlite3_finalize(stmt) }

            var result: [InterlinearVerse] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let verseNum = Int(sqlite3_column_int(stmt, 0))
                let text = GrapheRuntimeStorage.columnString(stmt, 1, path: dbPath) ?? ""
                let tokens = isRTL ? parseOT(text, prefix: prefix) : parseNT(text, prefix: prefix)
                result.append(InterlinearVerse(verse: verseNum, tokens: tokens))
            }
            return result
        } ?? []
    }

    // MARK: - Unified interlinear parser
    //
    // Handles all observed module formats by anchoring on <S>NNNN</S>
    // (the Strong's number tag that every token has). Extracts morphology
    // first into a position-indexed map, then walks each <S> boundary to
    // identify the original-language word and its translation.
    //
    // Formats handled:
    //   A. iESVTH   : English <n>Greek</n><S>n</S><m>morph</m>
    //   B. Spanish  : Greek <S>n</S> <m>morph</m> <n>Translation</n>
    //   C. VIN-el   : Greek <n>Translation</n><S>n</S><m>morph</m>
    //   D. BHPk/GNTTH : Greek<S>n</S><m>morph</m>           (no translation)
    //   E. HSB+     : <e>Hebrew</e> <S>n</S> <n>translit</n> English
    //   F. HSB2+    : Hebrew <S>n</S> <n>English</n>
    //   G. IHOT+    : Hebrew <S>n</S>English
    //   H. Ana+     : Hebrew <S>n</S><m>morph</m> <n><e>Russian</e></n>

    private nonisolated static func parseInterlinear(_ text: String, prefix: String, isRTL: Bool) -> [InterlinearToken] {
        // Step 0: locate every <m>...</m> with its byte position in the
        // original text, and associate it with the nearest <S>.
        let mRe = try! NSRegularExpression(pattern: #"<m>([^<]*)</m>"#)
        let sRe = try! NSRegularExpression(pattern: #"<S>(\d+)</S>"#)
        let ns  = text as NSString
        let textRange = NSRange(location: 0, length: ns.length)

        let mMatches = mRe.matches(in: text, range: textRange)
        let sMatches = sRe.matches(in: text, range: textRange)

        // Map each <S> to the morphology tag closest to it (in char distance).
        var morphByS: [Int: String] = [:]
        for mm in mMatches {
            let mPos   = mm.range.location
            let mEnd   = mPos + mm.range.length
            let morph  = ns.substring(with: mm.range(at: 1))
                          .trimmingCharacters(in: .whitespacesAndNewlines)
            // Find nearest <S> — the closest one in either direction wins.
            var bestIdx  = -1
            var bestDist = Int.max
            for (idx, sm) in sMatches.enumerated() {
                let sPos = sm.range.location
                let sEnd = sPos + sm.range.length
                let dist = (sPos >= mEnd) ? (sPos - mEnd) : (mPos - sEnd)
                if dist < bestDist {
                    bestDist = dist
                    bestIdx  = idx
                }
            }
            if bestIdx >= 0 && morphByS[bestIdx] == nil {
                morphByS[bestIdx] = morph
            }
        }

        // Step 1: strip <m>...</m> entirely so they don't clutter translations.
        var clean = mRe.stringByReplacingMatches(in: text, range: textRange, withTemplate: "")

        // Step 2: merge double Strong's <S>A</S><S>B</S> → <S>A</S>
        // (common in Ana+ where the second S is a secondary morphology code).
        let dblRe = try! NSRegularExpression(pattern: #"(<S>\d+</S>)\s*<S>\d+</S>"#)
        clean = dblRe.stringByReplacingMatches(
            in: clean, range: NSRange(location: 0, length: (clean as NSString).length),
            withTemplate: "$1")

        // Step 3: split on <S>NNNN</S>.
        // Swift's regex split isn't as clean as Python's — we roll our own.
        let cleanNS = clean as NSString
        let sMatches2 = sRe.matches(in: clean,
                                     range: NSRange(location: 0, length: cleanNS.length))
        guard !sMatches2.isEmpty else { return [] }

        var tokens: [InterlinearToken] = []
        var zoneStart = 0
        let zoneCount = sMatches2.count
        for i in 0..<zoneCount {
            let sRange = sMatches2[i].range
            let sNum   = cleanNS.substring(with: sMatches2[i].range(at: 1))

            // before zone = from end of previous (or start) to current <S>
            let beforeRange = NSRange(location: zoneStart,
                                       length: sRange.location - zoneStart)
            let before = cleanNS.substring(with: beforeRange)

            // after zone = from end of current <S> to start of next <S> (or EOF)
            let afterStart = sRange.location + sRange.length
            let afterEnd   = (i + 1 < zoneCount) ? sMatches2[i + 1].range.location : cleanNS.length
            let after = cleanNS.substring(with: NSRange(location: afterStart,
                                                         length: afterEnd - afterStart))

            var original = ""
            var english  = ""

            // Format A / VIN-el: <n>X</n> immediately before <S>
            if let aRe = try? NSRegularExpression(pattern: #"<n>([^<]*)</n>\s*$"#) {
                if let am = aRe.firstMatch(in: before,
                                            range: NSRange(location: 0, length: (before as NSString).length)) {
                    let nContent = (before as NSString).substring(with: am.range(at: 1))
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    let outside  = stripTags((before as NSString).substring(
                                        with: NSRange(location: 0, length: am.range.location)))
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    let nIsOrig  = isOriginalScript(nContent)
                    let oIsOrig  = isOriginalScript(outside)
                    if nIsOrig && !oIsOrig {
                        original = nContent
                        english  = outside
                    } else if oIsOrig && !nIsOrig {
                        original = outside.split(separator: " ").last.map(String.init) ?? outside
                        english  = nContent
                    } else {
                        original = nContent
                        english  = outside
                    }
                }
            }

            if original.isEmpty {
                // <e>word</e> wrapper (HSB family)
                if let eRe = try? NSRegularExpression(pattern: #"<e>([^<]*)</e>\s*$"#) {
                    if let em = eRe.firstMatch(in: before,
                                                range: NSRange(location: 0, length: (before as NSString).length)) {
                        original = (before as NSString).substring(with: em.range(at: 1))
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                if original.isEmpty {
                    let cleanedBefore = stripTags(before).trimmingCharacters(in: .whitespacesAndNewlines)
                    let words = cleanedBefore.split(whereSeparator: { $0.isWhitespace })
                    if words.isEmpty { continue }
                    original = String(words.last!)
                }

                // Translation from after-zone
                if let nRe = try? NSRegularExpression(pattern: #"^\s*<n>(.*?)</n>"#,
                                                      options: [.dotMatchesLineSeparators]) {
                    if let nm = nRe.firstMatch(in: after,
                                                range: NSRange(location: 0, length: (after as NSString).length)) {
                        english = stripTags((after as NSString).substring(with: nm.range(at: 1)))
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                if english.isEmpty {
                    let cleanedAfter = stripTags(after).trimmingCharacters(in: .whitespacesAndNewlines)
                    let words = cleanedAfter.split(whereSeparator: { $0.isWhitespace })
                    if words.count > 1 {
                        english = words.dropLast().joined(separator: " ")
                    }
                }
            }

            // Clean up: collapse whitespace, strip quotes/punctuation edges
            english  = normalizeSpaces(english)
            original = normalizeSpaces(original)
            let cruft = CharacterSet(charactersIn: "\u{201C}\u{201D}\" \t\n¦·")
            english  = english.trimmingCharacters(in: cruft)
            original = original.trimmingCharacters(in: cruft)

            guard !original.isEmpty else {
                zoneStart = afterEnd
                continue
            }

            tokens.append(InterlinearToken(
                english:    english,
                original:   original,
                strongsNum: prefix + sNum,
                morphology: morphByS[i] ?? ""))

            zoneStart = afterEnd
        }
        return tokens
    }

    /// Remove all HTML/XML-ish tags from a string.
    private nonisolated static func stripTags(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"<[^>]+>"#) else { return s }
        let ns = s as NSString
        return re.stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    /// Collapse runs of whitespace to a single space.
    private nonisolated static func normalizeSpaces(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\s+"#) else { return s }
        let ns = s as NSString
        return re.stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
    }

    /// True if `s` contains more Greek/Hebrew characters than Latin/Cyrillic.
    /// Used to distinguish the original-language word from its translation
    /// when both could be on either side of <S>.
    private nonisolated static func isOriginalScript(_ s: String) -> Bool {
        var originalCount = 0
        var letterCount   = 0
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if (0x0370...0x03FF).contains(v)   // Greek
            || (0x1F00...0x1FFF).contains(v)   // Greek Extended
            || (0x0590...0x05FF).contains(v) { // Hebrew
                originalCount += 1
            }
            if CharacterSet.letters.contains(scalar) {
                letterCount += 1
            }
        }
        if letterCount == 0 { return false }
        return Double(originalCount) / Double(letterCount) > 0.5
    }

    // MARK: - Back-compat shims
    // Old call sites expected separate parseNT / parseOT. The unified
    // parser handles both; these wrappers preserve source compatibility.

    private nonisolated static func parseNT(_ text: String, prefix: String) -> [InterlinearToken] {
        parseInterlinear(text, prefix: prefix, isRTL: false)
    }

    private nonisolated static func parseOT(_ text: String, prefix: String) -> [InterlinearToken] {
        parseInterlinear(text, prefix: prefix, isRTL: true)
    }

    // MARK: - SQLite helper

    private nonisolated static func prepare(_ db: OpaquePointer?, _ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }
}
