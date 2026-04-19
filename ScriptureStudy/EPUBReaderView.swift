import SwiftUI
import WebKit
import ZIPFoundation

/// Serial queue for all ZIPFoundation Archive access — Archive is NOT thread-safe.
private let epubArchiveQueue = DispatchQueue(label: "com.graphe.epub.archive", qos: .userInitiated)

struct EPUBBookmark: Identifiable, Codable {
    let id:      UUID   = UUID()
    let href:    String
    let title:   String
    var scrollY: Double = 0
    enum CodingKeys: String, CodingKey { case id, href, title, scrollY }
}

struct EPUBReaderView: View {
    let epubURL: URL
    var folderURL:          URL?    = nil   // security-scoped parent folder
    var initialHref:        String? = nil
    var initialSearchQuery: String? = nil
    var initialScrollY:     Double  = 0

    @EnvironmentObject var myBible: MyBibleService

    @AppStorage("fontSize")      private var fontSize:  Double = 16
    @AppStorage("epubFontSize")  private var epubFontSize: Double = 17
    @AppStorage("fontName")      private var fontName:  String = ""
    @AppStorage("themeID")       private var themeID:   String = "light"
    @AppStorage("filigreeColor") private var filigreeColor: Int = 0
    var theme:  AppTheme { AppTheme.find(themeID) }
    var accent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }

    @State private var book:         EPUBBook? = nil
    @State private var archive:      Archive?  = nil
    @State private var isParsing:    Bool      = true
    @State private var heldFolderURL: URL?     = nil  // keeps folder security scope alive
    @State private var toc:          [TOCItem] = []
    @State private var currentHref:  String    = ""
    @State private var currentTitle: String    = ""
    @State private var currentScrollY: Double   = 0
    @State private var restoreScrollY: Double   = 0
    @State private var bookmarks:    [EPUBBookmark] = []
    @State private var showBookmarks:    Bool          = true
    @State private var scriptureRef:       ScriptureRef? = nil
    @State private var showScripturePanel: Bool          = false
    @State private var showSearch:         Bool          = false
    @State private var searchQuery:        String        = ""
    @State private var searchCount:        Int           = 0
    @State private var searchIndex:        Int           = 0


    var body: some View {
        Group {
            if isParsing {
                VStack { Spacer(); ProgressView("Opening book…"); Spacer() }
                    .background(theme.background)
            } else if let book = book {
                #if os(macOS)
                HSplitView {
                    tocSidebar(book: book).frame(minWidth: 200, maxWidth: 260)
                    ZStack(alignment: .bottom) {
                    if let arc = archive, !currentHref.isEmpty {
                        ZStack(alignment: .topTrailing) {
                        EPUBPageView(href: currentHref, archive: arc, theme: theme,
                                     fontSize: epubFontSize, fontName: fontName,
                                     onNavigate: { target in
                                         let base = (currentHref as NSString).deletingLastPathComponent
                                         let newHref = base.isEmpty ? target : "\(base)/\(target)"
                                         currentHref  = newHref
                                         if let item = findTOCItem(href: newHref, in: toc) {
                                             currentTitle = item.title
                                         }
                                     },
                                     restoreScrollY: restoreScrollY,
                                     onScrollY:      { y in currentScrollY = y },
                                     searchQuery:    searchQuery,
                                     searchStep:     searchIndex,
                                     searchForward:  true,
                                     onSearchCount:  { n in searchCount = n; searchIndex = 0 },
                                     onSearchIndex:  { i in searchIndex = i })
                            .id(currentHref)
                            Button { toggleBookmark() } label: {
                                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 22))
                                    .foregroundStyle(isBookmarked ? Color(red: 0.25, green: 0.45, blue: 0.75) : Color.secondary.opacity(0.3))
                                    .padding(12)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        VStack {
                            Spacer()
                            Image(systemName: "book.closed")
                                .font(.system(size: 48)).foregroundStyle(.quaternary)
                            Text("Select a chapter from the contents")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity).background(theme.background)
                    }
                    if showScripturePanel, let ref = scriptureRef {
                        VStack(spacing: 0) {
                            Capsule().fill(Color.secondary.opacity(0.3))
                                .frame(width: 36, height: 4).padding(.top, 8)
                            ScriptureSlideUpPanel(
                                ref: ref,
                                onDismiss: { withAnimation(.spring(response: 0.35)) { showScripturePanel = false } },
                                onOpenInBible: { r in
                                    showScripturePanel = false
                                    let resolved = ScriptureReferenceParser.resolveBookNumber(r, in: myBible)
                                    NotificationCenter.default.post(
                                        name: Notification.Name("navigateToPassage"), object: nil,
                                        userInfo: ["bookNumber": resolved.bookNumber, "chapter": resolved.chapter, "verse": resolved.verse])
                                }
                            ).environmentObject(myBible)
                        }
                        .frame(maxWidth: .infinity).frame(height: 380)
                        .background(Color.platformWindowBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: -4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(10)
                    }
                    // Search bar
                    if showSearch {
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                TextField("Search in this book…", text: $searchQuery)
                                    .textFieldStyle(.plain)
                                    .onSubmit { searchIndex += 1 }
                                if searchCount > 0 {
                                    Text("\(searchIndex + 1) of \(searchCount)")
                                        .font(.caption).foregroundStyle(.secondary).frame(minWidth: 52)
                                    Button { searchIndex = max(0, searchIndex - 1) } label: {
                                        Image(systemName: "chevron.up").font(.system(size: 11))
                                    }.buttonStyle(.plain)
                                    Button { searchIndex = min(searchCount - 1, searchIndex + 1) } label: {
                                        Image(systemName: "chevron.down").font(.system(size: 11))
                                    }.buttonStyle(.plain)
                                } else if !searchQuery.isEmpty {
                                    Text("No results").font(.caption).foregroundStyle(.secondary)
                                }
                                Button { withAnimation { showSearch = false; searchQuery = "" } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }.buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.platformWindowBg)
                            Divider()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(20)
                    }
                    } // end ZStack(.bottom)
                    .animation(.spring(response: 0.35), value: showScripturePanel)
                }
                .onReceive(NotificationCenter.default.publisher(for: .scriptureRefTapped)) { note in
                    if let ref = note.userInfo?["ref"] as? ScriptureRef {
                        scriptureRef = ref
                        withAnimation(.spring(response: 0.35)) { showScripturePanel = true }
                    }
                }
                .navigationTitle(currentTitle.isEmpty ? book.title : currentTitle)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 8) {
                            Button { epubFontSize = max(10, epubFontSize - 1) } label: {
                                Text("A").font(.system(size: 12))
                            }.help("Decrease text size")
                            Text("\(Int(epubFontSize))pt")
                                .font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 36)
                            Button { epubFontSize = min(32, epubFontSize + 1) } label: {
                                Text("A").font(.system(size: 16, weight: .medium))
                            }.help("Increase text size")
                            Divider().frame(height: 16)
                            Button { withAnimation { showSearch.toggle(); if !showSearch { searchQuery = "" } } } label: {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(showSearch ? accent : .primary)
                            }.help("Search in this book")
                        }
                    }
                }
                #else
                Text("Books not available on this platform")
                    .navigationTitle(currentTitle.isEmpty ? book.title : currentTitle)
                #endif
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48)).foregroundStyle(.quaternary)
                    Text("Could not open this EPUB").foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .onAppear {
            if let folder = folderURL, heldFolderURL == nil {
                let ok = folder.startAccessingSecurityScopedResource()
                if ok { heldFolderURL = folder }
            }
            parseBook()
            loadBookmarks()
        }
        .onDisappear {
            heldFolderURL?.stopAccessingSecurityScopedResource()
            heldFolderURL = nil
        }
        .onChange(of: currentHref) { savePosition() }
    }

    var isBookmarked: Bool {
        bookmarks.contains { $0.href == currentHref }
    }

    func toggleBookmark() {
        if isBookmarked {
            bookmarks.removeAll { $0.href == currentHref }
        } else {
            bookmarks.append(EPUBBookmark(
                href: currentHref,
                title: currentTitle.isEmpty ? currentHref : currentTitle,
                scrollY: currentScrollY
            ))
        }
        saveBookmarks()
    }

    func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: "epubBookmarks_\(epubURL.lastPathComponent)")
        }
    }

    func loadBookmarks() {
        if let data = UserDefaults.standard.data(forKey: "epubBookmarks_\(epubURL.lastPathComponent)"),
           let bm = try? JSONDecoder().decode([EPUBBookmark].self, from: data) {
            bookmarks = bm
        }
    }


    // MARK: - Reading position persistence

    /// Key used to store last-read href for this specific book
    private var positionKey: String {
        "epub_pos_" + epubURL.lastPathComponent
    }

    private func savePosition() {
        guard !currentHref.isEmpty else { return }
        UserDefaults.standard.set(currentHref, forKey: positionKey)
        UserDefaults.standard.set(currentTitle, forKey: positionKey + "_title")
    }

    private func restorePosition() -> (href: String, title: String)? {
        guard let href = UserDefaults.standard.string(forKey: positionKey),
              !href.isEmpty else { return nil }
        let title = UserDefaults.standard.string(forKey: positionKey + "_title") ?? ""
        return (href, title)
    }

    private func parseBook() {
        let epubURL = self.epubURL
        Task.detached(priority: .userInitiated) {
            let arc: Archive? = {
                do {
                    let a = try Archive(url: epubURL, accessMode: .read, pathEncoding: nil)
                    return a
                } catch {
                    return nil
                }
            }()
            let parsed = arc != nil ? EPUBParser.parse(url: epubURL, archive: arc!) : EPUBParser.parse(url: epubURL)
            await MainActor.run {
                archive   = arc
                book      = parsed
                isParsing = false
                if let b = parsed {
                    toc = b.toc
                    if let href = initialHref, !href.isEmpty {
                        currentHref  = href
                        currentTitle = findTOCItem(href: href, in: b.toc)?.title ?? ""
                        if initialScrollY > 0 {
                            restoreScrollY = initialScrollY
                        }
                        if let q = initialSearchQuery, !q.isEmpty {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                searchQuery = q
                                showSearch  = true
                            }
                        }
                    } else if let saved = restorePosition() {
                        currentHref  = saved.href
                        currentTitle = saved.title
                    } else if let first = firstLeaf(toc) {
                        navigate(to: first)
                    }
                }
            }
        }
    }

    // MARK: - TOC Sidebar

    private func tocSidebar(book: EPUBBook) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(book.title)
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
                    // Bookmarks section
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
                                        .foregroundStyle(currentHref == bm.href ? accent : .primary)
                                        .lineLimit(1)
                                    Spacer()
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
                                .background(currentHref == bm.href ? accent.opacity(0.10) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    restoreScrollY = bm.scrollY
                                    currentHref  = bm.href
                                    currentTitle = bm.title
                                    // Reset after load so subsequent pages aren't affected
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                        restoreScrollY = 0
                                    }
                                }
                            }
                            Divider().padding(.vertical, 4)
                        }
                    }

                    // Contents section
                    HStack {
                        Text("CONTENTS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)

                    ForEach(toc) { item in
                        TOCRowView(item: item, depth: 0, currentHref: currentHref,
                                   accent: accent,
                                   onSelect: { navigate(to: $0) },
                                   onToggle: { toggleExpanded(id: $0, in: &toc) })
                    }
                }
                .padding(.bottom, 16)
            }
            .background(Color.platformWindowBg)
        }
    }

    private func navigate(to item: TOCItem) {
        currentHref  = item.href
        currentTitle = item.title
    }

    private func firstLeaf(_ items: [TOCItem]) -> TOCItem? {
        for item in items {
            if item.children.isEmpty { return item }
            if let leaf = firstLeaf(item.children) { return leaf }
        }
        return items.first
    }

    private func findTOCItem(href: String, in items: [TOCItem]) -> TOCItem? {
        for item in items {
            if item.href == href { return item }
            if let found = findTOCItem(href: href, in: item.children) { return found }
        }
        return nil
    }

    private func toggleExpanded(id: UUID, in items: inout [TOCItem]) {
        for i in items.indices {
            if items[i].id == id { items[i].isExpanded.toggle(); return }
            toggleExpanded(id: id, in: &items[i].children)
        }
    }
}

