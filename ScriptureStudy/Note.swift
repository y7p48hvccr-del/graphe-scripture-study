import Foundation

struct Note: Identifiable, Equatable {
    var id:            UUID   = UUID()
    var title:         String = "Untitled"
    var content:       String = ""
    var richDocument:  RichNoteDocument? = nil
    var bookNumber:    Int    = 0    // MyBible book number (0 = no reference)
    var chapterNumber: Int    = 0
    var verseNumbers:  [Int]  = []   // empty = whole chapter
    var updatedAt:     Date   = Date()
    var isLocked:      Bool   = false
    /// Archived notes are hidden from the main list but preserved. The
    /// "Show archived" toggle at the bottom of the Notes tab surfaces
    /// them. Archive is a soft-hide, separate from Trash.
    var isArchived:    Bool   = false
    /// When non-nil, the note has been moved to Trash. Trash is kept
    /// forever until the user empties it (no auto-purge). Restore
    /// clears this field back to nil.
    var deletedAt:     Date?  = nil

    // MARK: - Computed reference string

    var verseReference: String {
        guard bookNumber > 0,
              let bookName = myBibleBookNumbers[bookNumber] else { return "" }
        if verseNumbers.isEmpty { return "\(bookName) \(chapterNumber)" }
        return "\(bookName) \(chapterNumber):\(formattedVerses)"
    }

    var formattedVerses: String {
        guard !verseNumbers.isEmpty else { return "" }
        let sorted = verseNumbers.sorted()
        var result: [String] = []
        var i = 0
        while i < sorted.count {
            var j = i
            while j + 1 < sorted.count && sorted[j+1] == sorted[j] + 1 { j += 1 }
            result.append(i == j ? "\(sorted[i])" : "\(sorted[i])–\(sorted[j])")
            i = j + 1
        }
        return result.joined(separator: ",")
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title
    }

    var wordCount: Int {
        plainTextContent.trimmingCharacters(in: .whitespacesAndNewlines)
               .split { $0.isWhitespace }.count
    }

    var formattedDate: String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: updatedAt)
    }

    var safeFilename: String {
        let illegal = CharacterSet(charactersIn: #"/\:*?"<>|"#)
        let safe    = displayTitle.components(separatedBy: illegal).joined(separator: "-")
                                  .trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.isEmpty ? "Untitled" : safe
    }

    // MARK: - File format
    // Line 1: title
    // Line 2: bookNumber
    // Line 3: chapterNumber
    // Line 4: verseNumbers (comma separated, empty string if none)
    // Line 5: ISO date (updatedAt)
    // Line 6: UUID
    // Line 7: locked | unlocked
    // Line 8: archived | active    (added 2026-04-21, optional on read)
    // Line 9: ISO deletedAt | ""   (added 2026-04-21, optional on read)
    // Line 10: ---
    // Lines 11+: plain content OR rich envelope body
    //
    // Backward compatibility: notes written before the archive/trash
    // fields existed have line 8 = "---" (the separator). The parser
    // detects the separator earlier than expected and treats the
    // missing fields as their defaults (not archived, not deleted).

    private static let richEnvelopeMarker = "__RICH_NOTE_JSON__"

    var plainTextContent: String {
        richDocument?.plainText ?? content
    }

    var fileText: String {
        let iso      = ISO8601DateFormatter().string(from: updatedAt)
        let verses   = verseNumbers.map(String.init).joined(separator: ",")
        let locked   = isLocked   ? "locked"   : "unlocked"
        let archived = isArchived ? "archived" : "active"
        let deletedISO = deletedAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
        return "\(title)\n\(bookNumber)\n\(chapterNumber)\n\(verses)\n\(iso)\n\(id.uuidString)\n\(locked)\n\(archived)\n\(deletedISO)\n---\n\(persistedBody)"
    }

    static func parse(from text: String) -> Note? {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 7 else { return nil }
        var note            = Note()
        note.title          = lines[0]
        note.bookNumber     = Int(lines[1]) ?? 0
        note.chapterNumber  = Int(lines[2]) ?? 0
        note.verseNumbers   = lines[3].split(separator: ",").compactMap { Int($0) }
        if let date = ISO8601DateFormatter().date(from: lines[4]) { note.updatedAt = date }
        if let uid  = UUID(uuidString: lines[5]) { note.id = uid }
        note.isLocked = lines.count > 6 && lines[6] == "locked"
        // Backward-compatible parsing for archived + deletedAt.
        // Old-format notes have "---" at line 7 (index 7). New-format
        // notes have archive + deletedAt at indexes 7 and 8, and
        // "---" at index 9.
        if lines.count > 7 && lines[7] == "archived" {
            note.isArchived = true
        }
        if lines.count > 8, !lines[8].isEmpty,
           let d = ISO8601DateFormatter().date(from: lines[8]) {
            note.deletedAt = d
        }
        if let sep = lines.firstIndex(of: "---") {
            let bodyLines = Array(lines.dropFirst(sep + 1))
            note.loadBody(from: bodyLines)
        }
        return note
    }

    private var persistedBody: String {
        guard let richDocument else { return content }
        let envelope = NoteBodyEnvelope(
            mode: .rich,
            plainText: richDocument.plainText,
            richDocument: richDocument
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(envelope),
           let json = String(data: data, encoding: .utf8) {
            return "\(Self.richEnvelopeMarker)\n\(json)"
        }
        return content
    }

    private mutating func loadBody(from bodyLines: [String]) {
        guard let first = bodyLines.first, first == Self.richEnvelopeMarker else {
            content = bodyLines.joined(separator: "\n")
            richDocument = nil
            return
        }

        let json = bodyLines.dropFirst().joined(separator: "\n")
        guard let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(NoteBodyEnvelope.self, from: data) else {
            content = bodyLines.joined(separator: "\n")
            richDocument = nil
            return
        }

        content = envelope.plainText
        richDocument = envelope.richDocument
    }
}

private struct NoteBodyEnvelope: Codable, Equatable {
    enum Mode: String, Codable, Equatable {
        case rich
    }

    var mode: Mode
    var plainText: String
    var richDocument: RichNoteDocument
}
