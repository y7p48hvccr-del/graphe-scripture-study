import SwiftUI
import PDFKit
#if os(macOS)
import AppKit
#endif

// PDF_FIX_V9 — 2026-04-21 — bookmarks now store precise scroll position
// (PDFBookmark.destinationY), matching EPUB precision. PDFKitView
// continuously reports the top-of-viewport Y via the scrollY binding;
// toggleBookmark captures that value when adding a bookmark. The
// unified bookmarks panel in EPUBLibraryView posts pdfGoToDestination
// when a PDF entry is clicked, restoring the user's exact spot.
//
// Also: bookmark mutations now post .libraryBookmarksChanged so the
// panel refreshes immediately. Floating-subview ribbon (V6/V8 design)
// retained — visible when current page contains a bookmark.
//
// V8 (basis) — AppKit floating subview ribbon, decorative only.
// V7 (superseded interim) — added scroll capture but as ribbon-click
// jump target, before the "ribbon is decoration only" decision was
// finalised. V9 brings back the scroll capture for panel use only.
// V2–V5 (superseded) — SwiftUI overlay attempts that vanished on
// PDFKit scroll. V1 (still in effect) — bookmark in window toolbar.

// MARK: - PDF Bookmark

struct PDFBookmark: Identifiable, Codable {
    let id:    UUID
    let page:  Int
    let title: String
    /// Precise scroll position within the page where the bookmark was
    /// dropped, in PDFKit page-local coordinates (origin at page bottom).
    /// Optional so older bookmarks (saved before this field existed)
    /// load gracefully; for those, opening a bookmark just lands at
    /// the page top.
    var destinationY: Double? = nil
}

// MARK: - PDF Reader View

struct PDFReaderView: View {

    let pdfURL: URL
    /// Optional page to navigate to as soon as the document loads.
    /// Used when opening a PDF from a bookmark click in the unified
    /// bookmarks panel — without this, the reader would honour
    /// `restoreLastPage` instead of going to the bookmarked page.
    var initialPage: Int? = nil
    /// Optional page-local scroll Y to land on once the page is shown.
    /// Paired with `initialPage` so panel-bookmark clicks can restore
    /// the user's exact spot, matching EPUB precision.
    var initialDestinationY: Double? = nil

    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"

    var accent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var theme:  AppTheme { AppTheme.find(themeID) }

    @State private var pdfDocument:   PDFDocument? = nil
    @State private var currentPage:   Int          = 0
    @State private var totalPages:    Int          = 0
    /// Latest scroll Y in page-local coordinates, updated continuously
    /// by PDFKitView's coordinator. Read by `toggleBookmark` so the new
    /// bookmark records the user's exact spot, not just the page.
    @State private var currentScrollY: Double = 0
    @State private var bookmarks:     [PDFBookmark] = []
    @State private var showBookmarks: Bool         = true
    @State private var showOutline:   Bool         = true
    @State private var pageInput:     String       = ""

    // Persist last-read page per file
    private var lastPageKey: String { "pdf_lastpage_\(pdfURL.lastPathComponent)" }
    private var bookmarksKey: String { "pdf_bookmarks_\(pdfURL.lastPathComponent)" }

    var isBookmarked: Bool { bookmarks.contains { $0.page == currentPage } }

