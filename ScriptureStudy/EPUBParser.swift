
import Foundation
import ZIPFoundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Scripture Reference

struct ScriptureRef {
    let bookName:   String   // canonical name e.g. "John"
    let bookNumber: Int      // MyBible book number e.g. 430
    let chapter:    Int
    let verse:      Int      // 0 = whole chapter
    let verseEnd:   Int      // 0 = single verse
    let display:    String   // original text as written e.g. "Jn 3:16"

    var url: String {
        "scripture://\(bookNumber)/\(chapter)/\(verse)"
    }
}

// MARK: - Parser

struct ScriptureReferenceParser {

    // MARK: - Book lookup table (name/abbreviation -> MyBible book number)

    static let bookNumbers: [String: Int] = [
        // Old Testament
        "genesis": 10, "gen": 10, "ge": 10, "gn": 10,
        "exodus": 20, "exo": 20, "ex": 20, "exod": 20,
        "leviticus": 30, "lev": 30, "le": 30, "lv": 30,
        "numbers": 40, "num": 40, "nu": 40, "nb": 40,
        "deuteronomy": 50, "deut": 50, "de": 50, "dt": 50,
        "joshua": 60, "josh": 60, "jos": 60, "jsh": 60,
        "judges": 70, "judg": 70, "jdg": 70, "jg": 70,
        "ruth": 80, "rut": 80, "ru": 80,
        "1 samuel": 90, "1samuel": 90, "1sa": 90, "1sam": 90, "1s": 90,
        "2 samuel": 100, "2samuel": 100, "2sa": 100, "2sam": 100, "2s": 100,
        "1 kings": 110, "1kings": 110, "1ki": 110, "1kgs": 110,
        "2 kings": 120, "2kings": 120, "2ki": 120, "2kgs": 120, "2 kgs": 120, "2 ki": 120,
        "1 chronicles": 130, "1chronicles": 130, "1ch": 130, "1chr": 130, "1chron": 130,
        "2 chronicles": 140, "2chronicles": 140, "2ch": 140, "2chr": 140, "2chron": 140,
        "ezra": 150, "ezr": 150,
        "nehemiah": 160, "neh": 160, "ne": 160,
        "esther": 170, "est": 170, "esth": 170,
        "job": 180, "jb": 180,
        "psalms": 190, "psalm": 190, "ps": 190, "psa": 190, "pss": 190,
        "proverbs": 200, "prov": 200, "pr": 200, "prv": 200,
        "ecclesiastes": 210, "eccl": 210, "ecc": 210, "ec": 210, "qoh": 210,
        "song of solomon": 220, "song": 220, "sos": 220, "ss": 220, "cant": 220, "sg": 220,
        "isaiah": 230, "isa": 230, "is": 230,
        "jeremiah": 240, "jer": 240, "je": 240,
        "lamentations": 250, "lam": 250, "la": 250,
        "ezekiel": 260, "ezek": 260, "eze": 260, "ezk": 260,
        "daniel": 270, "dan": 270, "da": 270, "dn": 270,
        "hosea": 280, "hos": 280, "ho": 280,
        "joel": 290, "joe": 290, "jl": 290,
        "amos": 300, "am": 300,
        "obadiah": 310, "obad": 310, "ob": 310,
        "jonah": 320, "jon": 320, "jnh": 320,
        "micah": 330, "mic": 330, "mi": 330,
        "nahum": 340, "nah": 340, "na": 340,
        "habakkuk": 350, "hab": 350,
        "zephaniah": 360, "zeph": 360, "zep": 360,
        "haggai": 370, "hag": 370,
        "zechariah": 380, "zech": 380, "zec": 380,
        "malachi": 390, "mal": 390, "ml": 390,
        // New Testament
        "matthew": 470, "matt": 470, "mat": 470, "mt": 470,
        "mark": 480, "mrk": 480, "mk": 480, "mr": 480,
        "luke": 490, "luk": 490, "lk": 490,
        "john": 500, "joh": 500, "jn": 500, "jhn": 500,
        "acts": 510, "act": 510, "ac": 510,
        "romans": 520, "rom": 520, "ro": 520, "rm": 520,
        "1 corinthians": 530, "1corinthians": 530, "1cor": 530, "1co": 530,
        "2 corinthians": 540, "2corinthians": 540, "2cor": 540, "2co": 540,
        "1 cor": 530, "2 cor": 540, "cor": 530,
        "galatians": 550, "gal": 550, "ga": 550,
        "ephesians": 560, "eph": 560,
        "philippians": 570, "phil": 570, "php": 570, "pp": 570,
        "colossians": 580, "col": 580,
        "1 thessalonians": 590, "1thessalonians": 590, "1thess": 590, "1th": 590,
        "2 thessalonians": 600, "2thessalonians": 600, "2thess": 600, "2th": 600,
        "1 timothy": 610, "1timothy": 610, "1tim": 610, "1ti": 610,
        "2 timothy": 620, "2timothy": 620, "2tim": 620, "2ti": 620,
        "titus": 630, "tit": 630, "ti": 630,
        "philemon": 640, "phlm": 640, "phm": 640,
        "hebrews": 650, "heb": 650,
        "james": 660, "jas": 660, "jm": 660,
        "1 peter": 670, "1peter": 670, "1pet": 670, "1pe": 670, "1pt": 670,
        "2 peter": 680, "2peter": 680, "2pet": 680, "2pe": 680, "2pt": 680,
        "1 john": 690, "1john": 690, "1joh": 690, "1jn": 690, "1jo": 690,
        "2 john": 700, "2john": 700, "2joh": 700, "2jn": 700, "2jo": 700,
        "3 john": 710, "3john": 710, "3joh": 710, "3jn": 710, "3jo": 710,
        "jude": 720, "jud": 720,
        "revelation": 730, "rev": 730, "re": 730, "apoc": 730,
    ]

