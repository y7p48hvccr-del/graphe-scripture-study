import Foundation

struct RichNoteDocument: Codable, Equatable {
    var version: Int = 1
    var plainText: String
    var blocks: [RichNoteBlock]
    var links: [RichNoteLink]

    init(
        version: Int = 1,
        plainText: String,
        blocks: [RichNoteBlock] = [],
        links: [RichNoteLink] = []
    ) {
        self.version = version
        self.plainText = plainText
        self.blocks = blocks
        self.links = links
    }
}

struct RichNoteBlock: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var kind: RichNoteBlockKind
    var inlines: [RichNoteInline]

    init(
        id: UUID = UUID(),
        kind: RichNoteBlockKind,
        inlines: [RichNoteInline]
    ) {
        self.id = id
        self.kind = kind
        self.inlines = inlines
    }
}

enum RichNoteBlockKind: Codable, Equatable {
    case paragraph
    case heading(level: Int)
    case bulletItem(depth: Int)
    case numberedItem(depth: Int, ordinal: Int?)
}

extension RichNoteBlockKind {
    var token: String {
        switch self {
        case .paragraph:
            return "paragraph"
        case .heading(let level):
            return "heading:\(level)"
        case .bulletItem(let depth):
            return "bullet:\(depth)"
        case .numberedItem(let depth, let ordinal):
            return "numbered:\(depth):\(ordinal.map(String.init) ?? "")"
        }
    }

    init?(token: String) {
        if token == "paragraph" {
            self = .paragraph
            return
        }
        if token.hasPrefix("heading:"), let level = Int(token.dropFirst("heading:".count)) {
            self = .heading(level: level)
            return
        }
        if token.hasPrefix("bullet:"), let depth = Int(token.dropFirst("bullet:".count)) {
            self = .bulletItem(depth: depth)
            return
        }
        if token.hasPrefix("numbered:") {
            let components = token.components(separatedBy: ":")
            if components.count >= 3, let depth = Int(components[1]) {
                self = .numberedItem(depth: depth, ordinal: Int(components[2]))
                return
            }
        }
        return nil
    }
}

struct RichNoteInline: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var styles: Set<RichNoteInlineStyle> = []

    init(
        id: UUID = UUID(),
        text: String,
        styles: Set<RichNoteInlineStyle> = []
    ) {
        self.id = id
        self.text = text
        self.styles = styles
    }
}

enum RichNoteInlineStyle: String, Codable, CaseIterable, Hashable {
    case bold
    case italic
    case underline
    case highlight
}

struct RichNoteLink: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var blockID: UUID
    var utf16Range: RichTextRange
    var target: RichNoteLinkTarget

    init(
        id: UUID = UUID(),
        blockID: UUID,
        utf16Range: RichTextRange,
        target: RichNoteLinkTarget
    ) {
        self.id = id
        self.blockID = blockID
        self.utf16Range = utf16Range
        self.target = target
    }
}

struct RichTextRange: Codable, Equatable {
    var location: Int
    var length: Int

    init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

enum RichNoteLinkTarget: Codable, Equatable {
    case scripture(ScriptureLinkTarget)
    case strongs(StrongsLinkTarget)
    case url(URL)
    case note(UUID)
}

struct ScriptureLinkTarget: Codable, Equatable {
    var bookNumber: Int
    var chapterNumber: Int
    var verseNumbers: [Int]

    init(bookNumber: Int, chapterNumber: Int, verseNumbers: [Int] = []) {
        self.bookNumber = bookNumber
        self.chapterNumber = chapterNumber
        self.verseNumbers = verseNumbers
    }
}

struct StrongsLinkTarget: Codable, Equatable {
    var number: String
    var isOldTestament: Bool?

    init(number: String, isOldTestament: Bool? = nil) {
        self.number = number
        self.isOldTestament = isOldTestament
    }
}

extension RichNoteBlock {
    var plainText: String {
        inlines.map(\.text).joined()
    }
}

enum RichNoteDocumentInvariant {
    enum Violation: Equatable {
        case duplicateBlockID(UUID)
        case danglingLinkBlockID(UUID)
        case linkRangeOutOfBounds(blockID: UUID, range: RichTextRange, contentLength: Int)
        case nonCanonicalPlainText(expected: String, actual: String)
    }

