import SwiftUI
import WebKit

// MARK: - Parsed segment types

enum DefinitionSegment {
    case text(String)
    case verseLink(label: String, bookNumber: Int, chapter: Int, verseStart: Int, verseEnd: Int)
    case strongsLink(label: String, number: String)
}

struct VerseLinkTarget: Identifiable, Equatable {
    let bookNumber: Int
    let chapter: Int
    let verseStart: Int
    let verseEnd: Int

    var id: String { "\(bookNumber)-\(chapter)-\(verseStart)-\(verseEnd)" }
}

// MARK: - HTML parser

struct DefinitionParser {

    /// MyBible book numbers (multiples of 10) → app book numbers (same scale)
    /// MyBible uses the same numbering so we pass through directly
    static func parse(_ html: String) -> [DefinitionSegment] {
        var segments: [DefinitionSegment] = []
        var remaining = normaliseLexiconHTML(html)

        // Strip outer tags we don't need: <b>, <i>, </b>, </i>, <p/>, <br/>
        // We'll handle these by keeping their text content
        while !remaining.isEmpty {

            // Look for next <a href=...> tag
            guard let aStart = remaining.range(of: "<a href='") ?? remaining.range(of: "<a href=\"") else {
                // No more links — append remaining as text
                let clean = stripBasicTags(remaining)
                if !clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(clean))
                }
                break
            }

            // Text before the link
            let before = String(remaining[remaining.startIndex..<aStart.lowerBound])
            let cleanBefore = stripBasicTags(before)
            if !cleanBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.text(cleanBefore))
            }

            // Move past <a href='
            remaining = String(remaining[aStart.upperBound...])

            // Find closing quote
            let quoteChar: Character = remaining.first == "\"" ? "\"" : "'"
            guard let hrefEnd = remaining.firstIndex(of: quoteChar) else { break }
            let href = String(remaining[remaining.startIndex..<hrefEnd])
            remaining = String(remaining[remaining.index(after: hrefEnd)...])

            // Skip >
            if remaining.hasPrefix(">") { remaining = String(remaining.dropFirst()) }

            // Find </a>
            guard let closeTag = remaining.range(of: "</a>") else { break }
            let linkLabel = cleanDisplayText(String(remaining[remaining.startIndex..<closeTag.lowerBound]))
            remaining = String(remaining[closeTag.upperBound...])

            // Parse href
            if href.hasPrefix("B:") {
                // Verse reference: B:{booknum} {chapter}:{verse}
                let ref = String(href.dropFirst(2)) // remove "B:"
                let parts = ref.components(separatedBy: " ")
                if parts.count == 2,
                   let bookNum = Int(parts[0]) {
                    let cvParts = parts[1].components(separatedBy: ":")
                    if cvParts.count == 2,
                       let chapter = Int(cvParts[0]) {
                        let verseParts = cvParts[1].components(separatedBy: CharacterSet(charactersIn: "-–"))
                        guard let verseStart = Int(verseParts[0]) else { continue }
                        let verseEnd = verseParts.count > 1 ? (Int(verseParts[1]) ?? verseStart) : verseStart
                        segments.append(.verseLink(
                            label: linkLabel,
                            bookNumber: bookNum,
                            chapter: chapter,
                            verseStart: verseStart,
                            verseEnd: verseEnd
                        ))
                        continue
                    }
                }
            } else if href.hasPrefix("S:") || href.hasPrefix("G") || href.hasPrefix("H") {
                // Strong's reference
                let number = href.hasPrefix("S:") ? String(href.dropFirst(2)) : href
                segments.append(.strongsLink(label: linkLabel, number: number))
                continue
            }

            // Unrecognised href — just show as text
            if !linkLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.text(linkLabel))
            }
        }

        return mergeAdjacentText(segments)
    }

    private static func cleanDisplayText(_ input: String) -> String {
        decodeHTMLEntities(stripBasicTags(input))
    }

    private static func normaliseLexiconHTML(_ input: String) -> String {
        var s = input
        s = s.replacingOccurrences(of: "<hr>", with: "\n\n")
        s = s.replacingOccurrences(of: "<hr/>", with: "\n\n")
        s = s.replacingOccurrences(of: "<hr />", with: "\n\n")
        // Replace <p/> and <br/> with newline
        s = s.replacingOccurrences(of: "<p/>", with: "\n")
        s = s.replacingOccurrences(of: "<br/>", with: "\n")
        s = s.replacingOccurrences(of: "<br>", with: "\n")
        s = s.replacingOccurrences(of: "</p>", with: "\n")
        s = s.replacingOccurrences(of: "<p>", with: "")
        return s
    }

    private static func stripBasicTags(_ input: String) -> String {
        var s = input
        // Strip remaining tags
        while let open = s.range(of: "<"),
              let close = s.range(of: ">", range: open.upperBound..<s.endIndex) {
            s.removeSubrange(open.lowerBound...close.lowerBound)
        }
        // Clean up multiple newlines
        while s.contains("\n\n\n") {
            s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return s
    }

    private static func decodeHTMLEntities(_ input: String) -> String {
        var s = input
        let namedEntities: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'"
        ]
        for (entity, replacement) in namedEntities {
            s = s.replacingOccurrences(of: entity, with: replacement)
        }

        let pattern = #"&#(x?[0-9A-Fa-f]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let nsString = s as NSString
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: nsString.length)).reversed()
        var result = s

        for match in matches {
            let token = nsString.substring(with: match.range(at: 1))
            let scalarValue: UInt32?
            if token.lowercased().hasPrefix("x") {
                scalarValue = UInt32(token.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(token, radix: 10)
            }

            guard let scalarValue,
                  let scalar = UnicodeScalar(scalarValue) else { continue }
            result = (result as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
        }

        return result
    }

    private static func mergeAdjacentText(_ segments: [DefinitionSegment]) -> [DefinitionSegment] {
        var result: [DefinitionSegment] = []
        for seg in segments {
            if case .text(let new) = seg, case .text(let existing) = result.last {
                result[result.count - 1] = .text(existing + new)
            } else {
                result.append(seg)
            }
        }
        return result
    }
}

