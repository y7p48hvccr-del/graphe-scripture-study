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
        bookmarks.contains { $0.bookNumber == book && $0.chapterNumber == chapter }
    }

    func toggle(book: Int, chapter: Int) {
        if let idx = bookmarks.firstIndex(where: {
            $0.bookNumber == book && $0.chapterNumber == chapter
        }) {
            bookmarks.remove(at: idx)
        } else {
            bookmarks.insert(Bookmark(bookNumber: book, chapterNumber: chapter), at: 0)
        }
    }

    func delete(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
    }
}
