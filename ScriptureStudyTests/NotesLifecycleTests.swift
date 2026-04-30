#if os(macOS)
import Foundation
import Testing
@testable import ScriptureStudy

@MainActor
struct NotesLifecycleTests {
    @Test
    func deleteAndRestorePersistTrashStateAndSelectionFallback() throws {
        let storageDirectory = makeTemporaryNotesDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let manager = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )

        var first = Note()
        first.title = "First"
        first.content = "Alpha"
        first.bookNumber = 43
        first.chapterNumber = 3
        first.verseNumbers = [16]

        var second = Note()
        second.title = "Second"
        second.content = "Beta"
        second.bookNumber = 43
        second.chapterNumber = 3
        second.verseNumbers = [17]

        manager.save(first)
        manager.save(second)
        manager.selectedNote = manager.notes.first(where: { $0.id == first.id })

        let savedFirst = try #require(manager.notes.first(where: { $0.id == first.id }))
        let savedSecond = try #require(manager.notes.first(where: { $0.id == second.id }))

        manager.delete(savedFirst)

        let trashed = try #require(manager.notes.first(where: { $0.id == savedFirst.id }))
        #expect(trashed.deletedAt != nil)
        #expect(manager.selectedNote?.id == savedSecond.id)
        #expect(manager.notes(forBook: 43, chapter: 3, verse: 16).isEmpty)

