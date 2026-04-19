#if os(macOS)
import SwiftUI
import WebKit
import AppKit

// MARK: - Help Window

class HelpWindowController: NSWindowController {
    static let shared = HelpWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask:   [.titled, .closable, .resizable, .miniaturizable],
            backing:     .buffered,
            defer:       false
        )
        window.title          = "Graphē One Help"
        window.minSize        = NSSize(width: 700, height: 500)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        let helpView = HelpView()
        window.contentView = NSHostingView(rootView: helpView)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(page: String = "index", anchor: String = "") {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Post notification so HelpView can navigate to the requested page
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: Notification.Name("helpNavigateTo"),
                object: nil,
                userInfo: ["page": page, "anchor": anchor]
            )
        }
    }
}

// MARK: - Help View

struct HelpView: View {
    @State private var selectedPage   = "index"
    @State private var selectedAnchor  = ""
    @State private var searchText       = ""


    let pages: [(id: String, title: String, section: String)] = [
        ("index",               "Welcome",              "Getting Started"),
        ("quickstart",          "Quick Start",          "Getting Started"),
        ("modules",             "Module Formats",       "Getting Started"),
        ("library",             "Archives",             "Getting Started"),
        ("bible-panel",         "Bible Panel",          "Reading"),
        ("strongs",             "Strong's Numbers",     "Reading"),
        ("bookmarks",           "Bookmarks",            "Reading"),
        ("comparison",          "Companion Panel",      "Companion Panel"),
        ("commentary",          "Commentary",           "Companion Panel"),
        ("cross-references",    "Cross-References",     "Companion Panel"),
        ("dictionaries",        "Dictionaries",         "Companion Panel"),
        ("interlinear",         "Interlinear",          "Companion Panel"),
        ("notes-companion",     "Notes",                "Companion Panel"),
        ("timeline",            "Timeline",             "Companion Panel"),
        ("maps",                "Bible Maps",           "Companion Panel"),
        ("web",                 "Web Panel",            "Companion Panel"),
        ("devotional",          "Devotional",           "Study & Organisation"),
        ("organizer",           "Organizer",            "Study & Organisation"),
        ("search",              "Search",               "Study & Organisation"),
        ("ai",                  "AI Assistant",         "Study & Organisation"),
        ("themes",              "Themes & Fonts",       "Customisation"),
        ("settings",            "Settings",             "Customisation"),
        ("shortcuts",           "Keyboard Shortcuts",   "Reference"),
        ("formats",             "File Formats",         "Reference"),
        ("troubleshooting",     "Troubleshooting",      "Reference"),
    ]

    var sections: [String] {
        var seen = Set<String>()
        return pages.compactMap { seen.insert($0.section).inserted ? $0.section : nil }
    }