    // Canonical display name for book number
    static let bookNames: [Int: String] = [
        10: "Genesis", 20: "Exodus", 30: "Leviticus", 40: "Numbers",
        50: "Deuteronomy", 60: "Joshua", 70: "Judges", 80: "Ruth",
        90: "1 Samuel", 100: "2 Samuel", 110: "1 Kings", 120: "2 Kings",
        130: "1 Chronicles", 140: "2 Chronicles", 150: "Ezra", 160: "Nehemiah",
        170: "Esther", 180: "Job", 190: "Psalms", 200: "Proverbs",
        210: "Ecclesiastes", 220: "Song of Solomon", 230: "Isaiah", 240: "Jeremiah",
        250: "Lamentations", 260: "Ezekiel", 270: "Daniel", 280: "Hosea",
        290: "Joel", 300: "Amos", 310: "Obadiah", 320: "Jonah",
        330: "Micah", 340: "Nahum", 350: "Habakkuk", 360: "Zephaniah",
        370: "Haggai", 380: "Zechariah", 390: "Malachi",
        470: "Matthew", 480: "Mark", 490: "Luke", 500: "John",
        510: "Acts", 520: "Romans", 530: "1 Corinthians", 540: "2 Corinthians",
        550: "Galatians", 560: "Ephesians", 570: "Philippians", 580: "Colossians",
        590: "1 Thessalonians", 600: "2 Thessalonians", 610: "1 Timothy", 620: "2 Timothy",
        630: "Titus", 640: "Philemon", 650: "Hebrews", 660: "James",
        670: "1 Peter", 680: "2 Peter", 690: "1 John", 700: "2 John",
        710: "3 John", 720: "Jude", 730: "Revelation",
    ]

    // MARK: - Parse a URL back to ScriptureRef

