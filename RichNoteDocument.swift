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
