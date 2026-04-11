import SwiftUI
import ZIPFoundation
import PDFKit
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Book File Model

enum BookFormat: String {
    case epub = "epub"
    case pdf  = "pdf"
    case azw3 = "azw3"
    case mobi = "mobi"

    var priority: Int { switch self {
        case .epub: return 0; case .pdf: return 1; case .azw3: return 2; case .mobi: return 3
    } }
    var label: String { rawValue.uppercased() }
    var isReadable: Bool { self == .epub || self == .pdf }
    var isEPUB: Bool { self == .epub }
    var isPDF:  Bool { self == .pdf }
}

struct BookFile: Identifiable {
    let id = UUID()
    let url:    URL
    let format: BookFormat
    var title:  String { url.deletingPathExtension().lastPathComponent
        .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ") }
}

final class CoverStore: ObservableObject {
    #if os(macOS)
    @Published var covers: [String: PlatformImage] = [:]
    #else
    @Published var covers: [String: UIImage] = [:]
    #endif

    func loadCovers(for urls: [URL]) { }

    func loadCover(for url: URL) { }
}


struct EPUBLibraryView: View {
    @AppStorage("epubFolder")    private var epubFolder:    String = ""
    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    @StateObject private var coverStore = CoverStore()
    var theme:          AppTheme { AppTheme.find(themeID) }
    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }

    @State private var bookFiles:  [BookFile] = []
    @State private var epubURLs:   [URL]  = []
    @State private var isScanning: Bool   = false
    @State private var selectedURL:          URL?        = nil
    @State private var selectedFormat:       BookFormat? = nil
    @State private var selectedInitialHref:  String?     = nil
    @State private var selectedSearchQuery:  String?     = nil
    @State private var bookToDelete:   BookFile?   = nil
    @State private var showingImportPicker: Bool   = false
    @State private var activeTab:           String = "mybooks"
    @State private var searchText:          String = ""
    @State private var searchMode:          String = "title"
    @State private var showBookSearch:      Bool   = false
    @StateObject private var bookSearch            = BookSearchService()
    @AppStorage("newBookPaths") private var newBookPathsRaw: String = ""
    @AppStorage("epubViewMode")   private var viewMode:       String = "large"
    @AppStorage("epubSortOrder")  private var sortOrder:      String = "title"
    @AppStorage("epubLastOpened")  private var lastOpenedData:  Data   = Data()

    var sortedBooks: [BookFile] {
        switch sortOrder {
        case "author":
            return bookFiles.sorted { authorName($0.url) < authorName($1.url) }
        case "recent":
            let recents = (try? JSONDecoder().decode([String].self, from: lastOpenedData)) ?? []
            return bookFiles.sorted { a, b in
                let ai = recents.firstIndex(of: a.url.path) ?? Int.max
                let bi = recents.firstIndex(of: b.url.path) ?? Int.max
                return ai < bi
            }
        default:
            return bookFiles.sorted { cleanTitle($0.url) < cleanTitle($1.url) }
        }
    }
    var sortedURLs: [URL] { sortedBooks.map { $0.url } }

    var newBookNames: Set<String> {
        Set(newBookPathsRaw.components(separatedBy: ",").filter { !$0.isEmpty })
    }

    var filteredBooks: [BookFile] {
        guard !searchText.isEmpty else { return sortedBooks }
        let q = searchText.lowercased()
        return sortedBooks.filter {
            cleanTitle($0.url).lowercased().contains(q) ||
            authorName($0.url).lowercased().contains(q)
        }
    }

    // Books grouped by first letter for A-Z jump bar
    var booksByLetter: [(letter: String, books: [BookFile])] {
        let books = filteredBooks
        var dict: [String: [BookFile]] = [:]
        for book in books {
            let first = String(cleanTitle(book.url).prefix(1)).uppercased()
            let key = first.first?.isLetter == true ? first : "#"
            dict[key, default: []].append(book)
        }
        return dict.keys.sorted().map { (letter: $0, books: dict[$0]!) }
    }

