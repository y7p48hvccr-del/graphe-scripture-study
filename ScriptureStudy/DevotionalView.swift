import SwiftUI
import WebKit

struct DevotionalView: View {

    @EnvironmentObject var myBible: MyBibleService

    @AppStorage("themeID")       private var themeID:      String = "light"
    @AppStorage("filigreeColor") private var filigreeColor: Int   = 0
    @AppStorage("fontSize")      private var fontSize:     Double = 16
    @AppStorage("fontName")      private var fontName:     String = ""
    @AppStorage("devotionalStartDay") private var storedStartDay: Int = 1

    var theme:              AppTheme { AppTheme.find(themeID) }
    var filigreeAccent:     Color    { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color    { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }

    @State private var entry:        MyBibleService.DevotionalEntry? = nil
    @State private var isLoading:    Bool = true
    @State private var currentDay:   Int  = 1
    @State private var totalDays:    Int  = 365

    var today: Int {
        Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
    }

    var body: some View {
        #if os(macOS)
        HSplitView {
            devotionalSide
                .frame(minWidth: 380)
            ReadingPlanPanel()
                .frame(minWidth: 380)
        }
        #else
        VStack(spacing: 0) {
            devotionalSide
            Divider()
            ReadingPlanPanel()
        }
        #endif
    }

    // MARK: - Left half — the devotional page (single panel, no sub-split)

    private var devotionalSide: some View {
        VStack(spacing: 0) {
            // ── Title strip ─────────────────────────────────────────
            HStack {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(filigreeAccent)
                Text("DEVOTIONAL")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(filigreeAccent)
                    .tracking(1.2)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .background(theme.background)

            // ── Header bar ──────────────────────────────────────────
            HStack(spacing: 12) {
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
            .padding(.bottom, 10)
            .background(theme.background)

            Divider()

            // ── Content ─────────────────────────────────────────────
            if myBible.selectedDevotional == nil {
                emptyState
            } else if isLoading {
                VStack { Spacer(); ProgressView("Loading…"); Spacer() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @State private var selectedVerseTarget: VerseLinkTarget? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                Text(entry.title)
                    .font(titleFont)
                    .foregroundStyle(filigreeAccent)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                DevotionalWebView(
                    html:       entry.html,
                    theme:      theme,
                    fontSize:   fontSize,
                    fontName:   fontName,
                    accentHex:  filigreeAccent.toHex(),
                    onVerseTap: { target in
                        selectedVerseTarget = target
                    }
                )
                .frame(minHeight: 2000)
            }
            .padding(24)
        }
        .background(theme.background)
        .popover(item: $selectedVerseTarget, arrowEdge: .bottom) { target in
            VersePreviewPopover(
                bookNumber: target.bookNumber,
                chapter: target.chapter,
                verseStart: target.verseStart,
                verseEnd: target.verseEnd,
                accent: filigreeAccent,
                onOpenInBible: nil
            )
            .frame(width: 320)
        }
    }

    private var titleFont: Font {
        guard !fontName.isEmpty else { return .system(size: fontSize + 6, weight: .semibold) }
        return .custom(fontName, size: fontSize + 6).weight(.semibold)
    }
}

// MARK: - WebView for devotion body
//
// Tapping a Bible reference inside the HTML posts .navigateToPassage with
// book/chapter/verse — the main tab router switches to the Bible tab and
// LocalBibleView jumps to the passage. Same wiring the reading plan uses.

struct DevotionalWebView: WKViewRepresentable {
    let html:       String
    let theme:      AppTheme
    let fontSize:   Double
    let fontName:   String
    let accentHex:  String
    var onVerseTap: ((VerseLinkTarget) -> Void)? = nil

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onVerseTap = onVerseTap
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            load(in: webView)
        }
    }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onVerseTap = onVerseTap
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            load(in: webView)
        }
    }
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

        var body = html
        body = body.replacingOccurrences(of: "<p/>", with: "</p><p>")

        let page = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width,initial-scale=1.0">
        <style>
          html, body {
            font-family: '\(font)', -apple-system, serif;
            font-size: \(fontSize)px;
            line-height: 1.8;
            color: \(textHex);
            background: transparent;
            margin: 0; padding: 0;
            -webkit-font-smoothing: antialiased;
          }
          p { margin: 0 0 1em 0; }
          a { color: \(accentHex); text-decoration: none; cursor: pointer; }
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

    func makeCoordinator() -> Coordinator { Coordinator(onVerseTap: onVerseTap) }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String = ""
        var onVerseTap: ((VerseLinkTarget) -> Void)?

        init(onVerseTap: ((VerseLinkTarget) -> Void)? = nil) {
            self.onVerseTap = onVerseTap
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let href = action.request.url?.absoluteString ?? ""
            // Allow the initial blank/data load so the HTML can render.
            if href.hasPrefix("about:") || href.isEmpty {
                decisionHandler(.allow); return
            }
            handleBibleLink(href)
            decisionHandler(.cancel)
        }

        /// Hrefs in the devotional HTML use a URL-encoded MyBible "B:" format,
        /// e.g. `b:540%208:1-24`. We lowercase-tolerate, decode the %20 space,
        /// and accept an optional verse with an optional range suffix.
        private func handleBibleLink(_ href: String) {
            let normalised = href
                .replacingOccurrences(of: "%20", with: " ")
                .replacingOccurrences(of: "%3A", with: ":")
            let pattern = try? NSRegularExpression(
                pattern: #"[bB]:\s*(\d+)\s+(\d+)(?::(\d+)(?:[-–](\d+))?)?"#
            )
            let ns = normalised as NSString
            guard let m = pattern?.firstMatch(in: normalised,
                                              range: NSRange(location: 0, length: ns.length))
            else { return }
            let book = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let ch   = Int(ns.substring(with: m.range(at: 2))) ?? 1
            let verseStart: Int
            if m.range(at: 3).location != NSNotFound {
                verseStart = Int(ns.substring(with: m.range(at: 3))) ?? 1
            } else {
                verseStart = 1
            }
            let verseEnd: Int
            if m.range(at: 4).location != NSNotFound {
                verseEnd = Int(ns.substring(with: m.range(at: 4))) ?? verseStart
            } else {
                verseEnd = verseStart
            }
            DispatchQueue.main.async {
                self.onVerseTap?(
                    VerseLinkTarget(
                        bookNumber: book,
                        chapter: ch,
                        verseStart: verseStart,
                        verseEnd: verseEnd
                    )
                )
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