    /// Title shown in the window title bar — cleaned-up filename, matches
    /// the EPUB reader's treatment.
    private var readerTitle: String {
        pdfURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

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
                                            .foregroundStyle(SilkBookmarkRibbonView.silkRed)
                                        Text(bm.title)
                                            .font(.system(size: 12))
                                            .foregroundStyle(bm.page == currentPage ? SilkBookmarkRibbonView.silkRed : .primary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("p.\(bm.page + 1)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                        Button {
                                            bookmarks.removeAll { $0.id == bm.id }
                                            saveBookmarks()
                                            NotificationCenter.default.post(
                                                name: .libraryBookmarksChanged, object: nil)
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
            // PDFKitView mounts the silk bookmark ribbon as a floating
            // subview of its own NSScrollView. Floating subviews are
            // pinned to the viewport — they don't scroll with PDF
            // content. The ribbon is purely decorative: visible whenever
            // the current page contains a bookmark, dismissed only by
            // clicking the toolbar bookmark button. The ribbon itself
            // is non-interactive.
            PDFKitView(
                url:         pdfURL,
                document:    $pdfDocument,
                currentPage: $currentPage,
                totalPages:  $totalPages,
                scrollY:     $currentScrollY,
                isBookmarked: isBookmarked
            )
            .background(theme.background)
        }
        .navigationTitle(readerTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    // Previous page
                    Button { goToPage(currentPage - 1) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(currentPage <= 0)
                    .help("Previous page")

                    // Page counter / jump field
                    Text("\(currentPage + 1) / \(max(totalPages, 1))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 52)
                        .help("Current page / total pages")

                    // Next page
                    Button { goToPage(currentPage + 1) } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(currentPage >= totalPages - 1)
                    .help("Next page")

                    Divider().frame(height: 16)

                    // Bookmark — matches EPUB V8 placement and colour.
                    // Active state uses the silk ribbon's red so the
                    // toolbar control and the on-page ribbon read as
                    // one system. PDFKit handles Cmd+F find natively,
                    // so no separate search button needed here.
                    if pdfDocument != nil {
                        Button { toggleBookmark() } label: {
                            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                                .foregroundStyle(isBookmarked ? SilkBookmarkRibbonView.silkRed : .primary)
                        }.help(isBookmarked ? "Remove bookmark" : "Bookmark this page")
                    }
                }
            }
        }
        .onAppear {
            loadBookmarks()
            // initialPage takes precedence over restoreLastPage when set
            // (used by bookmark clicks from the unified bookmarks panel).
            // Tiny delay because the PDFView needs the document loaded
            // before navigation will take effect.
            if let target = initialPage {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if let y = initialDestinationY {
                        // Precise destination — page + scroll Y
                        NotificationCenter.default.post(
                            name: .pdfGoToDestination,
                            object: nil,
                            userInfo: ["page": target, "y": y])
                    } else {
                        // Page only (older bookmark)
                        goToPage(target)
                    }
                }
            } else {
                restoreLastPage()
            }
        }
        .onChange(of: currentPage) { saveLastPage() }
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
            // Capture current scroll Y so panel-bookmark clicks can
            // restore the user's exact spot, matching EPUB precision.
            bookmarks.insert(
                PDFBookmark(id: UUID(),
                            page: currentPage,
                            title: title,
                            destinationY: currentScrollY),
                at: 0)
        }
        saveBookmarks()
        // Notify the unified bookmarks panel so it refreshes immediately
        // rather than waiting for the next .onAppear.
        NotificationCenter.default.post(name: .libraryBookmarksChanged, object: nil)
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
    /// Sent by the unified bookmarks panel (or any code wanting to land
    /// at a precise spot) carrying `page` and `y` (page-local Y). The
    /// PDFKitView coordinator uses PDFDestination to navigate.
    static let pdfGoToDestination = Notification.Name("pdfGoToDestination")
    /// Sent by either reader after any bookmark mutation (add, remove
    /// via toolbar, remove via sidebar X). The unified bookmarks panel
    /// in EPUBLibraryView listens for this and rebuilds its list, so
    /// the panel updates immediately rather than waiting for the next
    /// .onAppear.
    static let libraryBookmarksChanged = Notification.Name("libraryBookmarksChanged")
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
    /// Latest scroll Y in page-local coordinates, posted up by the
    /// Coordinator on every scroll. Read by PDFReaderView.toggleBookmark
    /// when the user creates a new bookmark.
    @Binding var scrollY:     Double
    /// Current bookmark state, passed in from PDFReaderView. Drives the
    /// AppKit-side floating ribbon visibility on every SwiftUI update
    /// pass via `updateNSView`.
    var isBookmarked: Bool = false

    #if os(macOS)
    func makeNSView(context: Context) -> PDFView { makeView(context: context) }
    func updateNSView(_ nsView: PDFView, context: Context) {
        // Reflect the latest SwiftUI state into the AppKit ribbon. The
        // hosting view's rootView is replaced (not mutated) so SwiftUI
        // re-evaluates and the ribbon shows/hides as `isBookmarked`
        // changes from outside (toolbar button click or sidebar X).
        context.coordinator.refreshRibbon(isBookmarked: isBookmarked)
    }
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

