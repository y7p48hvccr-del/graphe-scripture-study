import Foundation
import SwiftUI

/// Persistent store of books (EPUB and PDF) the user has starred as
/// favourites. Backed by UserDefaults for simplicity — the data is just
/// a set of URL path strings, small enough that iCloud sync isn't needed
/// yet.
///
/// Newly-added favourites go to the front of the list, so the most
/// recently starred book is always at the top of any UI that renders
/// `favouritePaths` — no auto-scroll logic needed.
@MainActor
final class FavouritesStore: ObservableObject {

    /// List of book URL paths in most-recently-starred-first order.
    @Published private(set) var favouritePaths: [String] = []

    private let storageKey = "favouriteBookPaths"

    init() {
        load()
    }

    // MARK: - Public API

    func isFavourite(_ url: URL) -> Bool {
        favouritePaths.contains(url.path)
    }

    func toggle(_ url: URL) {
        let path = url.path
        if let idx = favouritePaths.firstIndex(of: path) {
            favouritePaths.remove(at: idx)
        } else {
            favouritePaths.insert(path, at: 0)
        }
        save()
    }

    /// Return the list of favourites as URLs. We don't check file
    /// existence here — the Books tab has a security-scoped bookmark
    /// granting access to the library folder, but other tabs (like the
    /// Bible tab's sidebar) don't, so `FileManager.fileExists` would
    /// falsely report missing files from those contexts. If a book has
    /// truly been deleted, tapping its favourite will just do nothing.
    var favouriteURLs: [URL] {
        favouritePaths.map { URL(fileURLWithPath: $0) }
    }

    func remove(_ url: URL) {
        favouritePaths.removeAll { $0 == url.path }
        save()
    }

    // MARK: - Persistence

    private func load() {
        if let arr = UserDefaults.standard.stringArray(forKey: storageKey) {
            favouritePaths = arr
        }
    }

    private func save() {
        UserDefaults.standard.set(favouritePaths, forKey: storageKey)
    }
}