    static func parse(url: URL) -> ScriptureRef? {
        guard url.scheme == "scripture",
              let host = url.host,
              let standardBookNumber = Int(host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 1, let chapter = Int(parts[0]) else { return nil }
        let verse    = parts.count >= 2 ? Int(parts[1]) ?? 0 : 0
        let verseEnd = parts.count >= 3 ? Int(parts[2]) ?? 0 : 0
        let name     = bookNames[standardBookNumber] ?? "Book \(standardBookNumber)"
        return ScriptureRef(bookName: name, bookNumber: standardBookNumber,
                            chapter: chapter, verse: verse,
                            verseEnd: verseEnd, display: name)
    }

    /// Resolves the standard book number to the correct number for the given Bible module.
    /// Different Bible files may use different book numbering schemes.
    @MainActor
    static func resolveBookNumber(_ ref: ScriptureRef, in myBible: MyBibleService) -> ScriptureRef {
        guard let bible = myBible.selectedBible else { return ref }
        // Try to find the actual book number by name in this Bible's books table
        if let actualNumber = myBible.bookNumber(forName: ref.bookName, in: bible),
           actualNumber != ref.bookNumber {
            return ScriptureRef(bookName: ref.bookName, bookNumber: actualNumber,
                                chapter: ref.chapter, verse: ref.verse,
                                verseEnd: ref.verseEnd, display: ref.display)
        }
        return ref
    }

    // MARK: - Inject links into HTML

    /// Faster variant — only scans text inside <p> and <div> tags, skipping
    /// headers, nav, footnotes and other structural elements.

    /// Scans the body text of an HTML string and wraps scripture references
    /// in <a href="scripture://bookNumber/chapter/verse"> links.
    static func injectLinks(into html: String, accentHex: String) -> String {
        // Wrap everything in a safety net — never crash the EPUB reader
        do {
            return try injectLinksInternal(into: html, accentHex: accentHex)
        } catch {
            return html  // Return unmodified HTML on any error
        }
    }

    private static func injectLinksInternal(into html: String, accentHex: String) throws -> String {
        // Only process text nodes — don't scan inside existing <a> tags or <style>/<script>
        // Strategy: split on tags, process text segments only
        let linkCSS = """
        a.scripture-ref {
            color: \(accentHex);
            text-decoration: underline;
            text-decoration-style: dotted;
            text-underline-offset: 2px;
            cursor: pointer;
        }
        """

        var result = html

        // Inject the scripture link style
        if result.contains("</style>") {
            result = result.replacingOccurrences(of: "</style>",
                with: linkCSS + "\n</style>",
                options: .backwards)
        }

        // Pattern: optional number prefix + book name + chapter + optional :verse + optional -endverse
        // e.g. "John 3:16", "1 Cor. 2:5-8", "Ps 23", "Matt. 5:1"
        let pattern = #"(?<!\w)(?:(1|2|3)\s+)?([A-Z][a-zA-Z]{1,14})\.?\s+(\d{1,3})(?::(\d{1,3})(?:-(\d{1,3}))?)?"#
        _ = pattern // used in processTextSegment via injectLinksSimple

        // Process text nodes only — skip content inside < >
        // We'll work on the full string but only replace matches that are in text context
        var output    = ""
        var lastEnd   = result.startIndex
        var insideTag = false

        var i = result.startIndex
        while i < result.endIndex {
            let ch = result[i]
            if ch == "<" {
                insideTag = true
                output.append(contentsOf: result[lastEnd..<i])
                // Check if this is an opening <a> — skip until </a>
                let remaining = String(result[i...])
                if remaining.lowercased().hasPrefix("<a ") || remaining.lowercased().hasPrefix("<a>") {
                    // Find end of </a>
                    if let closeRange = remaining.range(of: "</a>", options: .caseInsensitive) {
                        let fullTag = String(remaining[remaining.startIndex..<closeRange.upperBound])
                        output.append(fullTag)
                        i = result.index(i, offsetBy: fullTag.count, limitedBy: result.endIndex) ?? result.endIndex
                        lastEnd = i
                        insideTag = false
                        continue
                    }
                }
                output.append(ch)
                lastEnd = result.index(after: i)
            } else if ch == ">" {
                insideTag = false
                output.append(ch)
                lastEnd = result.index(after: i)
            } else if !insideTag {
                // Accumulate text — we'll process at tag boundaries
                i = result.index(after: i)
                continue
            }
            i = result.index(after: i)
        }

        // Simpler, more reliable approach: regex replace on the full HTML
        // but skip anything inside existing <a...> tags
        // Process the body text using a segment-based approach
        return injectLinksSimple(into: html, accentHex: accentHex, linkCSS: linkCSS)
    }

    private static func injectLinksSimple(into html: String, accentHex: String, linkCSS: String) -> String {
        var result = html

        // Inject CSS
        if result.contains("</style>") {
            result = result.replacingOccurrences(of: "</style>",
                with: linkCSS + "\n</style>", options: .backwards)
        }

        // Stream through the HTML character by character, writing directly to output.
        // Never materialise a segments array — process each text node inline and discard it.
        var out          = ""
        out.reserveCapacity(result.count + result.count / 4)
        var textBuf      = ""
        var inTag        = false
        var insideAnchor = false
        var tagBuf       = ""

        // Max text node size to attempt scripture-ref injection.
        // Nodes larger than this (e.g. inline scripts, huge paragraphs) are passed through unchanged.
        let maxTextNode = 2_000

        func flushText() {
            guard !textBuf.isEmpty else { return }
            if insideAnchor || textBuf.count > maxTextNode {
                out.append(textBuf)
            } else {
                out.append(processTextSegment(textBuf))
            }
            textBuf = ""
        }

        for ch in result {
            if ch == "<" {
                if !inTag {
                    flushText()
                    tagBuf = "<"
                    inTag  = true
                } else {
                    tagBuf.append(ch)
                }
            } else if ch == ">" && inTag {
                tagBuf.append(ch)
                let lower = tagBuf.lowercased()
                if lower.hasPrefix("<a ") || lower == "<a>" { insideAnchor = true }
                if lower.hasPrefix("</a")                   { insideAnchor = false }
                out.append(tagBuf)
                tagBuf = ""
                inTag  = false
            } else if inTag {
                tagBuf.append(ch)
            } else {
                textBuf.append(ch)
            }
        }
        // Flush any remaining content
        if !tagBuf.isEmpty { out.append(tagBuf) }
        flushText()

        return out
    }

    private static func processTextSegment(_ text: String) -> String {
        let pattern = #"(?<![A-Za-z\d])(?:(1|2|3)\s+)?([A-Z][a-z]{1,14})\.?\s+(\d{1,3})(?::\s*(\d{1,3})(?:[-\u2013\u2014](\d{1,3}))?)?"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }

        // Words that look like book names but aren't scripture references
        let blacklist: Set<String> = [
            "the", "this", "that", "these", "those", "there", "their", "they",
            "then", "than", "thus", "through", "though", "therefore", "therein",
            "chapter", "verse", "see", "note", "page", "part", "section",
            "vol", "volume", "line", "figure", "table", "step", "item",
            "no", "number", "col", "row", "para", "par",
            "latin", "greek", "hebrew", "where", "when", "which", "while",
            "with", "without", "within", "after", "before", "since", "until",
            "upon", "under", "over", "above", "below", "between", "among",
            "for", "from", "into", "onto", "about", "against", "across",
            "but", "and", "not", "nor", "yet", "so", "or", "as", "if",
            "also", "even", "only", "just", "both", "either", "neither",
            "every", "each", "all", "any", "some", "many", "much", "more",
            "most", "other", "another", "such", "same", "own", "few",
            "here", "now", "how", "why", "what", "who", "whom", "whose",
        ]

        let ns      = text as NSString
        let range   = NSRange(location: 0, length: ns.length)
        let matches = re.matches(in: text, range: range)

        // Build replacements list, then apply in reverse so ranges stay valid
        var replacements: [(range: Range<String.Index>, link: String)] = []

        for m in matches {
            let bookStr  = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
            let chapStr  = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : ""
            let prefix   = m.range(at: 1).location != NSNotFound && m.range(at: 1).length > 0
                           ? ns.substring(with: m.range(at: 1)) : ""
            let verseStr = m.range(at: 4).location != NSNotFound && m.range(at: 4).length > 0
                           ? ns.substring(with: m.range(at: 4)) : ""

            guard !blacklist.contains(bookStr.lowercased()) else { continue }
            guard bookStr.count >= 2 else { continue }
            if verseStr.isEmpty && bookStr.count < 3 { continue }

            let lookupKey = prefix.isEmpty ? bookStr.lowercased() : "\(prefix) \(bookStr.lowercased())"
            guard let bookNum = bookNumbers[lookupKey],
                  let chapter = Int(chapStr) else { continue }

            let verse   = Int(verseStr) ?? 0
            let matched = ns.substring(with: m.range)
            let url     = "scripture://\(bookNum)/\(chapter)/\(verse)"
            let link    = "<a href=\"\(url)\" class=\"scripture-ref\">\(matched)</a>"

            guard let swiftRange = Range(m.range, in: text) else { continue }
            replacements.append((range: swiftRange, link: link))
        }

        // Apply in reverse order so earlier ranges stay valid
        var result = text
        for rep in replacements.reversed() {
            result.replaceSubrange(rep.range, with: rep.link)
        }
        return result
    }
}


// MARK: - Models

struct EPUBBook: Identifiable {
    let id         = UUID()
    let url:       URL
    var title:     String    = "Unknown"
    var author:    String    = ""
    var coverImage: PlatformImage? = nil
    var toc:       [TOCItem] = []
    var opfBase:   String    = ""
}

struct TOCItem: Identifiable {
    let id         = UUID()
    let title:     String
    let href:      String
    var fragment:  String?       // optional anchor inside the file (e.g. "ch5")
    var children:  [TOCItem] = []
    var isExpanded: Bool     = false
}

struct SpineItem: Identifiable {
    let id    = UUID()
    let idref: String
    let href:  String
}

// MARK: - Parser

class EPUBParser {

