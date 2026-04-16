import Foundation

func parseVerseReferences(text: String) -> [(book: String, chapter: Int, verse: String)] {
    let referenceRegex = #"([1-3]*\s*[A-Z][a-z]+\.?)?\s*(\d+):?\s*(\d+(?:[,-–]\d+)?(?:,\s*\d+(?:[,-–]\d+)?)*)"#

    let matches = text.matches(of: referenceRegex)

    var references: [(book: String, chapter: Int, verse: String)] = []

    for match in matches {
        let halves = match.split(separator: ";")

        var bookName = ""

        for (index, half) in halves.enumerated() {
            var currentText = String(half.trimmingCharacters(in: .whitespacesAndNewlines))

            if let matchResult = currentText.firstMatch(of: referenceRegex) {
                // Fix 1: book is Substring, not Optional — use isEmpty directly
                let bookSubstring = matchResult.1
                if !bookSubstring.isEmpty {
                    bookName = bookSubstring.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if index > 0 {
                    currentText = "\(bookName) \(currentText)"
                }

                let chapter = Int(matchResult.2)!
                // Fix 2: convert Substring to String
                let verseList = String(matchResult.3)

                references.append((book: bookName, chapter: chapter, verse: verseList))
            }
        }
    }

    return references
}

// MARK: - Regex helpers

extension String {
    // Fix 3: convert NSRange → Range<String.Index> before subscripting
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
