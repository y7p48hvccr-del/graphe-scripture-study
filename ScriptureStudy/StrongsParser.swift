import Foundation

// MARK: - Verse Segment

enum VerseSegment {
    case text(String)
    case word(String, strongsNumber: String)
}

// MARK: - Strong's Parser

struct StrongsParser {

    static func parse(_ input: String) -> [VerseSegment] {
        if input.contains("<S>") {
            return parsePostfixFormat(input)
        } else if input.contains("<WG>") || input.contains("<WH>") || input.contains("<W>") {
            return parsePrefixFormat(input)
        } else {
            return [.text(stripAllTags(input))]
        }
    }

    // MARK: - Postfix format: word<S>1234</S>
    // Some words have no translation (e.g. Hebrew את H853) and appear as <S>853</S>
    // with only whitespace before them — these must be silently discarded.

    private static func parsePostfixFormat(_ input: String) -> [VerseSegment] {
        // Pre-normalise: strip formatting tags (<J>, <i>, <t>, ¶) but keep their text content
        // so that word<J>text</J><S>num</S> becomes wordtext<S>num</S>
        var normalised = input
        for tag in ["J", "i", "t"] {
            normalised = normalised.replacingOccurrences(of: "<\(tag)>",  with: "")
            normalised = normalised.replacingOccurrences(of: "</\(tag)>", with: "")
        }
        normalised = normalised.replacingOccurrences(of: "¶ ", with: "")
        normalised = normalised.replacingOccurrences(of: "¶",  with: "")

        var segments: [VerseSegment] = []
        var remaining = normalised[normalised.startIndex...]

        while !remaining.isEmpty {
            guard let sOpen = remaining.range(of: "<S>") else {
                let clean = stripAllTags(String(remaining))
                if !clean.isEmpty { segments.append(.text(clean)) }
                break
            }

            // Text before this <S> tag
            let before = String(remaining[remaining.startIndex..<sOpen.lowerBound])
            let (plainPart, lastWord) = splitLastWord(before)

            // Append plain text portion
            let cleanPlain = stripAllTags(plainPart)
            if !cleanPlain.isEmpty { segments.append(.text(cleanPlain)) }

            // Consume this and any immediately following <S> tags
            remaining = remaining[sOpen.upperBound...]
            var strongsKeys: [String] = []

            if let sClose = remaining.range(of: "</S>") {
                let raw = String(remaining[remaining.startIndex..<sClose.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                remaining = remaining[sClose.upperBound...]
                strongsKeys.append(normaliseKey(raw))

                // Consume additional consecutive <S> tags
                while remaining.hasPrefix("<S>") {
                    let nextOpen = remaining.range(of: "<S>")!
                    remaining = remaining[nextOpen.upperBound...]
                    guard let nextClose = remaining.range(of: "</S>") else { break }
                    let extra = String(remaining[remaining.startIndex..<nextClose.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    remaining = remaining[nextClose.upperBound...]
                    strongsKeys.append(normaliseKey(extra))
                }
            }

            let strongsKey = strongsKeys.first ?? ""

            if !lastWord.isEmpty && !strongsKey.isEmpty {
                // Normal case: word with Strong's number
                segments.append(.word(lastWord, strongsNumber: strongsKey))
            } else if !lastWord.isEmpty {
                // Word with no usable Strong's number — treat as plain text
                segments.append(.text(lastWord))
            }
            // If lastWord is empty: standalone Strong's tag (untranslated particle) — silently discard
        }

        return mergeAdjacentText(segments)
    }

    // MARK: - Split "In the beginning" → ("In the ", "beginning")

    private static func splitLastWord(_ text: String) -> (String, String) {
        var i = text.endIndex
        // Skip trailing whitespace
        while i > text.startIndex {
            let prev = text.index(before: i)
            if !text[prev].isWhitespace { break }
            i = prev
        }
        let wordEnd = i
        // Walk back to find word start
        while i > text.startIndex {
            let prev = text.index(before: i)
            if text[prev].isWhitespace || text[prev] == ">" { break }
            i = prev
        }
        let lastWord = stripAllTags(String(text[i..<wordEnd]))
        let prefix   = String(text[text.startIndex..<i])
        return (prefix, lastWord)
    }

    // MARK: - Prefix format: <WG>1234</WG>word

    private static func parsePrefixFormat(_ input: String) -> [VerseSegment] {
        var text = input
        text = replaceTagged(text, open: "<W>G", close: "</W>", newOpen: "<WG>", newClose: "</WG>")
        text = replaceTagged(text, open: "<W>H", close: "</W>", newOpen: "<WH>", newClose: "</WH>")
        text = text.replacingOccurrences(of: "<WT>",  with: "")
        text = text.replacingOccurrences(of: "</WT>", with: "")

        var segments: [VerseSegment] = []
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            let greekRange  = remaining.range(of: "<WG>")
            let hebrewRange = remaining.range(of: "<WH>")

            let tagRange: Range<Substring.Index>?
            let isGreek: Bool
            switch (greekRange, hebrewRange) {
            case (.some(let g), .some(let h)):
                isGreek  = g.lowerBound <= h.lowerBound
                tagRange = isGreek ? g : h
            case (.some(let g), .none): isGreek = true;  tagRange = g
            case (.none, .some(let h)): isGreek = false; tagRange = h
            case (.none, .none):        isGreek = false; tagRange = nil
            }

            guard let found = tagRange else {
                let clean = stripAllTags(String(remaining))
                if !clean.isEmpty { segments.append(.text(clean)) }
                break
            }

            let before = String(remaining[remaining.startIndex..<found.lowerBound])
            let clean  = stripAllTags(before)
            if !clean.isEmpty { segments.append(.text(clean)) }

            let closeTag = isGreek ? "</WG>" : "</WH>"
            let prefix   = isGreek ? "G" : "H"
            remaining    = remaining[found.upperBound...]

            guard let closeRange = remaining.range(of: closeTag) else {
                let rest = stripAllTags(String(remaining))
                if !rest.isEmpty { segments.append(.text(rest)) }
                break
            }

            let number     = String(remaining[remaining.startIndex..<closeRange.lowerBound])
            let strongsKey = prefix + number
            remaining      = remaining[closeRange.upperBound...]

            let word = extractNextWord(&remaining)
            if !word.isEmpty {
                segments.append(.word(word, strongsNumber: strongsKey))
            }
            // If no following word, silently discard (untranslated particle)
        }

        return mergeAdjacentText(segments)
    }

    private static func extractNextWord(_ remaining: inout Substring) -> String {
        while remaining.first?.isWhitespace == true { remaining = remaining.dropFirst() }
        var word = ""
        while let ch = remaining.first, ch != "<", !(ch.isWhitespace && !word.isEmpty) {
            word.append(ch)
            remaining = remaining.dropFirst()
        }
        return word.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Normalise key: "430" stays as-is, "G1234" stays as-is

    private static func normaliseKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Tag replacement

    private static func replaceTagged(
        _ input: String, open: String, close: String,
        newOpen: String, newClose: String
    ) -> String {
        var result = input
        while let s = result.range(of: open),
              let e = result.range(of: close, range: s.upperBound..<result.endIndex) {
            let inner = String(result[s.upperBound..<e.lowerBound])
            result.replaceSubrange(s.lowerBound..<e.upperBound, with: newOpen + inner + newClose)
        }
        return result
    }

    // MARK: - Strip all HTML/markup tags

    static func stripAllTags(_ input: String) -> String {
        var result = input

        // Replace page break markers with a space to prevent words merging
        // e.g. "Isaac,<pb/>Jacob" → "Isaac, Jacob" not "Isaac,Jacob"
        result = result.replacingOccurrences(of: "<pb/>", with: " ")
        result = result.replacingOccurrences(of: "<pb>",  with: " ")

        // Strip <f>...</f> footnote markers AND their content entirely
        // (circled letters ⓐ, ⓑ and numbered refs [1] are footnote symbols, not verse text)
        while let open  = result.range(of: "<f>"),
              let close = result.range(of: "</f>", range: open.lowerBound..<result.endIndex) {
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }

        // Strip remaining tags (keep content)
        while let s = result.range(of: "<"),
              let e = result.range(of: ">", range: s.upperBound..<result.endIndex) {
            result.removeSubrange(s.lowerBound...e.lowerBound)
        }

        // Clean up double spaces left by removed markers
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Merge adjacent text segments

    private static func mergeAdjacentText(_ segments: [VerseSegment]) -> [VerseSegment] {
        var result: [VerseSegment] = []
        for seg in segments {
            if case .text(let new) = seg, case .text(let existing) = result.last {
                result[result.count - 1] = .text(existing + " " + new)
            } else {
                result.append(seg)
            }
        }
        return result
    }
}
