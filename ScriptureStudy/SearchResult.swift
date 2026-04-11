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

    enum ResultType: String {
        case bible       = "Bible"
        case notes       = "Notes"
        case commentary  = "Commentary"
        var icon: String {
            switch self {
            case .bible:      return "book.fill"
            case .notes:      return "note.text"
            case .commentary: return "text.quote"
            }
        }
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