    func cleanTitle(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    func authorName(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        if name.contains(" - ") { return name.components(separatedBy: " - ").first ?? name }
        if name.contains("_-_") { return name.components(separatedBy: "_-_").first?
            .replacingOccurrences(of: "_", with: " ") ?? name }
        return name
    }

    func recordOpened(_ url: URL) {
        var recents = (try? JSONDecoder().decode([String].self, from: lastOpenedData)) ?? []
        recents.removeAll { $0 == url.path }
        recents.insert(url.path, at: 0)
        lastOpenedData = (try? JSONEncoder().encode(Array(recents.prefix(100)))) ?? Data()
    }

    var body: some View {
        Group {
            if let url = selectedURL {
                Group {
                    if selectedFormat?.isPDF == true {
                        PDFReaderView(pdfURL: url)
                    } else {
                        EPUBReaderView(epubURL: url,
                                       initialHref: selectedInitialHref,
                                       initialSearchQuery: selectedSearchQuery)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button { selectedURL = nil; selectedFormat = nil; selectedInitialHref = nil; selectedSearchQuery = nil } label: {
                            Label("Archives", systemImage: "chevron.left")
                        }
                    }
                }
            } else {
                VStack(spacing: 0) {
                    // My Books / Magazines / Discover switcher
                    Picker("", selection: $activeTab) {
                        Text("My Books").tag("mybooks")
                        Text("Magazines").tag("magazines")
                        Text("Discover").tag("discover")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    Divider()

                    if activeTab == "mybooks" {
                        libraryView
                    } else if activeTab == "magazines" {
                        MagazinesView(booksFolder: epubFolder)
                    } else {
                        DiscoverView()
                            .onDisappear { }
                    }
                }
            }
        }
    }

    private var libraryView: some View {
        NavigationStack {
            Group {
                if epubFolder.isEmpty {
                    emptyState
                } else if isScanning {
                    VStack { Spacer(); ProgressView("Scanning…"); Spacer() }
                } else if bookFiles.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "books.vertical")
                            .font(.system(size: 48)).foregroundStyle(.quaternary)
                        Text("No EPUB files found").foregroundStyle(.secondary)
                        chooseFolderButton("Choose Different Folder")
                        Spacer()
                    }
                } else {
                    bookGrid
                }
            }
            .navigationTitle("Books")
            .background(theme.background)
            .onAppear { if !epubFolder.isEmpty && epubURLs.isEmpty { scan() } }
            .alert("Delete Book", isPresented: Binding(
                get: { bookToDelete != nil },
                set: { if !$0 { bookToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let book = bookToDelete { deleteBook(book) }
                    bookToDelete = nil
                }
                Button("Cancel", role: .cancel) { bookToDelete = nil }
            } message: {
                Text("This will permanently delete this resource! Do you want to continue?")
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result { importBookFiles(urls) }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { pickFolder() } label: {
                        Label("Choose Folder", systemImage: "folder.badge.plus")
                    }.help("Choose books folder")
                }
                ToolbarItem {
                    Button { showingImportPicker = true } label: {
                        Label("Import Files", systemImage: "plus.circle")
                    }
                    .help("Copy EPUB or PDF files into your books folder")
                    .disabled(epubFolder.isEmpty)
                }
                ToolbarItem {
                    Button { scan() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(epubFolder.isEmpty)
                    .help("Rescan folder")
                }
                ToolbarItem {
                    Menu {
                        Section("Sort") {
                            Button { sortOrder = "title"  } label: { Label("Title A–Z",       systemImage: sortOrder == "title"  ? "checkmark" : "textformat") }
                            Button { sortOrder = "author" } label: { Label("Author",           systemImage: sortOrder == "author" ? "checkmark" : "person") }
                            Button { sortOrder = "recent" } label: { Label("Recently Opened",  systemImage: sortOrder == "recent" ? "checkmark" : "clock") }
                        }
                        Section("View") {
                            Button { viewMode = "large" } label: { Label("Large Grid",  systemImage: viewMode == "large" ? "checkmark" : "square.grid.2x2") }
                            Button { viewMode = "small" } label: { Label("Small Grid",  systemImage: viewMode == "small" ? "checkmark" : "square.grid.3x3") }
                            Button { viewMode = "list"  } label: { Label("List",        systemImage: viewMode == "list"  ? "checkmark" : "list.bullet") }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .help("Sort and view options")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "books.vertical").font(.system(size: 56)).foregroundStyle(.quaternary)
            Text("No books folder selected").font(.title2.weight(.semibold))
            Text("Choose a folder containing your EPUB files.")
                .foregroundStyle(.secondary)
            chooseFolderButton("Choose Books Folder")
            Spacer()
        }
    }

    private func chooseFolderButton(_ label: String) -> some View {
        Button(label) { pickFolder() }
            .buttonStyle(.plain)
            .foregroundStyle(filigreeAccent)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(filigreeAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(filigreeAccent, lineWidth: 1))
    }

    @ViewBuilder
    private var bookGrid: some View {
        VStack(spacing: 0) {
            // Search bar with mode toggle
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(bookSearch.isSearching || !bookSearch.lastQuery.isEmpty || searchMode == "inside"
                              ? "Search inside books…"
                              : "Search by title or author…",
                              text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit { if searchMode == "inside" { triggerInsideSearch() } }
                    if bookSearch.isSearching {
                        ProgressView().controlSize(.small)
                    } else if !searchText.isEmpty {
                        if searchMode == "inside" {
                            Button {
                                triggerInsideSearch()
                            } label: {
                                Text("Search")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(filigreeAccent)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                        Button { searchText = ""; bookSearch.cancel() } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)

                // Mode toggle
                HStack(spacing: 0) {
                    ForEach([("title", "Title & Author"), ("inside", "Inside Books")], id: \.0) { mode, label in
                        Button {
                            searchMode = mode
                            searchText = ""
                            bookSearch.cancel()
                        } label: {
                            Text(label)
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(searchMode == mode ? filigreeAccent.opacity(0.15) : Color.clear)
                                .foregroundStyle(searchMode == mode ? filigreeAccent : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        if mode == "title" {
                            Divider().frame(height: 20)
                        }
                    }
                }
                .background(Color.platformWindowBg)
            }

            Divider()

            if searchMode == "inside" && (!bookSearch.results.isEmpty || bookSearch.isSearching || !bookSearch.lastQuery.isEmpty) {
                // Inside-books search results
                if bookSearch.isSearching {
                    VStack { Spacer(); ProgressView("Searching \(bookFiles.filter { $0.format.isEPUB }.count) books…"); Spacer() }
                } else if bookSearch.results.isEmpty {
                    VStack { Spacer(); Text("No results for \u{201C}\(bookSearch.lastQuery)\u{201D}").foregroundStyle(.secondary); Spacer() }
                } else {
                    List {
                        ForEach(bookSearch.results) { result in
                            Button {
                                selectedInitialHref  = result.href
                                selectedSearchQuery  = bookSearch.lastQuery
                                selectedURL    = result.bookURL
                                selectedFormat = .epub
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(result.bookTitle)
                                            .font(.system(size: 13, weight: .semibold))
                                            .lineLimit(1)
                                        Spacer()
                                        Text(result.chapterTitle)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Text(result.snippet)
                                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if filteredBooks.isEmpty {
                VStack {
                    Spacer()
                    Text(searchText.isEmpty ? "No books" : "No results for \u{201C}\(searchText)\u{201D}")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if viewMode == "list" {
                // List mode — no A-Z bar needed, just scroll
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredBooks) { book in
                            HStack(spacing: 0) {
                                BookListRow(url: book.url, format: book.format, accent: filigreeAccent,
                                            cover: coverStore.covers[book.url.path],
                                            isNew: newBookNames.contains(book.url.lastPathComponent))
                                    .onTapGesture { openBook(book) }
                                    .onAppear { coverStore.loadCover(for: book.url) }
                                Button { bookToDelete = book } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 12)
                                .help("Delete this book")
                            }
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            } else {
                // Grid modes — with A-Z jump bar
                HStack(alignment: .top, spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(booksByLetter, id: \.letter) { group in
                                    // Section header
                                    Text(group.letter)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 20)
                                        .padding(.top, 16)
                                        .padding(.bottom, 6)
                                        .id("letter_\(group.letter)")

                                    // Books in section
                                    let cols = viewMode == "small"
                                        ? [GridItem(.adaptive(minimum: 90, maximum: 110), spacing: 10)]
                                        : [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)]
                                    let sz: BookTileSize = viewMode == "small" ? .small : .large
                                    LazyVGrid(columns: cols, spacing: viewMode == "small" ? 12 : 20) {
                                        ForEach(group.books) { book in
                                            bookTile(book, size: sz)
                                        }
                                    }
                                    .padding(.horizontal, viewMode == "small" ? 16 : 20)
                                    .padding(.bottom, viewMode == "small" ? 4 : 8)
                                }
                            }
                            .padding(.bottom, 20)
                        }
                        .onChange(of: searchText) { _ in
                            if let first = booksByLetter.first {
                                proxy.scrollTo("letter_\(first.letter)", anchor: .top)
                            }
                        }
                        .overlay(alignment: .trailing) {
                            // A-Z jump bar
                            VStack(spacing: 1) {
                                ForEach(booksByLetter, id: \.letter) { group in
                                    Button {
                                        withAnimation { proxy.scrollTo("letter_\(group.letter)", anchor: .top) }
                                    } label: {
                                        Text(group.letter)
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(filigreeAccent)
                                            .frame(width: 16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.trailing, 4)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func bookTile(_ book: BookFile, size: BookTileSize) -> some View {
        ZStack(alignment: .topTrailing) {
            SimpleBookTile(url: book.url, format: book.format, accent: filigreeAccent,
                           cover: coverStore.covers[book.url.path], size: size)
                .onTapGesture { openBook(book) }
                .onAppear { coverStore.loadCover(for: book.url) }
                .contextMenu {
                    Button(role: .destructive) { bookToDelete = book } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            // New pill badge
            if newBookNames.contains(book.url.lastPathComponent) {
                Text("New")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(filigreeAccent)
                    .clipShape(Capsule())
                    .offset(x: -4, y: 4)
            }
        }
    }

    private func openBook(_ book: BookFile) {
        markOpened(book)
        recordOpened(book.url)
        selectedInitialHref = nil
        selectedSearchQuery = nil
        if book.format.isReadable {
            selectedURL    = book.url
            selectedFormat = book.format
        } else {
            #if os(macOS)
            let alert = NSAlert()
            alert.messageText = "Cannot Open \(book.format.label)"
            alert.informativeText = "\(book.format.label) files need to be converted to EPUB before they can be read. Use Calibre to convert this file."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            #endif
        }
    }

    private func importBookFiles(_ urls: [URL]) {
        let destFolder = URL(fileURLWithPath: epubFolder)
        var copied = 0
        var skipped = 0
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            let ext = url.pathExtension.lowercased()
            guard ["epub", "pdf", "azw3", "mobi"].contains(ext) else {
                skipped += 1
                continue
            }
            let dest = destFolder.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
                copied += 1
            } catch {
                return
            }
        }
        if copied > 0 { scan() }
    }

    private func triggerInsideSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        bookSearch.search(query: searchText, in: bookFiles)
    }

    private func markOpened(_ book: BookFile) {
        let name = book.url.lastPathComponent
        let names = newBookPathsRaw.components(separatedBy: ",").filter { !$0.isEmpty && $0 != name }
        newBookPathsRaw = names.joined(separator: ",")
    }

    private func deleteBook(_ book: BookFile) {
        try? FileManager.default.trashItem(at: book.url, resultingItemURL: nil)
        scan()
    }

    private func pickFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Books Folder"
        if panel.runModal() == .OK, let url = panel.url {
            epubFolder = url.path
            scan()
        }
        #endif
    }

    private func scan() {
        guard !epubFolder.isEmpty else { return }
        isScanning = true
        let folder = epubFolder
        Task {
            let files = await Task.detached(priority: .userInitiated) {
                EPUBLibraryView.findBooks(in: URL(fileURLWithPath: folder))
            }.value
            bookFiles  = files
            epubURLs   = files.map { $0.url }
            isScanning = false
            coverStore.loadCovers(for: files.map { $0.url })
        }
    }

    /// Scan for epub, azw3, mobi files and deduplicate by base title,
    /// preferring epub > azw3 > mobi when multiple formats of the same book exist.
    nonisolated static func findBooks(in dir: URL) -> [BookFile] {
        let supportedExts: Set<String> = ["epub", "pdf", "azw3", "mobi"]
        var allFiles: [BookFile] = []
        guard let e = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        while let obj = e.nextObject() {
            guard let url = obj as? URL else { continue }
            let ext = url.pathExtension.lowercased()
            guard supportedExts.contains(ext),
                  let format = BookFormat(rawValue: ext) else { continue }
            allFiles.append(BookFile(url: url, format: format))
        }

        // Deduplicate: group by normalised base filename (without extension),
        // stripping spaces, underscores, hyphens and punctuation for fuzzy matching.
        // e.g. "Adam - Ted Dekker.epub" and "Adam_Ted_Dekker.mobi" → same book
        func normaliseKey(_ url: URL) -> String {
            url.deletingPathExtension().lastPathComponent
                .lowercased()
                .components(separatedBy: .init(charactersIn: " _-.,;:!?()[]{}'\"/\\"))
                .joined()
        }

        var byTitle: [String: BookFile] = [:]
        for file in allFiles {
            let key = normaliseKey(file.url)
            if let existing = byTitle[key] {
                if file.format.priority < existing.format.priority {
                    byTitle[key] = file
                }
            } else {
                byTitle[key] = file
            }
        }
        return Array(byTitle.values).sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    nonisolated static func findEPUBs(in dir: URL) -> [URL] {
        findBooks(in: dir).filter { $0.format.isReadable }.map { $0.url }
    }
}

// MARK: - Book Tile

enum BookTileSize { case large, small }

struct SimpleBookTile: View {
    let url:    URL
    var format: BookFormat = .epub
    let accent: Color
#if os(macOS)
    var cover:  PlatformImage? = nil
    #else
    var cover:  UIImage? = nil
    #endif
    var size:   BookTileSize = .large

    var title: String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private var w: CGFloat { size == .large ? 140 : 88 }
    private var h: CGFloat { size == .large ? 196 : 123 }
    private var iconSize: CGFloat { size == .large ? 36 : 22 }
    private var fontSize: CGFloat { size == .large ? 11 : 9 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let cover = cover {
                    #if os(macOS)
                    Image(nsImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: w, height: h)
                        .clipped()
                    #else
                    Image(uiImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: w, height: h)
                        .clipped()
                    #endif
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.659, green: 0.784, blue: 0.878).opacity(0.25))
                        .frame(width: w, height: h)
                    VStack(spacing: 6) {
                        BrandedQuillIcon(size: iconSize * 1.4)
                        Text(title)
                            .font(.system(size: fontSize, weight: .medium))
                            .foregroundStyle(Color(red: 0.659, green: 0.784, blue: 0.878))
                            .multilineTextAlignment(.center)
                            .lineLimit(3).padding(.horizontal, 6)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            .overlay(alignment: .bottomLeading) {
                if format == .azw3 || format == .mobi {
                    Text(format.label)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(format == .azw3 ? Color.orange : Color.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                }
            }
            Text(title)
                .font(.system(size: fontSize, weight: .medium))
                .lineLimit(2).foregroundStyle(.primary)
        }
        .frame(width: w)
    }
}


// MARK: - List Row

struct BookListRow: View {
    let url:          URL
    var format:       BookFormat = .epub
    let accent:       Color
    var cover:        PlatformImage? = nil
    var isNew:        Bool = false

    var title: String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    var author: String {
        let name = url.deletingPathExtension().lastPathComponent
        if name.contains(" - ") { return name.components(separatedBy: " - ").first ?? "" }
        if name.contains("_-_") { return name.components(separatedBy: "_-_").first?
            .replacingOccurrences(of: "_", with: " ") ?? "" }
        return ""
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                if let cover = cover {
                    #if os(macOS)
                    Image(nsImage: cover)
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 50).clipped()
                    #else
                    Image(uiImage: cover)
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 50).clipped()
                    #endif
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.659, green: 0.784, blue: 0.878).opacity(0.25))
                        .frame(width: 36, height: 50)
                    BrandedQuillIcon(size: 18)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !author.isEmpty {
                    Text(author)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(format.label)
                    .font(.system(size: 10))
                    .foregroundStyle(format == .azw3 || format == .mobi ? Color.white : Color.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(format == .azw3 ? Color.orange
                        : format == .mobi ? Color.purple
                        : Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Spacer()
            if isNew {
                Text("New")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(accent)
                    .clipShape(Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Source definitions

struct DiscoverSource: Identifiable {
    let id:      String
    let name:    String
    let url:     String
    let icon:    String
    let blurb:   String
}

let discoverSources: [DiscoverSource] = [
    DiscoverSource(id: "monergism",
                   name: "Monergism",
                   url:  "https://www.monergism.com/1100-free-ebooks-listed-alphabetically-author",
                   icon: "books.vertical.fill",
                   blurb: "1,300+ Reformed theology classics — EPUB & PDF"),
    DiscoverSource(id: "ccel",
                   name: "CCEL",
                   url:  "https://ccel.org/index/format/epub",
                   icon: "building.columns.fill",
                   blurb: "Christian Classics Ethereal Library — patristics to Puritans"),
    DiscoverSource(id: "inspiredwalk",
                   name: "Inspired Walk",
                   url:  "https://www.inspiredwalk.com/free-christian-ebooks",
                   icon: "figure.walk",
                   blurb: "400+ free devotional & teaching ebooks"),
    DiscoverSource(id: "biblesnet",
                   name: "BiblesNet",
                   url:  "https://www.biblesnet.com/ebooks.html",
                   icon: "book.fill",
                   blurb: "Free classic Christian ebooks — Spurgeon, Ryle & more"),
    DiscoverSource(id: "spiritualibrary",
                   name: "Spiritual Library",
                   url:  "https://www.spiritualibrary.com/",
                   icon: "leaf.fill",
                   blurb: "Christian living, devotionals & magazines — many languages"),
    DiscoverSource(id: "standardebooks",
                   name: "Standard Ebooks",
                   url:  "https://standardebooks.org/ebooks?query=&subject=Religion",
                   icon: "star.fill",
                   blurb: "Beautifully formatted public domain classics"),
    DiscoverSource(id: "openlibrary",
                   name: "Open Library",
                   url:  "https://openlibrary.org/subjects/christian_literature",
                   icon: "globe",
                   blurb: "Internet Archive — borrow or download free Christian texts"),
    DiscoverSource(id: "interlinear",
                   name: "Interlinear Bible",
                   url:  "https://archive.org/search?query=interlinear+bible&mediatype=texts",
                   icon: "text.alignleft",
                   blurb: "Greek & Hebrew interlinear texts — downloadable EPUB & PDF"),
    DiscoverSource(id: "scripture4all",
                   name: "Scripture4All",
                   url:  "https://www.scripture4all.org/OnlineInterlinear/Greek_Index.htm",
                   icon: "character.book.closed.fill",
                   blurb: "Word-level Greek NT & Hebrew OT interlinear — chapter PDFs"),
    DiscoverSource(id: "lxx",
                   name: "Septuagint (LXX)",
                   url:  "https://archive.org/search?query=septuagint+lxx&mediatype=texts",
                   icon: "scroll.fill",
                   blurb: "Greek Old Testament — Brenton and other editions, EPUB & PDF"),
    DiscoverSource(id: "christianhistory",
                   name: "Christian History",
                   url:  "https://christianhistoryinstitute.org/magazine",
                   icon: "clock.fill",
                   blurb: "Christian History Magazine — free back issues in PDF"),
    DiscoverSource(id: "reasonstobelieve",
                   name: "Reasons to Believe",
                   url:  "https://reasons.org/explore/blogs/category/creation-views",
                   icon: "star.and.crescent",
                   blurb: "Hugh Ross — faith and science articles, creation views"),
]

// MARK: - Main Discover View

struct DiscoverView: View {
    @AppStorage("epubFolder")    private var epubFolder:    String = ""
    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }

    @State private var selectedSource: DiscoverSource = discoverSources[0]
    @State private var downloadStatus: String?        = nil
    @State private var downloadIsError: Bool          = false
    @State private var isDownloading:   Bool          = false

    var body: some View {
        VStack(spacing: 0) {
            // Source picker
            sourcePicker

            Divider()

            if epubFolder.isEmpty {
                noFolderPrompt
            } else {
                // Browser
                ZStack(alignment: .bottom) {
                    DiscoverBrowserView(
                        source:         selectedSource,
                        booksFolder:    epubFolder,
                        filigreeAccent: filigreeAccent,
                        onDownloadStart: { filename in
                            isDownloading  = true
                            downloadStatus = "Downloading \(filename)…"
                            downloadIsError = false
                        },
                        onDownloadComplete: { filename in
                            isDownloading  = false
                            downloadStatus = "\(filename) saved to Books"
                            downloadIsError = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                downloadStatus = nil
                            }
                        },
                        onDownloadError: { message in
                            isDownloading  = false
                            downloadStatus = message
                            downloadIsError = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                downloadStatus = nil
                            }
                        }
                    )

                    // Download toast
                    if let status = downloadStatus {
                        HStack(spacing: 8) {
                            if isDownloading {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: downloadIsError
                                      ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(downloadIsError ? .red : .green)
                            }
                            Text(status).font(.caption.weight(.medium))
                            Spacer()
                            if !isDownloading {
                                Button { downloadStatus = nil } label: {
                                    Image(systemName: "xmark").font(.system(size: 10))
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut, value: downloadStatus)
            }
        }
    }

    // MARK: - Source Picker

    private var sourcePicker: some View {
        ZStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(discoverSources) { source in
                        Button {
                            selectedSource = source
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: source.icon)
                                    .font(.system(size: 11))
                                Text(source.name)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(selectedSource.id == source.id
                                        ? filigreeAccent
                                        : filigreeAccent.opacity(0.1))
                            .foregroundStyle(selectedSource.id == source.id ? .white : filigreeAccent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(source.blurb)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            // Left fade
            HStack {
                LinearGradient(
                    colors: [Color(nsColor: .windowBackgroundColor), .clear],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(width: 24)
                Spacer()
            }
            .allowsHitTesting(false)

            // Right fade
            HStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, Color(nsColor: .windowBackgroundColor)],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(width: 24)
            }
            .allowsHitTesting(false)
        }
        .frame(height: 36)
    }

    // MARK: - No folder prompt

    private var noFolderPrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48)).foregroundStyle(.quaternary)
            Text("No books folder set")
                .font(.title2.weight(.semibold))
            Text("Go to the My Books tab and choose a folder\nbefore browsing for downloads.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }
}

// MARK: - WKWebView wrapper

struct DiscoverBrowserView: NSViewRepresentable {
    let source:             DiscoverSource
    let booksFolder:        String
    let filigreeAccent:     Color
    let onDownloadStart:    (String) -> Void
    let onDownloadComplete: (String) -> Void
    let onDownloadError:    (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(booksFolder:        booksFolder,
                    onDownloadStart:    onDownloadStart,
                    onDownloadComplete: onDownloadComplete,
                    onDownloadError:    onDownloadError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        if let url = URL(string: source.url) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Navigate when source changes
        if context.coordinator.currentSourceID != source.id {
            context.coordinator.currentSourceID = source.id
            if let url = URL(string: source.url) {
                webView.load(URLRequest(url: url))
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        let booksFolder:        String
        let onDownloadStart:    (String) -> Void
        let onDownloadComplete: (String) -> Void
        let onDownloadError:    (String) -> Void
        var currentSourceID:    String = ""
        weak var webView:       WKWebView?

        private let downloadableExtensions: Set<String> = ["epub", "pdf", "mobi", "azw3"]

        init(booksFolder:        String,
             onDownloadStart:    @escaping (String) -> Void,
             onDownloadComplete: @escaping (String) -> Void,
             onDownloadError:    @escaping (String) -> Void)
        {
            self.booksFolder        = booksFolder
            self.onDownloadStart    = onDownloadStart
            self.onDownloadComplete = onDownloadComplete
            self.onDownloadError    = onDownloadError
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void)
        {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let ext = url.pathExtension.lowercased()
            if downloadableExtensions.contains(ext) {
                decisionHandler(.cancel)
                downloadFile(from: url)
            } else {
                decisionHandler(.allow)
            }
        }

        // Magazine sources — PDF downloads go into Magazines/[Publication]/ subfolder
        private let magazineSources: [String: String] = [
            "christianhistory":  "Christian History",
            "reasonstobelieve":  "Reasons to Believe",
        ]

        private func downloadFile(from url: URL) {
            let filename = url.lastPathComponent
            DispatchQueue.main.async { self.onDownloadStart(filename) }

            let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                if let error = error {
                    DispatchQueue.main.async { self.onDownloadError("Download failed: \(error.localizedDescription)") }
                    return
                }
                guard let tempURL = tempURL else {
                    DispatchQueue.main.async { self.onDownloadError("Download failed — no data") }
                    return
                }

                let ext = url.pathExtension.lowercased()
                let isMagazine = self.magazineSources[self.currentSourceID] != nil
                let publicationName = self.magazineSources[self.currentSourceID] ?? ""

                // Determine destination folder
                let booksURL = URL(fileURLWithPath: self.booksFolder)
                let destFolder: URL
                if isMagazine && !publicationName.isEmpty {
                    let magazinesFolder = booksURL.appendingPathComponent("Magazines")
                        .appendingPathComponent(publicationName)
                    try? FileManager.default.createDirectory(
                        at: magazinesFolder,
                        withIntermediateDirectories: true)
                    destFolder = magazinesFolder
                } else {
                    destFolder = booksURL
                }

                // Determine clean filename
                var finalName: String
                if isMagazine && ext == "pdf" {
                    // Extract title from first page of PDF
                    if let title = Self.extractPDFTitle(from: tempURL, publication: publicationName) {
                        finalName = title + ".pdf"
                    } else if let suggested = (response as? HTTPURLResponse)?.suggestedFilename ?? response?.suggestedFilename {
                        finalName = "\(publicationName) — \(suggested)"
                    } else {
                        finalName = "\(publicationName) — \(filename)"
                    }
                } else if let suggested = (response as? HTTPURLResponse)?.suggestedFilename ?? response?.suggestedFilename {
                    finalName = suggested
                } else {
                    finalName = filename
                }

                // Sanitise filename
                let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
                finalName = finalName.components(separatedBy: invalid).joined(separator: "-")

                let dest = destFolder.appendingPathComponent(finalName)

                do {
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: dest)
                    var raw = UserDefaults.standard.string(forKey: "newBookPaths") ?? ""
                    let existing = raw.components(separatedBy: ",").filter { !$0.isEmpty }
                    if !existing.contains(finalName) {
                        raw = (existing + [finalName]).joined(separator: ",")
                        UserDefaults.standard.set(raw, forKey: "newBookPaths")
                    }
                    DispatchQueue.main.async { self.onDownloadComplete(finalName) }
                } catch {
                    DispatchQueue.main.async {
                        self.onDownloadError("Could not save \(finalName): \(error.localizedDescription)")
                    }
                }
            }
            task.resume()
        }

        /// Extracts a clean title from the first page of a PDF
        private static func extractPDFTitle(from url: URL, publication: String) -> String? {
            let pdfDoc = PDFDocument(url: url)
            guard let pdfPage = pdfDoc?.page(at: 0),
                  let text = pdfPage.string, !text.isEmpty
            else { return nil }
            return parseTitle(from: text, publication: publication)
        }

        private static func parseTitle(from text: String, publication: String) -> String? {
            let lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var issueNumber: String? = nil
            var candidates: [String] = []

            // Join pairs of short lines that look like they're one title split across two lines
            var i = 0
            while i < lines.count {
                let line = lines[i]
                // Check for issue number
                if let match = line.range(of: #"Issue\s+(\d+)"#, options: .regularExpression) {
                    let num = line[match].components(separatedBy: .whitespaces).last ?? ""
                    issueNumber = "Issue \(num)"
                    i += 1
                    continue
                }
                // Skip junk lines
                if line.hasPrefix("©") || line.count < 3 || line.count > 80 {
                    i += 1
                    continue
                }
                // If this line and next are both short, join them
                if i + 1 < lines.count {
                    let next = lines[i+1]
                    if line.count < 30 && next.count < 30
                        && next.range(of: #"Issue\s+\d+"#, options: .regularExpression) == nil {
                        candidates.append(line + " " + next)
                        i += 2
                        continue
                    }
                    if line.count < 25 && next.count < 35
                        && !next.hasPrefix("©")
                        && next.range(of: #"Issue\s+\d+"#, options: .regularExpression) == nil {
                        candidates.append(line + " " + next)
                        i += 2
                        continue
                    }
                }
                candidates.append(line)
                i += 1
            }

            // Pick the longest candidate as the main title (most descriptive)
            let title = candidates
                .filter { $0.count > 5 }
                .sorted { $0.count > $1.count }
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !title.isEmpty else { return nil }

            if let issue = issueNumber {
                return "\(publication) — \(title) (\(issue))"
            }
            return "\(publication) — \(title)"
        }
    }
}

// MARK: - Branded Quill Placeholder

struct BrandedQuillIcon: View {
    let size: CGFloat

    var body: some View {
        Canvas { ctx, canvasSize in
            let cx = canvasSize.width  / 2
            let cy = canvasSize.height / 2
            let s  = size / 40.0

            ctx.withCGContext { cg in
                cg.translateBy(x: cx, y: cy)
                cg.rotate(by: -.pi / 4)

                #if os(macOS)
                let vane  = NSColor(red: 0.94, green: 0.90, blue: 0.84, alpha: 0.95)
                let spine = NSColor(red: 0.78, green: 0.66, blue: 0.43, alpha: 1.0)
                let nib   = NSColor(red: 0.50, green: 0.35, blue: 0.10, alpha: 1.0)
                #else
                let vane  = UIColor(red: 0.94, green: 0.90, blue: 0.84, alpha: 0.95)
                let spine = UIColor(red: 0.78, green: 0.66, blue: 0.43, alpha: 1.0)
                let nib   = UIColor(red: 0.50, green: 0.35, blue: 0.10, alpha: 1.0)
                #endif

                // Left vane
                let lv = CGMutablePath()
                lv.move(to:    CGPoint(x:  0,    y: -18*s))
                lv.addCurve(to: CGPoint(x: -4*s, y:  -6*s), control1: CGPoint(x: -1*s, y: -14*s), control2: CGPoint(x: -5*s, y: -11*s))
                lv.addCurve(to: CGPoint(x: -4*s, y:   8*s), control1: CGPoint(x: -5*s, y:  -2*s), control2: CGPoint(x: -5*s, y:   3*s))
                lv.addLine(to: CGPoint(x:  0,    y:  14*s))
                lv.closeSubpath()
                cg.addPath(lv); cg.setFillColor(vane.cgColor); cg.fillPath()

                // Right vane
                let rv = CGMutablePath()
                rv.move(to:    CGPoint(x:  0,    y: -18*s))
                rv.addCurve(to: CGPoint(x:  3*s, y:  -6*s), control1: CGPoint(x:  1*s, y: -14*s), control2: CGPoint(x:  4*s, y: -11*s))
                rv.addCurve(to: CGPoint(x:  3*s, y:   8*s), control1: CGPoint(x:  4*s, y:  -2*s), control2: CGPoint(x:  4*s, y:   3*s))
                rv.addLine(to: CGPoint(x:  0,    y:  14*s))
                rv.closeSubpath()
                cg.addPath(rv); cg.setFillColor(vane.cgColor); cg.fillPath()

                // Spine
                cg.setStrokeColor(spine.cgColor)
                cg.setLineWidth(0.9 * s)
                cg.move(to:    CGPoint(x: 0, y: -18*s))
                cg.addLine(to: CGPoint(x: 0, y:  14*s))
                cg.strokePath()

                // Calamus
                cg.setLineWidth(1.2 * s)
                cg.move(to:    CGPoint(x: 0, y:  14*s))
                cg.addLine(to: CGPoint(x: 0, y:  22*s))
                cg.strokePath()

                // Nib
                cg.setStrokeColor(nib.cgColor)
                cg.setLineWidth(0.7 * s)
                cg.move(to:    CGPoint(x: -1.5*s, y: 20*s))
                cg.addLine(to: CGPoint(x:  0.5*s, y: 24*s))
                cg.move(to:    CGPoint(x:  2.0*s, y: 20*s))
                cg.addLine(to: CGPoint(x:  0.5*s, y: 24*s))
                cg.strokePath()
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Cross-book search panel

struct BookSearchPanel: View {
    @ObservedObject var service: BookSearchService
    let books:    [BookFile]
    let accent:   Color
    let onOpen:   (BookSearchResult) -> Void

    @State private var query: String = ""
    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "text.magnifyingglass").foregroundStyle(accent)
                TextField("Search inside all books…", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { runSearch() }
                if service.isSearching {
                    ProgressView().controlSize(.small)
                } else if !query.isEmpty {
                    Button { runSearch() } label: {
                        Text("Search")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(accent)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.platformWindowBg)

            Divider()

            if service.isSearching {
                VStack {
                    Spacer()
                    ProgressView("Searching \(books.filter { $0.format.isEPUB }.count) books…")
                    Spacer()
                }
            } else if service.results.isEmpty && !service.lastQuery.isEmpty {
                VStack {
                    Spacer()
                    Text("No results for \u{201C}\(service.lastQuery)\u{201D}")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if service.results.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 40)).foregroundStyle(.quaternary)
                    Text("Type a word or phrase and tap Search")
                        .foregroundStyle(.secondary)
                    Text("Searches text content across all your EPUB books")
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(service.results) { result in
                        Button { onOpen(result) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(result.bookTitle)
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(result.chapterTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Text(result.snippet)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    private func runSearch() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        service.search(query: query, in: books)
    }
}

// MARK: - Result types

struct BookSearchResult: Identifiable {
    let id       = UUID()
    let bookURL:  URL
    let bookTitle: String
    let chapterTitle: String
    let snippet:  String        // surrounding text with match context
    let href:     String        // chapter href to open
}

// MARK: - Service

final class BookSearchService: ObservableObject {
    @Published var results:    [BookSearchResult] = []
    @Published var isSearching: Bool               = false
    @Published var lastQuery:   String             = ""

    private var task: Task<Void, Never>?

    func search(query: String, in books: [BookFile]) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []; lastQuery = ""; return
        }
        task?.cancel()
        isSearching = true
        lastQuery   = query
        let q       = query

        task = Task {
            var found: [BookSearchResult] = []
            for book in books where book.format.isEPUB {
                if Task.isCancelled { break }
                let bookURL = book.url
                let r = await Task.detached(priority: .userInitiated) {
                    BookSearchService.searchEPUB(url: bookURL, query: q)
                }.value
                found.append(contentsOf: r)
            }
            let results = found
            await MainActor.run {
                self.results    = results
                self.isSearching = false
            }
        }
    }

    func cancel() {
        task?.cancel()
        task        = nil
        isSearching = false
        results     = []
        lastQuery   = ""
    }

    // MARK: - EPUB text search

    nonisolated static func searchEPUB(url: URL, query: String) -> [BookSearchResult] {
        guard let archive = try? Archive(url: url, accessMode: .read, pathEncoding: nil) else { return [] }
        let book = EPUBParser.parse(url: url) ?? makeBasicBook(url: url, archive: archive)
        let spineHrefs = extractSpineHrefs(from: archive, opfBase: book.opfBase)
        var results: [BookSearchResult] = []

        // Build whole-word regex once
        let escapedQuery = NSRegularExpression.escapedPattern(for: query)
        guard let wordRegex = try? NSRegularExpression(pattern: "\\b\(escapedQuery)\\b",
                                                        options: .caseInsensitive)
        else { return results }

        for href in spineHrefs {
            guard let data = EPUBParser.read(href, from: archive),
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            else { continue }

            let text = stripHTML(html)
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)

            if let match = wordRegex.firstMatch(in: text, range: fullRange) {
                if let swiftRange = Range(match.range, in: text) {
                    let snippet = extractSnippet(from: text, around: swiftRange, query: query)
                    let chapterTitle = chapterTitleFor(href: href, in: book.toc)
                    results.append(BookSearchResult(
                        bookURL:      url,
                        bookTitle:    book.title,
                        chapterTitle: chapterTitle,
                        snippet:      snippet,
                        href:         href
                    ))
                }
            }
        }
        return results
    }

    // MARK: - Helpers

    private static func makeBasicBook(url: URL, archive: Archive) -> EPUBBook {
        var b = EPUBBook(url: url)
        b.title = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return b
    }

    private static func extractSpineHrefs(from archive: Archive, opfBase: String) -> [String] {
        // Try to find OPF file and extract spine hrefs
        guard let containerData = EPUBParser.read("META-INF/container.xml", from: archive),
              let containerStr  = String(data: containerData, encoding: .utf8),
              let opfPath       = extractAttr(containerStr, tag: "rootfile", attr: "full-path"),
              let opfData       = EPUBParser.read(opfPath, from: archive),
              let opfStr        = String(data: opfData, encoding: .utf8)
        else { return fallbackHTMLFiles(from: archive) }

        let base = (opfPath as NSString).deletingLastPathComponent
        // Extract manifest id -> href
        var manifest: [String: String] = [:]
        let manifestPattern = #"<item[^>]+id="([^"]+)"[^>]+href="([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: manifestPattern) {
            let matches = regex.matches(in: opfStr, range: NSRange(opfStr.startIndex..., in: opfStr))
            for m in matches {
                if let idRange   = Range(m.range(at: 1), in: opfStr),
                   let hrefRange = Range(m.range(at: 2), in: opfStr) {
                    let id   = String(opfStr[idRange])
                    let href = String(opfStr[hrefRange])
                    manifest[id] = base.isEmpty ? href : "\(base)/\(href)"
                }
            }
        }
        // Extract spine order
        let spinePattern = #"<itemref[^>]+idref="([^"]+)""#
        var hrefs: [String] = []
        if let regex = try? NSRegularExpression(pattern: spinePattern) {
            let matches = regex.matches(in: opfStr, range: NSRange(opfStr.startIndex..., in: opfStr))
            for m in matches {
                if let idRange = Range(m.range(at: 1), in: opfStr) {
                    let id = String(opfStr[idRange])
                    if let href = manifest[id] { hrefs.append(href) }
                }
            }
        }
        return hrefs.isEmpty ? fallbackHTMLFiles(from: archive) : hrefs
    }

    private static func fallbackHTMLFiles(from archive: Archive) -> [String] {
        var hrefs: [String] = []
        for entry in archive where entry.type == .file {
            let p = entry.path.lowercased()
            if p.hasSuffix(".html") || p.hasSuffix(".xhtml") || p.hasSuffix(".htm") {
                hrefs.append(entry.path)
            }
        }
        return hrefs.sorted()
    }

    private static func extractAttr(_ str: String, tag: String, attr: String) -> String? {
        let pattern = "<\(tag)[^>]+\(attr)=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)),
              let r = Range(m.range(at: 1), in: str)
        else { return nil }
        return String(str[r])
    }

    private static func stripHTML(_ html: String) -> String {
        // Remove script/style blocks
        var text = html
        for tag in ["script", "style"] {
            let pattern = "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>"
            if let r = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = r.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
            }
        }
        // Remove tags
        if let r = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = r.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        // Decode common entities
        text = text
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
        // Collapse whitespace
        if let r = try? NSRegularExpression(pattern: "\\s+") {
            text = r.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func extractSnippet(from text: String, around range: Range<String.Index>, query: String) -> String {
        let contextLen = 80
        let start = text.index(range.lowerBound, offsetBy: -min(contextLen, text.distance(from: text.startIndex, to: range.lowerBound)), limitedBy: text.startIndex) ?? text.startIndex
        let end   = text.index(range.upperBound, offsetBy: min(contextLen, text.distance(from: range.upperBound, to: text.endIndex)), limitedBy: text.endIndex) ?? text.endIndex
        var snippet = String(text[start..<end]).trimmingCharacters(in: .whitespaces)
        if start > text.startIndex { snippet = "…" + snippet }
        if end   < text.endIndex   { snippet = snippet + "…" }
        return snippet
    }

    private static func chapterTitleFor(href: String, in toc: [TOCItem]) -> String {
        func search(_ items: [TOCItem]) -> String? {
            for item in items {
                if item.href.contains(href) || href.contains(item.href) { return item.title }
                if let found = search(item.children) { return found }
            }
            return nil
        }
        return search(toc) ?? (href as NSString).lastPathComponent
    }
}

// MARK: - Magazines View

struct MagazinesView: View {
    let booksFolder: String

    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }

    @State private var publications: [MagazinePublication] = []
    @State private var selectedFile: URL?     = nil
    @State private var expandedPub: String?   = nil

    var body: some View {
        Group {
            if let url = selectedFile {
                VStack(spacing: 0) {
                    HStack {
                        Button { selectedFile = nil } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Magazines")
                            }
                            .foregroundStyle(filigreeAccent)
                            .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        Spacer()
                    }
                    Divider()
                    PDFReaderView(pdfURL: url)
                }
            } else if publications.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "magazine")
                        .font(.system(size: 48)).foregroundStyle(.quaternary)
                    Text("No magazines yet")
                        .font(.title3).foregroundStyle(.secondary).padding(.top, 8)
                    Text("Download magazines from the Discover tab.\nThey'll appear here organised by publication.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center).padding(.top, 4)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(publications) { pub in
                            // Publication header
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedPub = expandedPub == pub.name ? nil : pub.name
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "magazine.fill")
                                        .foregroundStyle(filigreeAccent)
                                        .frame(width: 24)
                                    Text(pub.name)
                                        .font(.system(size: 14, weight: .semibold))
                                    Spacer()
                                    Text("\(pub.issues.count) issue\(pub.issues.count == 1 ? "" : "s")")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Image(systemName: expandedPub == pub.name ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Color.platformWindowBg)
                            }
                            .buttonStyle(.plain)

                            Divider()

                            if expandedPub == pub.name {
                                ForEach(pub.issues) { issue in
                                    Button { selectedFile = issue.url } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "doc.richtext.fill")
                                                .foregroundStyle(filigreeAccent.opacity(0.7))
                                                .frame(width: 24)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(issue.displayName)
                                                    .font(.system(size: 13))
                                                    .lineLimit(2)
                                                Text(issue.fileSize)
                                                    .font(.caption2).foregroundStyle(.tertiary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 11)).foregroundStyle(.tertiary)
                                        }
                                        .padding(.leading, 40).padding(.trailing, 16).padding(.vertical, 8)
                                    }
                                    .buttonStyle(.plain)
                                    Divider().padding(.leading, 40)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { scanMagazines() }
    }

    private func scanMagazines() {
        guard !booksFolder.isEmpty else { return }
        let magazinesURL = URL(fileURLWithPath: booksFolder)
            .appendingPathComponent("Magazines")
        guard FileManager.default.fileExists(atPath: magazinesURL.path) else { return }

        var pubs: [MagazinePublication] = []
        let fm = FileManager.default

        guard let pubFolders = try? fm.contentsOfDirectory(
            at: magazinesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles)
        else { return }

        for pubFolder in pubFolders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: pubFolder.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }

            let pubName = pubFolder.lastPathComponent
            guard let files = try? fm.contentsOfDirectory(
                at: pubFolder,
                includingPropertiesForKeys: [.fileSizeKey],
                options: .skipsHiddenFiles)
            else { continue }

            let issues: [MagazineIssue] = files
                .filter { ["pdf","epub"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
                .map { fileURL in
                    let name = fileURL.deletingPathExtension().lastPathComponent
                    // Strip publication prefix if present e.g. "Christian History — Title" → "Title"
                    let display = name.hasPrefix(pubName + " — ")
                        ? String(name.dropFirst(pubName.count + 3))
                        : name
                    let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    let sizeStr = size > 0 ? ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) : ""
                    return MagazineIssue(url: fileURL, displayName: display, fileSize: sizeStr)
                }

            if !issues.isEmpty {
                pubs.append(MagazinePublication(name: pubName, issues: issues))
            }
        }

        publications = pubs
        // Auto-expand if only one publication
        if pubs.count == 1 { expandedPub = pubs[0].name }
    }
}

struct MagazinePublication: Identifiable {
    let id   = UUID()
    let name: String
    let issues: [MagazineIssue]
}

struct MagazineIssue: Identifiable {
    let id          = UUID()
    let url:         URL
    let displayName: String
    let fileSize:    String
}
