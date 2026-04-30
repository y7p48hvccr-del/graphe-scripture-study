import Foundation
import Combine

/// Owns the user's saved chat threads. Follows the same storage pattern as
/// NotesManager: iCloud ubiquitous container preferred, with a local
/// Documents fallback, one .txt file per thread, and an NSMetadataQuery
/// watching for remote iCloud changes so the sidebar stays in sync across
/// devices.
///
/// Threads live in `Documents/Chats/` — sibling to `Documents/Notes/`.
@MainActor
final class ChatHistoryManager: ObservableObject {

    // MARK: - Published state

    /// All saved threads, sorted newest-first. Rendered directly by the
    /// sidebar.
    @Published private(set) var threads: [ChatThread] = []

    /// ID of the thread the user currently has open. `nil` means a fresh
    /// blank chat — nothing persisted yet.
    @Published var currentThreadID: UUID? = nil

    @Published var syncStatus: SyncStatus = .idle

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case error(String)
    }

    // MARK: - Storage

    private var chatsDirectory: URL {
        iCloudDirectory ?? localDirectory
    }

    private var iCloudDirectory: URL? {
        guard let container = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.com.scripturetstudy.app"
        ) else { return nil }
        let dir = container.appendingPathComponent("Documents/Chats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var localDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Graphē One Chats", isDirectory: true)
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
        migrateLocalToiCloudIfNeeded()
        startMetadataQuery()
    }

    deinit {
        if let obs = queryObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        metadataQuery?.stop()
    }

    // MARK: - Public API

    /// The currently-open thread, if any.
    var currentThread: ChatThread? {
        guard let id = currentThreadID else { return nil }
        return threads.first(where: { $0.id == id })
    }

    /// Clear the current thread ID so the Chat view starts fresh.
    /// Does not delete anything — just unmounts whatever was loaded.
    func startNewChat() {
        currentThreadID = nil
    }

    /// Load an existing thread into current state and return its messages
    /// so ChatView can populate its state. Re-reads from disk in case the
    /// in-memory copy is stale.
    func openThread(_ thread: ChatThread) -> [ChatMessage] {
        currentThreadID = thread.id
        if let fresh = readThread(id: thread.id) {
            if let idx = threads.firstIndex(where: { $0.id == thread.id }) {
                threads[idx] = fresh
            }
            return fresh.messages
        }
        return thread.messages
    }

    /// Persist the supplied messages as the current thread. If there's no
    /// current thread, create one now and auto-generate its title from the
    /// first user message. `passageContext` carries book/chapter/verses
    /// from the user's current reading position.
    func save(messages: [ChatMessage],
              bookNumber: Int,
              chapterNumber: Int,
              verseNumbers: [Int]) {
        guard !messages.isEmpty else { return }

        if let id = currentThreadID,
           let idx = threads.firstIndex(where: { $0.id == id }) {
            // Update existing thread in place
            threads[idx].messages       = messages
            threads[idx].updatedAt      = Date()
            // Don't overwrite a good title; only fill it in if empty
            if threads[idx].title.isEmpty,
               let firstUser = messages.first(where: { $0.role == "user" }) {
                threads[idx].title = ChatThread.deriveTitle(from: firstUser.content)
            }
            // Bubble to front (newest-first)
            let t = threads.remove(at: idx)
            threads.insert(t, at: 0)
            writeThread(threads[0])
        } else {
            // Create brand-new thread
            var new = ChatThread()
            new.messages      = messages
            new.bookNumber    = bookNumber
            new.chapterNumber = chapterNumber
            new.verseNumbers  = verseNumbers
            new.createdAt     = Date()
            new.updatedAt     = Date()
            if let firstUser = messages.first(where: { $0.role == "user" }) {
                new.title = ChatThread.deriveTitle(from: firstUser.content)
            }
            threads.insert(new, at: 0)
            currentThreadID = new.id
            writeThread(new)
        }
    }

    /// Remove a thread from the list and delete its file.
    func delete(_ thread: ChatThread) {
        threads.removeAll { $0.id == thread.id }
        if currentThreadID == thread.id { currentThreadID = nil }
        removeFile(for: thread.id)
    }

    /// Change the display title. Empty strings are ignored so we don't
    /// lose auto-generated titles by accident.
    func rename(_ thread: ChatThread, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = threads.firstIndex(where: { $0.id == thread.id })
        else { return }
        threads[idx].title     = trimmed
        threads[idx].updatedAt = Date()
        writeThread(threads[idx])
    }

    // MARK: - Load

    func load() {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var loaded: [ChatThread] = []

        coordinator.coordinate(readingItemAt: chatsDirectory,
                                options: .withoutChanges,
                                error: &error) { url in
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return }

            loaded = files
                .filter { $0.pathExtension == "txt" }
                .compactMap { fileURL -> ChatThread? in
                    if isUsingiCloud {
                        try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
                    }
                    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                        return nil
                    }
                    return ChatThread.parse(from: text)
                }
                .sorted { $0.updatedAt > $1.updatedAt }
        }

        threads = loaded
    }

    // MARK: - Metadata query (iCloud remote changes)

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

    private func migrateLocalToiCloudIfNeeded() {
        guard isUsingiCloud else { return }
        let local = localDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: local, includingPropertiesForKeys: nil
        ) else { return }

        let txtFiles = files.filter { $0.pathExtension == "txt" }
        guard !txtFiles.isEmpty else { return }

        for file in txtFiles {
            let dest = chatsDirectory.appendingPathComponent(file.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: dest.path) else { continue }
            try? FileManager.default.copyItem(at: file, to: dest)
        }
    }

    // MARK: - Disk helpers

    private func writeThread(_ thread: ChatThread) {
        // Remove any existing file for this ID before writing, so a rename
        // doesn't leave the old filename behind.
        removeFile(for: thread.id)

        let coordinator = NSFileCoordinator()
        var error: NSError?
        let url = uniqueURL(for: thread)

        coordinator.coordinate(writingItemAt: url,
                                options: .forReplacing,
                                error: &error) { writeURL in
            try? thread.fileText.write(to: writeURL,
                                       atomically: true,
                                       encoding: .utf8)
        }
    }

    private func readThread(id: UUID) -> ChatThread? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: chatsDirectory, includingPropertiesForKeys: nil
        ) else { return nil }

        for url in files where url.pathExtension == "txt" {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               text.contains(id.uuidString),
               let parsed = ChatThread.parse(from: text) {
                return parsed
            }
        }
        return nil
    }

    private func removeFile(for id: UUID) {
        let coordinator = NSFileCoordinator()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: chatsDirectory, includingPropertiesForKeys: nil
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

    private func uniqueURL(for thread: ChatThread) -> URL {
        let base = thread.safeFilename
        var url  = chatsDirectory.appendingPathComponent("\(base).txt")
        var n    = 2
        while FileManager.default.fileExists(atPath: url.path) {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               text.contains(thread.id.uuidString) { break }
            url = chatsDirectory.appendingPathComponent("\(base) (\(n)).txt")
            n  += 1
        }
        return url
    }

    // MARK: - Passage lookup (for future NotesView integration)

    /// Returns every thread whose passage context matches the given verse.
    /// Used later to show "conversations about this passage" inside Notes.
    func threads(forBook book: Int, chapter: Int, verse: Int? = nil) -> [ChatThread] {
        threads.filter { t in
            guard t.bookNumber == book, t.chapterNumber == chapter else { return false }
            if let v = verse, !t.verseNumbers.isEmpty {
                return t.verseNumbers.contains(v)
            }
            return true
        }
    }
}
