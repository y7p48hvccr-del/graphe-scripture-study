//
//  BMapsService.swift
//  ScriptureStudy
//
//  Reads the same "modulesFolder" UserDefaults key as MyBibleService
//  so it looks in exactly the same user-selected folder.
//

import Foundation
import Combine

@MainActor
class BMapsService: ObservableObject {

    // STARTUP DIAGNOSTIC — 2026-04-21
    init() {
        print("[STARTUP] BMapsService.init()")
    }

    @Published var maps:   [BibleMap]        = []
    @Published var places: [BiblePlaceEntry] = []
    @Published var isLoaded: Bool            = false

    private(set) var placeVerseIndex: [String: [String]] = [:]
    private(set) var placeMapsIndex:  [String: [String]] = [:]

    // MARK: - Load

    func loadIfNeeded() {
        print("[STARTUP] BMapsService.loadIfNeeded() isLoaded=\(isLoaded)")
        guard !isLoaded else { return }

        // Use the same folder the user picked in Settings → Library
        guard let folderPath = UserDefaults.standard.string(forKey: "modulesFolder"),
              !folderPath.isEmpty else {
            print("[BMapsService] modulesFolder not set — open Settings > Library and select your modules folder")
            return
        }

        let folderURL = URL(fileURLWithPath: folderPath)
        guard let dbURL = findDB(in: folderURL) else {
            print("[BMapsService] BMaps.dictionary.SQLite3 not found in \(folderPath)")
            print("[BMapsService] Files present: \((try? FileManager.default.contentsOfDirectory(atPath: folderPath)) ?? [])")
            return
        }

        print("[BMapsService] Found DB at \(dbURL.path) — parsing…")
        let path = dbURL.path
        Task.detached(priority: .userInitiated) {
            let result = BMapsParser.parse(dbPath: path)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.maps   = result.maps
                self.places = result.places
                self.buildIndices()
                self.isLoaded = true
                print("[BMapsService] Loaded \(result.maps.count) maps, \(result.places.count) places")
            }
        }
    }

    // MARK: - Lookups

    func mapsForPlace(_ name: String) -> [BibleMap] {
        let key = name.lowercased()
        guard let ids = placeMapsIndex[key] else { return [] }
        return maps.filter { ids.contains($0.id) }
    }

    /// Returns true if `word` matches any known place name exactly OR as a
    /// prefix before a qualifier suffix like ", tribe", ", region", ", river" etc.
    /// Use this for right-click context menu checks.
    func wordMatchesPlace(_ word: String) -> Bool {
        let lower = word.lowercased()
        // 1. Exact match
        if placeMapsIndex[lower] != nil { return true }
        // 2. Prefix match — e.g. "Zebulun" matches "Zebulun, tribe"
        return places.contains {
            let name = $0.name.lowercased()
            return name.hasPrefix(lower + ",") || name.hasPrefix(lower + " (")
        }
    }

    /// Returns the best-matching place name for a word, including suffix variants.
    func resolvedPlaceName(for word: String) -> String {
        let lower = word.lowercased()
        if placeMapsIndex[lower] != nil { return word }
        // Return the first place whose name starts with the word
        return places.first {
            let name = $0.name.lowercased()
            return name.hasPrefix(lower + ",") || name.hasPrefix(lower + " (")
        }?.name ?? word
    }

    func versesForPlace(_ name: String) -> [String] {
        placeVerseIndex[name.lowercased()] ?? []
    }

    func placesNear(verseRef: String) -> [BiblePlaceEntry] {
        let lower = verseRef.lowercased()
        return places.filter { place in
            guard let refs = placeVerseIndex[place.name.lowercased()] else { return false }
            return refs.contains { $0.lowercased().contains(lower) }
        }
    }

    // MARK: - Private

    private func buildIndices() {
        var verseIdx: [String: Set<String>] = [:]
        var mapsIdx:  [String: Set<String>] = [:]

        for map in maps {
            for mapPlace in map.places {
                let key = mapPlace.name.lowercased()
                mapPlace.verseRefs.forEach { verseIdx[key, default: []].insert($0) }
                mapsIdx[key, default: []].insert(map.id)
            }
        }
        for place in places {
            let key = place.name.lowercased()
            place.mapRefs.forEach { mapsIdx[key, default: []].insert($0.mapID) }
        }

        placeVerseIndex = verseIdx.mapValues { Array($0).sorted() }
        placeMapsIndex  = mapsIdx.mapValues  { Array($0).sorted() }
    }

    private func findDB(in dir: URL) -> URL? {
        let fm = FileManager.default
        // Direct match first — dot and underscore variants
        let candidates = [
            dir.appendingPathComponent("BMaps.dictionary.SQLite3"),
            dir.appendingPathComponent("BMaps.dictionary.sqlite3"),
            dir.appendingPathComponent("BMaps.dictionary.db"),
            dir.appendingPathComponent("BMaps_dictionary.SQLite3"),
            dir.appendingPathComponent("BMaps_dictionary.sqlite3"),
            dir.appendingPathComponent("BMaps_dictionary.db"),
            dir.appendingPathComponent("BMaps.dictionary.graphe"),
            dir.appendingPathComponent("BMaps_dictionary.graphe")
        ]
        if let hit = candidates.first(where: { fm.fileExists(atPath: $0.path) }) { return hit }

        // Recursive search — match any file starting with bmaps.dictionary or bmaps_dictionary
        guard let enumerator = fm.enumerator(at: dir,
                                              includingPropertiesForKeys: nil,
                                              options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent.lowercased()
            if name.hasPrefix("bmaps.dictionary") || name.hasPrefix("bmaps_dictionary") {
                return url
            }
        }
        return nil
    }
}