// MARK: - TOC Row

struct TOCRowView: View {
    let item:        TOCItem
    let depth:       Int
    let currentHref: String
    let accent:      Color
    let onSelect:    (TOCItem) -> Void
    let onToggle:    (UUID) -> Void

    var isSelected: Bool { currentHref == item.href }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(Color.clear).frame(width: CGFloat(depth) * 14 + 8)
                if !item.children.isEmpty {
                    Button { onToggle(item.id) } label: {
                        Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary).frame(width: 16)
                    }.buttonStyle(.plain)
                } else {
                    Rectangle().fill(Color.clear).frame(width: 16)
                }
                Button { onSelect(item) } label: {
                    Text(item.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? accent : .primary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5).padding(.trailing, 8)
                }.buttonStyle(.plain)
            }
            .background(isSelected ? accent.opacity(0.10) : Color.clear)
            if item.isExpanded {
                ForEach(item.children) { child in
                    TOCRowView(item: child, depth: depth + 1, currentHref: currentHref,
                               accent: accent, onSelect: onSelect, onToggle: onToggle)
                }
            }
        }
    }
}

// MARK: - Page WebView

/// Shared mutable reference used to bridge WKWebView delegate callbacks to SwiftUI state.
/// Using a class avoids stale closure captures that occur with struct-based callbacks.

