import SwiftUI
import WebKit

struct DictionaryView: View {
    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("fontName") private var fontName: String = ""
    var resolvedFont: Font {
        guard !fontName.isEmpty else { return .system(size: fontSize) }
        return .custom(fontName, size: fontSize)
    }

    @EnvironmentObject var myBible: MyBibleService
    @AppStorage("selectedTab") private var selectedTab: Int = 0
    @State private var selectedDictionary: MyBibleModule?
    @State private var searchText = ""
    @State private var selectedEntry: DictionaryEntry?
    @State private var searchTask: Task<Void, Never>?
    @State private var clipboardTimer: Timer?
    #if os(macOS)
    @State private var lastChangeCount: Int = NSPasteboard.general.changeCount
    #else
    @State private var lastChangeCount: Int = 0
    #endif

    var dictionaries: [MyBibleModule] { myBible.modules.filter { $0.type == .dictionary } }

    var body: some View {
        #if os(macOS)
        HSplitView {
            VStack(spacing: 0) {
                if !dictionaries.isEmpty {
                    Picker("Dictionary", selection: $selectedDictionary) {
                        Text("Select…").tag(Optional<MyBibleModule>.none)
                        ForEach(dictionaries) { module in
                            Text(module.name).tag(Optional(module))
                        }
                    }
                    .padding(10)
                    .onChange(of: selectedDictionary) {
                        selectedEntry = nil
                        triggerSearch()
                    }
                    .onAppear { selectedDictionary = dictionaries.first }
                    .onAppear { startClipboardMonitor() }
                    .onDisappear { stopClipboardMonitor() }
                }

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search topics…", text: $searchText)
                        .textFieldStyle(.plain)
                        .onChange(of: searchText) { triggerSearch() }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.platformWindowBg)

                Divider()

                if myBible.dictionaryEntries.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "character.book.closed.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.quaternary)
                        Text(selectedDictionary == nil ? "Select a dictionary above" : "No entries found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    List(myBible.dictionaryEntries, selection: $selectedEntry) { entry in
                        Text(entry.topic)
                            .font(resolvedFont)
                            .tag(entry)
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 200, maxWidth: 260)

            Group {
                if let entry = selectedEntry {
                    DictionaryArticleWebView(
                        html: DictionaryArticleRenderer.html(
                            topic: entry.topic,
                            definitionHTML: entry.definition,
                            fontName: fontName,
                            fontSize: fontSize
                        ),
                        onVerseTap: handleVerseTap,
                        onDictionaryTap: handleDictionaryTap
                    )
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "character.book.closed")
                            .font(.system(size: 48))
                            .foregroundStyle(.quaternary)
                        Text("Select a topic from the list\nto read its definition.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.platformWindowBg)
        }
        .onChange(of: myBible.dictionaryEntries) { _, entries in
            guard !entries.isEmpty else {
                selectedEntry = nil
                return
            }
            if let selectedEntry,
               let refreshed = entries.first(where: { $0.topic == selectedEntry.topic }) {
                self.selectedEntry = refreshed
            } else if self.selectedEntry == nil {
                self.selectedEntry = entries.first
            }
        }
        #else
        Text("Dictionary not available on this platform")
        #endif
    }

    private func handleVerseTap(_ target: VerseLinkTarget) {
        selectedTab = 0
        var userInfo: [String: Any] = [
            "bookNumber": target.bookNumber,
            "chapter": target.chapter
        ]
        if target.verseStart > 0 {
            userInfo["verse"] = target.verseStart
        }
        NotificationCenter.default.post(name: .navigateToPassage, object: nil, userInfo: userInfo)
    }

    private func handleDictionaryTap(_ target: String) {
        guard let module = selectedDictionary else { return }
        let cleanTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTarget.isEmpty else { return }

        let service = myBible
        Task {
            let result = await service.lookupLinkedWord(word: cleanTarget, in: module)
            guard let result else { return }
            await MainActor.run {
                searchText = result.topic
                let entry = DictionaryEntry(topic: result.topic, definition: result.definition)
                if let existingIndex = myBible.dictionaryEntries.firstIndex(where: { $0.topic == result.topic }) {
                    myBible.dictionaryEntries[existingIndex] = entry
                } else {
                    myBible.dictionaryEntries.insert(entry, at: 0)
                }
                selectedEntry = entry
            }
        }
    }

    private func startClipboardMonitor() {
        #if os(macOS)
        lastChangeCount = NSPasteboard.general.changeCount
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            let current = NSPasteboard.general.changeCount
            guard current != lastChangeCount else { return }
            lastChangeCount = current
            guard let text = NSPasteboard.general.string(forType: .string) else { return }
            let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let isOneWord = !word.isEmpty && word.count <= 40 && !word.contains(" ") && !word.contains("\n")
            guard isOneWord else { return }
            DispatchQueue.main.async {
                searchText = word
                selectedTab = 2
                triggerSearch()
            }
        }
        #endif
    }

    private func stopClipboardMonitor() {
        #if os(macOS)
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        #endif
    }

    private func triggerSearch() {
        searchTask?.cancel()
        guard let module = selectedDictionary else { return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await myBible.searchDictionary(module: module, query: searchText)
        }
    }
}

private struct DictionaryArticleWebView: WKViewRepresentable {
    let html: String
    var onVerseTap: (VerseLinkTarget) -> Void
    var onDictionaryTap: (String) -> Void

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { updateWebView(webView, context: context) }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { updateWebView(webView, context: context) }
    #endif

