import Foundation

// MARK: - Verse Segment

enum VerseSegment {
    case text(String)
    case word(String, strongsNumber: String)
    case footnote(marker: String, content: String)
}

// MARK: - Strong's Parser

struct StrongsParser {

    static func parse(_ input: String) -> [VerseSegment] {
        // Strip <n>...</n> gloss notes before parsing
        var cleaned = input
        while let o = cleaned.range(of: "<n>"),
              let c = cleaned.range(of: "</n>", range: o.lowerBound..<cleaned.endIndex) {
            cleaned.removeSubrange(o.lowerBound..<c.upperBound)
        }
        if cleaned.contains("<S>") {
            return parsePostfixFormat(cleaned)
        } else if cleaned.contains("<WG>") || cleaned.contains("<WH>") || cleaned.contains("<W>") {
            return parsePrefixFormat(cleaned)
        } else {
            return parsePlainWithFootnotes(cleaned)
        }
    }

    // MARK: - Plain text with footnote extraction

    static func parsePlainWithFootnotes(_ input: String) -> [VerseSegment] {
        var segments: [VerseSegment] = []
        var remaining = input
        var footnoteIndex = 0
        let markers = ["ᵃ","ᵇ","ᶜ","ᵈ","ᵉ","ᶠ","ᵍ","ʰ","ⁱ","ʲ"]

        while !remaining.isEmpty {
            guard let fOpen = remaining.range(of: "<f>"),
                  let fClose = remaining.range(of: "</f>",
                      range: fOpen.lowerBound..<remaining.endIndex) else {
                // No more footnotes — append remaining as plain text
                let plain = stripAllTags(remaining)
                if !plain.isEmpty { segments.append(.text(plain)) }
                break
            }

            // Text before this footnote
            let before = String(remaining[remaining.startIndex..<fOpen.lowerBound])
            let plain  = stripAllTags(before)
            if !plain.isEmpty { segments.append(.text(plain)) }

            // Footnote content
            let content = String(remaining[fOpen.upperBound..<fClose.lowerBound])
            let marker  = footnoteIndex < markers.count ? markers[footnoteIndex] : "†"
            footnoteIndex += 1
            segments.append(.footnote(marker: marker, content: stripAllTags(content)))

            remaining = String(remaining[fClose.upperBound...])
        }

        return segments
    }

    // MARK: - Postfix format: word<S>1234</S>

    private static func parsePostfixFormat(_ input: String) -> [VerseSegment] {
        // First extract footnotes, preserving their positions
        var footnoteMap: [String: String] = [:]
        var footnoteIndex = 0
        let markerList = ["ᵃ","ᵇ","ᶜ","ᵈ","ᵉ","ᶠ","ᵍ","ʰ","ⁱ","ʲ"]
        var preprocessed = input

        while let fOpen = preprocessed.range(of: "<f>"),
              let fClose = preprocessed.range(of: "</f>",
                  range: fOpen.lowerBound..<preprocessed.endIndex) {
            let content = String(preprocessed[fOpen.upperBound..<fClose.lowerBound])
            let marker  = footnoteIndex < markerList.count ? markerList[footnoteIndex] : "†"
            footnoteIndex += 1
            let placeholder = "⟨FN:\(marker)⟩"
            footnoteMap[placeholder] = content
            preprocessed.replaceSubrange(fOpen.lowerBound..<fClose.upperBound,
                                         with: " \(placeholder) ")
        }

        // Now parse Strong's as before
        var normalised = preprocessed
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
                let clean = stripAllTagsAndExpandFootnotes(String(remaining),
                                                           footnoteMap: footnoteMap,
                                                           segments: &segments)
                if !clean.isEmpty { segments.append(.text(clean)) }
                break
            }

            let before = String(remaining[remaining.startIndex..<sOpen.lowerBound])
            let (plainPart, lastWord) = splitLastWord(before)

            expandFootnotesInText(stripAllTags(plainPart),
                                  footnoteMap: footnoteMap,
                                  segments: &segments)

            remaining = remaining[sOpen.upperBound...]
            var strongsKeys: [String] = []

            if let sClose = remaining.range(of: "</S>") {
                let raw = String(remaining[remaining.startIndex..<sClose.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                remaining = remaining[sClose.upperBound...]
                strongsKeys.append(normaliseKey(raw))

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
                segments.append(.word(lastWord, strongsNumber: strongsKey))
            } else if !lastWord.isEmpty {
                segments.append(.text(lastWord))
            }
        }

        return mergeAdjacentText(segments)
    }

    // MARK: - Prefix format: <WG>1234</WG>word

