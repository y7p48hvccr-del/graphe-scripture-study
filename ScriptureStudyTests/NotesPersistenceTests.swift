#if os(macOS)
import Foundation
import Testing
@testable import ScriptureStudy

@MainActor
struct NotesPersistenceTests {
    @Test
    func plainNoteRoundTripsThroughPersistentStore() throws {
        let storageDirectory = makeTemporaryNotesDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let manager = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )
        var note = Note()
        note.title = "Persistence"
        note.content = "Plain content"
        note.bookNumber = 43
        note.chapterNumber = 3
        note.verseNumbers = [16]

        manager.save(note)

        let reloadedManager = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )
        let reloaded = try #require(reloadedManager.notes.first(where: { $0.id == note.id }))

        #expect(reloaded.title == "Persistence")
        #expect(reloaded.content == "Plain content")
        #expect(reloaded.richDocument == nil)
        #expect(reloaded.bookNumber == 43)
        #expect(reloaded.chapterNumber == 3)
        #expect(reloaded.verseNumbers == [16])
    }

    @Test
    func richNoteRoundTripsThroughPersistentStore() throws {
        let storageDirectory = makeTemporaryNotesDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let blockID = UUID()
        let richDocument = RichNoteDocument(
            plainText: "Jn 3:16\nG25",
            blocks: [
                RichNoteBlock(id: blockID, kind: .paragraph, inlines: [
                    RichNoteInline(text: "Jn 3:16"),
                    RichNoteInline(text: "\n"),
                    RichNoteInline(text: "G25")
                ])
            ],
            links: [
                RichNoteLink(
                    blockID: blockID,
                    utf16Range: RichTextRange(location: 0, length: 7),
                    target: .scripture(
                        ScriptureLinkTarget(bookNumber: 500, chapterNumber: 3, verseNumbers: [16])
                    )
                ),
                RichNoteLink(
                    blockID: blockID,
                    utf16Range: RichTextRange(location: 8, length: 3),
                    target: .strongs(
                        StrongsLinkTarget(number: "G25", isOldTestament: false)
                    )
                )
            ]
        )

        let manager = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )
        var note = Note()
        note.title = "Rich"
        note.content = richDocument.plainText
        note.richDocument = richDocument

        manager.save(note)

        let reloadedManager = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )
        let reloaded = try #require(reloadedManager.notes.first(where: { $0.id == note.id }))
        let reloadedDocument = try #require(reloaded.richDocument)

        #expect(reloaded.content == richDocument.plainText)
        #expect(reloaded.plainTextContent == richDocument.plainText)
        #expect(reloadedDocument == richDocument)
        #expect(RichNoteDocumentInvariant.validate(reloadedDocument).isEmpty)
    }

    @Test
    func malformedRichEnvelopeFallsBackToPlainContentOnLoad() throws {
        let storageDirectory = makeTemporaryNotesDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let noteID = UUID()
        let updatedAt = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_000))
        let malformedFile = """
        Broken Rich Note
        0
        0

        \(updatedAt)
        \(noteID.uuidString)
        unlocked
        active

        ---
        __RICH_NOTE_JSON__
        { not valid json
        """
        try malformedFile.write(
            to: storageDirectory.appendingPathComponent("Broken Rich Note.txt"),
            atomically: true,
            encoding: .utf8
        )

        let manager = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )
        let reloaded = try #require(manager.notes.first(where: { $0.id == noteID }))

        #expect(reloaded.richDocument == nil)
        #expect(reloaded.content == "__RICH_NOTE_JSON__\n{ not valid json")
    }

    @Test
    func legacyNoteFormatWithoutArchiveFieldsStillParses() throws {
        let updatedAt = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_100))
        let noteID = UUID()
        let legacyFile = """
        Legacy Note
        500
        3
        16,17
        \(updatedAt)
        \(noteID.uuidString)
        locked
        ---
        Legacy body
        """

        let parsed = try #require(Note.parse(from: legacyFile))

        #expect(parsed.title == "Legacy Note")
        #expect(parsed.bookNumber == 500)
        #expect(parsed.chapterNumber == 3)
        #expect(parsed.verseNumbers == [16, 17])
        #expect(parsed.isLocked)
        #expect(!parsed.isArchived)
        #expect(parsed.deletedAt == nil)
        #expect(parsed.content == "Legacy body")
        #expect(parsed.richDocument == nil)
    }

    private func makeTemporaryNotesDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptureStudyTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
#endif
