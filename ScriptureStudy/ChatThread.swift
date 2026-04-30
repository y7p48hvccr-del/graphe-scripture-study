import Foundation

/// A saved chat conversation. Stores message history, title (auto-generated
/// from the first user message or user-edited), creation/update times, and
/// optional Bible passage context — which book/chapter/verse(s) the user
/// was reading when the thread was started.
///
/// File format mirrors Note.swift for consistency: plain-text header lines,
/// a "---" separator, then a JSON blob containing the messages. Human-
/// readable enough to recover by hand if needed, but structured enough to
/// round-trip losslessly.
struct ChatThread: Identifiable, Equatable {

    var id:             UUID   = UUID()
    var title:          String = ""
    var bookNumber:     Int    = 0   // MyBible book number (0 = no passage context)
    var chapterNumber:  Int    = 0
    var verseNumbers:   [Int]  = []  // empty = whole chapter
    var createdAt:      Date   = Date()
    var updatedAt:      Date   = Date()
    var messages:       [ChatMessage] = []

    // MARK: - Computed

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        // Fall back to first user message if no explicit title
        if let firstUser = messages.first(where: { $0.role == "user" }) {
            return Self.deriveTitle(from: firstUser.content)
        }
        return "New chat"
    }

    /// Passage string like "Romans 8" or "John 3:16" — empty when no context.
    var passageReference: String {
        guard bookNumber > 0,
              let bookName = myBibleBookNumbers[bookNumber] else { return "" }
        if verseNumbers.isEmpty { return "\(bookName) \(chapterNumber)" }
        return "\(bookName) \(chapterNumber):\(formattedVerses)"
    }

    /// Short summary of the conversation — the first user message, truncated.
    var snippet: String {
        guard let firstUser = messages.first(where: { $0.role == "user" }) else { return "" }
        let raw = firstUser.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if raw.count <= 80 { return raw }
        let cut = raw.prefix(80)
        if let lastSpace = cut.lastIndex(of: " ") {
            return String(cut[..<lastSpace]) + "…"
        }
        return String(cut) + "…"
    }

    var formattedDate: String {
        let f = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(updatedAt) {
            f.dateFormat = "HH:mm"
            return "Today " + f.string(from: updatedAt)
        }
        if cal.isDateInYesterday(updatedAt) {
            f.dateFormat = "HH:mm"
            return "Yesterday " + f.string(from: updatedAt)
        }
        // Same year? Show "Mon 14 Apr". Different year? Show "14 Apr 2025"
        if cal.component(.year, from: updatedAt) == cal.component(.year, from: Date()) {
            f.dateFormat = "EEE d MMM"
        } else {
            f.dateFormat = "d MMM yyyy"
        }
        return f.string(from: updatedAt)
    }

    var safeFilename: String {
        let illegal = CharacterSet(charactersIn: #"/\:*?"<>|"#)
        let base = displayTitle
            .components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? "Chat" : base
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

    // MARK: - File format
    //
    // Line 1: title (or empty if auto-derived)
    // Line 2: bookNumber
    // Line 3: chapterNumber
    // Line 4: verseNumbers (comma separated, empty string if none)
    // Line 5: createdAt ISO date
    // Line 6: updatedAt ISO date
    // Line 7: UUID
    // Line 8: ---
    // Lines 9+: JSON-encoded [ChatMessage]

    var fileText: String {
        let iso1    = ISO8601DateFormatter().string(from: createdAt)
        let iso2    = ISO8601DateFormatter().string(from: updatedAt)
        let verses  = verseNumbers.map(String.init).joined(separator: ",")
        let encoder = JSONEncoder()
        let json: String
        if let data = try? encoder.encode(messages),
           let str  = String(data: data, encoding: .utf8) {
            json = str
        } else {
            json = "[]"
        }
        return "\(title)\n\(bookNumber)\n\(chapterNumber)\n\(verses)\n\(iso1)\n\(iso2)\n\(id.uuidString)\n---\n\(json)"
    }

    static func parse(from text: String) -> ChatThread? {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 8,
              let sep = lines.firstIndex(of: "---") else { return nil }

        var thread = ChatThread()
        thread.title         = lines[0]
        thread.bookNumber    = Int(lines[1]) ?? 0
        thread.chapterNumber = Int(lines[2]) ?? 0
        thread.verseNumbers  = lines[3].split(separator: ",").compactMap { Int($0) }
        if let d = ISO8601DateFormatter().date(from: lines[4]) { thread.createdAt = d }
        if let d = ISO8601DateFormatter().date(from: lines[5]) { thread.updatedAt = d }
        if let u = UUID(uuidString: lines[6]) { thread.id = u }

        let jsonStr = lines.dropFirst(sep + 1).joined(separator: "\n")
        if let data = jsonStr.data(using: .utf8),
           let msgs = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            thread.messages = msgs
        }
        return thread
    }

    // MARK: - Helpers

    /// Turns the first user message into a short sidebar title. Used only
    /// as a fallback — callers can also set `title` explicitly.
    static func deriveTitle(from firstMessage: String) -> String {
        let cleaned = firstMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard cleaned.count > 44 else { return cleaned }
        let cut = cleaned.prefix(42)
        if let lastSpace = cut.lastIndex(of: " ") {
            return String(cut[..<lastSpace]) + "…"
        }
        return String(cut) + "…"
    }
}