extension Notification.Name {
    static let scriptureRefTapped = Notification.Name("scriptureRefTapped")
}

final class EPUBPageActions: ObservableObject {
    var onNavigate:     ((String) -> Void)?
    var onScriptureRef: ((ScriptureRef) -> Void)?
}

struct EPUBPageView: WKViewRepresentable {
    let href:           String
    let archive:        Archive
    let theme:          AppTheme
    let fontSize:       Double
    let fontName:       String
    var onNavigate:     ((String) -> Void)? = nil
    var restoreScrollY: Double = 0
    var onScrollY:      ((Double) -> Void)? = nil
    var searchQuery:    String = ""
    var searchStep:     Int    = 0   // incremented to trigger next/prev
    var searchForward:  Bool   = true
    var onSearchCount:  ((Int) -> Void)? = nil
    var onSearchIndex:  ((Int) -> Void)? = nil

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ wv: WKWebView, context: Context) { updateWebView(wv, context: context) }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ wv: WKWebView, context: Context) { updateWebView(wv, context: context) }
    #endif

    private func makeWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "scrollY")
        config.userContentController.add(context.coordinator, name: "searchCount")
        config.userContentController.add(context.coordinator, name: "searchIndex")
        // Report scrollY back to Swift periodically while scrolling
        let scrollScript = WKUserScript(
            source: """
            window.addEventListener('scroll', function() {
                window.webkit.messageHandlers.scrollY.postMessage(window.scrollY);
            }, { passive: true });
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true)
        config.userContentController.addUserScript(scrollScript)
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        context.coordinator.onNavigate      = onNavigate
        context.coordinator.onScrollY       = onScrollY
        context.coordinator.onSearchCount   = onSearchCount
        context.coordinator.onSearchIndex   = onSearchIndex
        context.coordinator.restoreScrollY  = restoreScrollY
        load(in: wv, coordinator: context.coordinator)
        return wv
    }

    private func updateWebView(_ wv: WKWebView, context: Context) {
        context.coordinator.onNavigate    = onNavigate
        context.coordinator.onScrollY     = onScrollY
        context.coordinator.onSearchCount = onSearchCount
        context.coordinator.onSearchIndex = onSearchIndex
        guard !context.coordinator.isLoading else { return }
        let needsReload = context.coordinator.currentHref != href
                       || context.coordinator.currentFontSize != fontSize
                       || !context.coordinator.hasContent
        if needsReload {
            context.coordinator.currentHref      = href
            context.coordinator.currentFontSize  = fontSize
            context.coordinator.restoreScrollY   = restoreScrollY
            context.coordinator.lastSearchQuery  = ""
            context.coordinator.lastSearchStep   = 0
            load(in: wv, coordinator: context.coordinator)
            return
        }
        // Handle search
        if !searchQuery.isEmpty && searchQuery != context.coordinator.lastSearchQuery {
            context.coordinator.lastSearchQuery = searchQuery
            context.coordinator.lastSearchStep  = searchStep
            runSearchJS(in: wv, query: searchQuery)
        } else if !searchQuery.isEmpty && searchStep != context.coordinator.lastSearchStep {
            context.coordinator.lastSearchStep = searchStep
            let js = searchForward
                ? "if(window._se&&window._se.length){window._si=(window._si+1)%window._se.length;window._se[window._si].scrollIntoView({behavior:'smooth',block:'center'});window.webkit.messageHandlers.searchIndex.postMessage(window._si);}"
                : "if(window._se&&window._se.length){window._si=(window._si-1+window._se.length)%window._se.length;window._se[window._si].scrollIntoView({behavior:'smooth',block:'center'});window.webkit.messageHandlers.searchIndex.postMessage(window._si);}"
            wv.evaluateJavaScript(js, completionHandler: nil)
        } else if searchQuery.isEmpty && context.coordinator.lastSearchQuery != "" {
            context.coordinator.lastSearchQuery = ""
            wv.evaluateJavaScript("document.querySelectorAll('mark.sse').forEach(function(m){var t=document.createTextNode(m.textContent);m.parentNode.replaceChild(t,m);});document.body.normalize();", completionHandler: nil)
        }
    }

    private func runSearchJS(in wv: WKWebView, query: String) {
        // Escape special regex characters
        let escapedRegex = query.replacingOccurrences(of: "\\", with: "\\\\")
                               .replacingOccurrences(of: ".", with: "\\.")
                               .replacingOccurrences(of: "*", with: "\\*")
                               .replacingOccurrences(of: "+", with: "\\+")
                               .replacingOccurrences(of: "?", with: "\\?")
                               .replacingOccurrences(of: "(", with: "\\(")
                               .replacingOccurrences(of: ")", with: "\\)")
                               .replacingOccurrences(of: "[", with: "\\[")
                               .replacingOccurrences(of: "]", with: "\\]")
                               .replacingOccurrences(of: "{", with: "\\{")
                               .replacingOccurrences(of: "}", with: "\\}")
                               .replacingOccurrences(of: "^", with: "\\^")
                               .replacingOccurrences(of: "$", with: "\\$")
                               .replacingOccurrences(of: "|", with: "\\|")
                               .replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function(){
            document.querySelectorAll('mark.sse').forEach(function(m){
                var t=document.createTextNode(m.textContent);
                m.parentNode.replaceChild(t,m);
            });
            document.body.normalize();
            var re=new RegExp('\\\\b\(escapedRegex)\\\\b','gi');
            var count=0;
            function walk(n){
                if(n.nodeType===3){
                    var t=n.textContent,m,pos=0;
                    re.lastIndex=0;
                    if(!re.test(t)) return;
                    re.lastIndex=0;
                    var frag=document.createDocumentFragment();
                    while((m=re.exec(t))!==null){
                        frag.appendChild(document.createTextNode(t.slice(pos,m.index)));
                        var mk=document.createElement('mark');
                        mk.className='sse';
                        mk.style.cssText='background:rgba(255,200,0,0.55);border-radius:2px;padding:0 1px;';
                        mk.textContent=m[0];
                        frag.appendChild(mk);
                        count++;pos=m.index+m[0].length;
                    }
                    frag.appendChild(document.createTextNode(t.slice(pos)));
                    n.parentNode.replaceChild(frag,n);
                } else if(n.nodeType===1&&!/^(script|style|mark)$/i.test(n.tagName)){
                    Array.from(n.childNodes).forEach(walk);
                }
            }
            walk(document.body);
            window._se=document.querySelectorAll('mark.sse');
            window._si=0;
            if(window._se.length>0) window._se[0].scrollIntoView({behavior:'smooth',block:'center'});
            window.webkit.messageHandlers.searchCount.postMessage(count);
        })();
        """
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    private func load(in wv: WKWebView, coordinator: Coordinator) {
        let href          = self.href
        let archive       = self.archive
        let theme         = self.theme
        let fontSize      = self.fontSize
        let fontName      = self.fontName
        let restoreY      = coordinator.restoreScrollY
        coordinator.hasContent  = false
        coordinator.isLoading   = true
        // Show loading placeholder immediately
        wv.loadHTMLString(EPUBParser.loadingPage(theme: theme, fontSize: fontSize), baseURL: nil)
        epubArchiveQueue.async {
            let html = EPUBParser.pageContent(
                href: href, archive: archive,
                theme: theme, fontSize: fontSize, fontName: fontName)
            DispatchQueue.main.async {
                wv.loadHTMLString(html, baseURL: nil)
                coordinator.hasContent = true
                coordinator.isLoading  = false
                if restoreY > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        wv.evaluateJavaScript("window.scrollTo(0, \(restoreY))")
                        coordinator.restoreScrollY = 0
                    }
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigate: onNavigate, currentHref: href, currentFontSize: fontSize)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onNavigate:      ((String) -> Void)?
        var onScrollY:       ((Double) -> Void)?
        var onSearchCount:   ((Int) -> Void)?
        var onSearchIndex:   ((Int) -> Void)?
        var currentHref:     String
        var currentFontSize: Double
        var lastSearchQuery: String = ""
        var lastSearchStep:  Int    = 0
        var hasContent:      Bool   = false
        var isLoading:       Bool   = false
        var restoreScrollY:  Double = 0

        init(onNavigate: ((String) -> Void)?, currentHref: String, currentFontSize: Double) {
            self.onNavigate      = onNavigate
            self.currentHref     = currentHref
            self.currentFontSize = currentFontSize
        }

        // Receives scrollY and search messages from JS
        func userContentController(_ ucc: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "scrollY", let y = message.body as? Double {
                DispatchQueue.main.async { self.onScrollY?(y) }
            } else if message.name == "searchCount", let n = message.body as? Int {
                DispatchQueue.main.async { self.onSearchCount?(n) }
            } else if message.name == "searchIndex", let i = message.body as? Int {
                DispatchQueue.main.async { self.onSearchIndex?(i) }
            }
        }

        func webView(_ wv: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else {
                decisionHandler(.allow); return
            }
            if url.scheme == "scripture" {
                if let ref = ScriptureReferenceParser.parse(url: url) {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .scriptureRefTapped, object: nil,
                            userInfo: ["ref": ref])
                    }
                }
                decisionHandler(.cancel)
            } else if url.scheme == "epub-internal" {
                let target = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !target.isEmpty { DispatchQueue.main.async { self.onNavigate?(target) } }
                decisionHandler(.cancel)
            } else if url.scheme == "https" || url.scheme == "http" {
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                UIApplication.shared.open(url)
                #endif
                decisionHandler(.cancel)
            } else if url.scheme == "about" || url.scheme == "blob" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