// MARK: - Linked Definition View

struct LinkedDefinitionView: View {
    let html:          String
    let font:          Font
    let textColor:     Color
    let accentColor:   Color
    let onVerseTap:    (Int, Int, Int) -> Void   // bookNumber, chapter, verse
    let onStrongsTap:  (String) -> Void          // Strong's number

    @State private var selectedVerseTarget: VerseLinkTarget?
    @EnvironmentObject var myBible: MyBibleService

    private var segments: [DefinitionSegment] {
        DefinitionParser.parse(html)
    }

    private var attributedText: AttributedString {
        var output = AttributedString()

        for segment in segments {
            switch segment {
            case .text(let text):
                var piece = AttributedString(text)
                piece.foregroundColor = textColor
                output += piece

            case .verseLink(let label, let bookNumber, let chapter, let verseStart, let verseEnd):
                var piece = AttributedString(label)
                piece.foregroundColor = accentColor
                piece.underlineStyle = .single
                piece.link = URL(string: "verse://\(bookNumber)/\(chapter)/\(verseStart)/\(verseEnd)")
                output += piece

            case .strongsLink(let label, _):
                var piece = AttributedString(label)
                piece.foregroundColor = textColor
                output += piece
            }
        }

        return output
    }

    var body: some View {
        Text(attributedText)
            .font(font)
            .lineSpacing(6)
            .environment(\.openURL, OpenURLAction { url in
                guard let scheme = url.scheme else { return .systemAction }

                if scheme == "verse" {
                    let pathComponents = url.pathComponents.filter { $0 != "/" }
                    if let host = url.host,
                       pathComponents.count >= 2,
                       let bookNumber = Int(host),
                       let chapter = Int(pathComponents[0]),
                       let verseStart = Int(pathComponents[1]) {
                        let verseEnd = pathComponents.count > 2 ? (Int(pathComponents[2]) ?? verseStart) : verseStart
                        selectedVerseTarget = VerseLinkTarget(bookNumber: bookNumber, chapter: chapter, verseStart: verseStart, verseEnd: verseEnd)
                        return .handled
                    }
                }

                return .systemAction
            })
            .frame(maxWidth: .infinity, alignment: .leading)
            .popover(item: $selectedVerseTarget, arrowEdge: .bottom) { target in
                VersePreviewPopover(
                    bookNumber: target.bookNumber,
                    chapter: target.chapter,
                    verseStart: target.verseStart,
                    verseEnd: target.verseEnd,
                    accent: accentColor,
                    onOpenInBible: {
                        onVerseTap(target.bookNumber, target.chapter, target.verseStart)
                        selectedVerseTarget = nil
                    }
                )
                .frame(width: 320)
            }
    }
}

// MARK: - Verse Preview Popover

struct VersePreviewPopover: View {
    let bookNumber: Int
    let chapter:    Int
    let verseStart: Int
    let verseEnd:   Int
    let accent:     Color
    var onOpenInBible: (() -> Void)? = nil