    // MARK: - Pre-compiled style-stripping regexes (compiled once, reused on every page)
    private static func stripStylesAndImages(from html: String) -> String {
        return html
    }

    // MARK: - Page content cache (keyed by href+theme+fontSize)
    private static let pageCache = NSCache<NSString, NSString>()

    private static func cacheKey(href: String, theme: AppTheme, fontSize: Double) -> NSString {
        "\(href)|\(theme.id)|\(Int(fontSize))" as NSString
    }

    static func invalidateCache() {
        pageCache.removeAllObjects()
    }

    // MARK: - Parse EPUB

    /// Convenience overload — opens its own archive from the URL.
    /// Prefer parse(url:archive:) when you already have an open archive
    /// to avoid opening the ZIP file a second time (which can fail under sandbox).
    static func parse(url: URL) -> EPUBBook? {
        guard let archive = try? Archive(url: url, accessMode: .read, pathEncoding: nil) else { return nil }
        return parse(url: url, archive: archive)
    }

    /// Primary parse entry point — uses the supplied archive so no second open is needed.
    static func parse(url: URL, archive: Archive) -> EPUBBook? {
        var book = EPUBBook(url: url)

        // 1. container.xml -> OPF path
        guard let containerData = read("META-INF/container.xml", from: archive),
              let containerStr  = String(data: containerData, encoding: .utf8),
              let opfPath       = firstCapture(in: containerStr, pattern: "full-path=\"([^\"]+)\"")
        else { return nil }

        book.opfBase = (opfPath as NSString).deletingLastPathComponent

        // 2. OPF metadata
        guard let opfData = read(opfPath, from: archive),
              let opfStr  = String(data: opfData, encoding: .utf8)
        else { return nil }

        book.title  = tagContent("dc:title",   in: opfStr) ?? url.deletingPathExtension().lastPathComponent
        book.author = tagContent("dc:creator", in: opfStr) ?? ""

        // 3. Manifest id -> href map
        let manifest = buildManifest(opfStr, base: book.opfBase)

        // 4. Cover image
        book.coverImage = findCover(opfStr: opfStr, manifest: manifest, archive: archive)

        // 5. TOC - try NAV (epub3) then NCX (epub2)
        if let navHref = manifest.values.first(where: { $0.hasSuffix("nav.xhtml") || $0.contains("/nav.") }),
           let navData  = read(navHref, from: archive),
           let navStr   = String(data: navData, encoding: .utf8) {
            book.toc = parseNavTOC(navStr, base: book.opfBase)
        } else if let ncxHref = manifest.values.first(where: { $0.hasSuffix(".ncx") }),
                  let ncxData  = read(ncxHref, from: archive),
                  let ncxStr   = String(data: ncxData, encoding: .utf8) {
            book.toc = parseNCXTOC(ncxStr, base: book.opfBase)
        }

        // 6. If TOC is flat (no nesting), try to synthesize chapter children
        //    from anchor links inside each top-level entry's content page.
        //    Useful for Bibles where the publisher only lists books in the TOC
        //    and puts chapter links at the top of each book's first page.
        book.toc = synthesizeChildrenFromContent(toc: book.toc, archive: archive)

        return book
    }

    // MARK: - Loading / placeholder page

    static func loadingPage(theme: AppTheme, fontSize: Double) -> String {
        let bg = theme.background.toHex()
        let fg = theme.secondary.toHex()
        return """
        <html><body style='background:\(bg);margin:0;display:flex;
        align-items:center;justify-content:center;height:100vh;'>
        <p style='font-family:Georgia,serif;font-size:\(Int(fontSize))px;
        color:\(fg);opacity:0.5;'>Loading…</p>
        </body></html>
        """
    }

    // MARK: - Page HTML

    static func pageContent(href: String, archive: Archive,
                            theme: AppTheme, fontSize: Double, fontName: String) -> String {
        // Split off the #fragment — archive lookups must use the bare file path.
        // The fragment, if any, will be used to scroll to that anchor after load.
        let filePath: String
        let fragment: String?
        if let hashIdx = href.firstIndex(of: "#") {
            filePath = String(href[..<hashIdx])
            fragment = String(href[href.index(after: hashIdx)...])
        } else {
            filePath = href
            fragment = nil
        }

        // Cache key uses only the file path + styling — the same file rendered
        // for two different fragments is the same HTML; we just scroll to a
        // different anchor. Avoids duplicate cache entries per book in a shared file.
        let key = cacheKey(href: filePath, theme: theme, fontSize: fontSize)
        if UserDefaults.standard.bool(forKey: "preCacheEpubPages"),
           let cached = pageCache.object(forKey: key) {
            return injectFragmentScroll(into: cached as String, fragment: fragment)
        }

        guard let data = read(filePath, from: archive),
              var html = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1)
        else { return loadingPage(theme: theme, fontSize: fontSize) }

        // Strip existing styles and images
        html = EPUBParser.stripStylesAndImages(from: html)

        let font   = fontName.isEmpty ? "Georgia, serif" : "'\(fontName)', Georgia, serif"
        let bg     = theme.background.toHex()
        let fg     = theme.text.toHex()
        let sub    = theme.secondary.toHex()