        let reloadedAfterDelete = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )
        let reloadedTrashed = try #require(reloadedAfterDelete.notes.first(where: { $0.id == savedFirst.id }))
        #expect(reloadedTrashed.deletedAt != nil)
        #expect(reloadedAfterDelete.notes(forBook: 43, chapter: 3, verse: 16).isEmpty)

        reloadedAfterDelete.restore(reloadedTrashed)

        let reloadedAfterRestore = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )
        let restored = try #require(reloadedAfterRestore.notes.first(where: { $0.id == savedFirst.id }))
        #expect(restored.deletedAt == nil)
        #expect(reloadedAfterRestore.notes(forBook: 43, chapter: 3, verse: 16).map(\.id) == [savedFirst.id])
    }

    @Test
    func archiveAndUnarchivePersistAndAffectVerseVisibility() throws {
        let storageDirectory = makeTemporaryNotesDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let manager = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )

        var note = Note()
        note.title = "Archive Me"
        note.content = "Gamma"
        note.bookNumber = 19
        note.chapterNumber = 23
        note.verseNumbers = [1]
        manager.save(note)

        let saved = try #require(manager.notes.first(where: { $0.id == note.id }))
        #expect(manager.notes(forBook: 19, chapter: 23, verse: 1).map(\.id) == [saved.id])

        manager.archive(saved)

        let reloadedArchived = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )
        let archived = try #require(reloadedArchived.notes.first(where: { $0.id == saved.id }))
        #expect(archived.isArchived)
        #expect(reloadedArchived.notes(forBook: 19, chapter: 23, verse: 1).isEmpty)

        reloadedArchived.unarchive(archived)

        let reloadedUnarchived = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )
        let unarchived = try #require(reloadedUnarchived.notes.first(where: { $0.id == saved.id }))
        #expect(!unarchived.isArchived)
        #expect(reloadedUnarchived.notes(forBook: 19, chapter: 23, verse: 1).map(\.id) == [saved.id])
    }

    @Test
    func emptyTrashRemovesFilesPermanently() throws {
        let storageDirectory = makeTemporaryNotesDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let manager = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )

        var first = Note()
        first.title = "Trash One"
        first.content = "One"

        var second = Note()
        second.title = "Trash Two"
        second.content = "Two"

        manager.save(first)
        manager.save(second)

        let savedFirst = try #require(manager.notes.first(where: { $0.id == first.id }))
        let savedSecond = try #require(manager.notes.first(where: { $0.id == second.id }))

        manager.delete(savedFirst)
        manager.delete(savedSecond)

        #expect(textFileCount(in: storageDirectory) == 2)

        manager.emptyTrash()

        #expect(manager.notes.isEmpty)
        #expect(textFileCount(in: storageDirectory) == 0)
    }

    @Test
    func duplicateTitlesUseDistinctFilenamesAndPreserveBothNotes() throws {
        let storageDirectory = makeTemporaryNotesDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let manager = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )

        var first = Note()
        first.title = "Shared Title"
        first.content = "First body"

        var second = Note()
        second.title = "Shared Title"
        second.content = "Second body"

        manager.save(first)
        manager.save(second)

        let filenames = noteFilenames(in: storageDirectory)
        #expect(filenames.count == 2)
        #expect(filenames.contains("Shared Title.txt"))
        #expect(filenames.contains("Shared Title (2).txt"))

        let reloaded = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )
        #expect(reloaded.notes.count == 2)
        #expect(Set(reloaded.notes.map(\.content)) == ["First body", "Second body"])
    }

    @Test
    func renamingNoteReplacesOldFilenameWithoutLeavingStaleFile() throws {
        let storageDirectory = makeTemporaryNotesDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let manager = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )

        var note = Note()
        note.title = "Original Title"
        note.content = "Rename me"
        manager.save(note)

        #expect(noteFilenames(in: storageDirectory) == ["Original Title.txt"])

        var saved = try #require(manager.notes.first(where: { $0.title == "Original Title" }))
        saved.title = "Renamed Title"
        manager.save(saved)

        let filenamesAfterRename = noteFilenames(in: storageDirectory)
        #expect(filenamesAfterRename == ["Renamed Title.txt"])

        let reloaded = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )
        let renamed = try #require(reloaded.notes.first(where: { $0.id == saved.id }))
        #expect(renamed.title == "Renamed Title")
        #expect(renamed.content == "Rename me")
    }

    @Test
    func deleteIfEmptyOnlyRemovesUntouchedPlaceholderNotes() throws {
        let storageDirectory = makeTemporaryNotesDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let manager = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )

        var placeholder = Note()
        placeholder.bookNumber = 500
        placeholder.chapterNumber = 3
        placeholder.verseNumbers = [16]
        placeholder.title = placeholder.verseReference
        manager.save(placeholder)

        let savedPlaceholder = try #require(manager.notes.first(where: { $0.id == placeholder.id }))
        #expect(manager.deleteIfEmpty(savedPlaceholder))
        #expect(manager.notes.first(where: { $0.id == placeholder.id }) == nil)
        #expect(textFileCount(in: storageDirectory) == 0)

        var titled = Note()
        titled.title = "Sermon Notes"
        titled.bookNumber = 43
        titled.chapterNumber = 3
        titled.verseNumbers = [16]
        manager.save(titled)

        let savedTitled = try #require(manager.notes.first(where: { $0.id == titled.id }))
        #expect(!manager.deleteIfEmpty(savedTitled))
        #expect(manager.notes.first(where: { $0.id == titled.id }) != nil)

        var contentful = Note()
        contentful.title = "John 3:16"
        contentful.content = "Keep me"
        contentful.bookNumber = 43
        contentful.chapterNumber = 3
        contentful.verseNumbers = [16]
        manager.save(contentful)

        let savedContentful = try #require(manager.notes.first(where: { $0.id == contentful.id }))
        #expect(!manager.deleteIfEmpty(savedContentful))
        #expect(manager.notes.first(where: { $0.id == contentful.id }) != nil)
    }

    @Test
    func exportURLWritesCurrentFilePayload() throws {
        let storageDirectory = makeTemporaryNotesDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let manager = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )

        var note = Note()
        note.title = "Export Me"
        note.content = "Export body"
        note.bookNumber = 1
        note.chapterNumber = 2
        note.verseNumbers = [3, 4]
        manager.save(note)

        let saved = try #require(manager.notes.first(where: { $0.id == note.id }))
        let exportURL = try #require(manager.exportURL(for: saved))
        defer { try? FileManager.default.removeItem(at: exportURL) }

        let exportedText = try String(contentsOf: exportURL, encoding: .utf8)
        #expect(exportURL.lastPathComponent == "Export Me.txt")
        #expect(exportedText == saved.fileText)
    }

    @Test
    func loadingRepairsVerseMetadataFromTitleAndPersistsTheRepair() throws {
        let storageDirectory = makeTemporaryNotesDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let noteID = UUID()
        let updatedAt = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_100_000))
        let mismatchedFile = """
        John 3:16-17
        0
        0

        \(updatedAt)
        \(noteID.uuidString)
        unlocked
        active

        ---
        Repair me
        """
        let fileURL = storageDirectory.appendingPathComponent("John 3:16-17.txt")
        try mismatchedFile.write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = NotesManager(
            storageDirectoryOverride: storageDirectory,
            remoteSyncEnabled: false
        )

        let repaired = try #require(manager.notes.first(where: { $0.id == noteID }))
        #expect(repaired.bookNumber != 0)
        #expect(repaired.chapterNumber == 3)
        #expect(repaired.verseNumbers == [16, 17])

        let repairedFileURL = try #require((try? FileManager.default.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil
        ))?.first(where: { $0.pathExtension == "txt" }))
        let persistedText = try String(contentsOf: repairedFileURL, encoding: .utf8)
        let reparsed = try #require(Note.parse(from: persistedText))
        #expect(reparsed.bookNumber == repaired.bookNumber)
        #expect(reparsed.chapterNumber == 3)
        #expect(reparsed.verseNumbers == [16, 17])
    }

    private func makeTemporaryNotesDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptureStudyLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func noteFilenames(in directory: URL) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension == "txt" }
            .map(\.lastPathComponent)
            .sorted()
    }

    private func textFileCount(in directory: URL) -> Int {
        noteFilenames(in: directory).count
    }
}
#endif