    @EnvironmentObject var myBible: MyBibleService
    @State private var verseText: String = ""
    @State private var loading = true

    /// Map MyBible book number to book name
    private var bookName: String {
        // MyBible book numbers are multiples of 10 — divide by 10 to get index
        let names = ["", "Gen","Exo","Lev","Num","Deu","Jos","Jdg","Rut","1Sa","2Sa",
                     "1Ki","2Ki","1Ch","2Ch","Ezr","Neh","Est","Job","Psa","Pro",
                     "Ecc","Sng","Isa","Jer","Lam","Eze","Dan","Hos","Joe","Amo",
                     "Oba","Jon","Mic","Nah","Hab","Zep","Hag","Zec","Mal",
                     "Mat","Mar","Luk","Joh","Act","Rom","1Co","2Co","Gal","Eph",
                     "Php","Col","1Th","2Th","1Ti","2Ti","Tit","Phm","Heb","Jas",
                     "1Pe","2Pe","1Jn","2Jn","3Jn","Jud","Rev"]
        let idx = bookNumber / 10
        return idx < names.count ? names[idx] : "Book \(bookNumber)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let onOpenInBible {
                    Button {
                        onOpenInBible()
                    } label: {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(accent)
                            .underline()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help("Open in Bible")
                } else {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .help("Open in Bible")
                }
            }
            Divider()
            if loading {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if verseText.isEmpty {
                Text("Verse not found")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(verseText)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160, maxHeight: 440)
            }
        }
        .padding(12)
        .task {
            await loadVerse()
        }
    }

    private var title: String {
        if verseStart == verseEnd {
            return "\(bookName) \(chapter):\(verseStart)"
        }
        return "\(bookName) \(chapter):\(verseStart)-\(verseEnd)"
    }

    private func loadVerse() async {
        loading = true
        guard let bible = myBible.selectedBible else {
            loading = false
            return
        }
        let verses = await myBible.fetchVerses(module: bible, bookNumber: bookNumber, chapter: chapter)
        let rangeVerses = verses.filter { $0.verse >= verseStart && $0.verse <= verseEnd }
        verseText = rangeVerses.map { "\($0.verse) \($0.text)" }.joined(separator: "\n\n")
        loading = false
    }
}

// MARK: - Strong's Preview Popover

struct StrongsPreviewPopover: View {
    let number: String
    let accent:  Color
    var module:  MyBibleModule? = nil   // if nil, falls back to selectedStrongs

    @EnvironmentObject var myBible: MyBibleService
    @State private var currentNumber: String
    @State private var entry: StrongsEntry? = nil
    @State private var loading = true
    @State private var backStack: [String] = []
    @State private var forwardStack: [String] = []
    @State private var selectedVerseTarget: VerseLinkTarget?

