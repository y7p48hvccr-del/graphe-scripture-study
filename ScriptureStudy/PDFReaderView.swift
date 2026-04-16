import SwiftUI
import PDFKit
#if os(macOS)
import AppKit
#endif

// MARK: - PDF Bookmark

struct PDFBookmark: Identifiable, Codable {
    let id:    UUID
    let page:  Int
    let title: String
}

// MARK: - PDF Reader View

struct PDFReaderView: View {

    let pdfURL: URL

    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"

    var accent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var theme:  AppTheme { AppTheme.find(themeID) }

    @State private var pdfDocument:   PDFDocument? = nil
    @State private var currentPage:   Int          = 0
    @State private var totalPages:    Int          = 0
    @State private var bookmarks:     [PDFBookmark] = []
    @State private var showBookmarks: Bool         = true
    @State private var showOutline:   Bool         = true
    @State private var pageInput:     String       = ""

    // Persist last-read page per file
    private var lastPageKey: String { "pdf_lastpage_\(pdfURL.lastPathComponent)" }
    private var bookmarksKey: String { "pdf_bookmarks_\(pdfURL.lastPathComponent)" }

    var isBookmarked: Bool { bookmarks.contains { $0.page == currentPage } }

    var body: some View {
        HStack(spacing: 0) {
            // ── Sidebar ──────────────────────────────────────────────────
            VStack(spacing: 0) {
                // File title
                HStack {
                    Text(pdfURL.deletingPathExtension().lastPathComponent
                            .replacingOccurrences(of: "_", with: " ")
                            .replacingOccurrences(of: "-", with: " "))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.platformWindowBg)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {

                        // ── Bookmarks ─────────────────────────────────
                        if !bookmarks.isEmpty {
                            HStack {
                                Image(systemName: showBookmarks ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text("BOOKMARKS")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture { showBookmarks.toggle() }

                            if showBookmarks {
                                ForEach(bookmarks) { bm in
                                    HStack(spacing: 8) {
                                        Rectangle().fill(Color.clear).frame(width: 8)
                                        Image(systemName: "bookmark.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(accent)
                                        Text(bm.title)
                                            .font(.system(size: 12))
                                            .foregroundStyle(bm.page == currentPage ? accent : .primary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("p.\(bm.page + 1)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                        Button {
                                            bookmarks.removeAll { $0.id == bm.id }
                                            saveBookmarks()
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }.buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 5)
                                    .background(bm.page == currentPage ? accent.opacity(0.10) : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture { goToPage(bm.page) }
                                }
                                Divider().padding(.vertical, 4)
                            }
                        }

                        // ── Outline / TOC ─────────────────────────────
                        if let outline = pdfDocument?.outlineRoot, outline.numberOfChildren > 0 {
                            HStack {
                                Image(systemName: showOutline ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text("CONTENTS")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture { showOutline.toggle() }

                            if showOutline {
                                PDFOutlineView(
                                    outline:     outline,
                                    document:    pdfDocument!,
                                    currentPage: currentPage,
                                    accent:      accent,
                                    depth:       0,
                                    onSelect:    { goToPage($0) }
                                )
                            }
                        } else {
                            // No outline — show page list
                            HStack {
                                Text("PAGES")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)

                            ForEach(0..<totalPages, id: \.self) { i in
                                HStack {
                                    Text("Page \(i + 1)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(i == currentPage ? accent : .primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 20).padding(.vertical, 4)
                                .background(i == currentPage ? accent.opacity(0.10) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { goToPage(i) }
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
                .background(Color.platformWindowBg)
            }
            .frame(minWidth: 200, maxWidth: 260)

            Divider()

            // ── PDF View ──────────────────────────────────────────────────
            ZStack(alignment: .topTrailing) {
                PDFKitView(
                    url:         pdfURL,
                    document:    $pdfDocument,
                    currentPage: $currentPage,
                    totalPages:  $totalPages
                )
                .background(theme.background)

                // Bookmark ribbon — top right corner
                VStack {
                    Button {
                        toggleBookmark()
                    } label: {
                        BookmarkRibbon()
                            .fill(isBookmarked ? Color(red: 0.25, green: 0.45, blue: 0.75) : Color.gray.opacity(0.12))
                            .overlay(
                                BookmarkRibbon()
                                    .stroke(isBookmarked ? Color(red: 0.25, green: 0.45, blue: 0.75).opacity(0.7) : Color.gray.opacity(0.25),
                                            lineWidth: 0.75)
                            )
                            .contentShape(BookmarkRibbon())
                            .frame(width: 16, height: 34)
                            .animation(.easeInOut(duration: 0.15), value: isBookmarked)
                    }
                    .buttonStyle(.plain)
                    .help(isBookmarked ? "Remove bookmark" : "Bookmark this page")
                    Spacer()
                }
                .padding(.top, 2).padding(.trailing, 22)
            }
        }
        .onAppear { loadBookmarks(); restoreLastPage() }
        .onChange(of: currentPage) { _ in saveLastPage() }
    }

    // MARK: - Navigation

    private func goToPage(_ page: Int) {
        guard let doc = pdfDocument, page >= 0, page < doc.pageCount else { return }
        NotificationCenter.default.post(
            name: .pdfGoToPage,
            object: nil,
            userInfo: ["page": page]
        )
    }

    // MARK: - Bookmarks

    private func toggleBookmark() {
        if isBookmarked {
            bookmarks.removeAll { $0.page == currentPage }
        } else {
            let title = pdfDocument?.page(at: currentPage)?.label ?? "Page \(currentPage + 1)"
            bookmarks.insert(PDFBookmark(id: UUID(), page: currentPage, title: title), at: 0)
        }
        saveBookmarks()
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }

    private func loadBookmarks() {
        if let data = UserDefaults.standard.data(forKey: bookmarksKey),
           let bms  = try? JSONDecoder().decode([PDFBookmark].self, from: data) {
            bookmarks = bms
        }
    }

    private func saveLastPage() {
        UserDefaults.standard.set(currentPage, forKey: lastPageKey)
    }

    private func restoreLastPage() {
        let saved = UserDefaults.standard.integer(forKey: lastPageKey)
        if saved > 0 { goToPage(saved) }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let pdfGoToPage = Notification.Name("pdfGoToPage")
}

// MARK: - PDFKit cross-platform view wrapper

#if os(macOS)
typealias PDFViewRepresentable = NSViewRepresentable
typealias PlatformPDFViewType  = NSView
#else
typealias PDFViewRepresentable = UIViewRepresentable
typealias PlatformPDFViewType  = UIView
#endif

struct PDFKitView: PDFViewRepresentable {
    let url:          URL
    @Binding var document:    PDFDocument?
    @Binding var currentPage: Int
    @Binding var totalPages:  Int

    #if os(macOS)
    func makeNSView(context: Context) -> PDFView { makeView(context: context) }
    func updateNSView(_ nsView: PDFView, context: Context) {}
    #else
    func makeUIView(context: Context) -> PDFView { makeView(context: context) }
    func updateUIView(_ uiView: PDFView, context: Context) {}
    #endif

    private func makeView(context: Context) -> PDFView {
        let pdfView              = PDFView()
        pdfView.autoScales       = true
        pdfView.displayMode      = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.pageShadowsEnabled = false
        pdfView.displayBox       = .trimBox  // clips crop/bleed/registration marks

        if let doc = PDFDocument(url: url) {
            pdfView.document = doc
            DispatchQueue.main.async {
                document   = doc
                totalPages = doc.pageCount
                currentPage = 0
            }
        }

        // Observe page changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        // Observe navigation requests from sidebar
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.goToPage(_:)),
            name: .pdfGoToPage,
            object: nil
        )

        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent:  PDFKitView
        weak var pdfView: PDFView?

        init(_ parent: PDFKitView) { self.parent = parent }

        @objc func pageChanged(_ note: Notification) {
            guard let pdfView = note.object as? PDFView,
                  let page    = pdfView.currentPage,
                  let doc     = pdfView.document else { return }
            let index = doc.index(for: page)
            DispatchQueue.main.async { self.parent.currentPage = index }
        }

        @objc func goToPage(_ note: Notification) {
            guard let page = note.userInfo?["page"] as? Int,
                  let doc  = pdfView?.document,
                  let p    = doc.page(at: page) else { return }
            pdfView?.go(to: p)
        }
    }
}

// MARK: - PDF Outline View (recursive)

struct PDFOutlineView: View {
    let outline:     PDFOutline
    let document:    PDFDocument
    let currentPage: Int
    let accent:      Color
    let depth:       Int
    let onSelect:    (Int) -> Void

    var body: some View {
        ForEach(0..<outline.numberOfChildren, id: \.self) { i in
            if let child = outline.child(at: i) {
                PDFOutlineRowView(
                    node:        child,
                    document:    document,
                    currentPage: currentPage,
                    accent:      accent,
                    depth:       depth,
                    onSelect:    onSelect
                )
            }
        }
    }
}

struct PDFOutlineRowView: View {
    let node:        PDFOutline
    let document:    PDFDocument
    let currentPage: Int
    let accent:      Color
    let depth:       Int
    let onSelect:    (Int) -> Void

    @State private var isExpanded = true

    var pageIndex: Int? {
        guard let dest = node.destination,
              let page = dest.page else { return nil }
        return document.index(for: page)
    }

    var isSelected: Bool { pageIndex == currentPage }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(Color.clear).frame(width: CGFloat(depth) * 14 + 8)
                if node.numberOfChildren > 0 {
                    Button { isExpanded.toggle() } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary).frame(width: 16)
                    }.buttonStyle(.plain)
                } else {
                    Rectangle().fill(Color.clear).frame(width: 16)
                }
                Button {
                    if let p = pageIndex { onSelect(p) }
                } label: {
                    Text(node.label ?? "Untitled")
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? accent : .primary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5).padding(.trailing, 8)
                }.buttonStyle(.plain)
            }
            .background(isSelected ? accent.opacity(0.10) : Color.clear)

            if isExpanded && node.numberOfChildren > 0 {
                PDFOutlineView(
                    outline:     node,
                    document:    document,
                    currentPage: currentPage,
                    accent:      accent,
                    depth:       depth + 1,
                    onSelect:    onSelect
                )
            }
        }
    }
}
