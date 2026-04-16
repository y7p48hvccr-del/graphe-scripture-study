//
//  BMapsParser.swift
//  ScriptureStudy
//
//  Parses the BMaps.dictionary.SQLite3 atlas module into structured data.
//

import Foundation
import SQLite3

// MARK: - Data Models

struct BibleMap: Identifiable, Hashable {
    let id: String          // e.g. "#02. Israel's Exodus..."
    let number: String      // e.g. "02"
    let title: String       // e.g. "Israel's Exodus from Egypt and Entry into Canaan"
    let imageName: String?  // e.g. "2214x1838.png" (if embedded in content_fragments)
    let places: [MapPlace]  // named locations on this map with verse refs
}

struct MapPlace: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let verseRefs: [String] // e.g. ["Exod 14", "Num 33:8"]
}

struct BiblePlaceEntry: Identifiable, Hashable {
    let id: String          // the place name
    let name: String
    let mapRefs: [PlaceMapRef]
}

struct PlaceMapRef: Hashable {
    let mapID: String       // e.g. "#11. The Holy Land in New Testament Times"
    let mapTitle: String
    let gridRef: String     // e.g. "11:C3"
}

// MARK: - Book Number → Abbreviation

private let bmapsBookNumberMap: [Int: String] = [
    10:  "Gen",   20:  "Exod",  40:  "Num",   50:  "Deut",
    60:  "Josh",  70:  "Judg",  80:  "Ruth",  90:  "1Sam",
    100: "2Sam",  110: "1Kgs",  120: "2Kgs",  130: "1Chr",
    140: "2Chr",  150: "Ezra",  160: "Neh",   170: "Esth",
    180: "Job",   190: "Isa",   200: "Jer",   300: "Ezek",
    330: "Dan",   340: "Hos",   360: "Joel",  390: "Amos",
    470: "Matt",  480: "Mark",  490: "Luke",  500: "John",
    510: "Acts",  520: "Rom",   540: "1Cor",  580: "Gal",
    730: "Rev"
]

// MARK: - Parser

class BMapsParser {

