import Foundation

class BookmarksManager: ObservableObject {

    private let store      = NSUbiquitousKeyValueStore.default
    private let localStore = UserDefaults.standard
    private let key        = "scriptureBookmarks"

    @Published var bookmarks: [Bookmark] = [] {
        didSet { persist() }
    }

    init() {
        load()
        // Listen for iCloud changes pushed from other devices
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        store.synchronize()
    }

    // MARK: - iCloud notification

    @objc private func iCloudDidChange(_ notification: Notification) {
        guard let keys = notification.userInfo?[
            NSUbiquitousKeyValueStoreChangedKeysKey
        ] as? [String], keys.contains(key) else { return }
        DispatchQueue.main.async { self.load() }
    }

    // MARK: - Persistence (iCloud when available, UserDefaults as fallback)

    private func persist() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        // Try iCloud first; if synchronize() returns false it isn't available
        store.set(data, forKey: key)
        if !store.synchronize() {
            localStore.set(data, forKey: key)
        }
    }

    private func load() {
        // Prefer iCloud data; fall back to local UserDefaults
        let data = store.data(forKey: key) ?? localStore.data(forKey: key)
        guard let data,
              let saved = try? JSONDecoder().decode([Bookmark].self, from: data)
        else { return }
        bookmarks = saved
    }

    // MARK: - Public API

    func isBookmarked(book: Int, chapter: Int) -> Bool {
        bookmarks.contains {
            $0.deletedAt == nil &&
            $0.bookNumber == book &&
            $0.chapterNumber == chapter &&
            $0.verseNumber == nil
        }
    }

    /// Verse-level bookmark check. Use this for the inline icons next to
    /// verse numbers.
    func isBookmarked(book: Int, chapter: Int, verse: Int) -> Bool {
        bookmarks.contains {
            $0.deletedAt == nil &&
            $0.bookNumber == book &&
            $0.chapterNumber == chapter &&
            $0.verseNumber == verse
        }
    }

    /// Returns the set of verse numbers in the given chapter that have
    /// bookmarks. Used by the Bible reader to render inline icons
    /// efficiently — one set lookup per verse instead of a linear scan.
    /// Excludes trashed bookmarks.
    func bookmarkedVerses(book: Int, chapter: Int) -> Set<Int> {
        var result: Set<Int> = []
        for bm in bookmarks where bm.deletedAt == nil
                               && bm.bookNumber == book
                               && bm.chapterNumber == chapter {
            if let v = bm.verseNumber { result.insert(v) }
        }
        return result
    }

    func toggle(book: Int, chapter: Int) {
        // Active-only match — if the only matching bookmark is trashed,
        // toggle creates a new active one rather than un-trashing.
        if let idx = bookmarks.firstIndex(where: {
            $0.deletedAt == nil &&
            $0.bookNumber == book &&
            $0.chapterNumber == chapter &&
            $0.verseNumber == nil
        }) {
            bookmarks.remove(at: idx)
        } else {
            bookmarks.insert(Bookmark(bookNumber: book, chapterNumber: chapter), at: 0)
        }
    }

    /// Verse-level toggle. Tapping the inline ox-blood bookmark icon
    /// next to a verse number calls this; the popover's "Add bookmark"
    /// action calls this too.
    func toggle(book: Int, chapter: Int, verse: Int) {
        if let idx = bookmarks.firstIndex(where: {
            $0.deletedAt == nil &&
            $0.bookNumber == book &&
            $0.chapterNumber == chapter &&
            $0.verseNumber == verse
        }) {
            bookmarks.remove(at: idx)
        } else {
            // Defensive: if an active bookmark for this exact verse
            // already exists (e.g. via a race with iCloud load), do
            // not insert a duplicate.
            let exists = bookmarks.contains {
                $0.deletedAt == nil &&
                $0.bookNumber == book &&
                $0.chapterNumber == chapter &&
                $0.verseNumber == verse
            }
            guard !exists else { return }
            bookmarks.insert(
                Bookmark(bookNumber: book,
                         chapterNumber: chapter,
                         verseNumber: verse),
                at: 0)
        }
    }

    // MARK: - Delete / Trash
    //
    // Design (2026-04-21):
    //  - delete(_:)           — PERMANENT for bookmarks (individual
    //                           removal always permanent, per user
    //                           direction). Warning dialog shown by
    //                           callers.
    //  - moveToTrash(_:)      — used by bulk-delete flow. Sets
    //                           deletedAt rather than removing from
    //                           the array.
    //  - restore(_:)          — clear deletedAt
    //  - deletePermanently(_:) — called from Trash view or Empty Trash
    //  - emptyTrash()         — permanently delete all trashed bookmarks

    /// PERMANENT delete of a single bookmark. Called from the individual
    /// row-trash affordance, the sidebar X, the verse popover's
    /// "Remove Bookmark", etc. Callers should show a warning dialog
    /// before invoking this.
    func delete(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
    }

    /// Soft-delete — move to Trash. Used by bulk-delete flow from
    /// the CompanionPanel unified list. Recoverable via restore(_:)
    /// until the user empties the Trash.
    func moveToTrash(_ bookmark: Bookmark) {
        guard let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[idx].deletedAt = Date()
    }

    /// Restore a trashed bookmark back to active.
    func restore(_ bookmark: Bookmark) {
        guard let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[idx].deletedAt = nil
    }

    /// Hard-delete a trashed bookmark.
    func deletePermanently(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
    }

    /// Permanently delete every bookmark currently in Trash.
    func emptyTrash() {
        bookmarks.removeAll { $0.deletedAt != nil }
    }
}