    init(number: String, accent: Color, module: MyBibleModule? = nil) {
        self.number = number
        self.accent = accent
        self.module = module
        _currentNumber = State(initialValue: number)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if loading {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else if let e = entry {
                Divider()
                StrongsPopoverWebView(
                    html: strongsCardHTML(for: e),
                    onVerseTap: { target in
                        selectedVerseTarget = target
                    },
                    onStrongsTap: { tappedNumber in
                        navigateToStrongs(tappedNumber)
                    }
                )
                .frame(minHeight: 220, idealHeight: 320, maxHeight: 420)
                footer
            } else {
                Text("Not found")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .background(Color(red: 0.973, green: 0.890, blue: 0.667))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
        .task(id: currentNumber) {
            await loadEntry()
        }
        .popover(item: $selectedVerseTarget, arrowEdge: .bottom) { target in
            VersePreviewPopover(
                bookNumber: target.bookNumber,
                chapter: target.chapter,
                verseStart: target.verseStart,
                verseEnd: target.verseEnd,
                accent: accent
            )
            .frame(width: 320)
        }
    }

    private func loadEntry() async {
        loading = true
        // Use passed module first, then fall back to selectedStrongs
        guard let strongsModule = module ?? myBible.selectedStrongs else {
            loading = false
            return
        }
        entry = await myBible.lookupStrongs(
            module: strongsModule,
            number: currentNumber,
            isOldTestament: currentNumber.uppercased().hasPrefix("H")
        )
        loading = false
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top) {
            Text(headerTitle)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(red: 0.78, green: 0.02, blue: 0.02))
                .underline()
            Spacer()
            if let badge = sourceBadge {
                Text(badge)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 0.78, green: 0.02, blue: 0.02))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Button {
                guard let previous = backStack.popLast() else { return }
                forwardStack.append(currentNumber)
                currentNumber = previous
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(backStack.isEmpty)
            .opacity(backStack.isEmpty ? 0.35 : 1)

            Button {
                guard let next = forwardStack.popLast() else { return }
                backStack.append(currentNumber)
                currentNumber = next
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(forwardStack.isEmpty)
            .opacity(forwardStack.isEmpty ? 0.35 : 1)

            Spacer()

            Text(currentNumber)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(Color(red: 0.17, green: 0.24, blue: 0.43))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var headerTitle: String {
        guard let entry else { return currentNumber }
        let summary = entry.shortDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return currentNumber }
        return "\(currentNumber) (\(summary))."
    }

    private var sourceBadge: String? {
        guard let entry else { return nil }
        if entry.hasExpandedDefinition { return "ETCBC+" }
        if entry.sourceFlags == "strong" { return "Strong's" }
        return entry.sourceFlags.uppercased()
    }

    private func navigateToStrongs(_ tappedNumber: String) {
        let normalised = tappedNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalised.isEmpty, normalised != currentNumber else { return }
        backStack.append(currentNumber)
        forwardStack.removeAll()
        currentNumber = normalised
    }

    private func strongsCardHTML(for entry: StrongsEntry) -> String {
        StrongsCardRenderer.html(for: entry)
    }

    private func headerLine(for entry: StrongsEntry) -> String {
        let parts = [
            entry.lexeme.isEmpty ? nil : "<span class=\"lexeme\">\(entry.lexeme)</span>",
            entry.transliteration.isEmpty ? nil : "<span class=\"meta\">(\(entry.transliteration)</span>",
            entry.pronunciation.isEmpty ? nil : "<span class=\"meta\">\(entry.pronunciation)</span>",
            partOfSpeech(in: entry.preferredDefinitionHTML).map { "<span class=\"pos\">\($0)</span>" },
            entry.shortDefinition.isEmpty ? nil : "<span class=\"gloss\">\(entry.shortDefinition)</span><span class=\"meta\">)</span>"
        ].compactMap { $0 }

        guard !parts.isEmpty else { return "" }
        return "<div class=\"entry-title\">\(parts.joined(separator: " <span class=\"meta\">|</span> "))</div>"
    }

    private func referencesLine(for entry: StrongsEntry) -> String {
        guard !entry.references.isEmpty else { return "" }
        return "<hr><div class=\"refs\">\(normaliseStrongsHTML(entry.references))</div>"
    }

    private func partOfSpeech(in html: String) -> String? {
        let pattern = #"<span class="part-of-speech">.*?<span class="[^"]+">([^<]+)</span>.*?</span>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let nsHTML = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length)),
              match.numberOfRanges > 1 else { return nil }
        return nsHTML.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normaliseStrongsHTML(_ html: String) -> String {
        StrongsCardRenderer.normaliseStrongsHTML(html)
    }
}

struct StrongsPopoverWebView: WKViewRepresentable {
    let html: String
    var onVerseTap: (VerseLinkTarget) -> Void
    var onStrongsTap: (String) -> Void

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { updateWebView(webView, context: context) }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { updateWebView(webView, context: context) }
    #endif