    static func parse(dbPath: String) -> (maps: [BibleMap], places: [BiblePlaceEntry]) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            print("[BMapsParser] Failed to open DB at \(dbPath)")
            return ([], [])
        }
        defer { sqlite3_close(db) }

        // 1. Load image filenames from content_fragments
        var imageNames: Set<String> = []
        let imgSQL = "SELECT id FROM content_fragments"
        var imgStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, imgSQL, -1, &imgStmt, nil) == SQLITE_OK {
            while sqlite3_step(imgStmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(imgStmt, 0) {
                    imageNames.insert(String(cString: cStr))
                }
            }
        }
        sqlite3_finalize(imgStmt)

        // 2. Load all dictionary entries
        // Detect whether this is an encrypted .graphe module
        let isGraphe = dbPath.hasSuffix(".graphe")

        var maps: [BibleMap] = []
        var places: [BiblePlaceEntry] = []
        var mapTitleLookup: [String: String] = [:]  // id -> title

        let dictSQL = "SELECT topic, definition FROM dictionary ORDER BY topic"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, dictSQL, -1, &stmt, nil) == SQLITE_OK else {
            return ([], [])
        }

        var rawEntries: [(topic: String, definition: String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let topicC = sqlite3_column_text(stmt, 0) else { continue }
            let topic = String(cString: topicC)

            // For .graphe modules the definition column is AES-256-CBC encrypted;
            // read it as a blob and decrypt — same path as MyBibleService.col().
            let definition: String
            if isGraphe {
                let ptr = sqlite3_column_blob(stmt, 1)?.assumingMemoryBound(to: UInt8.self)
                let len = sqlite3_column_bytes(stmt, 1)
                guard let decrypted = grapheDecrypt(ptr, len, filePath: dbPath) else { continue }
                definition = decrypted
            } else {
                guard let defC = sqlite3_column_text(stmt, 1) else { continue }
                definition = String(cString: defC)
            }

            rawEntries.append((topic, definition))
        }
        sqlite3_finalize(stmt)

        // First pass: build map title lookup
        for entry in rawEntries where entry.topic.hasPrefix("#") {
            let title = entry.topic
                .replacingOccurrences(of: #"^#\d+\.\s*"#, with: "", options: .regularExpression)
            mapTitleLookup[entry.topic] = title
        }

        // Second pass: parse map articles
        for entry in rawEntries where entry.topic.hasPrefix("#") && !entry.topic.contains("Index") {
            let mapID = entry.topic
            let title = mapTitleLookup[mapID] ?? mapID
            let number = String(mapID.dropFirst(1).prefix(2))

            // Extract first image referenced via <!-- INCLUDE(filename) -->
            let imageName = firstInclude(in: entry.definition)

            // Parse named places from <li> segments
            let mapPlaces = parseMapPlaces(from: entry.definition)

            maps.append(BibleMap(
                id: mapID,
                number: number,
                title: title,
                imageName: imageName,
                places: mapPlaces
            ))
        }
        maps.sort { $0.number < $1.number }

        // Third pass: parse place entries
        for entry in rawEntries where !entry.topic.hasPrefix("#") {
            let refs = parsePlaceMapRefs(from: entry.definition, titleLookup: mapTitleLookup)
            if !refs.isEmpty {
                places.append(BiblePlaceEntry(id: entry.topic, name: entry.topic, mapRefs: refs))
            }
        }

        return (maps, places)
    }

    // MARK: - Private helpers

    private static func firstInclude(in html: String) -> String? {
        let pattern = #"<!--\s*INCLUDE\(([^)]+)\)\s*-->"#
        guard let range = html.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(html[range])
        let inner = match
            .replacingOccurrences(of: #"<!--\s*INCLUDE\("#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\)\s*-->"#, with: "", options: .regularExpression)
        return inner.isEmpty ? nil : inner
    }

    private static func parseMapPlaces(from html: String) -> [MapPlace] {
        var result: [MapPlace] = []
        // Split on list items
        let segments = html.components(separatedBy: "<li")
        for seg in segments {
            guard let nameRange = seg.range(of: "<strong>") else { continue }
            let afterOpen = seg[nameRange.upperBound...]
            guard let closeRange = afterOpen.range(of: "</strong>") else { continue }
            let placeName = String(afterOpen[..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !placeName.isEmpty else { continue }

            let verseRefs = extractVerseRefs(from: seg)
            if !verseRefs.isEmpty {
                result.append(MapPlace(name: placeName, verseRefs: verseRefs))
            }
        }
        return result
    }

    private static func extractVerseRefs(from segment: String) -> [String] {
        var refs: [String] = []
        // Pattern: href="B:BOOKNUM CHAPTER:VERSE"
        let pattern = #"href="B:(\d+)\s+([^"]+)""#
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsStr = segment as NSString
        let matches = regex?.matches(in: segment, range: NSRange(location: 0, length: nsStr.length)) ?? []
        for match in matches {
            let bookNumStr = nsStr.substring(with: match.range(at: 1))
            let ref       = nsStr.substring(with: match.range(at: 2))
            if let bookNum = Int(bookNumStr),
               let abbr = bmapsBookNumberMap[bookNum] {
                refs.append("\(abbr) \(ref)")
            }
        }
        return refs
    }

    private static func parsePlaceMapRefs(from html: String,
                                           titleLookup: [String: String]) -> [PlaceMapRef] {
        var result: [PlaceMapRef] = []
        // Pattern: href="S:#XX. Map Title">GRIDREF<
        let pattern = #"href="S:(#[^"]+)">([^<]+)<"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsStr = html as NSString
        let matches = regex?.matches(in: html, range: NSRange(location: 0, length: nsStr.length)) ?? []
        for match in matches {
            let mapID   = nsStr.substring(with: match.range(at: 1))
            let gridRef = nsStr.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            let title   = titleLookup[mapID] ?? mapID
            result.append(PlaceMapRef(mapID: mapID, mapTitle: title, gridRef: gridRef))
        }
        return result
    }
}
