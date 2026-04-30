import Foundation
import Testing
@testable import ScriptureStudy

struct RichNoteDocumentInvariantTests {
    @Test
    func validDocumentHasNoViolations() {
        let firstBlock = RichNoteBlock(
            id: UUID(),
            kind: .paragraph,
            inlines: [RichNoteInline(text: "Alpha")]
        )
        let secondBlock = RichNoteBlock(
            id: UUID(),
            kind: .paragraph,
            inlines: [RichNoteInline(text: "Beta")]
        )
        let document = RichNoteDocument(
            plainText: "Alpha\nBeta",
            blocks: [firstBlock, secondBlock],
            links: [
                RichNoteLink(
                    blockID: firstBlock.id,
                    utf16Range: RichTextRange(location: 0, length: 5),
                    target: .scripture(
                        ScriptureLinkTarget(bookNumber: 43, chapterNumber: 3, verseNumbers: [16])
                    )
                )
            ]
        )

        #expect(RichNoteDocumentInvariant.validate(document).isEmpty)
    }

    @Test
    func detectsDuplicateBlockIdentifiers() {
        let sharedID = UUID()
        let document = RichNoteDocument(
            plainText: "Alpha\nBeta",
            blocks: [
                RichNoteBlock(id: sharedID, kind: .paragraph, inlines: [RichNoteInline(text: "Alpha")]),
                RichNoteBlock(id: sharedID, kind: .paragraph, inlines: [RichNoteInline(text: "Beta")])
            ]
        )

        let violations = RichNoteDocumentInvariant.validate(document)

        #expect(violations.contains(.duplicateBlockID(sharedID)))
    }

    @Test
    func detectsDanglingAndOutOfBoundsLinks() {
        let validBlockID = UUID()
        let missingBlockID = UUID()
        let document = RichNoteDocument(
            plainText: "Alpha",
            blocks: [
                RichNoteBlock(id: validBlockID, kind: .paragraph, inlines: [RichNoteInline(text: "Alpha")])
            ],
            links: [
                RichNoteLink(
                    blockID: missingBlockID,
                    utf16Range: RichTextRange(location: 0, length: 1),
                    target: .note(UUID())
                ),
                RichNoteLink(
                    blockID: validBlockID,
                    utf16Range: RichTextRange(location: 3, length: 5),
                    target: .url(URL(string: "https://example.com")!)
                )
            ]
        )

        let violations = RichNoteDocumentInvariant.validate(document)

        #expect(violations.contains(.danglingLinkBlockID(missingBlockID)))
        #expect(
            violations.contains(
                .linkRangeOutOfBounds(
                    blockID: validBlockID,
                    range: RichTextRange(location: 3, length: 5),
                    contentLength: 5
                )
            )
        )
    }

    @Test
    func detectsNonCanonicalPlainText() {
        let document = RichNoteDocument(
            plainText: "stale text",
            blocks: [
                RichNoteBlock(
                    kind: .numberedItem(depth: 0, ordinal: 1),
                    inlines: [RichNoteInline(text: "Actual")]
                )
            ]
        )

        let violations = RichNoteDocumentInvariant.validate(document)

        #expect(
            violations.contains(
                .nonCanonicalPlainText(expected: "1. Actual", actual: "stale text")
            )
        )
    }

    @Test
    func linkCodecRoundTripsTypedTargets() throws {
        let noteID = UUID()
        let targets: [RichNoteLinkTarget] = [
            .scripture(ScriptureLinkTarget(bookNumber: 46, chapterNumber: 8, verseNumbers: [1, 28, 31, 32])),
            .strongs(StrongsLinkTarget(number: "G25", isOldTestament: false)),
            .note(noteID),
            .url(URL(string: "https://example.com")!)
        ]

        for target in targets {
            let url = try #require(RichNoteLinkCodec.url(for: target))
            let decoded = try #require(RichNoteLinkCodec.target(from: url))
            #expect(decoded == target)
        }
    }

    @Test
    func linkCodecTreatsMalformedCustomSchemeAsURL() throws {
        let malformed = try #require(URL(string: "grapheone-note://entry"))
        let decoded = try #require(RichNoteLinkCodec.target(from: malformed))

        #expect(decoded == .url(malformed))
    }

    @Test
    func migratedPlainNoteBuildsCanonicalStructuredDocument() {
        var note = Note()
        note.title = "Plain"
        note.content = "# Heading\n- Bullet\n2. Numbered"

        let migrated = RichNoteBridge.migratedNote(from: note)

        #expect(migrated.content == "Heading\nBullet\n2. Numbered")
        let document = try? #require(migrated.richDocument)
        #expect(document?.blocks.map(\.kind) == [
            .heading(level: 1),
            .bulletItem(depth: 0),
            .numberedItem(depth: 0, ordinal: 2)
        ])
        #expect(document?.plainText == "Heading\nBullet\n2. Numbered")
        #expect(document.map(RichNoteDocumentInvariant.validate) == [])
    }

    @Test
    func migratedNoteLeavesExistingRichDocumentUntouched() {
        let originalDocument = RichNoteDocument(
            plainText: "Already rich",
            blocks: [RichNoteBlock(kind: .paragraph, inlines: [RichNoteInline(text: "Already rich")])],
            links: []
        )
        var note = Note()
        note.title = "Rich"
        note.content = "Legacy content"
        note.richDocument = originalDocument

        let migrated = RichNoteBridge.migratedNote(from: note)

        #expect(migrated == note)
    }

    @Test
    func linkCodecDecodesTypedTargetsFromStoredStringValues() throws {
        let targets: [RichNoteLinkTarget] = [
            .scripture(ScriptureLinkTarget(bookNumber: 500, chapterNumber: 3, verseNumbers: [16])),
            .strongs(StrongsLinkTarget(number: "G25", isOldTestament: false)),
            .note(UUID())
        ]

        for target in targets {
            let url = try #require(RichNoteLinkCodec.url(for: target))
            let decoded = try #require(RichNoteLinkCodec.target(from: url.absoluteString))
            #expect(decoded == target)
        }
    }

    @Test
    func blockKindTokenRoundTripsSharedEncoding() throws {
        let kinds: [RichNoteBlockKind] = [
            .paragraph,
            .heading(level: 2),
            .bulletItem(depth: 1),
            .numberedItem(depth: 0, ordinal: 3),
            .numberedItem(depth: 2, ordinal: nil)
        ]

        for kind in kinds {
            let decoded = try #require(RichNoteBlockKind(token: kind.token))
            #expect(decoded == kind)
        }
    }

    @Test
    func documentFromPlainTextParsesMarkdownStylesAndListStructure() {
        let document = RichNoteBridge.document(fromPlainText: """
        # Heading
        - **Bold** and *italic*
        Plain text
        """)

        #expect(document.blocks.map(\.kind) == [
            .heading(level: 1),
            .bulletItem(depth: 0),
            .paragraph
        ])
        #expect(document.blocks[0].plainText == "Heading")
        #expect(document.blocks[1].inlines.map(\.text) == ["Bold", " and ", "italic"])
        #expect(document.blocks[1].inlines[0].styles == [.bold])
        #expect(document.blocks[1].inlines[1].styles.isEmpty)
        #expect(document.blocks[1].inlines[2].styles == [.italic])
        #expect(document.plainText == "Heading\nBold and italic\nPlain text")
        #expect(RichNoteDocumentInvariant.validate(document).isEmpty)
    }
}
