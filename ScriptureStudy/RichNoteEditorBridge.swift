import Foundation

#if os(macOS)
import AppKit

extension NSAttributedString.Key {
    static let richNoteBlockKind = NSAttributedString.Key("RichNoteBlockKind")
}

enum RichNoteEditorBridge {
    private static let noteHighlightColor = NSColor.systemYellow.withAlphaComponent(0.35)

    static func attributedString(
        from document: RichNoteDocument,
        baseFont: NSFont
    ) -> NSAttributedString {
#if DEBUG
        let violations = RichNoteDocumentInvariant.validate(document)
        assert(violations.isEmpty, "Attempted to render invalid RichNoteDocument: \(violations)")
#endif
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
                    .paragraphStyle: paragraph,
                    .richNoteBlockKind: block.kind.token
                ]
                result.append(NSAttributedString(string: prefix, attributes: prefixAttributes))
            }

            for inline in block.inlines {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font(for: inline.styles, baseFont: blockFont),
                    .paragraphStyle: paragraph,
                    .richNoteBlockKind: block.kind.token
                ]
                if inline.styles.contains(.underline) {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                if inline.styles.contains(.highlight) {
                    attributes[.backgroundColor] = noteHighlightColor
                }
                result.append(NSAttributedString(string: inline.text, attributes: attributes))
            }
        }

        applyLinks(document, to: result)
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
            let rawParagraphText = nsString.substring(with: range)
            let paragraphText = rawParagraphText.hasSuffix("\n")
                ? String(rawParagraphText.dropLast())
                : rawParagraphText

            let blockID = UUID()
            let kind = blockKind(in: attributedString, paragraphRange: range, paragraphText: paragraphText)
            let contentText = stripRenderedPrefix(from: paragraphText, for: kind)
            let contentRange = adjustedContentRange(for: range, originalText: rawParagraphText, kind: kind)
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
            plainText: RichNoteBridge.canonicalPlainText(from: blocks),
            blocks: blocks,
            links: links
        )
#if DEBUG
        let violations = RichNoteDocumentInvariant.validate(document)
        assert(violations.isEmpty, "RichNoteEditorBridge produced invalid document: \(violations)")
