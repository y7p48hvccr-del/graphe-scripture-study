#if os(macOS)
import AppKit
import Testing
@testable import ScriptureStudy

struct RichNoteEditorBridgeTests {
    @Test
    func roundTripPreservesLinksByBlockIdentifier() {
        let firstBlockID = UUID()
        let secondBlockID = UUID()
        let document = RichNoteDocument(
            plainText: "Alpha\nBeta",
            blocks: [
                RichNoteBlock(id: firstBlockID, kind: .paragraph, inlines: [RichNoteInline(text: "Alpha")]),
                RichNoteBlock(id: secondBlockID, kind: .paragraph, inlines: [RichNoteInline(text: "Beta")])
            ],
            links: [
                RichNoteLink(
                    blockID: secondBlockID,
                    utf16Range: RichTextRange(location: 0, length: 4),
                    target: .strongs(StrongsLinkTarget(number: "G25", isOldTestament: false))
                ),
                RichNoteLink(
                    blockID: firstBlockID,
                    utf16Range: RichTextRange(location: 0, length: 5),
                    target: .scripture(
                        ScriptureLinkTarget(bookNumber: 43, chapterNumber: 3, verseNumbers: [16])
                    )
                )
            ]
        )

        let attributed = RichNoteEditorBridge.attributedString(
            from: document,
            baseFont: .systemFont(ofSize: 14)
        )
        let roundTripped = RichNoteEditorBridge.document(
            from: attributed,
            baseFont: .systemFont(ofSize: 14)
        )

        #expect(RichNoteDocumentInvariant.validate(roundTripped).isEmpty)
        #expect(roundTripped.plainText == "Alpha\nBeta")
        #expect(roundTripped.links.count == 2)

        let scriptureLink = roundTripped.links.first {
            if case .scripture = $0.target { return true }
            return false
        }
        let strongsLink = roundTripped.links.first {
            if case .strongs = $0.target { return true }
            return false
        }

        #expect(scriptureLink?.blockID == roundTripped.blocks[0].id)
        #expect(strongsLink?.blockID == roundTripped.blocks[1].id)
    }

    @Test
    func roundTripPreservesInlineStyles() throws {
        let attributed = NSMutableAttributedString(
            string: "Styled",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 15),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.35)
            ]
        )

        let document = RichNoteEditorBridge.document(
            from: attributed,
            baseFont: .systemFont(ofSize: 15)
        )
        let styles = try #require(document.blocks.first?.inlines.first?.styles)

        #expect(styles.contains(.bold))
        #expect(styles.contains(.underline))
        #expect(styles.contains(.highlight))
    }

    @Test
    func roundTripPreservesStructuredBlocksAndCanonicalPlainText() {
        let attributed = NSMutableAttributedString()
        attributed.append(NSAttributedString(
            string: "Heading\n",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 18),
                .richNoteBlockKind: "heading:1"
            ]
        ))
        attributed.append(NSAttributedString(
            string: "Bullet item\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .richNoteBlockKind: "bullet:0"
            ]
        ))
        attributed.append(NSAttributedString(
            string: "Numbered item",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .richNoteBlockKind: "numbered:0:2"
            ]
        ))

        let document = RichNoteEditorBridge.document(
            from: attributed,
            baseFont: .systemFont(ofSize: 14)
        )

        #expect(document.blocks.map(\.kind) == [
            .heading(level: 1),
            .bulletItem(depth: 0),
            .numberedItem(depth: 0, ordinal: 2)
        ])
        #expect(document.plainText == "Heading\nBullet item\n2. Numbered item")
        #expect(RichNoteDocumentInvariant.validate(document).isEmpty)
    }

    @Test
    func malformedBlockKindTokenFallsBackToVisibleParagraphSyntax() {
        let attributed = NSMutableAttributedString(
            string: "### Visible heading",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .richNoteBlockKind: "heading:not-a-number"
            ]
        )

        let document = RichNoteEditorBridge.document(
            from: attributed,
            baseFont: .systemFont(ofSize: 14)
        )

        #expect(document.blocks.count == 1)
        #expect(document.blocks.first?.kind == .heading(level: 3))
        #expect(document.blocks.first?.inlines.map(\.text).joined() == "Visible heading")
        #expect(document.plainText == "Visible heading")
    }

    @Test
    func bulletMarkerDotParsesAsBulletWithoutLeakingPrefixIntoContent() {
        let attributed = NSMutableAttributedString(
            string: "• Bullet item",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .richNoteBlockKind: "bullet:0"
            ]
        )

        let document = RichNoteEditorBridge.document(
            from: attributed,
            baseFont: .systemFont(ofSize: 14)
        )

        #expect(document.blocks.count == 1)
        #expect(document.blocks.first?.kind == .bulletItem(depth: 0))
        #expect(document.blocks.first?.inlines.map(\.text).joined() == "Bullet item")
        #expect(document.plainText == "Bullet item")
    }

    @Test
    func emptyStructuredBlocksRoundTripWithCanonicalPlainText() {
        let document = RichNoteDocument(
            plainText: "\n",
            blocks: [
                RichNoteBlock(kind: .paragraph, inlines: [RichNoteInline(text: "")]),
                RichNoteBlock(kind: .bulletItem(depth: 0), inlines: [RichNoteInline(text: "")])
            ],
            links: []
        )

        let attributed = RichNoteEditorBridge.attributedString(
            from: document,
            baseFont: .systemFont(ofSize: 14)
        )
        let roundTripped = RichNoteEditorBridge.document(
            from: attributed,
            baseFont: .systemFont(ofSize: 14)
        )

        #expect(roundTripped.blocks.map(\.kind) == [.paragraph, .bulletItem(depth: 0)])
        #expect(roundTripped.blocks.map { $0.inlines.map(\.text).joined() } == ["", ""])
        #expect(roundTripped.plainText == "\n")
        #expect(RichNoteDocumentInvariant.validate(roundTripped).isEmpty)
    }
}
#endif