    var body: some View {
        HSplitView {
            // Sidebar with search
            VStack(spacing: 0) {
                // Search box
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Search help…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                if searchText.isEmpty {
                    // Normal page list
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Graphē One ScriptureStudy Pro")
                                .font(.headline)
                                .padding(.horizontal, 16).padding(.vertical, 14)

                            ForEach(sections, id: \.self) { section in
                                Text(section.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 3)

                                ForEach(pages.filter { $0.section == section }, id: \.id) { page in
                                    Button { selectedPage = page.id } label: {
                                        Text(page.title)
                                            .font(.system(size: 13))
                                            .foregroundStyle(selectedPage == page.id ? Color.accentColor : Color.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 16).padding(.vertical, 4)
                                            .background(selectedPage == page.id ? Color.accentColor.opacity(0.12) : Color.clear)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.bottom, 16)
                    }
                } else {
                    // Search results
                    let results = searchResults
                    if results.isEmpty {
                        VStack {
                            Spacer()
                            Text("No results").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(results, id: \.id) { result in
                                    Button {
                                        selectedPage = result.id
                                        searchText   = ""
                                    } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(result.title)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(Color.primary).lineLimit(1)
                                            Text(result.snippet)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .background(selectedPage == result.id ? Color.accentColor.opacity(0.1) : Color.clear)
                                    Divider().padding(.leading, 12)
                                }
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 200, maxWidth: 230)
            .background(Color(NSColor.windowBackgroundColor))

            // Content
            HelpWebView(pageID: selectedPage, anchor: selectedAnchor)
                .id(selectedPage + selectedAnchor)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("helpNavigateTo"))) { note in
            if let page = note.userInfo?["page"] as? String {
                selectedPage   = page
                selectedAnchor = note.userInfo?["anchor"] as? String ?? ""
            }
        }
    }
    struct SearchResult {
        let id: String
        let title: String
        let snippet: String
    }

    var searchResults: [SearchResult] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var results: [SearchResult] = []

        // Find HelpPages folder — same strategies as page loader
        let helpDir: URL? = {
            // Strategy 1: folder reference
            if let d = Bundle.main.url(forResource: "HelpPages", withExtension: nil) { return d }
            // Strategy 2: resource URL subdirectory
            if let d = Bundle.main.resourceURL?.appendingPathComponent("HelpPages"),
               FileManager.default.fileExists(atPath: d.path) { return d }
            // Strategy 3: bundle URL subdirectory
            if let d = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/HelpPages") as URL?,
               FileManager.default.fileExists(atPath: d.path) { return d }
            return nil
        }()

        for page in pages {
            guard page.id != "index" else { continue }
            let titleMatch = page.title.lowercased().contains(q)

            // Try to load and search the HTML file
            var fileText = ""
            if let dir = helpDir {
                let url = dir.appendingPathComponent("\(page.id).html")
                if let html = try? String(contentsOf: url, encoding: .utf8) {
                    var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    text = text.replacingOccurrences(of: "&amp;", with: "&")
                    text = text.replacingOccurrences(of: "&lt;", with: "<")
                    text = text.replacingOccurrences(of: "&gt;", with: ">")
                    text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                    fileText = text
                }
            }

            let contentMatch = fileText.lowercased().contains(q)

            guard titleMatch || contentMatch else { continue }

            // Build snippet
            var snippet = ""
            if contentMatch {
                let lower = fileText.lowercased()
                if let range = lower.range(of: q) {
                    let start = lower.index(range.lowerBound, offsetBy: -60, limitedBy: lower.startIndex) ?? lower.startIndex
                    let end   = lower.index(range.upperBound, offsetBy: 100, limitedBy: lower.endIndex) ?? lower.endIndex
                    snippet = (start > lower.startIndex ? "…" : "") + String(fileText[start..<end]) + (end < lower.endIndex ? "…" : "")
                }
            } else {
                snippet = page.title
            }

            results.append(SearchResult(id: page.id, title: page.title, snippet: snippet))
        }
        return results
    }

}


// MARK: - WebView

struct HelpWebView: NSViewRepresentable {
    let pageID:  String
    var anchor:  String = ""


    private func load(_ pageID: String, in webView: WKWebView) {
        // Try multiple lookup strategies
        let fm = FileManager.default

        // Strategy 1: folder reference copied as-is
        if let dir = Bundle.main.url(forResource: "HelpPages", withExtension: nil) {
            let page = dir.appendingPathComponent("\(pageID).html")
            if fm.fileExists(atPath: page.path) {
                webView.loadFileURL(page, allowingReadAccessTo: dir)
                return
            }
        }

        // Strategy 2: files copied flat into bundle root
        if let page = Bundle.main.url(forResource: pageID, withExtension: "html") {
            let dir = page.deletingLastPathComponent()
            webView.loadFileURL(page, allowingReadAccessTo: dir)
            return
        }

        // Strategy 3: files in a HelpPages subdirectory
        if let page = Bundle.main.url(forResource: pageID, withExtension: "html",
                                       subdirectory: "HelpPages") {
            let dir = page.deletingLastPathComponent()
            webView.loadFileURL(page, allowingReadAccessTo: dir)
            return
        }

        // Diagnostic: list bundle contents
        let bundleURL  = Bundle.main.bundleURL
        let resURL     = Bundle.main.resourceURL ?? bundleURL
        let contents   = (try? fm.contentsOfDirectory(atPath: resURL.path)) ?? []
        let list       = contents.prefix(30).joined(separator: "\n")
        showError(in: webView, message: "Help files not found.<br><br><strong>Bundle resources:</strong><br><pre>\(list)</pre>")
    }

    private func showError(in webView: WKWebView, message: String) {
        let html = "<html><body style=\'font-family:system-ui;padding:40px;color:#666\'><h2>\(message)</h2></body></html>"
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeNSView(context: Context) -> WKWebView {
        // Set anchor BEFORE loading so didFinish can scroll to it
        context.coordinator.anchor = anchor.isEmpty ? nil : anchor
        context.coordinator.currentPage = pageID
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        load(pageID, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // .id() on the view means this only fires for same page/anchor combos
        // makeNSView handles fresh loads; nothing needed here
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: pageID)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var currentPage: String
        var anchor: String? = nil
        init(currentPage: String) { self.currentPage = currentPage }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let anchor = anchor, !anchor.isEmpty else { return }
            // Small delay ensures page layout is complete before scrolling
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let js = "var el=document.getElementById('\(anchor)'); if(el){el.scrollIntoView({behavior:'smooth',block:'start'});}"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url, url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

// MARK: - Reusable Help Button

struct HelpButton: View {
    let page:   String
    var anchor: String = ""
    var body: some View {
        Button {
            HelpWindowController.shared.show(page: page, anchor: anchor)
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary.opacity(0.7))
        }
        .buttonStyle(.plain)
        .help("Open Help")
    }
}

#endif
