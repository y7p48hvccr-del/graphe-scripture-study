import Foundation

func parseVerseReferences(text: String) -> [(book: String, chapter: Int, verse: String)] {
    // Added \s* after the colon to handle "5: 10" style references
    let referenceRegex = #"([1-3]*\s*[A-Z][a-z]+\.?)?\s*(\d+):\s*(\d+(?:[,-–]\d+)?(?:,\s*\d+(?:[,-–]\d+)?)*)"#

    var references: [(book: String, chapter: Int, verse: String)] = []
    var lastBook = ""

    let halves = text.components(separatedBy: ";")

    for half in halves {
        let current = half.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = current.firstMatch(of: referenceRegex) else { continue }

        let bookSubstring = m.1.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bookSubstring.isEmpty {
            lastBook = bookSubstring
        }

        guard !lastBook.isEmpty, let chapter = Int(m.2) else { continue }
        let verse = String(m.3)

        references.append((book: lastBook, chapter: chapter, verse: verse))
    }

    return references
}

// MARK: - Regex helpers

extension String {
    func matches(of regex: String) -> [Substring] {
        let re = try! NSRegularExpression(pattern: regex)
        let ns = self as NSString
        return re.matches(in: self, range: NSRange(location: 0, length: ns.length))
            .compactMap { Range($0.range, in: self).map { self[$0] } }
    }

    func firstMatch(of regex: String) -> (String, Substring, Substring, Substring)? {
        let re = try! NSRegularExpression(pattern: regex)
        guard let match = re.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              let r1 = Range(match.range(at: 1), in: self),
              let r2 = Range(match.range(at: 2), in: self),
              let r3 = Range(match.range(at: 3), in: self)
        else { return nil }
        return (self, self[r1], self[r2], self[r3])
    }
}