        let css = """
        <style>
        * { box-sizing: border-box; }
        body { font-family: \(font); font-size: \(fontSize)px; line-height: 1.85;
               color: \(fg); background: \(bg); margin: 0; padding: 28px 36px 56px; max-width: 740px; }
        h1,h2,h3,h4 { color: \(fg); line-height: 1.3; margin: 1.5em 0 0.4em; }
        h1 { font-size: \(Int(fontSize * 1.6))px; }
        h2 { font-size: \(Int(fontSize * 1.3))px; }
        h3 { font-size: \(Int(fontSize * 1.1))px; }
        p  { margin: 0 0 0.9em; }
        blockquote { border-left: 3px solid \(sub); margin: 1em 0; padding: 0.4em 1em; color: \(sub); }
        a  { color: \(sub); text-decoration: none; }
        </style>
        """
        let js = """
        <script>
        document.addEventListener('click', function(e) {
            var el = e.target;
            while (el && el.tagName !== 'A') el = el.parentElement;
            if (!el) return;
            var href = el.getAttribute('href');
            if (!href) return;
            e.preventDefault();
            if (href.indexOf('scripture://') === 0) {
                window.location.href = href;
            } else {
                window.location.href = 'epub-internal://' + href;
            }
        });
        </script>
        """
        if html.contains("</head>") {
            html = html.replacingOccurrences(of: "</head>", with: css + js + "</head>")
        } else {
            html = css + js + html
        }

        // Inject scripture reference links only if user has enabled it
        let detectRefs   = UserDefaults.standard.bool(forKey: "detectScriptureRefs")
        let usePageCache = UserDefaults.standard.bool(forKey: "preCacheEpubPages")

        if detectRefs {
            if let bodyRange = html.range(of: "<body", options: .caseInsensitive) {
                let head = String(html[html.startIndex..<bodyRange.lowerBound])
                let body = String(html[bodyRange.lowerBound...])
                html = head + ScriptureReferenceParser.injectLinks(into: body, accentHex: sub)
            }
        }

        // Cache if pre-caching is enabled — cache the bare page, scroll script
        // is injected fresh each call so it honours the current fragment.
        if usePageCache {
            pageCache.setObject(html as NSString, forKey: key)
        }

        return injectFragmentScroll(into: html, fragment: fragment)
    }

