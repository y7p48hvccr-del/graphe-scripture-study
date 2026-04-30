import Foundation

struct SearchResult: Identifiable {
    let id         = UUID()
    let type:      ResultType
    let reference: String
    let snippet:   String
    let moduleName: String    // which Bible/commentary it came from
    let bookNumber: Int
    let chapter:   Int
    let verse:     Int
    let noteID:    UUID?
    let modulePath: String?
    let lookupQuery: String?
    let referenceKind: ReferenceKind?

    enum ResultType: String {
        case bible       = "Bible"
        case notes       = "Notes"
        case commentary  = "Commentary"
        case reference   = "References"
        var icon: String {
            switch self {
            case .bible:      return "book.fill"
            case .notes:      return "note.text"
            case .commentary: return "text.quote"
            case .reference:  return "text.book.closed"
            }
        }
    }

    enum ReferenceKind {
        case dictionary
        case encyclopedia
    }
}

func makeSnippet(_ text: String, matching query: String) -> String {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let range = clean.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
    else { return String(clean.prefix(120)) }
    let lo = clean.index(range.lowerBound, offsetBy: -50, limitedBy: clean.startIndex) ?? clean.startIndex
    let hi = clean.index(range.upperBound,  offsetBy:  70, limitedBy: clean.endIndex)   ?? clean.endIndex
    var s  = String(clean[lo..<hi])
    if lo > clean.startIndex { s = "…" + s }
    if hi < clean.endIndex   { s = s + "…" }
    return s
}

extension Notification.Name {
    static let navigateToPassage    = Notification.Name("navigateToPassage")
    static let navigateToCommentary = Notification.Name("navigateToCommentary")
    static let navigateToNote       = Notification.Name("navigateToNote")
}

struct PassageNavigationRequest: Equatable {
    var bookNumber: Int
    var chapter: Int
    var verse: Int?
    var verses: [Int]
    var moduleName: String?

    init(
        bookNumber: Int,
        chapter: Int,
        verse: Int? = nil,
        verses: [Int] = [],
        moduleName: String? = nil
    ) {
        self.bookNumber = bookNumber
        self.chapter = chapter
        self.verse = verse
        self.verses = verses
        self.moduleName = moduleName
    }

    init(scriptureTarget: ScriptureLinkTarget, moduleName: String? = nil) {
        self.bookNumber = scriptureTarget.bookNumber
        self.chapter = scriptureTarget.chapterNumber
        self.verse = scriptureTarget.verseNumbers.first
        self.verses = scriptureTarget.verseNumbers
        self.moduleName = moduleName
    }

    init?(userInfo: [AnyHashable: Any]?) {
        guard let userInfo,
              let bookNumber = userInfo["bookNumber"] as? Int,
              let chapter = userInfo["chapter"] as? Int else {
            return nil
        }
        self.bookNumber = bookNumber
        self.chapter = chapter
        self.verse = userInfo["verse"] as? Int
        self.verses = userInfo["verses"] as? [Int] ?? []
        self.moduleName = userInfo["moduleName"] as? String
    }

    var userInfo: [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = [
            "bookNumber": bookNumber,
            "chapter": chapter
        ]
        if let verse {
            userInfo["verse"] = verse
        }
        if !verses.isEmpty {
            userInfo["verses"] = verses
        }
        if let moduleName, !moduleName.isEmpty {
            userInfo["moduleName"] = moduleName
        }
        return userInfo
    }
}
