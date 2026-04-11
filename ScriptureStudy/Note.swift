import Foundation

struct Note: Identifiable, Equatable {
    var id:            UUID   = UUID()
    var title:         String = "Untitled"
    var content:       String = ""
    var bookNumber:    Int    = 0    // MyBible book number (0 = no reference)
    var chapterNumber: Int    = 0
    var verseNumbers:  [Int]  = []   // empty = whole chapter
    var updatedAt:     Date   = Date()
    var isLocked:      Bool   = false

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
        content.trimmingCharacters(in: .whitespacesAndNewlines)
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
    // Line 5: ISO date
    // Line 6: UUID
    // Line 7: ---
    // Lines 8+: content

    var fileText: String {
        let iso     = ISO8601DateFormatter().string(from: updatedAt)
        let verses  = verseNumbers.map(String.init).joined(separator: ",")
        let locked  = isLocked ? "locked" : "unlocked"
        return "\(title)\n\(bookNumber)\n\(chapterNumber)\n\(verses)\n\(iso)\n\(id.uuidString)\n\(locked)\n---\n\(content)"
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
        if let sep  = lines.firstIndex(of: "---") {
            note.content = lines.dropFirst(sep + 1).joined(separator: "\n")
        }
        return note
    }
}