// MARK: - HTML Rendering (called on demand, not cached — images are large)

import SQLite3

extension BMapsService {

    /// Builds the full renderable HTML for a map article by substituting
    /// <!-- INCLUDE(filename) --> placeholders with base64 image data from content_fragments.
    func renderedHTML(for mapID: String) async -> String? {
        guard let path = UserDefaults.standard.string(forKey: "modulesFolder"),
              !path.isEmpty else { return nil }
        let folder = URL(fileURLWithPath: path)
        guard let dbURL = findDB(in: folder) else { return nil }

        let dbPath = dbURL.path
        let id     = mapID
        return await Task.detached(priority: .userInitiated) {
            BMapsService.buildHTML(dbPath: dbPath, mapID: id)
        }.value
    }

    private nonisolated static func buildHTML(dbPath: String, mapID: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        // Detect whether this is an encrypted .graphe file
        let isGraphe = dbPath.hasSuffix(".graphe")

        // Load CSS from info table
        var css = ""
        if let stmt = prepare(db, "SELECT value FROM info WHERE name='html_style'") {
            if sqlite3_step(stmt) == SQLITE_ROW {
                let raw: String?
                if isGraphe {
                    let ptr = sqlite3_column_blob(stmt, 0)?.assumingMemoryBound(to: UInt8.self)
                    let len = sqlite3_column_bytes(stmt, 0)
                    let decrypted = grapheDecrypt(ptr, len, filePath: dbPath)
                    raw = (decrypted?.isEmpty == false) ? decrypted : sqlite3_column_text(stmt, 0).map { String(cString: $0) }
                } else {
                    raw = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
                }
                css = (raw ?? "").replacingOccurrences(of: "%COLOR_TEXT%", with: "#333333")
            }
            sqlite3_finalize(stmt)
        }

        // Load map article HTML
        var articleHTML = ""
        if let stmt = prepare(db, "SELECT definition FROM dictionary WHERE topic=?") {
            sqlite3_bind_text(stmt, 1, mapID, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                if isGraphe {
                    let ptr = sqlite3_column_blob(stmt, 0)?.assumingMemoryBound(to: UInt8.self)
                    let len = sqlite3_column_bytes(stmt, 0)
                    articleHTML = grapheDecrypt(ptr, len, filePath: dbPath) ?? ""
                } else if let ptr = sqlite3_column_text(stmt, 0) {
                    articleHTML = String(cString: ptr)
                }
            }
            sqlite3_finalize(stmt)
        }
        guard !articleHTML.isEmpty else { return nil }

        // Load all content_fragments for substitution
        var fragments: [String: String] = [:]
        if let stmt = prepare(db, "SELECT id, fragment FROM content_fragments") {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idPtr = sqlite3_column_text(stmt, 0) else { continue }
                let key = String(cString: idPtr)
                var fragStr = ""
                if isGraphe {
                    let ptr = sqlite3_column_blob(stmt, 1)?.assumingMemoryBound(to: UInt8.self)
                    let len = sqlite3_column_bytes(stmt, 1)
                    // Try decryption first; some columns in .graphe may be plain text
                    if let decrypted = grapheDecrypt(ptr, len, filePath: dbPath), !decrypted.isEmpty {
                        fragStr = decrypted
                    } else if let textPtr = sqlite3_column_text(stmt, 1) {
                        fragStr = String(cString: textPtr)
                    }
                } else if let fragPtr = sqlite3_column_text(stmt, 1) {
                    fragStr = String(cString: fragPtr)
                }
                // Fix any missing base64 padding so browsers can decode the image
                fragments[key] = BMapsService.fixBase64Padding(in: fragStr)
            }
            sqlite3_finalize(stmt)
        }

