import Foundation

#if os(macOS)
import AppKit

enum RichNoteEditorBridge {
    static func attributedString(
        from document: RichNoteDocument,
        baseFont: NSFont
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()

        for (index, block) in document.blocks.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = blockIndent(for: block.kind)
            paragraph.firstLineHeadIndent = blockFirstLineIndent(for: block.kind)

            let blockFont = font(for: block.kind, baseFont: baseFont)
            let prefix = renderedPrefix(for: block.kind)
            if !prefix.isEmpty {
                let prefixAttributes: [NSAttributedString.Key: Any] = [
                    .font: blockFont,
                    .paragraphStyle: paragraph
                ]
                result.append(NSAttributedString(string: prefix, attributes: prefixAttributes))
            }

            for inline in block.inlines {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font(for: inline.styles, baseFont: blockFont),
                    .paragraphStyle: paragraph
                ]
                result.append(NSAttributedString(string: inline.text, attributes: attributes))
            }
        }

        applyLinks(document.links, to: result)
        return result
    }

    static func document(
        from attributedString: NSAttributedString,
        baseFont: NSFont
    ) -> RichNoteDocument {
        let string = attributedString.string
        let nsString = string as NSString
        let paragraphRanges = paragraphRanges(in: nsString)

        var blocks: [RichNoteBlock] = []
        var links: [RichNoteLink] = []

        for range in paragraphRanges {
            var paragraphText = nsString.substring(with: range)
            if paragraphText.hasSuffix("\n") {
                paragraphText.removeLast()
            }

            let blockID = UUID()
            let kind = inferBlockKind(from: paragraphText)
            let contentText = stripRenderedPrefix(from: paragraphText, for: kind)
            let contentRange = adjustedContentRange(for: range, originalText: paragraphText, kind: kind)
            let inlines = inlines(
                from: attributedString,
                contentText: contentText,
                contentRange: contentRange,
                baseFont: baseFont,
                blockKind: kind
            )

            blocks.append(RichNoteBlock(id: blockID, kind: kind, inlines: inlines))
            links.append(contentsOf: linkTargets(in: attributedString, contentRange: contentRange, blockID: blockID))
        }

        let document = RichNoteDocument(
            plainText: RichNoteBridge.plainText(
                from: RichNoteDocument(plainText: string, blocks: blocks, links: links)
            ),
            blocks: blocks,
            links: links
        )
        return document
    }

    private static func inlines(
        from attributedString: NSAttributedString,
        contentText: String,
        contentRange: NSRange,
        baseFont: NSFont,
        blockKind: RichNoteBlockKind
    ) -> [RichNoteInline] {
        guard contentRange.length > 0 else { return [RichNoteInline(text: "")] }

        var result: [RichNoteInline] = []
        attributedString.enumerateAttributes(in: contentRange, options: []) { attributes, range, _ in
            let text = (attributedString.string as NSString).substring(with: range)
            let font = (attributes[.font] as? NSFont) ?? font(for: blockKind, baseFont: baseFont)
            let styles = inlineStyles(for: font, against: font(for: blockKind, baseFont: baseFont))
            result.append(RichNoteInline(text: text, styles: styles))
        }

        return result.isEmpty ? [RichNoteInline(text: contentText)] : result
    }

    private static func linkTargets(
        in attributedString: NSAttributedString,
        contentRange: NSRange,
        blockID: UUID
    ) -> [RichNoteLink] {
        guard contentRange.length > 0 else { return [] }

        var result: [RichNoteLink] = []
        attributedString.enumerateAttribute(.link, in: contentRange, options: []) { value, range, _ in
            guard let value else { return }
            let localRange = RichTextRange(location: range.location - contentRange.location, length: range.length)
            if let url = value as? URL {
                result.append(RichNoteLink(blockID: blockID, utf16Range: localRange, target: .url(url)))
            } else if let string = value as? String, let url = URL(string: string) {
                result.append(RichNoteLink(blockID: blockID, utf16Range: localRange, target: .url(url)))
            }
        }
        return result
    }

    private static func paragraphRanges(in text: NSString) -> [NSRange] {
        guard text.length > 0 else { return [NSRange(location: 0, length: 0)] }

        var ranges: [NSRange] = []
        var location = 0
        while location < text.length {
            let range = text.paragraphRange(for: NSRange(location: location, length: 0))
            ranges.append(range)
            location = NSMaxRange(range)
        }
        return ranges
    }

    private static func inferBlockKind(from paragraphText: String) -> RichNoteBlockKind {
        let trimmed = paragraphText.trimmingCharacters(in: .newlines)
        if let heading = parseHeading(from: trimmed) {
            return heading
        }
        if let bullet = parseBullet(from: trimmed) {
            return bullet
        }
        return .paragraph
    }

    private static func parseHeading(from text: String) -> RichNoteBlockKind? {
        let hashes = text.prefix { $0 == "#" }
        let level = hashes.count
        guard level > 0, level <= 6 else { return nil }
        let remainder = String(text.dropFirst(level))
        guard remainder.hasPrefix(" ") else { return nil }
        return .heading(level: level)
    }

    private static func parseBullet(from text: String) -> RichNoteBlockKind? {
        let trimmed = text.drop { $0 == " " || $0 == "\t" }
        guard trimmed.hasPrefix("- ") else { return nil }
        let depth = max(0, (text.count - trimmed.count) / 2)
        return .bulletItem(depth: depth)
    }

    private static func stripRenderedPrefix(from text: String, for kind: RichNoteBlockKind) -> String {
        switch kind {
        case .paragraph:
            return text
        case .heading(let level):
            return String(text.dropFirst(min(text.count, level + 1)))
        case .bulletItem:
            let trimmed = text.drop { $0 == " " || $0 == "\t" }
            return String(trimmed.dropFirst(min(trimmed.count, 2)))
        case .numberedItem:
            return text
        }
    }

    private static func adjustedContentRange(
        for paragraphRange: NSRange,
        originalText: String,
        kind: RichNoteBlockKind
    ) -> NSRange {
        let newlineTrimmedLength = originalText.hasSuffix("\n") ? 1 : 0
        let effectiveLength = paragraphRange.length - newlineTrimmedLength
        let prefixLength: Int

        switch kind {
        case .paragraph:
            prefixLength = 0
        case .heading(let level):
            prefixLength = min(effectiveLength, level + 1)
        case .bulletItem:
            let leadingSpaces = originalText.prefix { $0 == " " || $0 == "\t" }.count
            prefixLength = min(effectiveLength, leadingSpaces + 2)
        case .numberedItem:
            prefixLength = 0
        }

        return NSRange(
            location: paragraphRange.location + prefixLength,
            length: max(0, effectiveLength - prefixLength)
        )
    }

    private static func renderedPrefix(for kind: RichNoteBlockKind) -> String {
        switch kind {
        case .paragraph:
            return ""
        case .heading(let level):
            return String(repeating: "#", count: level) + " "
        case .bulletItem(let depth):
            return String(repeating: "  ", count: max(0, depth)) + "- "
        case .numberedItem(_, let ordinal):
            if let ordinal {
                return "\(ordinal). "
            }
            return ""
        }
    }

    private static func blockIndent(for kind: RichNoteBlockKind) -> CGFloat {
        switch kind {
        case .bulletItem(let depth):
            return CGFloat(18 + (depth * 18))
        case .numberedItem(let depth, _):
            return CGFloat(22 + (depth * 18))
        default:
            return 0
        }
    }

    private static func blockFirstLineIndent(for kind: RichNoteBlockKind) -> CGFloat {
        switch kind {
        case .bulletItem(let depth):
            return CGFloat(depth * 18)
        case .numberedItem(let depth, _):
            return CGFloat(depth * 18)
        default:
            return 0
        }
    }

    private static func font(for kind: RichNoteBlockKind, baseFont: NSFont) -> NSFont {
        switch kind {
        case .heading(let level):
            let sizeBoost = max(2, 8 - level)
            return NSFont.boldSystemFont(ofSize: baseFont.pointSize + CGFloat(sizeBoost))
        default:
            return baseFont
        }
    }

    private static func font(for styles: Set<RichNoteInlineStyle>, baseFont: NSFont) -> NSFont {
        var traits = NSFontDescriptor.SymbolicTraits()
        if styles.contains(.bold) {
            traits.insert(.bold)
        }
        if styles.contains(.italic) {
            traits.insert(.italic)
        }

        guard let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) else {
            return baseFont
        }
        return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
    }

    private static func inlineStyles(for font: NSFont, against baseFont: NSFont) -> Set<RichNoteInlineStyle> {
        let traits = font.fontDescriptor.symbolicTraits
        let baseTraits = baseFont.fontDescriptor.symbolicTraits
        var styles: Set<RichNoteInlineStyle> = []

        if traits.contains(.bold) && !baseTraits.contains(.bold) {
            styles.insert(.bold)
        }
        if traits.contains(.italic) && !baseTraits.contains(.italic) {
            styles.insert(.italic)
        }
        return styles
    }

    private static func applyLinks(_ links: [RichNoteLink], to attributedString: NSMutableAttributedString) {
        for link in links {
            guard let target = targetValue(for: link.target) else { continue }
            let blockRange = blockContentRange(for: link.blockID, in: attributedString.string)
            guard blockRange.location != NSNotFound else { continue }
            let resolvedRange = NSRange(
                location: blockRange.location + link.utf16Range.location,
                length: link.utf16Range.length
            )
            guard NSMaxRange(resolvedRange) <= attributedString.length else { continue }
            attributedString.addAttribute(.link, value: target, range: resolvedRange)
        }
    }

    private static func targetValue(for target: RichNoteLinkTarget) -> Any? {
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

    private static func blockContentRange(for blockID: UUID, in fullText: String) -> NSRange {
        let document = RichNoteBridge.document(fromPlainText: fullText)
        let blocks = document.blocks
        var location = 0

        for (index, block) in blocks.enumerated() {
            let text = block.inlines.map(\.text).joined()
            let prefix = renderedPrefix(for: block.kind)
            let length = (prefix + text).utf16.count
            let contentLocation = location + prefix.utf16.count
            if block.id == blockID {
                return NSRange(location: contentLocation, length: text.utf16.count)
            }
            location += length
            if index < blocks.count - 1 {
                location += 1
            }
        }

        return NSRange(location: NSNotFound, length: 0)
    }
}
#endif