    func makeCoordinator() -> Coordinator {
        Coordinator(onVerseTap: onVerseTap, onDictionaryTap: onDictionaryTap)
    }

    private func makeWebView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        load(html, in: webView, coordinator: context.coordinator)
        return webView
    }

    private func updateWebView(_ webView: WKWebView, context: Context) {
        context.coordinator.onVerseTap = onVerseTap
        context.coordinator.onDictionaryTap = onDictionaryTap
        if context.coordinator.lastHTML != html {
            load(html, in: webView, coordinator: context.coordinator)
        }
    }

    private func load(_ html: String, in webView: WKWebView, coordinator: Coordinator) {
        coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String = ""
        var onVerseTap: (VerseLinkTarget) -> Void
        var onDictionaryTap: (String) -> Void

        init(onVerseTap: @escaping (VerseLinkTarget) -> Void, onDictionaryTap: @escaping (String) -> Void) {
            self.onVerseTap = onVerseTap
            self.onDictionaryTap = onDictionaryTap
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else {
                decisionHandler(.allow)
                return
            }

            let rawURL = url.absoluteString
            if rawURL.hasPrefix("about:") || rawURL.isEmpty {
                decisionHandler(.allow)
                return
            }

            let decoded = rawURL.removingPercentEncoding ?? rawURL
            let upper = decoded.uppercased().hasPrefix("B:") ? "B:" + decoded.dropFirst(2) :
                decoded.uppercased().hasPrefix("S:") ? "S:" + decoded.dropFirst(2) : decoded

            if upper.hasPrefix("B:") {
                if let target = verseTarget(from: String(upper.dropFirst(2))) {
                    onVerseTap(target)
                }
                decisionHandler(.cancel)
                return
            }

            if upper.hasPrefix("S:") {
                onDictionaryTap(String(upper.dropFirst(2)))
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        private func verseTarget(from ref: String) -> VerseLinkTarget? {
            let parts = ref.components(separatedBy: " ")
            guard parts.count >= 2, let bookNumber = Int(parts[0]) else { return nil }
            let cv = parts[1...].joined().components(separatedBy: ":")
            guard let chapter = Int(cv[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            var verseStart = 0
            var verseEnd = 0
            if cv.count >= 2 {
                let verseParts = cv[1].components(separatedBy: CharacterSet(charactersIn: "-–"))
                verseStart = Int(verseParts.first?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
                verseEnd = verseParts.count > 1 ? (Int(verseParts[1].trimmingCharacters(in: .whitespaces)) ?? verseStart) : verseStart
            }
            guard verseStart > 0 else { return nil }
            return VerseLinkTarget(bookNumber: bookNumber, chapter: chapter, verseStart: verseStart, verseEnd: verseEnd)
        }
    }
}

private enum DictionaryArticleRenderer {
    static func html(topic: String, definitionHTML: String, fontName: String, fontSize: Double) -> String {
        let fontFamily = cssFontFamily(fontName: fontName)

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width,initial-scale=1.0">
        <style>
          html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            color: #1d2430;
            font-family: \(fontFamily);
            font-size: \(fontSize)px;
            line-height: 1.55;
            -webkit-font-smoothing: antialiased;
          }
          body { padding: 18px; }
          h1 {
            margin: 0 0 14px 0;
            font-size: \(fontSize + 10)px;
            line-height: 1.2;
          }
          a {
            color: #8a1c1c;
            text-decoration: none;
          }
          a:hover { text-decoration: underline; }
          hr {
            border: 0;
            border-top: 1px solid rgba(29, 36, 48, 0.15);
            margin: 14px 0;
          }
          p { margin: 0 0 1em 0; }
        </style>
        </head>
        <body>
          <h1>\(escapeHTML(topic))</h1>
          \(normaliseHTML(definitionHTML))
        </body>
        </html>
        """
    }

    private static func cssFontFamily(fontName: String) -> String {
        guard !fontName.isEmpty else {
            return "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", serif"
        }
        let escaped = fontName.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\", -apple-system, BlinkMacSystemFont, \"SF Pro Text\", serif"
    }

    private static func normaliseHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<p/>", with: "<p></p>")
            .replacingOccurrences(of: "<p />", with: "<p></p>")
            .replacingOccurrences(of: "<pb/>", with: "<hr />")
            .replacingOccurrences(of: "<pb />", with: "<hr />")
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

