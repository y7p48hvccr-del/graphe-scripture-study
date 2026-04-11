import Foundation
import ZIPFoundation

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
                let r = await Task.detached(priority: .userInitiated) {
                    BookSearchService.searchEPUB(url: book.url, query: q)
                }.value
                found.append(contentsOf: r)
            }
            await MainActor.run {
                self.results    = found
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
        let lq = query.lowercased()
        var results: [BookSearchResult] = []

        for href in spineHrefs {
            guard let data = EPUBParser.read(href, from: archive),
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            else { continue }

            let text = stripHTML(html)
            let lower = text.lowercased()
            var searchFrom = lower.startIndex

            while let range = lower.range(of: lq, range: searchFrom..<lower.endIndex) {
                let snippet = extractSnippet(from: text, around: range, query: query)
                let chapterTitle = chapterTitleFor(href: href, in: book.toc)
                results.append(BookSearchResult(
                    bookURL:      url,
                    bookTitle:    book.title,
                    chapterTitle: chapterTitle,
                    snippet:      snippet,
                    href:         href
                ))
                // Move past this match — one result per chapter is enough
                break
            }
            _ = searchFrom  // suppress warning
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