    /// Append a script that scrolls to the given element ID once the page is laid out.
    /// No-op when fragment is nil or empty.
    private static func injectFragmentScroll(into html: String, fragment: String?) -> String {
        guard let frag = fragment, !frag.isEmpty else { return html }
        // JSON-escape to be safe — fragment IDs can contain unusual characters.
        let safe = frag.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "'",  with: "\\'")
        let scroll = """
        <script>
        (function() {
            var targetId = '\(safe)';
            var attempts = 0;
            function jump() {
                attempts++;
                var el = document.getElementById(targetId);
                if (!el) {
                    // Element may not exist; give up silently after first try.
                    return;
                }
                var rect = el.getBoundingClientRect();
                var y = rect.top + window.pageYOffset - 60;
                window.scrollTo(0, y < 0 ? 0 : y);
                // If layout shifts after fonts/CSS apply, position will
                // change — retry a few times over the first ~500ms.
                if (attempts < 5) { setTimeout(jump, 80); }
            }
            function start() { requestAnimationFrame(jump); }
            if (document.readyState === 'complete') {
                start();
            } else {
                window.addEventListener('load', start);
                // Also try earlier in case 'load' is slow (large pages, images)
                if (document.readyState === 'interactive') {
                    setTimeout(start, 50);
                } else {
                    window.addEventListener('DOMContentLoaded', function() {
                        setTimeout(start, 50);
                    });
                }
            }
        })();
        </script>
        """
        if let bodyEnd = html.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            return html.replacingCharacters(in: bodyEnd, with: scroll + "</body>")
        }
        return html + scroll
    }

    // MARK: - Archive helpers

    static func read(_ path: String, from archive: Archive) -> Data? {
        guard let entry = archive[path] else {
            return nil
        }
        var out = Data()
        out.reserveCapacity(Int(entry.uncompressedSize))
        do {
            _ = try archive.extract(entry) { chunk in
                out.append(chunk)
            }
            return out.isEmpty ? nil : out
        } catch {
            return nil
        }
    }

    // MARK: - XML helpers

    private static func firstCapture(in str: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m  = re.firstMatch(in: str, range: NSRange(str.startIndex..., in: str))
        else { return nil }
        let ns = str as NSString
        return ns.substring(with: m.range(at: 1))
    }

    private static func tagContent(_ tag: String, in xml: String) -> String? {
        return firstCapture(in: xml, pattern: "<\(tag)[^>]*>([^<]+)</\(tag)>")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func buildManifest(_ opf: String, base: String) -> [String: String] {
        var map: [String: String] = [:]
        guard let itemRe = try? NSRegularExpression(pattern: "<item[^>]+>"),
              let idRe   = try? NSRegularExpression(pattern: "\\bid=\"([^\"]+)\""),
              let hrefRe = try? NSRegularExpression(pattern: "href=\"([^\"]+)\"")
        else { return map }
        let ns = opf as NSString
        itemRe.enumerateMatches(in: opf, range: NSRange(opf.startIndex..., in: opf)) { m, _, _ in
            guard let m = m else { return }
            let tag = ns.substring(with: m.range)
            guard let idM   = idRe.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                  let hrefM = hrefRe.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag))
            else { return }
            let tagNS = tag as NSString
            let id    = tagNS.substring(with: idM.range(at: 1))
            let href  = tagNS.substring(with: hrefM.range(at: 1))
            map[id]   = base.isEmpty ? href : "\(base)/\(href)"
        }
        return map
    }

 

    private static func findCover(opfStr: String, manifest: [String: String],
                                   archive: Archive) -> PlatformImage? {
        // Strategy 1: meta name="cover" -> manifest id
        if let coverID = firstCapture(in: opfStr, pattern: "name=\"cover\"[^>]*content=\"([^\"]+)\""),
           let href = manifest[coverID],
           let data = read(href, from: archive),
           let img  = PlatformImage(data: data) { return img }

        // Strategy 2: manifest entry whose id contains "cover" and is an image
        let imageExts = ["jpg", "jpeg", "png"]
        if let href = manifest.first(where: { k, v in
            k.lowercased().contains("cover") && imageExts.contains((v as NSString).pathExtension.lowercased())
        })?.value,
           let data = read(href, from: archive),
           let img  = PlatformImage(data: data) { return img }

        // Strategy 3 and 4 disabled — too many file reads can trigger issues
        return nil
    }

    // Fast cover extraction — skips full parse
    static func quickCover(url: URL) -> PlatformImage? {
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read, pathEncoding: nil) } catch { return nil }

        // Find OPF
        guard let containerData = read("META-INF/container.xml", from: archive),
              let containerStr  = String(data: containerData, encoding: .utf8),
              let opfPath       = firstCapture(in: containerStr, pattern: "full-path=\"([^\"]+)\""),
              let opfData       = read(opfPath, from: archive),
              let opfStr        = String(data: opfData, encoding: .utf8)
        else {
            // Fallback: first image in archive
            return firstArchiveImage(archive)
        }

        let base = (opfPath as NSString).deletingLastPathComponent
        let manifest = buildManifest(opfStr, base: base)
        let exts = ["jpg","jpeg","png"]

        // Try manifest cover
        if let href = manifest.first(where: { k, v in
            k.lowercased().contains("cover") &&
            exts.contains((v as NSString).pathExtension.lowercased())
        })?.value,
           let data = read(href, from: archive),
           let img  = PlatformImage(data: data) { return img }

        // Try any image in manifest
        if let href = manifest.values.first(where: {
            exts.contains(($0 as NSString).pathExtension.lowercased())
        }),
           let data = read(href, from: archive),
           let img  = PlatformImage(data: data) { return img }

        return firstArchiveImage(archive)
    }

    private static func firstArchiveImage(_ archive: Archive) -> PlatformImage? {
        let exts = ["jpg","jpeg","png"]
        for entry in archive {
            if exts.contains((entry.path as NSString).pathExtension.lowercased()) {
                var data = Data()
                _ = try? archive.extract(entry) { data.append($0) }
                if let img = PlatformImage(data: data) { return img }
            }
        }
        return nil
    }


    // MARK: - NAV TOC (EPUB3)

    private static func parseNavTOC(_ nav: String, base: String) -> [TOCItem] {
        let section: String
        if let s = firstCapture(in: nav, pattern: "<nav[^>]*epub:type=\"toc\"[^>]*>([\\s\\S]*?)</nav>") {
            section = s
        } else {
            section = nav
        }
        return parseOLItems(section, base: base)
    }

    private static func parseOLItems(_ html: String, base: String) -> [TOCItem] {
        var items: [TOCItem] = []
        // Extract the contents of the outermost <ol>...</ol> (if present), then
        // walk that one level finding only the top-level <li>…</li> children.
        // Nested <ol> blocks inside a <li> are handed off to a recursive call.
        let scope = outermostTag("ol", in: html) ?? html
        for li in topLevelTagBodies("li", in: scope) {
            // The <a> or <span> naming this row lives BEFORE any nested <ol>.
            // Slicing there avoids the first <a> match being a descendant that
            // belongs to a child entry (which would misname the parent).
            let liNS   = li as NSString
            let olRng  = liNS.range(of: "<ol", options: .caseInsensitive)
            let header: String = olRng.location == NSNotFound
                ? li
                : liNS.substring(to: olRng.location)

            let title: String
            let href:  String
            if let aMatch = firstTag("a", in: header) {
                let rawHref = attribute("href", in: aMatch.openTag) ?? ""
                title = textBetween(aMatch.openTag, and: "</a>", in: header)
                         .trimmingCharacters(in: .whitespacesAndNewlines)
                href  = base.isEmpty ? rawHref : "\(base)/\(rawHref)"
            } else if let sMatch = firstTag("span", in: header) {
                title = textBetween(sMatch.openTag, and: "</span>", in: header)
                         .trimmingCharacters(in: .whitespacesAndNewlines)
                href  = ""   // structural header, not navigable
            } else {
                continue
            }
            var item = TOCItem(title: title, href: href)
            // Recurse into any nested <ol> inside this <li> for children.
            if let inner = outermostTag("ol", in: li) {
                item.children = parseOLItems(inner, base: base)
            }
            items.append(item)
        }
        return items
    }

    // MARK: - Small HTML/XML helpers used by the TOC parsers
    //
    // These are intentionally tiny and specific: they don't try to be a
    // general HTML parser — just enough to pick top-level children of a
    // known tag while respecting nesting.

    /// Returns the inner text of the first <tag>…</tag> found at any depth in `s`,
    /// or nil if there isn't one. Used for getting the contents of the outer
    /// <ol> or <navMap> before iterating its top-level children.
    private static func outermostTag(_ tag: String, in s: String) -> String? {
        let ns = s as NSString
        guard let open = ns.range(of: "<\(tag)", options: .caseInsensitive).upperBoundOrNil else { return nil }
        // Find end of the opening tag (the '>').
        guard let gt = ns.range(of: ">", range: NSRange(location: open, length: ns.length - open)).upperBoundOrNil
        else { return nil }
        // Now walk looking for the matching </tag> counting nesting.
        var depth = 1
        var idx   = gt
        let openPat  = "<\(tag)"
        let closePat = "</\(tag)>"
        while idx < ns.length {
            let rest = NSRange(location: idx, length: ns.length - idx)
            let nextOpen  = ns.range(of: openPat,  options: .caseInsensitive, range: rest)
            let nextClose = ns.range(of: closePat, options: .caseInsensitive, range: rest)
            if nextClose.location == NSNotFound { return nil }
            if nextOpen.location != NSNotFound && nextOpen.location < nextClose.location {
                depth += 1
                idx = nextOpen.location + nextOpen.length
            } else {
                depth -= 1
                if depth == 0 {
                    return ns.substring(with: NSRange(location: gt, length: nextClose.location - gt))
                }
                idx = nextClose.location + nextClose.length
            }
        }
        return nil
    }

    /// Returns the inner bodies of every direct <tag>…</tag> child inside `s`,
    /// skipping any tags found inside a deeper nesting level.
    private static func topLevelTagBodies(_ tag: String, in s: String) -> [String] {
        var result: [String] = []
        let ns = s as NSString
        let openPat  = "<\(tag)"
        let closePat = "</\(tag)>"
        var idx = 0
        while idx < ns.length {
            let rest = NSRange(location: idx, length: ns.length - idx)
            let open = ns.range(of: openPat, options: .caseInsensitive, range: rest)
            if open.location == NSNotFound { break }
            // Locate end of the opening tag.
            guard let gt = ns.range(of: ">", range: NSRange(location: open.location + open.length,
                                                            length: ns.length - open.location - open.length)).upperBoundOrNil
            else { break }
            // Walk to matching close, counting nesting.
            var depth = 1
            var j = gt
            var bodyEnd = -1
            var afterClose = -1
            while j < ns.length {
                let r = NSRange(location: j, length: ns.length - j)
                let nextOpen  = ns.range(of: openPat,  options: .caseInsensitive, range: r)
                let nextClose = ns.range(of: closePat, options: .caseInsensitive, range: r)
                if nextClose.location == NSNotFound { break }
                if nextOpen.location != NSNotFound && nextOpen.location < nextClose.location {
                    depth += 1
                    j = nextOpen.location + nextOpen.length
                } else {
                    depth -= 1
                    if depth == 0 {
                        bodyEnd    = nextClose.location
                        afterClose = nextClose.location + nextClose.length
                        break
                    }
                    j = nextClose.location + nextClose.length
                }
            }
            if bodyEnd < 0 { break }
            result.append(ns.substring(with: NSRange(location: gt, length: bodyEnd - gt)))
            idx = afterClose
        }
        return result
    }

    /// Locates the first <tag …> opening in `s` and returns both its opening-tag
    /// text (e.g. `<a href="…" class="…">`) and the offset where its body starts.
    private static func firstTag(_ tag: String, in s: String) -> (openTag: String, bodyStart: Int)? {
        let ns = s as NSString
        let r  = ns.range(of: "<\(tag)", options: .caseInsensitive)
        guard r.location != NSNotFound else { return nil }
        let afterName = r.location + r.length
        let gtR = ns.range(of: ">", range: NSRange(location: afterName, length: ns.length - afterName))
        guard gtR.location != NSNotFound else { return nil }
        let openLen = gtR.location + gtR.length - r.location
        let openStr = ns.substring(with: NSRange(location: r.location, length: openLen))
        return (openStr, gtR.location + gtR.length)
    }

    /// Returns the attribute value for `name` in an opening-tag string like `<a href="foo" …>`.
    private static func attribute(_ name: String, in openTag: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "\(name)\\s*=\\s*\"([^\"]*)\"",
                                                options: .caseInsensitive) else { return nil }
        let ns = openTag as NSString
        guard let m = re.firstMatch(in: openTag, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// Returns the text between `openTag` and the first occurrence of `closeTag` in `s`.
    private static func textBetween(_ openTag: String, and closeTag: String, in s: String) -> String {
        let ns = s as NSString
        let oR = ns.range(of: openTag)
        guard oR.location != NSNotFound else { return "" }
        let start = oR.location + oR.length
        let cR = ns.range(of: closeTag, options: .caseInsensitive,
                          range: NSRange(location: start, length: ns.length - start))
        guard cR.location != NSNotFound else { return "" }
        // Strip any inner tags — leaf TOC entries' labels should be plain text.
        let raw = ns.substring(with: NSRange(location: start, length: cR.location - start))
        let stripped = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode a handful of common HTML entities so titles like "Wisdom &amp; Poetry"
        // render as "Wisdom & Poetry" in the TOC.
        return stripped
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    // MARK: - NCX TOC (EPUB2)

    private static func parseNCXTOC(_ ncx: String, base: String) -> [TOCItem] {
        parseNavPoints(ncx, base: base)
    }

    private static func parseNavPoints(_ xml: String, base: String) -> [TOCItem] {
        var items: [TOCItem] = []
        // Only iterate top-level <navPoint>…</navPoint> pairs at this level.
        // Children are handled by recursing into each one's body.
        for body in topLevelTagBodies("navPoint", in: xml) {
            let bodyNS = body as NSString
            guard let textM = (try? NSRegularExpression(pattern: "<text>([^<]+)</text>"))?
                                .firstMatch(in: body, range: NSRange(location: 0, length: bodyNS.length)),
                  let srcM  = (try? NSRegularExpression(pattern: "src=\"([^\"]+)\""))?
                                .firstMatch(in: body, range: NSRange(location: 0, length: bodyNS.length))
            else { continue }

            let title  = bodyNS.substring(with: textM.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            // Keep full src (including any #fragment). Stripping collapses
            // multiple books that share the same file into a single href,
            // which breaks TOC highlight and intra-file navigation.
            let rawSrc = bodyNS.substring(with: srcM.range(at: 1))
            let href   = base.isEmpty ? rawSrc : "\(base)/\(rawSrc)"
            var item   = TOCItem(title: title, href: href)
            if body.contains("<navPoint") {
                item.children = parseNavPoints(body, base: base)
            }
            items.append(item)
        }
        return items
    }

    // MARK: - Synthesize chapter children from in-page anchor links
    //
    // For TOCs that are flat at the top level (typical of Bibles where the publisher
    // only lists 66 books and puts chapter links inline at the top of each book's
    // first page), this scans each book's content for anchor links that look like
    // chapter markers and turns them into nested children.
    //
    // Safety rules: never replaces children that already exist; never adds children
    // unless we find at least 3 chapter-like anchors (avoids polluting non-Bible EPUBs
    // whose first pages happen to contain stray links).

    private static func synthesizeChildrenFromContent(toc: [TOCItem], archive: Archive) -> [TOCItem] {
        guard !toc.isEmpty else {
            print("[TOC-Synth] TOC is empty, skipping")
            return toc
        }

        // If ANY entry already has nested children, the TOC is already structured —
        // leave it alone.
        if toc.contains(where: { !$0.children.isEmpty }) {
            print("[TOC-Synth] TOC already nested, skipping")
            return toc
        }

        print("[TOC-Synth] Flat TOC with \(toc.count) entries, attempting to synthesize children")

        return toc.enumerated().map { idx, item -> TOCItem in
            var updated = item
            let anchors = extractChapterAnchors(href: item.href, archive: archive, entryIndex: idx, title: item.title)
            if anchors.count >= 3 {
                print("[TOC-Synth] ✓ \(item.title): added \(anchors.count) chapter children")
                updated.children = anchors.map { (label, fragment) in
                    TOCItem(title: label, href: item.href, fragment: fragment)
                }
            } else {
                print("[TOC-Synth] ✗ \(item.title): only found \(anchors.count) chapter-like anchors")
            }
            return updated
        }
    }

    private static func extractChapterAnchors(href: String, archive: Archive, entryIndex: Int = 0, title: String = "") -> [(label: String, fragment: String)] {
        guard let data = read(href, from: archive),
              let html = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1)
        else {
            print("[TOC-Synth]   [\(title)] could not read content at \(href)")
            return []
        }

        // Look only at the first ~12 KB — chapter navigation is invariably at the
        // top of the page, and parsing the whole book file is unnecessary.
        let scanLimit = min(html.count, 12_000)
        let head      = String(html.prefix(scanLimit))

        // For the first entry, print a sample of what the HTML actually looks like
        // so we can see what patterns the chapter links use.
        if entryIndex == 0 {
            // Skip past the <head>...</head> so we see content, not metadata
            let bodyStart = head.range(of: "<body", options: .caseInsensitive)?.upperBound ?? head.startIndex
            let sample = String(head[bodyStart...].prefix(2500))
            print("[TOC-Synth]   [\(title)] HTML sample (after <body>):\n\(sample)\n[TOC-Synth]   -- end sample --")
        }

        // Pull every anchor that points to a fragment (#anchor or file#anchor) along
        // with its visible text.
        guard let aRe = try? NSRegularExpression(
            pattern: "<a[^>]+href=\"([^\"]*#[^\"]+)\"[^>]*>([^<]+)</a>",
            options: [.caseInsensitive]
        ) else { return [] }

        // Also count TOTAL anchors (not just fragment-pointing ones) so we can diagnose
        // whether chapters point to separate files rather than in-page anchors.
        if let anyARe = try? NSRegularExpression(pattern: "<a[^>]+href=\"([^\"]+)\"[^>]*>([^<]*)</a>",
                                                 options: [.caseInsensitive]) {
            let allMatches = anyARe.matches(in: head, range: NSRange(location: 0, length: (head as NSString).length))
            if entryIndex == 0 {
                print("[TOC-Synth]   [\(title)] total anchor tags in first 12KB: \(allMatches.count)")
                // Show the first 10 anchors so we can see what they look like
                let nsHead = head as NSString
                for (i, m) in allMatches.prefix(10).enumerated() {
                    let hrefStr = nsHead.substring(with: m.range(at: 1))
                    let textStr = nsHead.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    print("[TOC-Synth]     anchor \(i): href=\"\(hrefStr)\" text=\"\(textStr)\"")
                }
            }
        }

        var seen:    Set<String>                       = []
        var results: [(label: String, fragment: String)] = []
        let ns       = head as NSString
        aRe.enumerateMatches(in: head, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m else { return }
            let rawHref = ns.substring(with: m.range(at: 1))
            let rawText = ns.substring(with: m.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;",  with: "&")

            // Extract the fragment portion only (after #).
            guard let hashIdx = rawHref.firstIndex(of: "#") else { return }
            let fragment = String(rawHref[rawHref.index(after: hashIdx)...])
            guard !fragment.isEmpty, !seen.contains(fragment) else { return }

            // Filter for chapter-like text:
            //   - purely numeric ("1", "23", "150")
            //   - "Chapter N", "Ch N", "Ch. N"
            //   - Roman numerals up to 4 chars ("IV", "XII")
            // Anything else (footnote refs, cross-refs, copyright) is skipped.
            let label: String
            if rawText.allSatisfy({ $0.isNumber }), !rawText.isEmpty {
                label = "Chapter \(rawText)"
            } else if rawText.range(of: #"^(Chapter|Ch\.?|CHAPTER)\s*\d+$"#,
                                    options: [.regularExpression]) != nil {
                label = rawText
            } else if rawText.count <= 4,
                      rawText.allSatisfy({ "IVXLCDMivxlcdm".contains($0) }) {
                label = "Chapter \(rawText.uppercased())"
            } else {
                return
            }

            seen.insert(fragment)
            results.append((label, fragment))
            // Sanity cap — Bible books top out at 150 chapters (Psalms).
            if results.count >= 200 { return }
        }
        return results
    }
}

// Small NSRange convenience used by the depth-aware HTML helpers above.
// Returns nil when the range wasn't found, saving a NSNotFound guard at callsites.
private extension NSRange {
    var upperBoundOrNil: Int? {
        location == NSNotFound ? nil : location + length
    }
}