        // Substitute <!-- INCLUDE(key) --> placeholders
        let body = substituteIncludes(in: articleHTML, fragments: fragments)

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=3.0">
        <style>
        body { margin: 0; padding: 8px; font-family: -apple-system, sans-serif; font-size: 14px; }
        \(css)
        a[href^="S:"], a[href^="B:"] { color: #6b8cba; }

        /* Make map markers readable over any map background */
        .marker {
            position: absolute;
            background: rgba(255, 255, 255, 0.88);
            border: 1px solid rgba(0, 0, 0, 0.25);
            border-radius: 3px;
            padding: 1px 5px;
            font-size: 10px;
            font-weight: 600;
            color: #1a1a2e;
            white-space: nowrap;
            box-shadow: 0 1px 4px rgba(0,0,0,0.25);
            text-shadow: none;
            line-height: 1.4;
            pointer-events: none;
        }

        /* Ensure map container and image allow full-width display */
        .map-container { width: 100%; overflow: visible; }
        .map-container img { width: 100%; height: auto; display: block; }
        figure.map { width: 100%; margin: 0; padding: 0; overflow: visible; }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    private nonisolated static func prepare(_ db: OpaquePointer?, _ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    private nonisolated static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Finds `base64,XXXXX"` substrings in a fragment string and ensures the
    /// base64 payload is correctly padded to a multiple-of-4 length.
    /// Strips embedded newlines from the base64 payload before padding.
    private nonisolated static func fixBase64Padding(in fragment: String) -> String {
        guard let markerRange = fragment.range(of: "base64,") else { return fragment }
        // Everything before "base64," stays unchanged
        let prefix = fragment[fragment.startIndex..<markerRange.upperBound]
        let rest   = fragment[markerRange.upperBound...]
        // base64 payload ends at the first closing " ' or >
        let terminators = CharacterSet(charactersIn: "\"'>")
        let endIdx = rest.unicodeScalars.firstIndex(where: { terminators.contains($0) }) ?? rest.endIndex
        let b64Raw  = String(rest[rest.startIndex..<endIdx])
        let suffix  = String(rest[endIdx...])
        // Remove any embedded whitespace/newlines (some encoders wrap at 76 chars)
        let b64Clean = b64Raw.components(separatedBy: .whitespacesAndNewlines).joined()
        // Add missing padding
        let rem    = b64Clean.count % 4
        let padded = rem == 0 ? b64Clean : b64Clean + String(repeating: "=", count: 4 - rem)
        return prefix + padded + suffix
    }

    private nonisolated static func substituteIncludes(in html: String, fragments: [String: String]) -> String {
        // Replace <!-- INCLUDE(key) --> with fragment content
        var result = html
        let pattern = try! NSRegularExpression(pattern: #"<!--\s*INCLUDE\(([^)]+)\)\s*-->"#)
        let nsStr = html as NSString
        let matches = pattern.matches(in: html, range: NSRange(location: 0, length: nsStr.length))
        // Replace in reverse so ranges stay valid
        for match in matches.reversed() {
            let key = nsStr.substring(with: match.range(at: 1))
            let replacement = fragments[key] ?? ""
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }
}
