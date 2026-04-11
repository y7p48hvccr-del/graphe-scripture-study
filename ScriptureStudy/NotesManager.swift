import Foundation
import Combine

@MainActor
class NotesManager: ObservableObject {

    // MARK: - Published state

    @Published var notes:         [Note]   = []
    @Published var selectedNote:  Note?    = nil
    @Published var searchHighlight: String = ""
    @Published var syncStatus:    SyncStatus = .idle

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case error(String)
    }

    // MARK: - Storage

    /// iCloud ubiquitous container URL if available, else local Documents
    private var notesDirectory: URL {
        if let icloud = iCloudDirectory { return icloud }
        return localDirectory
    }

    private var iCloudDirectory: URL? {
        guard let container = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.com.scripturetstudy.app"
        ) else { return nil }
        let dir = container.appendingPathComponent("Documents/Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var localDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScriptureStudy Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var isUsingiCloud: Bool { iCloudDirectory != nil }

    // MARK: - iCloud metadata query

    private var metadataQuery: NSMetadataQuery?
    private var queryObserver: NSObjectProtocol?

    // MARK: - Init

    init() {
        load()
        migrateLocalNotesToiCloudIfNeeded()
        startMetadataQuery()
    }

    // MARK: - Metadata query (watches iCloud for remote changes)

    private func startMetadataQuery() {
        guard isUsingiCloud else { return }

        let query = NSMetadataQuery()
        query.searchScopes    = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate       = NSPredicate(format: "%K LIKE '*.txt'",
                                            NSMetadataItemFSNameKey)
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey,
                                                  ascending: true)]
        self.metadataQuery    = query

        queryObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object:  query,
            queue:   .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleRemoteChanges() }
        }

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object:  query,
            queue:   .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleRemoteChanges() }
        }

        query.start()
    }

    private func handleRemoteChanges() {
        metadataQuery?.disableUpdates()
        load()
        metadataQuery?.enableUpdates()
    }

    // MARK: - Migration

    private func migrateLocalNotesToiCloudIfNeeded() {
        guard isUsingiCloud else { return }
        let local = localDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: local, includingPropertiesForKeys: nil
        ) else { return }

        let txtFiles = files.filter { $0.pathExtension == "txt" }
        guard !txtFiles.isEmpty else { return }

        for file in txtFiles {
            let dest = notesDirectory.appendingPathComponent(file.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: dest.path) else { continue }
            try? FileManager.default.copyItem(at: file, to: dest)
        }
    }

    // MARK: - Load

    func load() {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var loaded: [Note] = []

        coordinator.coordinate(readingItemAt: notesDirectory,
                                options: .withoutChanges,
                                error: &error) { url in
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return }

            loaded = files
                .filter { $0.pathExtension == "txt" }
                .compactMap { fileURL -> Note? in
                    // Download from iCloud if needed
                    if isUsingiCloud {
                        try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
                    }
                    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                        return nil
                    }
                    return Note.parse(from: text)
                }
                .sorted { $0.updatedAt > $1.updatedAt }
        }

        notes = loaded

        // Preserve selectedNote if it still exists
        if let sel = selectedNote {
            selectedNote = notes.first(where: { $0.id == sel.id }) ?? notes.first
        } else {
            selectedNote = notes.first
        }
    }

    // MARK: - Save

    func save(_ note: Note) {
        var updated       = note
        updated.updatedAt = Date()

        let coordinator = NSFileCoordinator()
        var error: NSError?

        // Remove old file for this note
        removeFile(for: note.id, coordinator: coordinator)

        let url = uniqueURL(for: updated)

        coordinator.coordinate(writingItemAt: url,
                                options: .forReplacing,
                                error: &error) { writeURL in
            try? updated.fileText.write(to: writeURL,
                                        atomically: true,
                                        encoding: .utf8)
        }

        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = updated
        } else {
            notes.insert(updated, at: 0)
        }
        notes.sort { $0.updatedAt > $1.updatedAt }
        if selectedNote?.id == note.id { selectedNote = updated }
    }

    // MARK: - Create

    @discardableResult
    func createNote(bookNumber: Int = 0,
                    chapter:    Int = 0,
                    verses:   [Int] = []) -> Note {
        var note           = Note()
        note.bookNumber    = bookNumber
        note.chapterNumber = chapter
        note.verseNumbers  = verses
        if bookNumber > 0 { note.title = note.verseReference }
        save(note)
        selectedNote = note
        // Notify Organizer so it opens this note in the editor
        if bookNumber > 0 {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("noteCreatedFromVerse"),
                    object: nil,
                    userInfo: ["note": note]
                )
            }
        }
        return note
    }

    // MARK: - Delete

    func delete(_ note: Note) {
        let coordinator = NSFileCoordinator()
        removeFile(for: note.id, coordinator: coordinator)
        notes.removeAll { $0.id == note.id }
        if selectedNote?.id == note.id {
            selectedNote = notes.first
        }
    }

    // MARK: - Auto-delete empty notes

    @discardableResult
    func deleteIfEmpty(_ note: Note) -> Bool {
        let hasContent = !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTitle   = !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && note.title != note.verseReference
        if !hasContent && !hasTitle {
            delete(note)
            return true
        }
        return false
    }

    // MARK: - Verse lookups

    func notes(forBook book: Int, chapter: Int, verse: Int) -> [Note] {
        notes.filter {
            $0.bookNumber    == book &&
            $0.chapterNumber == chapter &&
            ($0.verseNumbers.isEmpty || $0.verseNumbers.contains(verse))
        }
    }

    func hasNote(forBook book: Int, chapter: Int, verse: Int) -> Bool {
        !notes(forBook: book, chapter: chapter, verse: verse).isEmpty
    }

    // MARK: - Export

    func exportURL(for note: Note) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(note.safeFilename).txt")
        try? note.fileText.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Search

    func searchHighlightURL(for note: Note) -> URL? { nil }

    // MARK: - Private helpers

    private func removeFile(for id: UUID, coordinator: NSFileCoordinator) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: notesDirectory, includingPropertiesForKeys: nil
        ) else { return }

        for url in files where url.pathExtension == "txt" {
            var err: NSError?
            coordinator.coordinate(readingItemAt: url,
                                    options: .withoutChanges,
                                    error: &err) { readURL in
                if let text = try? String(contentsOf: readURL, encoding: .utf8),
                   text.contains(id.uuidString) {
                    var delErr: NSError?
                    coordinator.coordinate(writingItemAt: url,
                                           options: .forDeleting,
                                           error: &delErr) { writeURL in
                        try? FileManager.default.removeItem(at: writeURL)
                    }
                }
            }
        }
    }

    private func uniqueURL(for note: Note) -> URL {
        let base = note.safeFilename
        var url  = notesDirectory.appendingPathComponent("\(base).txt")
        var n    = 2
        while FileManager.default.fileExists(atPath: url.path) {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               text.contains(note.id.uuidString) { break }
            url = notesDirectory.appendingPathComponent("\(base) (\(n)).txt")
            n  += 1
        }
        return url
    }
}