#endif
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
            let resolvedFont = (attributes[.font] as? NSFont) ?? font(for: blockKind, baseFont: baseFont)
            let styles = inlineStyles(
                from: attributes,
                font: resolvedFont,
                against: font(for: blockKind, baseFont: baseFont)
            )
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
            if let target = linkTarget(from: value) {
                result.append(RichNoteLink(blockID: blockID, utf16Range: localRange, target: target))
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
        if let numbered = parseNumberedItem(from: trimmed) {
            return numbered
        }
        return .paragraph
    }

    private static func blockKind(
        in attributedString: NSAttributedString,
        paragraphRange: NSRange,
        paragraphText: String
    ) -> RichNoteBlockKind {
        if paragraphRange.length > 0,
           let token = attributedString.attribute(.richNoteBlockKind, at: paragraphRange.location, effectiveRange: nil) as? String,
           let kind = RichNoteBlockKind(token: token) {
            return kind
        }
        return inferBlockKind(from: paragraphText)
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
        guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") else { return nil }
        let depth = max(0, (text.count - trimmed.count) / 2)
        return .bulletItem(depth: depth)
    }

    private static func parseNumberedItem(from text: String) -> RichNoteBlockKind? {
        let trimmed = text.drop { $0 == " " || $0 == "\t" }
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let remainder = trimmed.dropFirst(digits.count)
        guard remainder.hasPrefix(". ") else { return nil }
        let depth = max(0, (text.count - trimmed.count) / 2)
        return .numberedItem(depth: depth, ordinal: Int(digits))
    }

    private static func stripRenderedPrefix(from text: String, for kind: RichNoteBlockKind) -> String {
        switch kind {
        case .paragraph:
            return text
        case .heading(let level):
            if text.hasPrefix(String(repeating: "#", count: level) + " ") {
                return String(text.dropFirst(min(text.count, level + 1)))
            }
            return text
        case .bulletItem:
            let trimmed = text.drop { $0 == " " || $0 == "\t" }
            if trimmed.hasPrefix("• ") || trimmed.hasPrefix("- ") {
                return String(trimmed.dropFirst(min(trimmed.count, 2)))
            }
            return text
        case .numberedItem:
            let trimmed = text.drop { $0 == " " || $0 == "\t" }
            let digits = trimmed.prefix { $0.isNumber }
            guard !digits.isEmpty else { return text }
            let remainder = trimmed.dropFirst(digits.count)
            if remainder.hasPrefix(". ") {
                return String(remainder.dropFirst(2))
            }
            guard remainder.hasPrefix(" ") else { return text }
            return String(remainder.dropFirst())
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
            let markdownPrefix = String(repeating: "#", count: level) + " "
            prefixLength = originalText.hasPrefix(markdownPrefix) ? min(effectiveLength, level + 1) : 0
        case .bulletItem:
            let leadingSpaces = originalText.prefix { $0 == " " || $0 == "\t" }.count
            let trimmed = originalText.dropFirst(leadingSpaces)
            let markerLength = (trimmed.hasPrefix("• ") || trimmed.hasPrefix("- ")) ? 2 : 0
            prefixLength = min(effectiveLength, leadingSpaces + markerLength)
        case .numberedItem:
            let leadingSpaces = originalText.prefix { $0 == " " || $0 == "\t" }.count
            let trimmed = originalText.dropFirst(leadingSpaces)
            let digits = trimmed.prefix { $0.isNumber }
            if digits.isEmpty {
                prefixLength = 0
            } else {
                let remainder = trimmed.dropFirst(digits.count)
                if remainder.hasPrefix(". ") {
                    prefixLength = min(effectiveLength, leadingSpaces + digits.count + 2)
                } else {
                    prefixLength = remainder.hasPrefix(" ")
                        ? min(effectiveLength, leadingSpaces + digits.count + 1)
                        : 0
                }
            }
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
        case .heading:
            return ""
        case .bulletItem(let depth):
            return String(repeating: "  ", count: max(0, depth)) + "• "
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

        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
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

    private static func inlineStyles(
        from attributes: [NSAttributedString.Key: Any],
        font: NSFont,
        against baseFont: NSFont
    ) -> Set<RichNoteInlineStyle> {
        var styles = inlineStyles(for: font, against: baseFont)

        if let underlineStyle = attributes[.underlineStyle] as? Int,
           underlineStyle != 0 {
            styles.insert(.underline)
        }
        if attributes[.backgroundColor] != nil {
            styles.insert(.highlight)
        }

        return styles
    }

    private static func applyLinks(_ document: RichNoteDocument, to attributedString: NSMutableAttributedString) {
        let blockRanges = blockContentRanges(in: attributedString.string, blocks: document.blocks)

        for link in document.links {
            guard let target = RichNoteLinkCodec.url(for: link.target),
                  let blockRange = blockRanges[link.blockID] else { continue }

            guard link.utf16Range.location >= 0, link.utf16Range.length >= 0 else { continue }
            let resolvedRange = NSRange(location: blockRange.location + link.utf16Range.location, length: link.utf16Range.length)
            guard NSMaxRange(resolvedRange) <= NSMaxRange(blockRange) else { continue }
            attributedString.addAttributes([
                .link: target,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.linkColor
            ], range: resolvedRange)
        }
    }

    private static func linkTarget(from value: Any) -> RichNoteLinkTarget? {
        RichNoteLinkCodec.target(from: value)
    }

    private static func blockContentRanges(in fullText: String, blocks: [RichNoteBlock]) -> [UUID: NSRange] {
        let nsText = fullText as NSString
        guard !blocks.isEmpty else { return [:] }

        if nsText.length == 0 {
            if let block = blocks.first {
                return [block.id: NSRange(location: 0, length: 0)]
            }
            return [:]
        }

        var ranges: [UUID: NSRange] = [:]
        var location = 0

        for block in blocks {
            guard location < nsText.length else { break }
            let paragraphRange = nsText.paragraphRange(for: NSRange(location: location, length: 0))
            var paragraphText = nsText.substring(with: paragraphRange)
            if paragraphText.hasSuffix("\n") {
                paragraphText.removeLast()
            }
            ranges[block.id] = adjustedContentRange(for: paragraphRange, originalText: paragraphText, kind: block.kind)
            location = NSMaxRange(paragraphRange)
        }

        return ranges
    }

}
#endif