    func makeCoordinator() -> Coordinator {
        Coordinator(onVerseTap: onVerseTap, onStrongsTap: onStrongsTap)
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
        context.coordinator.onStrongsTap = onStrongsTap
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
        var onStrongsTap: (String) -> Void

        init(onVerseTap: @escaping (VerseLinkTarget) -> Void, onStrongsTap: @escaping (String) -> Void) {
            self.onVerseTap = onVerseTap
            self.onStrongsTap = onStrongsTap
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
            if decoded.uppercased().hasPrefix("B:") {
                if let target = verseTarget(from: String(decoded.dropFirst(2))) {
                    onVerseTap(target)
                }
                decisionHandler(.cancel)
                return
            }

            if let strongsTarget = strongsTarget(from: decoded) {
                onStrongsTap(strongsTarget)
                decisionHandler(.cancel)
                return
            }

            if decoded.lowercased().hasPrefix("s:") {
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        private func strongsTarget(from decodedURL: String) -> String? {
            guard decodedURL.count >= 3 else { return nil }

            let prefix = decodedURL.prefix(2).lowercased()
            guard prefix == "s:" else { return nil }

            let target = String(decodedURL.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else { return nil }

            let pattern = #"^(?:[GH]\d+[A-Z]?|\d+[A-Z]?)$"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let uppercasedTarget = target.uppercased()
            let range = NSRange(uppercasedTarget.startIndex..<uppercasedTarget.endIndex, in: uppercasedTarget)
            guard regex.firstMatch(in: uppercasedTarget, options: [], range: range) != nil else { return nil }

            return target
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

enum StrongsCardRenderer {
    static func html(for entry: StrongsEntry) -> String {
        let body = normaliseStrongsHTML(entry.preferredDefinitionHTML)
        let titleLine = headerLine(for: entry)
        let referencesLine = referencesLine(for: entry)

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
            color: #0d2b72;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", serif;
            font-size: 18px;
            line-height: 1.45;
            -webkit-font-smoothing: antialiased;
          }
          body { padding: 14px; }
          hr {
            border: 0;
            border-top: 1px solid rgba(13, 43, 114, 0.55);
            margin: 14px 0;
          }
          a {
            color: #c90f10;
            text-decoration: none;
          }
          a:hover { text-decoration: underline; }
          .entry-title {
            font-size: 18px;
            margin-bottom: 14px;
            color: #0d2b72;
          }
          .entry-title .lexeme {
            font-size: 23px;
            font-weight: 700;
          }
          .entry-title .meta {
            color: #6c7585;
          }
          .entry-title .pos {
            color: #c200d0;
            font-weight: 600;
          }
          .entry-title .gloss {
            color: #0027ff;
          }
          .refs {
            color: #0d2b72;
            margin-bottom: 12px;
          }
          .refs i { color: #0d2b72; }
          .refs a { color: #c90f10; }
          .source-marker {
            color: inherit;
            text-decoration: none;
          }
          .refs grk, .refs heb, grk, heb, el, wh, wg {
            color: #c90f10;
            font-style: normal;
          }
          .translit {
            color: #6c7585;
          }
          .section-label {
            font-weight: 700;
          }
          big { font-size: 1.15em; }
        </style>
        </head>
        <body>
          \(titleLine)
          \(referencesLine)
          \(body)
        </body>
        </html>
        """
    }

    private static func headerLine(for entry: StrongsEntry) -> String {
        let parts = [
            entry.lexeme.isEmpty ? nil : "<span class=\"lexeme\">\(entry.lexeme)</span>",
            entry.transliteration.isEmpty ? nil : "<span class=\"meta\">(\(entry.transliteration)</span>",
            entry.pronunciation.isEmpty ? nil : "<span class=\"meta\">\(entry.pronunciation)</span>",
            partOfSpeech(in: entry.preferredDefinitionHTML).map { "<span class=\"pos\">\($0)</span>" },
            entry.shortDefinition.isEmpty ? nil : "<span class=\"gloss\">\(entry.shortDefinition)</span><span class=\"meta\">)</span>"
        ].compactMap { $0 }

        guard !parts.isEmpty else { return "" }
        return "<div class=\"entry-title\">\(parts.joined(separator: " <span class=\"meta\">|</span> "))</div>"
    }

    private static func referencesLine(for entry: StrongsEntry) -> String {
        guard !entry.references.isEmpty else { return "" }
        return "<hr><div class=\"refs\">\(normaliseStrongsHTML(entry.references))</div>"
    }

    private static func partOfSpeech(in html: String) -> String? {
        let pattern = #"<span class=\"part-of-speech\">.*?<span class=\"[^\"]+\">([^<]+)</span>.*?</span>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let nsHTML = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length)),
              match.numberOfRanges > 1 else { return nil }
        return nsHTML.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normaliseStrongsHTML(_ html: String) -> String {
        var output = html
        let replacements: [(String, String)] = [
            ("<font color='5'>", "<span class=\"translit\">"),
            ("<font color=\"5\">", "<span class=\"translit\">"),
            ("</font>", "</span>"),
            ("<grk>", "<span class=\"grk\">"),
            ("</grk>", "</span>"),
            ("<heb>", "<span class=\"heb\">"),
            ("</heb>", "</span>"),
            ("<el>", "<span class=\"grk\">"),
            ("</el>", "</span>")
        ]
        for (from, to) in replacements {
            output = output.replacingOccurrences(of: from, with: to)
        }
        if let sourceAnchorRegex = try? NSRegularExpression(
            pattern: #"<a\b[^>]*href\s*=\s*['"]s:[^'"]+['"][^>]*>(.*?)</a>"#,
            options: [.dotMatchesLineSeparators]
        ) {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = sourceAnchorRegex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: "<span class=\"source-marker\">$1</span>")
        }
        if let regex = try? NSRegularExpression(pattern: #"\bs:[a-z0-9._-]+\b"#) {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: "")
        }
        return output
    }
}
