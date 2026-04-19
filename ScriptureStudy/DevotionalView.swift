import SwiftUI
import WebKit

struct DevotionalView: View {

    @EnvironmentObject var myBible: MyBibleService

    @AppStorage("themeID")       private var themeID:      String = "light"
    @AppStorage("filigreeColor") private var filigreeColor: Int   = 0
    @AppStorage("fontSize")      private var fontSize:     Double = 16
    @AppStorage("fontName")      private var fontName:     String = ""
    @AppStorage("devotionalStartDay") private var storedStartDay: Int = 1

    var theme:          AppTheme { AppTheme.find(themeID) }
    var filigreeAccent:     Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }

    @State private var entry:        MyBibleService.DevotionalEntry? = nil
    @State private var isLoading:    Bool = true
    @State private var currentDay:   Int  = 1
    @State private var totalDays:    Int  = 365

    var today: Int {
        // Day of year (1-365)
        Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header bar ──────────────────────────────────────────
            HStack(spacing: 12) {
                // Module picker
                devotionalPicker
                #if os(macOS)
                HelpButton(page: "devotional")
                #endif

                Spacer()

                // Day navigation
                HStack(spacing: 8) {
                    Button { changeDay(-1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(currentDay <= 1)

                    Button { goToToday() } label: {
                        Text("Day \(currentDay)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(currentDay == today ? filigreeAccent : .primary)
                    }
                    .buttonStyle(.plain)
                    .help("Jump to today (Day \(today))")

                    Button { changeDay(1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(currentDay >= totalDays)
                }
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(theme.background)

            Divider()

            // ── Content ─────────────────────────────────────────────
            if myBible.selectedDevotional == nil {
                emptyState
            } else if isLoading {
                VStack { Spacer(); ProgressView("Loading…"); Spacer() }
                    .background(theme.background)
            } else if let entry = entry {
                DevotionalContentView(
                    entry:         entry,
                    theme:         theme,
                    filigreeAccent: filigreeAccent,
                    fontSize:      fontSize,
                    fontName:      fontName
                )
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "book.closed").font(.system(size: 40)).foregroundStyle(.quaternary)
                    Text("No entry for Day \(currentDay)").foregroundStyle(.secondary)
                    Spacer()
                }
                .background(theme.background)
            }
        }
        .background(theme.background)
        .onAppear { goToToday() }
        .onChange(of: myBible.selectedDevotional) { load() }
    }

    // MARK: - Picker

    private var devotionalPicker: some View {
        let mods = myBible.modules.filter { $0.type == .devotional }
        let label = myBible.selectedDevotional?.name ?? "No devotional"
        return Menu {
            Button("None") { myBible.selectedDevotional = nil }
            Divider()
            ForEach(mods) { m in
                Button(m.name) { myBible.selectedDevotional = m; load() }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(filigreeAccent)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(filigreeAccent)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 56)).foregroundStyle(.quaternary)
            Text("No devotional selected")
                .font(.title2.weight(.semibold))
            Text("Add a devotional module to your modules folder\nand select it above.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }

    // MARK: - Navigation

    private func goToToday() {
        currentDay = min(today, totalDays)
        load()
    }

    private func changeDay(_ delta: Int) {
        currentDay = max(1, min(totalDays, currentDay + delta))
        load()
    }

    private func load() {
        guard myBible.selectedDevotional != nil else { entry = nil; return }
        isLoading = true
        let day = currentDay
        Task {
            async let entryResult = myBible.fetchDevotionalEntry(day: day)
            async let countResult = myBible.devotionalDayCount()
            let (e, count) = await (entryResult, countResult)
            await MainActor.run {
                entry      = e
                totalDays  = count
                isLoading  = false
            }
        }
    }
}

// MARK: - Content renderer

struct DevotionalContentView: View {
    let entry:          MyBibleService.DevotionalEntry
    let theme:          AppTheme
    let filigreeAccent: Color
    let fontSize:       Double
    let fontName:       String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Title / verse heading
                Text(entry.title)
                    .font(titleFont)
                    .foregroundStyle(filigreeAccent)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                // Body — rendered via WebView for HTML fidelity
                DevotionalWebView(
                    html:          entry.html,
                    theme:         theme,
                    fontSize:      fontSize,
                    fontName:      fontName,
                    accentHex:     filigreeAccent.toHex()
                )
                .frame(minHeight: 400)
            }
            .padding(24)
        }
        .background(theme.background)
    }

    private var titleFont: Font {
        guard !fontName.isEmpty else { return .system(size: fontSize + 6, weight: .semibold) }
        return .custom(fontName, size: fontSize + 6).weight(.semibold)
    }
}

// MARK: - WebView for devotion body

struct DevotionalWebView: WKViewRepresentable {
    let html:       String
    let theme:      AppTheme
    let fontSize:   Double
    let fontName:   String
    let accentHex:  String

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { if context.coordinator.lastHTML != html { context.coordinator.lastHTML = html; load(in: webView) } }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { if context.coordinator.lastHTML != html { context.coordinator.lastHTML = html; load(in: webView) } }
    #endif
    private func makeWebView(context: Context) -> WKWebView {
        let config  = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        load(in: webView)
        return webView
    }



    private func load(in webView: WKWebView) {
        let textHex = theme.text.toHex()
        let font    = fontName.isEmpty ? "-apple-system" : fontName

        // Convert B: links to custom scheme for navigation
        var body = html
        // Replace <p/> with proper paragraph breaks
        body = body.replacingOccurrences(of: "<p/>", with: "</p><p>")
        body = body.replacingOccurrences(of: "<p/>", with: "</p><p>")

        let page = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
          body {
            font-family: '\(font)', -apple-system, serif;
            font-size: \(fontSize)px;
            line-height: 1.8;
            color: \(textHex);
            background: transparent;
            margin: 0; padding: 0;
            -webkit-font-smoothing: antialiased;
          }
          p { margin: 0 0 1em 0; }
          a { color: \(accentHex); text-decoration: none; }
          a:hover { text-decoration: underline; }
          i, em { font-style: italic; }
          b, strong { font-weight: 600; }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
        webView.loadHTMLString(page, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String = ""

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, url.scheme == "about" || action.navigationType == .linkActivated
            else { decisionHandler(.allow); return }

            if let urlStr = action.request.url?.absoluteString,
               urlStr.contains("B:") {
                // Post Bible reference navigation
                if let href = action.request.url?.absoluteString {
                    parseBibleLink(href)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        private func parseBibleLink(_ href: String) {
            // Format: href contains B:BOOK CHAPTER:VERSE
            let pattern = try? NSRegularExpression(pattern: #"B:(\d+) (\d+):(\d+)"#)
            let ns = href as NSString
            if let m = pattern?.firstMatch(in: href, range: NSRange(location: 0, length: ns.length)) {
                let book = Int(ns.substring(with: m.range(at: 1))) ?? 0
                let ch   = Int(ns.substring(with: m.range(at: 2))) ?? 1
                let vs   = Int(ns.substring(with: m.range(at: 3))) ?? 1
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .navigateToPassage,
                        object: nil,
                        userInfo: ["bookNumber": book, "chapter": ch, "verse": vs]
                    )
                }
            }
        }
    }
}

// MARK: - Color hex helper

extension Color {
    func toHex() -> String {
        #if os(macOS)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r  = Int(ns.redComponent   * 255)
        let g  = Int(ns.greenComponent * 255)
        let b  = Int(ns.blueComponent  * 255)
        #else
        let ns = UIColor(self)
        var rf: CGFloat = 0, gf: CGFloat = 0, bf: CGFloat = 0
        ns.getRed(&rf, green: &gf, blue: &bf, alpha: nil)
        let r = Int(rf * 255), g = Int(gf * 255), b = Int(bf * 255)
        #endif
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
