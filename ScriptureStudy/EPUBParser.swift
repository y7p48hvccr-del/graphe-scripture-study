
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

        // Split into segments: alternating text and tag
        var segments: [(text: String, isTag: Bool)] = []
        var current  = ""
        var inTag    = false

        for ch in result {
            if ch == "<" {
                if !inTag {
                    if !current.isEmpty { segments.append((current, false)) }
                    current = "<"
                    inTag   = true
                } else {
                    current.append(ch)
                }
            } else if ch == ">" && inTag {
                current.append(ch)
                segments.append((current, true))
                current = ""
                inTag   = false
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { segments.append((current, inTag)) }

        // Track if we're inside an <a> tag — don't inject into nested links
        var insideAnchor = false
        var out          = ""

        for seg in segments {
            if seg.isTag {
                let lower = seg.text.lowercased()
                if lower.hasPrefix("<a ") || lower == "<a>" { insideAnchor = true }
                if lower.hasPrefix("</a") { insideAnchor = false }
                out.append(seg.text)
            } else {
                if insideAnchor {
                    out.append(seg.text)
                } else {
                    out.append(processTextSegment(seg.text))
                }
            }
        }

        return out
    }

    private static func processTextSegment(_ text: String) -> String {
        let pattern = #"(?<![A-Za-z\d])(?:(1|2|3)\s+)?([A-Z][a-z]{1,14})\.?\s+(\d{1,3})(?::\s*(\d{1,3})(?:[-\u2013\u2014](\d{1,3}))?)?"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }

        // Semicolon-inherited reference: "; 85: 3" or "; 85:3"
        let semiPattern = #";\s*(\d{1,3}):\s*(\d{1,3})"#
        guard let semiRe = try? NSRegularExpression(pattern: semiPattern) else { return text }

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
        var result  = text
        var offset  = 0

        let matches = re.matches(in: text, range: range)
        for m in matches {
            let fullRange = m.range
            let matched   = ns.substring(with: fullRange)

            let prefix   = m.range(at: 1).location != NSNotFound
                           && m.range(at: 1).length > 0
                           ? ns.substring(with: m.range(at: 1)) : ""
            let bookStr  = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
            let chapStr  = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : ""
            let verseStr = m.range(at: 4).location != NSNotFound
                           && m.range(at: 4).length > 0
                           ? ns.substring(with: m.range(at: 4)) : ""
            let verseEndStr = m.range(at: 5).location != NSNotFound
                              && m.range(at: 5).length > 0
                              ? ns.substring(with: m.range(at: 5)) : ""

            guard !blacklist.contains(bookStr.lowercased()) else { continue }
            guard bookStr.count >= 2 else { continue }
            if verseStr.isEmpty && bookStr.count < 3 { continue }

            let lookupKey = prefix.isEmpty
                ? bookStr.lowercased()
                : "\(prefix) \(bookStr.lowercased())"

            guard let bookNum = bookNumbers[lookupKey],
                  let chapter = Int(chapStr) else { continue }

            let verse = Int(verseStr)    ?? 0
            let _     = Int(verseEndStr) ?? 0
            let url   = "scripture://\(bookNum)/\(chapter)/\(verse)"
            let link  = "<a href=\"\(url)\" class=\"scripture-ref\">\(matched)</a>"

            let adjustedLoc = fullRange.location + offset
            guard let swiftRange = Range(NSRange(location: adjustedLoc, length: fullRange.length),
                                         in: result) else { continue }
            result.replaceSubrange(swiftRange, with: link)
            offset += link.count - fullRange.length

            // Immediately after linking this reference, check if a "; chapter: verse"
            // follows it in the result string — if so, link that too using this book.
            let searchStart = adjustedLoc + link.count
            guard searchStart < result.utf16.count else { continue }
            let searchRange = NSRange(location: searchStart, length: min(30, result.utf16.count - searchStart))
            if let semiMatch = semiRe.firstMatch(in: result, range: searchRange),
               let chapRange2  = Range(semiMatch.range(at: 1), in: result),
               let verseRange2 = Range(semiMatch.range(at: 2), in: result),
               let chapter2 = Int(result[chapRange2]),
               let verse2   = Int(result[verseRange2]) {

                let url2  = "scripture://\(bookNum)/\(chapter2)/\(verse2)"
                guard let semiSwift = Range(semiMatch.range, in: result) else { continue }
                let semiText = String(result[semiSwift])
                // Keep the semicolon as plain text, link just the number part
                let semiChar = semiText.prefix(while: { $0 == ";" || $0 == " " })
                let refText  = semiText.dropFirst(semiChar.count)
                let semiLink = "\(semiChar)<a href=\"\(url2)\" class=\"scripture-ref\">\(refText)</a>"
                result.replaceSubrange(semiSwift, with: semiLink)
                offset += semiLink.count - semiText.count
            }
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

    static func parse(url: URL) -> EPUBBook? {
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read, pathEncoding: nil) } catch { return nil }
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
        // Check cache before touching the ZIP archive (only when pre-caching is on)
        let key = cacheKey(href: href, theme: theme, fontSize: fontSize)
        if UserDefaults.standard.bool(forKey: "preCacheEpubPages"),
           let cached = pageCache.object(forKey: key) {
            return cached as String
        }

        guard let data = read(href, from: archive),
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

        // Cache if pre-caching is enabled
        if usePageCache {
            pageCache.setObject(html as NSString, forKey: key)
        }

        return html
    }

    // MARK: - Archive helpers

    static func read(_ path: String, from archive: Archive) -> Data? {
        guard let entry = archive[path] else { return nil }
        var out = Data()
        _ = try? archive.extract(entry) { out.append($0) }
        return out.isEmpty ? nil : out
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

        // Strategy 3: any manifest entry that is an image
        if let href = manifest.values.first(where: {
            imageExts.contains(($0 as NSString).pathExtension.lowercased())
        }),
           let data = read(href, from: archive),
           let img  = PlatformImage(data: data) { return img }

        // Strategy 4: first image file anywhere in archive
        for entry in archive {
            if imageExts.contains((entry.path as NSString).pathExtension.lowercased()) {
                var data = Data()
                _ = try? archive.extract(entry) { data.append($0) }
                if let img = PlatformImage(data: data) { return img }
            }
        }
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
        guard let liRe = try? NSRegularExpression(pattern: "<li[^>]*>([\\s\\S]*?)</li>"),
              let aRe  = try? NSRegularExpression(pattern: "<a[^>]+href=\"([^\"]+)\"[^>]*>([^<]+)</a>")
        else { return [] }
        let ns = html as NSString
        liRe.enumerateMatches(in: html, range: NSRange(location: 0, length: (html as NSString).length)) { m, _, _ in
            guard let m = m else { return }
            let li   = ns.substring(with: m.range(at: 1))
            let liNS = li as NSString
            guard let aM = aRe.firstMatch(in: li, range: NSRange(location: 0, length: (li as NSString).length)) else { return }
            var rawHref = liNS.substring(with: aM.range(at: 1))
            if let hash = rawHref.firstIndex(of: "#") { rawHref = String(rawHref[..<hash]) }
            let title   = liNS.substring(with: aM.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            let href    = base.isEmpty ? rawHref : "\(base)/\(rawHref)"
            var item    = TOCItem(title: title, href: href)
            if li.contains("<ol") { item.children = parseOLItems(li, base: base) }
            items.append(item)
        }
        return items
    }

    // MARK: - NCX TOC (EPUB2)

    private static func parseNCXTOC(_ ncx: String, base: String) -> [TOCItem] {
        parseNavPoints(ncx, base: base)
    }

    private static func parseNavPoints(_ xml: String, base: String) -> [TOCItem] {
        var items: [TOCItem] = []
        let ns = xml as NSString
        guard let startRe = try? NSRegularExpression(pattern: "<navPoint[^>]*>") else { return [] }
        let matches = startRe.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let bodyStart = m.range.location + m.range.length
            guard bodyStart < ns.length else { continue }
            let remaining = ns.substring(from: bodyStart)
            let closeRange = (remaining as NSString).range(of: "</navPoint>")
            guard closeRange.location != NSNotFound else { continue }
            let body   = (remaining as NSString).substring(to: closeRange.location)
            let bodyNS = body as NSString

            guard let textM = (try? NSRegularExpression(pattern: "<text>([^<]+)</text>"))?
                                .firstMatch(in: body, range: NSRange(location: 0, length: bodyNS.length)),
                  let srcM  = (try? NSRegularExpression(pattern: "src=\"([^\"]+)\""))?
                                .firstMatch(in: body, range: NSRange(location: 0, length: bodyNS.length))
            else { continue }

            let title  = bodyNS.substring(with: textM.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            var rawSrc = bodyNS.substring(with: srcM.range(at: 1))
            if let hash = rawSrc.firstIndex(of: "#") { rawSrc = String(rawSrc[..<hash]) }
            let href   = base.isEmpty ? rawSrc : "\(base)/\(rawSrc)"
            var item   = TOCItem(title: title, href: href)
            if body.contains("<navPoint") { item.children = parseNavPoints(body, base: base) }
            items.append(item)
        }
        return items
    }
}