    private static func parsePrefixFormat(_ input: String) -> [VerseSegment] {
        // Extract footnotes first
        var footnoteMap: [String: String] = [:]
        var footnoteIndex = 0
        let markerList = ["ᵃ","ᵇ","ᶜ","ᵈ","ᵉ","ᶠ","ᵍ","ʰ","ⁱ","ʲ"]
        var preprocessed = input

        while let fOpen = preprocessed.range(of: "<f>"),
              let fClose = preprocessed.range(of: "</f>",
                  range: fOpen.lowerBound..<preprocessed.endIndex) {
            let content = String(preprocessed[fOpen.upperBound..<fClose.lowerBound])
            let marker  = footnoteIndex < markerList.count ? markerList[footnoteIndex] : "†"
            footnoteIndex += 1
            let placeholder = "⟨FN:\(marker)⟩"
            footnoteMap[placeholder] = content
            preprocessed.replaceSubrange(fOpen.lowerBound..<fClose.upperBound,
                                         with: " \(placeholder) ")
        }

        var text = preprocessed
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
                expandFootnotesInText(stripAllTags(String(remaining)),
                                      footnoteMap: footnoteMap,
                                      segments: &segments)
                break
            }

            let before = String(remaining[remaining.startIndex..<found.lowerBound])
            expandFootnotesInText(stripAllTags(before),
                                  footnoteMap: footnoteMap,
                                  segments: &segments)

            let closeTag = isGreek ? "</WG>" : "</WH>"
            let prefix   = isGreek ? "G" : "H"
            remaining    = remaining[found.upperBound...]

            guard let closeRange = remaining.range(of: closeTag) else {
                expandFootnotesInText(stripAllTags(String(remaining)),
                                      footnoteMap: footnoteMap,
                                      segments: &segments)
                break
            }

            let number     = String(remaining[remaining.startIndex..<closeRange.lowerBound])
            let strongsKey = prefix + number
            remaining      = remaining[closeRange.upperBound...]

            let word = extractNextWord(&remaining)
            if !word.isEmpty {
                segments.append(.word(word, strongsNumber: strongsKey))
            }
        }

        return mergeAdjacentText(segments)
    }

    // MARK: - Footnote expansion helpers

    private static func expandFootnotesInText(_ text: String,
                                               footnoteMap: [String: String],
                                               segments: inout [VerseSegment]) {
        guard !footnoteMap.isEmpty else {
            if !text.isEmpty { segments.append(.text(text)) }
            return
        }
        var remaining = text
        while !remaining.isEmpty {
            var foundPlaceholder: String? = nil
            var foundRange: Range<String.Index>? = nil
            for placeholder in footnoteMap.keys {
                if let r = remaining.range(of: placeholder) {
                    if foundRange == nil || r.lowerBound < foundRange!.lowerBound {
                        foundPlaceholder = placeholder
                        foundRange = r
                    }
                }
            }
            guard let ph = foundPlaceholder, let r = foundRange else {
                if !remaining.isEmpty { segments.append(.text(remaining)) }
                break
            }
            let before = String(remaining[remaining.startIndex..<r.lowerBound])
            if !before.trimmingCharacters(in: .whitespaces).isEmpty {
                segments.append(.text(before))
            }
            let marker  = String(ph.dropFirst(5).dropLast(1)) // ⟨FN:X⟩ → X
            let content = footnoteMap[ph] ?? ""
            segments.append(.footnote(marker: marker, content: stripAllTags(content)))
            remaining = String(remaining[r.upperBound...])
        }
    }

    @discardableResult
    private static func stripAllTagsAndExpandFootnotes(_ text: String,
                                                        footnoteMap: [String: String],
                                                        segments: inout [VerseSegment]) -> String {
        let stripped = stripAllTags(text)
        expandFootnotesInText(stripped, footnoteMap: footnoteMap, segments: &segments)
        return ""
    }

    // MARK: - Split "In the beginning" → ("In the ", "beginning")

    private static func splitLastWord(_ text: String) -> (String, String) {
        var i = text.endIndex
        while i > text.startIndex {
            let prev = text.index(before: i)
            if !text[prev].isWhitespace { break }
            i = prev
        }
        let wordEnd = i
        while i > text.startIndex {
            let prev = text.index(before: i)
            if text[prev].isWhitespace || text[prev] == ">" { break }
            i = prev
        }
        let lastWord = stripAllTags(String(text[i..<wordEnd]))
        let prefix   = String(text[text.startIndex..<i])
        return (prefix, lastWord)
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

    private static func normaliseKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces)
    }

    private static func replaceTagged(
        _ input: String, open: String, close: String,
        newOpen: String, newClose: String
    ) -> String {
        var result = input
        while let s = result.range(of: open),
              let e = result.range(of: close, range: s.upperBound..<result.endIndex) {
            let inner = String(result[s.upperBound..<e.lowerBound])
            result.replaceSubrange(s.lowerBound..<e.upperBound,
                                   with: newOpen + inner + newClose)
        }
        return result
    }

    static func stripAllTags(_ input: String) -> String {
        var result = input
        result = result.replacingOccurrences(of: "<pb/>", with: " ")
        result = result.replacingOccurrences(of: "<pb>",  with: " ")

        // Strip footnote placeholders (already extracted above)
        // Strip <f>...</f> that weren't caught (safety net — drop content)
        while let open  = result.range(of: "<f>"),
              let close = result.range(of: "</f>",
                  range: open.lowerBound..<result.endIndex) {
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }

        // Strip remaining tags (keep content)
        while let s = result.range(of: "<"),
              let e = result.range(of: ">", range: s.upperBound..<result.endIndex) {
            result.removeSubrange(s.lowerBound...e.lowerBound)
        }

        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