    static func validate(_ document: RichNoteDocument) -> [Violation] {
        var violations: [Violation] = []
        var seenBlockIDs: Set<UUID> = []
        var blockTextLengths: [UUID: Int] = [:]

        for block in document.blocks {
            if !seenBlockIDs.insert(block.id).inserted {
                violations.append(.duplicateBlockID(block.id))
                continue
            }
            blockTextLengths[block.id] = (block.plainText as NSString).length
        }

        for link in document.links {
            guard let contentLength = blockTextLengths[link.blockID] else {
                violations.append(.danglingLinkBlockID(link.blockID))
                continue
            }
            let rangeEnd = link.utf16Range.location + link.utf16Range.length
            if link.utf16Range.location < 0 || link.utf16Range.length < 0 || rangeEnd > contentLength {
                violations.append(
                    .linkRangeOutOfBounds(
                        blockID: link.blockID,
                        range: link.utf16Range,
                        contentLength: contentLength
                    )
                )
            }
        }

        let canonicalPlainText = RichNoteBridge.canonicalPlainText(from: document.blocks)
        if document.plainText != canonicalPlainText {
            violations.append(.nonCanonicalPlainText(expected: canonicalPlainText, actual: document.plainText))
        }

        return violations
    }
}

enum RichNoteLinkCodec {
    static func url(for target: RichNoteLinkTarget) -> URL? {
        switch target {
        case .url(let url):
            return url
        case .scripture(let scripture):
            var components = URLComponents()
            components.scheme = "grapheone-scripture"
            components.host = "passage"
            components.queryItems = [
                URLQueryItem(name: "book", value: String(scripture.bookNumber)),
                URLQueryItem(name: "chapter", value: String(scripture.chapterNumber)),
                URLQueryItem(name: "verses", value: scripture.verseNumbers.map(String.init).joined(separator: ","))
            ]
            return components.url
        case .strongs(let strongs):
            var components = URLComponents()
            components.scheme = "grapheone-strongs"
            components.host = "entry"
            components.queryItems = [
                URLQueryItem(name: "number", value: strongs.number),
                URLQueryItem(name: "ot", value: strongs.isOldTestament.map { $0 ? "1" : "0" })
            ]
            return components.url
        case .note(let id):
            var components = URLComponents()
            components.scheme = "grapheone-note"
            components.host = "entry"
            components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
            return components.url
        }
    }

    static func url(from value: Any?) -> URL? {
        if let url = value as? URL {
            return url
        }
        if let string = value as? String {
            return URL(string: string)
        }
        return nil
    }

    static func target(from value: Any) -> RichNoteLinkTarget? {
        guard let url = url(from: value),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        switch url.scheme {
        case "grapheone-scripture":
            guard let bookNumber = components.queryItems?.first(where: { $0.name == "book" })?.value.flatMap(Int.init),
                  let chapterNumber = components.queryItems?.first(where: { $0.name == "chapter" })?.value.flatMap(Int.init) else {
                return .url(url)
            }
            let verseNumbers = components.queryItems?
                .first(where: { $0.name == "verses" })?
                .value?
                .split(separator: ",")
                .compactMap { Int($0) } ?? []
            return .scripture(
                ScriptureLinkTarget(
                    bookNumber: bookNumber,
                    chapterNumber: chapterNumber,
                    verseNumbers: verseNumbers
                )
            )
        case "grapheone-strongs":
            guard let number = components.queryItems?.first(where: { $0.name == "number" })?.value else {
                return .url(url)
            }
            let isOldTestament = components.queryItems?
                .first(where: { $0.name == "ot" })?
                .value
                .flatMap { value -> Bool? in
                    switch value {
                    case "1":
                        return true
                    case "0":
                        return false
                    default:
                        return nil
                    }
                }
            return .strongs(StrongsLinkTarget(number: number, isOldTestament: isOldTestament))
        case "grapheone-note":
            guard let idValue = components.queryItems?.first(where: { $0.name == "id" })?.value,
                  let noteID = UUID(uuidString: idValue) else {
                return .url(url)
            }
            return .note(noteID)
        default:
            return .url(url)
        }
    }
}
