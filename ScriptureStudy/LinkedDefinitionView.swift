import SwiftUI

// MARK: - Parsed segment types

enum DefinitionSegment {
    case text(String)
    case verseLink(label: String, bookNumber: Int, chapter: Int, verse: Int)
    case strongsLink(label: String, number: String)
}

// MARK: - HTML parser

struct DefinitionParser {

    /// MyBible book numbers (multiples of 10) → app book numbers (same scale)
    /// MyBible uses the same numbering so we pass through directly
    static func parse(_ html: String) -> [DefinitionSegment] {
        var segments: [DefinitionSegment] = []
        var remaining = html

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
            let linkLabel = String(remaining[remaining.startIndex..<closeTag.lowerBound])
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
                       let chapter = Int(cvParts[0]),
                       let verse   = Int(cvParts[1]) {
                        segments.append(.verseLink(
                            label: linkLabel,
                            bookNumber: bookNum,
                            chapter: chapter,
                            verse: verse
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
            segments.append(.text(linkLabel))
        }

        return mergeAdjacentText(segments)
    }

    private static func stripBasicTags(_ input: String) -> String {
        var s = input
        // Replace <p/> and <br/> with newline
        s = s.replacingOccurrences(of: "<p/>", with: "\n")
        s = s.replacingOccurrences(of: "<br/>", with: "\n")
        s = s.replacingOccurrences(of: "<br>", with: "\n")
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

    @State private var versePopover:   (Int, Int, Int)? = nil   // bookNumber, chapter, verse
    @State private var strongsPopover: String?           = nil   // Strong's number
    @EnvironmentObject var myBible: MyBibleService

    private var segments: [DefinitionSegment] {
        DefinitionParser.parse(html)
    }

    var body: some View {
        // Build a flow of Text + Button segments
        // We use a wrapping approach with VStack + HStack flow simulation
        // For simplicity, render as a series of inline elements using .init concat
        VStack(alignment: .leading, spacing: 4) {
            // Split by newlines first, then render each line
            let lines = reconstructLines(segments)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.isEmpty {
                    Spacer().frame(height: 4)
                } else {
                    lineView(line)
                }
            }
        }
    }

    @ViewBuilder
    private func lineView(_ segs: [DefinitionSegment]) -> some View {
        // Render segments inline using Text concatenation where possible
        // Links become buttons with popovers
        WrappingHStack(segs: segs, font: font, textColor: textColor, accentColor: accentColor,
                       versePopover: $versePopover, strongsPopover: $strongsPopover)
    }

    private func reconstructLines(_ segments: [DefinitionSegment]) -> [[DefinitionSegment]] {
        var lines: [[DefinitionSegment]] = [[]]
        for seg in segments {
            if case .text(let t) = seg {
                let parts = t.components(separatedBy: "\n")
                for (i, part) in parts.enumerated() {
                    if i > 0 { lines.append([]) }
                    if !part.isEmpty {
                        lines[lines.count - 1].append(.text(part))
                    }
                }
            } else {
                lines[lines.count - 1].append(seg)
            }
        }
        return lines
    }
}

// MARK: - Wrapping HStack for inline segments

struct WrappingHStack: View {
    let segs:         [DefinitionSegment]
    let font:         Font
    let textColor:    Color
    let accentColor:  Color
    @Binding var versePopover:   (Int, Int, Int)?
    @Binding var strongsPopover: String?

    var body: some View {
        // Use a flow layout approach — build a Text where possible, insert buttons for links
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .text(let t):
                    Text(t)
                        .font(font)
                        .foregroundStyle(textColor)
                        .fixedSize(horizontal: false, vertical: true)

                case .verseLink(let label, let bookNum, let chapter, let verse):
                    Button {
                        versePopover = (bookNum, chapter, verse)
                    } label: {
                        Text(label)
                            .font(font.weight(.semibold))
                            .foregroundStyle(accentColor)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: Binding(
                        get: { versePopover?.0 == bookNum && versePopover?.1 == chapter && versePopover?.2 == verse },
                        set: { if !$0 { versePopover = nil } }
                    ), arrowEdge: .bottom) {
                        VersePreviewPopover(
                            bookNumber: bookNum,
                            chapter: chapter,
                            verse: verse,
                            accent: accentColor
                        )
                        .frame(width: 320)
                    }

                case .strongsLink(let label, let number):
                    Button {
                        strongsPopover = number
                    } label: {
                        Text(label)
                            .font(font.weight(.semibold))
                            .foregroundStyle(accentColor)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: Binding(
                        get: { strongsPopover == number },
                        set: { if !$0 { strongsPopover = nil } }
                    ), arrowEdge: .bottom) {
                        StrongsPreviewPopover(number: number, accent: accentColor)
                            .frame(width: 320)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Verse Preview Popover

struct VersePreviewPopover: View {
    let bookNumber: Int
    let chapter:    Int
    let verse:      Int
    let accent:     Color

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
            Text("\(bookName) \(chapter):\(verse)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
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
                Text(verseText)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
            }
        }
        .padding(12)
        .task {
            await loadVerse()
        }
    }

    private func loadVerse() async {
        loading = true
        guard let bible = myBible.selectedBible else {
            loading = false
            return
        }
        let verses = await myBible.loadChapterVerses(
            module: bible, bookNumber: bookNumber, chapter: chapter)
        verseText = verses.first(where: { $0.verse == verse })?.text ?? ""
        loading = false
    }
}

// MARK: - Strong's Preview Popover

struct StrongsPreviewPopover: View {
    let number: String
    let accent:  Color
    var module:  MyBibleModule? = nil   // if nil, falls back to selectedStrongs

    @EnvironmentObject var myBible: MyBibleService
    @State private var entry: StrongsEntry? = nil
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(number)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
            Divider()
            if loading {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if let e = entry {
                if !e.lexeme.isEmpty {
                    Text(e.lexeme)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                }
                if !e.transliteration.isEmpty {
                    Text(e.transliteration)
                        .font(.system(size: 12).italic())
                        .foregroundStyle(.secondary)
                }
                // Show short definition as a quick summary if available
                if !e.shortDefinition.isEmpty {
                    Text(e.shortDefinition)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                // Full definition — use strongsDefinition, fall back to derivation, fall back to raw html
                let def = [e.strongsDefinition, e.derivation, e.kjv]
                    .first(where: { !$0.isEmpty }) ?? ""
                if !def.isEmpty {
                    Divider()
                    ScrollView {
                        Text(def)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: 200)
                } else if !e.rawDefinition.isEmpty {
                    // VGNT / prose HTML format — render with link support
                    Divider()
                    ScrollView {
                        LinkedDefinitionView(
                            html: e.rawDefinition,
                            font: .system(size: 12),
                            textColor: .primary,
                            accentColor: accent,
                            onVerseTap: { _, _, _ in },
                            onStrongsTap: { _ in }
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: 200)
                }
            } else {
                Text("Not found")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .task {
            await loadEntry()
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
            number: number,
            isOldTestament: number.hasPrefix("H")
        )
        loading = false
    }
}
