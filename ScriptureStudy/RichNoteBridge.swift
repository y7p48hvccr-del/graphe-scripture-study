import Foundation

enum RichNoteBridge {
    static func document(fromPlainText text: String) -> RichNoteDocument {
        let lines = text.components(separatedBy: "\n")
        let blocks = lines.map(makeBlock)
        return RichNoteDocument(
            plainText: canonicalPlainText(from: blocks),
            blocks: blocks,
            links: []
        )
    }

    static func plainText(from document: RichNoteDocument) -> String {
        canonicalPlainText(from: document.blocks)
    }

    static func migratedNote(from note: Note) -> Note {
        guard note.richDocument == nil else { return note }
        var updated = note
        let document = document(fromPlainText: note.content)
        updated.richDocument = document
        updated.content = document.plainText
        return updated
    }

    private static func makeBlock(from line: String) -> RichNoteBlock {
        if let heading = parseHeading(line) {
            return heading
        }
        if let bullet = parseBullet(line) {
            return bullet
        }
        if let numbered = parseNumbered(line) {
            return numbered
        }
        return RichNoteBlock(kind: .paragraph, inlines: parseInlines(in: line))
    }

    private static func parseHeading(_ line: String) -> RichNoteBlock? {
        let hashes = line.prefix { $0 == "#" }
        let level = hashes.count
        guard level > 0, level <= 6 else { return nil }
        let remainder = String(line.dropFirst(level))
        guard remainder.hasPrefix(" ") else { return nil }
        return RichNoteBlock(
            kind: .heading(level: level),
            inlines: parseInlines(in: String(remainder.dropFirst()))
        )
    }

    private static func parseBullet(_ line: String) -> RichNoteBlock? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard trimmed.hasPrefix("- ") else { return nil }
        let depth = max(0, (line.count - trimmed.count) / 2)
        return RichNoteBlock(
            kind: .bulletItem(depth: depth),
            inlines: parseInlines(in: String(trimmed.dropFirst(2)))
        )
    }

    private static func parseNumbered(_ line: String) -> RichNoteBlock? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let remainder = trimmed.dropFirst(digits.count)
        let contentStart: String.Index
        if remainder.hasPrefix(". ") {
            contentStart = remainder.index(remainder.startIndex, offsetBy: 2)
        } else if remainder.hasPrefix(" ") {
            contentStart = remainder.index(after: remainder.startIndex)
        } else {
            return nil
        }
        let depth = max(0, (line.count - trimmed.count) / 2)
        return RichNoteBlock(
            kind: .numberedItem(depth: depth, ordinal: Int(digits)),
            inlines: parseInlines(in: String(remainder[contentStart...]))
        )
    }

    private static func parseInlines(in text: String) -> [RichNoteInline] {
        guard !text.isEmpty else { return [RichNoteInline(text: "")] }

        var result: [RichNoteInline] = []
        var index = text.startIndex

        while index < text.endIndex {
            if let range = text[index...].range(of: "**"), range.lowerBound == index,
               let end = text[range.upperBound...].range(of: "**") {
                let content = String(text[range.upperBound..<end.lowerBound])
                result.append(RichNoteInline(text: content, styles: [.bold]))
                index = end.upperBound
                continue
            }

            if text[index] == "*",
               let end = text[text.index(after: index)...].firstIndex(of: "*") {
                let content = String(text[text.index(after: index)..<end])
                result.append(RichNoteInline(text: content, styles: [.italic]))
                index = text.index(after: end)
                continue
            }

            let nextSpecial = text[index...].firstIndex(where: { $0 == "*" }) ?? text.endIndex
            let content = String(text[index..<nextSpecial])
            if !content.isEmpty {
                result.append(RichNoteInline(text: content))
            }
            index = nextSpecial
        }

        return result.isEmpty ? [RichNoteInline(text: text)] : result
    }

    static func canonicalPlainText(from blocks: [RichNoteBlock]) -> String {
        blocks.map { block in
            let text = block.inlines.map(\.text).joined()
            switch block.kind {
            case .paragraph:
                return text
            case .heading:
                return text
            case .bulletItem:
                return text
            case .numberedItem(_, let ordinal):
                if let ordinal {
                    return "\(ordinal). \(text)"
                }
                return text
            }
        }
        .joined(separator: "\n")
    }
}