        // Observe precise destination requests from the unified bookmarks
        // panel (page + page-local Y).
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.goToDestination(_:)),
            name: .pdfGoToDestination,
            object: nil
        )

        context.coordinator.pdfView = pdfView

        #if os(macOS)
        // Set up scroll-position tracking. NSScrollView is buried inside
        // PDFView and may not exist yet when makeView is called, so we
        // try now and again on the next runloop tick.
        let attachScrollObserver = {
            guard let scroll = pdfView.enclosingScrollView else { return }
            scroll.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.scrollChanged(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scroll.contentView
            )
        }
        attachScrollObserver()
        DispatchQueue.main.async { attachScrollObserver() }

        // Mount the floating silk ribbon as soon as PDFView has joined
        // a window (and therefore has an enclosing NSScrollView). Done
        // on the next runloop tick because PDFView's scroll view
        // hierarchy isn't fully constructed inside makeView itself.
        DispatchQueue.main.async {
            context.coordinator.installRibbon(initialBookmarked: isBookmarked)
        }
        #endif

        return pdfView
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent:  PDFKitView
        weak var pdfView: PDFView?
        #if os(macOS)
        /// NSHostingView wrapping the SwiftUI silk ribbon. Lives as a
        /// floating subview of PDFView's enclosing NSScrollView, which
        /// keeps it pinned to the viewport as the user scrolls.
        var ribbonHost: NSHostingView<AnyView>?
        #endif

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

        /// Jump to a precise page + page-local Y position. Used when the
        /// user clicks an entry in the unified bookmarks panel.
        @objc func goToDestination(_ note: Notification) {
            guard let page = note.userInfo?["page"] as? Int,
                  let y    = note.userInfo?["y"]    as? Double,
                  let pdfView = pdfView,
                  let doc  = pdfView.document,
                  let p    = doc.page(at: page) else { return }
            let dest = PDFDestination(page: p, at: NSPoint(x: 0, y: y))
            pdfView.go(to: dest)
        }

        #if os(macOS)
        /// Continuously updated as the user scrolls. Captures the
        /// top-of-viewport position in page-local coordinates so that
        /// PDFReaderView.toggleBookmark can record the precise spot
        /// when the user creates a new bookmark.
        @objc func scrollChanged(_ note: Notification) {
            guard let pdfView = pdfView,
                  let scroll  = pdfView.enclosingScrollView,
                  let page    = pdfView.currentPage else { return }
            let visibleRect = scroll.documentVisibleRect
            // PDFKit page coordinates have Y origin at the page bottom,
            // so the top-of-viewport Y in document space corresponds to
            // visibleRect.maxY (top of visible region). Convert that
            // point into the current page's coordinate space.
            let topPointInDoc = NSPoint(x: visibleRect.minX,
                                        y: visibleRect.maxY)
            let pointOnPage = pdfView.convert(topPointInDoc, to: page)
            DispatchQueue.main.async {
                self.parent.scrollY = Double(pointOnPage.y)
            }
        }
        #endif

        #if os(macOS)
        /// Build the NSHostingView and attach it as a floating subview
        /// of PDFView's enclosing scroll view. NSScrollView's floating
        /// subviews are rendered above the document view and do NOT
        /// scroll with content — the AppKit pattern designed for pinned
        /// UI like line numbers. Cf. NSScrollView.addFloatingSubview.
        func installRibbon(initialBookmarked: Bool) {
            guard let pdfView = pdfView,
                  let scroll  = pdfView.enclosingScrollView,
                  ribbonHost == nil else { return }

            let host = NSHostingView(rootView: AnyView(
                ribbonView(isBookmarked: initialBookmarked)
            ))
            host.translatesAutoresizingMaskIntoConstraints = true
            host.autoresizingMask = [.minXMargin]  // pinned right
            // Frame: 12pt wide ribbon + breathing room. Right-anchored
            // so it stays clear of the NSScroller without overlapping.
            let ribbonWidth:  CGFloat = 12
            let ribbonHeight: CGFloat = 200
            let rightInset:   CGFloat = 28
            let topInset:     CGFloat = 0
            let docVisibleWidth = scroll.documentVisibleRect.width
            host.frame = NSRect(
                x: docVisibleWidth - rightInset - ribbonWidth,
                y: topInset,
                width:  ribbonWidth,
                height: ribbonHeight
            )

            scroll.addFloatingSubview(host, for: .vertical)
            ribbonHost = host
        }

        /// Replace the hosted SwiftUI rootView so the ribbon reflects
        /// the latest bookmark state. Called from updateNSView every
        /// time SwiftUI sees a state change.
        func refreshRibbon(isBookmarked: Bool) {
            guard let host = ribbonHost else { return }
            host.rootView = AnyView(ribbonView(isBookmarked: isBookmarked))
        }

        /// The SwiftUI ribbon — purely decorative. No click target,
        /// no interaction. Visible whenever the current page contains
        /// a bookmark; hidden otherwise. Dismissed only by the toolbar
        /// bookmark button or the sidebar X.
        @ViewBuilder
        private func ribbonView(isBookmarked: Bool) -> some View {
            ZStack(alignment: .top) {
                if isBookmarked {
                    SilkBookmarkRibbonView(length: 200, width: 12)
                        .allowsHitTesting(false)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal:   .opacity
                        ))
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.75),
                       value: isBookmarked)
        }
        #endif
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
