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

    private func makeTemporaryNotesDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptureStudyLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func textFileCount(in directory: URL) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return files.filter { $0.pathExtension == "txt" }.count
    }
}
#endif
