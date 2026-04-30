#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Editor Controller

class NoteEditorController: ObservableObject {
    @Published private(set) var isBoldActive = false
    @Published private(set) var isItalicActive = false
    @Published private(set) var isUnderlineActive = false
    @Published private(set) var isHighlightActive = false
    @Published private(set) var isHeadingActive = false
    @Published private(set) var isBulletActive = false
    @Published private(set) var isNumberedActive = false
    private static let noteHighlightColor = NSColor.systemYellow.withAlphaComponent(0.35)
    private static let scriptureBookPattern = [
        "Genesis", "Gen\\.?", "Ge\\.?",
        "Exodus", "Exod\\.?", "Ex\\.?",
        "Leviticus", "Lev\\.?", "Lv\\.?",
        "Numbers", "Num\\.?", "Nm\\.?", "Nu\\.?",
        "Deuteronomy", "Deut\\.?", "Dt\\.?",
        "Joshua", "Josh\\.?", "Jos\\.?",
        "Judges", "Judg\\.?", "Jdg\\.?", "Jgs\\.?",
        "Ruth",
        "Samuel", "Sam\\.?", "Sa\\.?",
        "Kings", "Kgs\\.?", "Ki\\.?", "Kg\\.?",
        "Chronicles", "Chron\\.?", "Chr\\.?", "Ch\\.?",
        "Ezra", "Ezr\\.?",
        "Nehemiah", "Neh\\.?", "Ne\\.?",
        "Esther", "Est\\.?", "Es\\.?",
        "Job",
        "Psalms?", "Ps\\.?", "Psa\\.?", "Psm\\.?",
        "Proverbs", "Prov\\.?", "Pr\\.?", "Pro\\.?",
        "Ecclesiastes", "Eccl\\.?", "Ecc\\.?", "Qoh\\.?",
        "Song[\\s\\p{Cf}]+of[\\s\\p{Cf}]+(?:Solomon|Songs)",
        "Song", "SOS\\.?", "So\\.?", "Cant\\.?",
        "Isaiah", "Isa\\.?", "Is\\.?",
        "Jeremiah", "Jer\\.?", "Je\\.?",
        "Lamentations", "Lam\\.?", "La\\.?",
        "Ezekiel", "Ezek\\.?", "Eze\\.?", "Ezk\\.?",
        "Daniel", "Dan\\.?", "Da\\.?",
        "Hosea", "Hos\\.?", "Ho\\.?",
        "Joel", "Joe\\.?", "Jl\\.?",
        "Amos",
        "Obadiah", "Obad\\.?", "Ob\\.?",
        "Jonah", "Jon\\.?",
        "Micah", "Mic\\.?", "Mc\\.?",
        "Nahum", "Nah\\.?", "Na\\.?",
        "Habakkuk", "Hab\\.?", "Hb\\.?",
        "Zephaniah", "Zeph\\.?", "Zep\\.?",
        "Haggai", "Hag\\.?", "Hg\\.?",
        "Zechariah", "Zech\\.?", "Zec\\.?",
        "Malachi", "Mal\\.?", "Ml\\.?",
        "Matthew", "Matt\\.?", "Mt\\.?",
        "Mark", "Mk\\.?", "Mrk\\.?", "Mar\\.?",
        "Luke", "Lk\\.?", "Luk\\.?",
        "John", "Jn\\.?", "Jhn\\.?", "Joh\\.?",
        "Acts", "Ac\\.?", "Act\\.?",
        "Romans", "Rom\\.?", "Ro\\.?", "Rm\\.?",
        "Corinthians", "Cor\\.?",
        "Galatians", "Gal\\.?", "Ga\\.?",
        "Ephesians", "Eph\\.?", "Ep\\.?",
        "Philippians", "Phil\\.?", "Php\\.?", "Pp\\.?",
        "Colossians", "Col\\.?",
        "Thessalonians", "Thess\\.?", "Thes\\.?", "Th\\.?",
        "Timothy", "Tim\\.?",
        "Titus", "Tit\\.?",
        "Philemon", "Philem\\.?", "Phlm\\.?", "Phm\\.?", "Pm\\.?",
        "Hebrews", "Heb\\.?", "He\\.?",
        "James", "Jas\\.?", "Jam\\.?", "Jm\\.?",
        "Peter", "Pet\\.?", "Pe\\.?",
        "Jude",
        "Revelation", "Rev\\.?", "Re\\.?", "Rv\\.?", "Apoc\\.?"
    ].joined(separator: "|")
    private static let scriptureBookAliases: [String: String] = [
        "ge": "genesis",
        "gen": "genesis",
        "lv": "leviticus",
        "ex": "exodus",
        "exod": "exodus",
        "lev": "leviticus",
        "nm": "numbers",
        "nu": "numbers",
        "num": "numbers",
        "dt": "deuteronomy",
        "deut": "deuteronomy",
        "josh": "joshua",
        "jos": "joshua",
        "judg": "judges",
        "jdg": "judges",
        "jgs": "judges",
        "sam": "samuel",
        "sa": "samuel",
        "kgs": "kings",
        "ki": "kings",
        "kg": "kings",
        "chron": "chronicles",
        "chr": "chronicles",
        "ch": "chronicles",
        "ezr": "ezra",
        "neh": "nehemiah",
        "ne": "nehemiah",
        "est": "esther",
        "es": "esther",
        "ps": "psalms",
        "psa": "psalms",
        "psm": "psalms",
        "prov": "proverbs",
        "pr": "proverbs",
        "pro": "proverbs",
        "eccl": "ecclesiastes",
        "ecc": "ecclesiastes",
        "qoh": "ecclesiastes",
        "song": "song of solomon",
        "song of songs": "song of solomon",
        "sos": "song of solomon",
        "so": "song of solomon",
        "cant": "song of solomon",
        "isa": "isaiah",
        "is": "isaiah",
        "jer": "jeremiah",
        "je": "jeremiah",
        "lam": "lamentations",
        "la": "lamentations",
        "ezek": "ezekiel",
        "eze": "ezekiel",
        "ezk": "ezekiel",
        "dan": "daniel",
        "da": "daniel",
        "hos": "hosea",
        "ho": "hosea",
        "joe": "joel",
        "jl": "joel",
        "obad": "obadiah",
        "ob": "obadiah",
        "jon": "jonah",
        "mic": "micah",
        "mc": "micah",
        "nah": "nahum",
        "na": "nahum",
        "hab": "habakkuk",
        "hb": "habakkuk",
        "zeph": "zephaniah",
        "zep": "zephaniah",
        "hag": "haggai",
        "hg": "haggai",
        "zech": "zechariah",
        "zec": "zechariah",
        "mal": "malachi",
        "ml": "malachi",
        "matt": "matthew",
        "mt": "matthew",
        "mk": "mark",
        "mrk": "mark",
        "mar": "mark",
        "lk": "luke",
        "luk": "luke",
        "jn": "john",
        "jhn": "john",
        "joh": "john",
        "ac": "acts",
        "act": "acts",
        "rom": "romans",
        "ro": "romans",
        "rm": "romans",
        "cor": "corinthians",
        "gal": "galatians",
        "ga": "galatians",
        "eph": "ephesians",
        "ep": "ephesians",
        "phil": "philippians",
        "php": "philippians",
        "pp": "philippians",
        "col": "colossians",
        "thess": "thessalonians",
        "thes": "thessalonians",
        "th": "thessalonians",
        "tim": "timothy",
        "tit": "titus",
        "philem": "philemon",
        "phlm": "philemon",
        "phm": "philemon",
        "pm": "philemon",
        "heb": "hebrews",
        "he": "hebrews",
        "jas": "james",
        "jam": "james",
        "jm": "james",
        "pet": "peter",
        "pe": "peter",
        "rev": "revelation",
        "re": "revelation",
        "rv": "revelation",
        "apoc": "revelation"
    ]
    private static let scriptureReferenceRegex: NSRegularExpression = {
        let pattern = "(?<!\\w)((?:[1-3][\\s\\p{Cf}]+)?(?:\(scriptureBookPattern)))[\\s\\p{Cf}]+(\\d+)(?:[\\p{Cf}]*:[\\s\\p{Cf}]*(\\d+(?:[\\s\\p{Cf}]*[-–][\\s\\p{Cf}]*\\d+)?(?:[\\s\\p{Cf}]*[,;][\\s\\p{Cf}]*\\d+(?:[\\s\\p{Cf}]*[-–][\\s\\p{Cf}]*\\d+)?)*)\\s*)?"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()
    private static let strongsReferenceRegex = try! NSRegularExpression(
        pattern: #"(?<!\w)([GHgh][\p{Cf}]*(?:\d[\p{Cf}]*){1,5}[A-Za-z]?)(?!\w)"#,
        options: []
    )
    private var editorBaseFont: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private var pendingCaretTypingFont: NSFont?
    private var lastSelectedRange: NSRange = NSRange(location: 0, length: 0)
    private var lastNonEmptySelectedRange: NSRange = NSRange(location: NSNotFound, length: 0)
    private var pendingToolbarSelectionSnapshot: NSRange?

    weak var textView: NSTextView? {
        didSet {
            // Register with router when text view is assigned
            if textView != nil {
                let isNewTextView = oldValue !== textView
                if isNewTextView {
                    editorBaseFont = textView?.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                }
                lastSelectedRange = textView?.selectedRange() ?? NSRange(location: 0, length: 0)
                if let range = textView?.selectedRange(), range.length > 0 {
                    lastNonEmptySelectedRange = range
                }
                NoteCommandRouter.shared.activeController = self
                DispatchQueue.main.async { [weak self] in
                    self?.syncFormattingState()
                }
            }
        }
    }

    func bold() {
        performFormattingAction {
            self.applyInlineStyle(.bold, prefix: "**", suffix: "**")
        }
    }

    func italic() {
        performFormattingAction {
            self.applyInlineStyle(.italic, prefix: "*", suffix: "*")
        }
    }

    func underline() {
        performFormattingAction {
            self.toggleTextAttribute(.underlineStyle, activeValue: NSUnderlineStyle.single.rawValue)
        }
    }

    func highlight() {
        performFormattingAction {
            self.toggleTextAttribute(.backgroundColor, activeValue: Self.noteHighlightColor)
        }
    }

    func heading() {
        performFormattingAction {
            self.applyBlockKind(.heading(level: 1), markdownPrefix: "# ")
        }
    }

    func bullet() {
        performFormattingAction {
            if !self.applyCaretBulletInsertionIfNeeded() {
                self.applyBlockKind(.bulletItem(depth: 0), markdownPrefix: "- ")
            }
        }
    }

    func numberedList() {
        performFormattingAction {
            if !self.applyCaretNumberedInsertionIfNeeded() {
                self.applyBlockKind(.numberedItem(depth: 0, ordinal: 1), markdownPrefix: "1. ")
            }
        }
    }

    func changeFontSize(by delta: CGFloat) {
        guard let tv = textView,
              let current = tv.font else { return }
        let newSize = max(8, current.pointSize + delta)
        tv.font = NSFont(name: current.fontName, size: newSize)
               ?? NSFont.systemFont(ofSize: newSize)
        // Persist via AppStorage key — post notification for SettingsView to pick up
        UserDefaults.standard.set(Double(newSize), forKey: "fontSize")
    }

    func captureToolbarSelectionSnapshot() {
        guard let textView else { return }
        let selection = textView.selectedRange()
        guard selection.location != NSNotFound else { return }
        pendingToolbarSelectionSnapshot = selection
    }

    private func applyInlineStyle(
        _ trait: NSFontDescriptor.SymbolicTraits,
        prefix: String,
        suffix: String
    ) {
        guard let tv = textView else { return }
        if tv.isRichText {
            toggleInlineTrait(trait, in: tv)
        } else {
            wrapSelection(prefix, suffix)
        }
        syncFormattingState()
    }

    @discardableResult
    private func applyCaretBulletInsertionIfNeeded() -> Bool {
        guard let textView, textView.isRichText else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }

        let nsString = textView.string as NSString
        let paragraphRange = paragraphRangeForCaret(in: nsString, selectionLocation: selection.location)
        let currentKind = currentBlockKind(in: textView, paragraphRange: paragraphRange)
        guard case .paragraph = currentKind else { return false }

        let contentRange = richContentRange(for: paragraphRange, in: nsString, currentKind: currentKind)
        let paragraphStyle = paragraphStyle(for: .bulletItem(depth: 0))
        let blockFont = blockFont(for: .bulletItem(depth: 0), baseFont: editorBaseFont)
        let prefix = NSAttributedString(string: "• ", attributes: [
            .font: blockFont,
            .paragraphStyle: paragraphStyle,
            .richNoteBlockKind: blockKindToken(for: .bulletItem(depth: 0))
        ])

        guard let storage = textView.textStorage else { return false }
        storage.beginEditing()
        storage.insert(prefix, at: contentRange.location)
        let updatedParagraphRange = NSRange(location: paragraphRange.location, length: min(paragraphRange.length + prefix.length, (storage.string as NSString).length - paragraphRange.location))
        let updatedContentRange = richContentRange(for: updatedParagraphRange, in: storage.string as NSString, currentKind: .bulletItem(depth: 0))
        if updatedContentRange.length > 0 {
            storage.addAttributes([
                .paragraphStyle: paragraphStyle,
                .richNoteBlockKind: blockKindToken(for: .bulletItem(depth: 0))
            ], range: updatedContentRange)
        }
        storage.endEditing()

        let caretOffset = max(0, selection.location - contentRange.location)
        let caretLocation = min(updatedContentRange.location + caretOffset, NSMaxRange(updatedContentRange))
        let caretRange = NSRange(location: caretLocation, length: 0)
        textView.setSelectedRange(caretRange)
        textView.typingAttributes[.font] = blockFont
        pendingCaretTypingFont = blockFont
        updateSelectedRange(caretRange)
        refreshLayout(in: textView)
        textView.didChangeText()
        syncFormattingState()
        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self, let textView, self.textView === textView else { return }
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(caretRange)
            self.updateSelectedRange(caretRange)
            self.syncFormattingState()
        }
        return true
    }

    @discardableResult
    private func applyCaretNumberedInsertionIfNeeded() -> Bool {
        guard let textView, textView.isRichText else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }

        let nsString = textView.string as NSString
        let paragraphRange = paragraphRangeForCaret(in: nsString, selectionLocation: selection.location)
        let currentKind = currentBlockKind(in: textView, paragraphRange: paragraphRange)
        guard case .paragraph = currentKind else { return false }

        let contentRange = richContentRange(for: paragraphRange, in: nsString, currentKind: currentKind)
        let paragraphStyle = paragraphStyle(for: .numberedItem(depth: 0, ordinal: 1))
        let blockFont = blockFont(for: .numberedItem(depth: 0, ordinal: 1), baseFont: editorBaseFont)
        let prefix = NSAttributedString(string: "1. ", attributes: [
            .font: blockFont,
            .paragraphStyle: paragraphStyle,
            .richNoteBlockKind: blockKindToken(for: .numberedItem(depth: 0, ordinal: 1))
        ])

        guard let storage = textView.textStorage else { return false }
        storage.beginEditing()
        storage.insert(prefix, at: contentRange.location)
        let updatedParagraphRange = NSRange(location: paragraphRange.location, length: min(paragraphRange.length + prefix.length, (storage.string as NSString).length - paragraphRange.location))
        let updatedContentRange = richContentRange(for: updatedParagraphRange, in: storage.string as NSString, currentKind: .numberedItem(depth: 0, ordinal: 1))
        if updatedContentRange.length > 0 {
            storage.addAttributes([
                .paragraphStyle: paragraphStyle,
                .richNoteBlockKind: blockKindToken(for: .numberedItem(depth: 0, ordinal: 1))
            ], range: updatedContentRange)
        }
        storage.endEditing()

        let caretOffset = max(0, selection.location - contentRange.location)
        let caretLocation = min(updatedContentRange.location + caretOffset, NSMaxRange(updatedContentRange))
        let caretRange = NSRange(location: caretLocation, length: 0)
        textView.setSelectedRange(caretRange)
        textView.typingAttributes[.font] = blockFont
        pendingCaretTypingFont = blockFont
        updateSelectedRange(caretRange)
        refreshLayout(in: textView)
        textView.didChangeText()
        syncFormattingState()
        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self, let textView, self.textView === textView else { return }
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(caretRange)
            self.updateSelectedRange(caretRange)
            self.syncFormattingState()
        }
        return true
    }

    private func wrapSelection(_ prefix: String, _ suffix: String) {
        guard let tv = textView else { return }
        let nsString = tv.string as NSString
        let range = tv.selectedRange()

        if range.length == 0 {
            let insertion = prefix + suffix
            tv.insertText(insertion, replacementRange: range)
            tv.setSelectedRange(NSRange(location: range.location + prefix.count, length: 0))
            return
        }

        let selected = nsString.substring(with: range)
        if selected.hasPrefix(prefix), selected.hasSuffix(suffix), selected.count >= prefix.count + suffix.count {
            let start = selected.index(selected.startIndex, offsetBy: prefix.count)
            let end = selected.index(selected.endIndex, offsetBy: -suffix.count)
            let unwrapped = String(selected[start..<end])
            tv.insertText(unwrapped, replacementRange: range)
            tv.setSelectedRange(NSRange(location: range.location, length: (unwrapped as NSString).length))
            return
        }

        let beforeRange = NSRange(location: max(0, range.location - prefix.count), length: prefix.count)
        let afterRange = NSRange(location: range.location + range.length, length: suffix.count)
        let hasWrappedMarkers =
            beforeRange.location + beforeRange.length <= nsString.length &&
            afterRange.location + afterRange.length <= nsString.length &&
            nsString.substring(with: beforeRange) == prefix &&
            nsString.substring(with: afterRange) == suffix

        if hasWrappedMarkers {
            let fullRange = NSRange(location: beforeRange.location, length: prefix.count + range.length + suffix.count)
            tv.insertText(selected, replacementRange: fullRange)
            tv.setSelectedRange(NSRange(location: beforeRange.location, length: range.length))
            return
        }

        let wrapped = prefix + selected + suffix
        tv.insertText(wrapped, replacementRange: range)
        tv.setSelectedRange(NSRange(location: range.location, length: (wrapped as NSString).length))
    }

    private func toggleInlineTrait(_ trait: NSFontDescriptor.SymbolicTraits, in textView: NSTextView) {
        let selection = textView.selectedRange()
        let baseFont = (textView.typingAttributes[.font] as? NSFont) ?? textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)

        if selection.length == 0 {
            let currentFont = (textView.typingAttributes[.font] as? NSFont) ?? baseFont
            let nsString = textView.string as NSString
            let paragraphRange = paragraphRangeForCaret(in: nsString, selectionLocation: selection.location)
            let blockKind = currentBlockKind(in: textView, paragraphRange: paragraphRange)
            let blockBaseFont = blockFont(for: blockKind, baseFont: editorBaseFont)
            let shouldEnable = !inlineTrait(trait, isPresentIn: currentFont, blockBaseFont: blockBaseFont)
            let updatedFont = font(byTogglingInline: trait, on: currentFont, blockBaseFont: blockBaseFont, enabling: shouldEnable)
            textView.typingAttributes[.font] = updatedFont
            pendingCaretTypingFont = updatedFont
            return
        }

        let effectiveSelection = richContentSelectionRange(in: textView, selection: selection)
        guard effectiveSelection.length > 0 else { return }
        guard let storage = textView.textStorage else { return }
        let shouldEnable = !selectionHasInlineTrait(trait, in: textView, range: effectiveSelection, baseFont: baseFont)

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: effectiveSelection, options: []) { value, range, _ in
            let currentFont = (value as? NSFont) ?? baseFont
            let paragraphRange = (textView.string as NSString).paragraphRange(for: NSRange(location: range.location, length: 0))
            let blockKind = currentBlockKind(in: textView, paragraphRange: paragraphRange)
            let blockBaseFont = blockFont(for: blockKind, baseFont: baseFont)
            let updatedFont = font(byTogglingInline: trait, on: currentFont, blockBaseFont: blockBaseFont, enabling: shouldEnable)
            storage.addAttribute(.font, value: updatedFont, range: range)
        }
        storage.endEditing()
        textView.didChangeText()
        syncFormattingState()
    }

    private func toggleTextAttribute(_ key: NSAttributedString.Key, activeValue: Any) {
        guard let textView else { return }
        let selection = textView.selectedRange()

        if selection.length == 0 {
            var typingAttributes = textView.typingAttributes
            let shouldEnable = !attributeValue(typingAttributes[key], matches: activeValue, for: key)
            if shouldEnable {
                typingAttributes[key] = activeValue
            } else {
                typingAttributes.removeValue(forKey: key)
            }
            textView.typingAttributes = typingAttributes
            syncFormattingState()
            return
        }

        let effectiveSelection = richContentSelectionRange(in: textView, selection: selection)
        guard effectiveSelection.length > 0, let storage = textView.textStorage else { return }
        let shouldEnable = !selectionHasAttribute(key, matching: activeValue, in: textView, range: effectiveSelection)

        storage.beginEditing()
        if shouldEnable {
            storage.addAttribute(key, value: activeValue, range: effectiveSelection)
        } else {
            storage.removeAttribute(key, range: effectiveSelection)
        }
        storage.endEditing()
        refreshLayout(in: textView)
        textView.didChangeText()
        syncFormattingState()
    }

    private func richContentSelectionRange(in textView: NSTextView, selection: NSRange) -> NSRange {
        guard selection.length > 0 else { return selection }
        let nsString = textView.string as NSString
        let paragraphRange = nsString.paragraphRange(for: NSRange(location: selection.location, length: 0))
        let kind = currentBlockKind(in: textView, paragraphRange: paragraphRange)
        switch kind {
        case .bulletItem, .numberedItem:
            break
        default:
            return selection
        }

        let contentRange = richContentRange(for: paragraphRange, in: nsString, currentKind: kind)
        let intersection = NSIntersectionRange(selection, contentRange)
        return intersection.length > 0 ? intersection : selection
    }

    private func selectionHasTrait(
        _ trait: NSFontDescriptor.SymbolicTraits,
        in textView: NSTextView,
        range: NSRange
    ) -> Bool {
        guard let storage = textView.textStorage else { return false }

        var sawFont = false
        var allHaveTrait = true
        storage.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
            let font = (value as? NSFont) ?? textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            sawFont = true
            if !font.fontDescriptor.symbolicTraits.contains(trait) {
                allHaveTrait = false
                stop.pointee = true
            }
        }
        return sawFont && allHaveTrait
    }

    private func font(
        byTogglingInline trait: NSFontDescriptor.SymbolicTraits,
        on font: NSFont,
        blockBaseFont: NSFont,
        enabling: Bool
    ) -> NSFont {
        var traits = blockBaseFont.fontDescriptor.symbolicTraits
        let currentTraits = font.fontDescriptor.symbolicTraits

        if currentTraits.contains(.italic), trait != .italic {
            traits.insert(.italic)
        }
        if currentTraits.contains(.bold), !blockBaseFont.fontDescriptor.symbolicTraits.contains(.bold), trait != .bold {
            traits.insert(.bold)
        }

        if enabling {
            traits.insert(trait)
        } else {
            traits.remove(trait)
        }

        let descriptor = blockBaseFont.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: blockBaseFont.pointSize) ?? blockBaseFont
    }

    private func selectionHasInlineTrait(
        _ trait: NSFontDescriptor.SymbolicTraits,
        in textView: NSTextView,
        range: NSRange,
        baseFont: NSFont
    ) -> Bool {
        guard let storage = textView.textStorage else { return false }

        var sawFont = false
        var allHaveTrait = true
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, stop in
            let currentFont = (value as? NSFont) ?? baseFont
            let paragraphRange = (textView.string as NSString).paragraphRange(for: NSRange(location: subrange.location, length: 0))
            let blockKind = currentBlockKind(in: textView, paragraphRange: paragraphRange)
            let blockBaseFont = blockFont(for: blockKind, baseFont: baseFont)
            sawFont = true
            if !inlineTrait(trait, isPresentIn: currentFont, blockBaseFont: blockBaseFont) {
                allHaveTrait = false
                stop.pointee = true
            }
        }
        return sawFont && allHaveTrait
    }

    private func selectionHasAttribute(
        _ key: NSAttributedString.Key,
        matching activeValue: Any,
        in textView: NSTextView,
        range: NSRange
    ) -> Bool {
        guard let storage = textView.textStorage else { return false }

        var sawValue = false
        var allMatch = true
        storage.enumerateAttribute(key, in: range, options: []) { value, _, stop in
            sawValue = true
            if !attributeValue(value, matches: activeValue, for: key) {
                allMatch = false
                stop.pointee = true
            }
        }
        return sawValue && allMatch
    }

    private func attributeValue(
        _ value: Any?,
        matches activeValue: Any,
        for key: NSAttributedString.Key
    ) -> Bool {
        switch key {
        case .underlineStyle:
            guard let number = value as? NSNumber else { return false }
            return number.intValue != 0
        case .backgroundColor:
            return value != nil
        default:
            return false
        }
    }

    private func inlineTrait(
        _ trait: NSFontDescriptor.SymbolicTraits,
        isPresentIn font: NSFont,
        blockBaseFont: NSFont
    ) -> Bool {
        let currentTraits = font.fontDescriptor.symbolicTraits
        let blockTraits = blockBaseFont.fontDescriptor.symbolicTraits
        return currentTraits.contains(trait) && !blockTraits.contains(trait)
    }

    private func applyBlockKind(_ kind: RichNoteBlockKind, markdownPrefix: String) {
        guard let tv = textView else { return }
        if tv.isRichText {
            toggleRichBlockKind(kind, in: tv)
        } else {
            insertAtLineStart(markdownPrefix)
        }
    }

    private func toggleRichBlockKind(_ targetKind: RichNoteBlockKind, in textView: NSTextView) {
        let nsString = textView.string as NSString
        let selection = textView.selectedRange()
        let targetParagraphRanges: [NSRange]
        if selection.length == 0 {
            targetParagraphRanges = [paragraphRangeForCaret(in: nsString, selectionLocation: selection.location)]
        } else {
            let lineRange = nsString.lineRange(for: selection)
            targetParagraphRanges = paragraphRanges(in: nsString, within: lineRange)
        }
        let shouldRemove = targetParagraphRanges.allSatisfy { currentBlockKind(in: textView, paragraphRange: $0) == targetKind }
        let destinationKind: RichNoteBlockKind = shouldRemove ? .paragraph : targetKind
        let baseFont = editorBaseFont
        let caretAnchor: NSRange?
        let caretWasAtParagraphEnd: Bool
        if selection.length == 0,
           let paragraphRange = targetParagraphRanges.first {
            let currentKind = currentBlockKind(in: textView, paragraphRange: paragraphRange)
            let originalContentRange = richContentRange(for: paragraphRange, in: nsString, currentKind: currentKind)
            let contentOffset = max(0, selection.location - originalContentRange.location)
            caretAnchor = NSRange(location: paragraphRange.location, length: contentOffset)
            caretWasAtParagraphEnd = selection.location >= NSMaxRange(originalContentRange)
        } else {
            caretAnchor = nil
            caretWasAtParagraphEnd = false
        }

        for paragraphRange in targetParagraphRanges.reversed() {
            replaceParagraph(in: textView, range: paragraphRange, targetKind: destinationKind, baseFont: baseFont)
        }
        let typingFont = blockFont(for: destinationKind, baseFont: baseFont)
        textView.typingAttributes[.font] = typingFont
        pendingCaretTypingFont = typingFont
        let updatedNSString = textView.string as NSString
        let caretLocation: Int
        if let caretAnchor {
            let updatedParagraphRange = updatedNSString.paragraphRange(for: NSRange(location: min(caretAnchor.location, updatedNSString.length), length: 0))
            let updatedContentRange = richContentRange(for: updatedParagraphRange, in: updatedNSString, currentKind: destinationKind)
            if caretWasAtParagraphEnd {
                caretLocation = NSMaxRange(updatedContentRange)
            } else {
                caretLocation = min(updatedContentRange.location + caretAnchor.length, updatedContentRange.location + updatedContentRange.length)
            }
        } else if selection.length == 0 {
            caretLocation = min(selection.location, updatedNSString.length)
        } else {
            let updatedLineRange = updatedNSString.lineRange(for: NSRange(location: min(selection.location, updatedNSString.length), length: 0))
            var lineEnd = NSMaxRange(updatedLineRange)
            if lineEnd > updatedLineRange.location,
               lineEnd <= updatedNSString.length,
               updatedNSString.substring(with: NSRange(location: lineEnd - 1, length: 1)) == "\n" {
                lineEnd -= 1
            }
            caretLocation = lineEnd
        }
        let caretRange = NSRange(location: caretLocation, length: 0)
        textView.setSelectedRange(caretRange)
        lastNonEmptySelectedRange = NSRange(location: NSNotFound, length: 0)
        updateSelectedRange(textView.selectedRange())
        syncTypingAttributesToCaret()
        refreshLayout(in: textView)
        textView.didChangeText()
        syncFormattingState()
        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self, let textView, self.textView === textView else { return }
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(caretRange)
            self.updateSelectedRange(caretRange)
            self.syncTypingAttributesToCaret()
            self.refreshLayout(in: textView)
            self.syncFormattingState()
        }
    }

    private func replaceParagraph(
        in textView: NSTextView,
        range paragraphRange: NSRange,
        targetKind: RichNoteBlockKind,
        baseFont: NSFont
    ) {
        guard let storage = textView.textStorage else { return }

        let paragraphText = (storage.string as NSString).substring(with: paragraphRange)
        let hasTrailingNewline = paragraphText.hasSuffix("\n")
        let currentKind = currentBlockKind(in: textView, paragraphRange: paragraphRange)
        let contentRange = richContentRange(for: paragraphRange, in: storage.string as NSString, currentKind: currentKind)
        let content = storage.attributedSubstring(from: contentRange).mutableCopy() as! NSMutableAttributedString

        normalizeFonts(in: content, from: currentKind, to: targetKind, baseFont: baseFont)

        let replacement = NSMutableAttributedString()
        let paragraphStyle = paragraphStyle(for: targetKind)
        let blockFont = blockFont(for: targetKind, baseFont: baseFont)
        let blockToken = blockKindToken(for: targetKind)
        let prefix = displayedPrefix(for: targetKind)

        if !prefix.isEmpty {
            replacement.append(NSAttributedString(string: prefix, attributes: [
                .font: blockFont,
                .paragraphStyle: paragraphStyle,
                .richNoteBlockKind: blockToken
            ]))
        }

        if content.length == 0 {
            replacement.append(NSAttributedString(string: "", attributes: [
                .font: blockFont,
                .paragraphStyle: paragraphStyle,
                .richNoteBlockKind: blockToken
            ]))
        } else {
            content.addAttributes([
                .paragraphStyle: paragraphStyle,
                .richNoteBlockKind: blockToken
            ], range: NSRange(location: 0, length: content.length))
            replacement.append(content)
        }

        if hasTrailingNewline {
            replacement.append(NSAttributedString(string: "\n", attributes: [
                .font: blockFont,
                .paragraphStyle: paragraphStyle,
                .richNoteBlockKind: blockToken
            ]))
        }

        storage.beginEditing()
        storage.replaceCharacters(in: paragraphRange, with: replacement)
        storage.endEditing()
    }

    private func normalizeFonts(
        in content: NSMutableAttributedString,
        from currentKind: RichNoteBlockKind,
        to targetKind: RichNoteBlockKind,
        baseFont: NSFont
    ) {
        let sourceBase = blockFont(for: currentKind, baseFont: baseFont)
        let targetBase = blockFont(for: targetKind, baseFont: baseFont)

        content.enumerateAttribute(.font, in: NSRange(location: 0, length: content.length), options: []) { value, range, _ in
            let currentFont = (value as? NSFont) ?? sourceBase
            let currentTraits = currentFont.fontDescriptor.symbolicTraits
            let sourceTraits = sourceBase.fontDescriptor.symbolicTraits

            var targetTraits = targetBase.fontDescriptor.symbolicTraits
            if currentTraits.contains(.italic) {
                targetTraits.insert(.italic)
            }
            if currentTraits.contains(.bold) && !sourceTraits.contains(.bold) {
                targetTraits.insert(.bold)
            }

            let descriptor = targetBase.fontDescriptor.withSymbolicTraits(targetTraits)
            let updatedFont = NSFont(descriptor: descriptor, size: targetBase.pointSize) ?? targetBase
            content.addAttribute(.font, value: updatedFont, range: range)
        }
    }

    private func paragraphRanges(in text: NSString, within lineRange: NSRange) -> [NSRange] {
        var result: [NSRange] = []
        var location = lineRange.location
        let end = NSMaxRange(lineRange)

        while location < end {
            let paragraphRange = text.paragraphRange(for: NSRange(location: location, length: 0))
            result.append(paragraphRange)
            location = NSMaxRange(paragraphRange)
        }
        return result
    }

    private func paragraphRangeForCaret(in text: NSString, selectionLocation: Int) -> NSRange {
        let clampedLocation = min(selectionLocation, text.length)
        if clampedLocation == text.length,
           clampedLocation > 0,
           text.substring(with: NSRange(location: clampedLocation - 1, length: 1)) == "\n" {
            return NSRange(location: clampedLocation, length: 0)
        }

        let probeLocation = max(0, min(clampedLocation, max(0, text.length - 1)))
        return text.paragraphRange(for: NSRange(location: probeLocation, length: 0))
    }

    private func currentBlockKind(in textView: NSTextView, paragraphRange: NSRange) -> RichNoteBlockKind {
        let paragraphText = ((textView.string as NSString).substring(with: paragraphRange)).trimmingCharacters(in: .newlines)
        let trimmedParagraph = paragraphText.trimmingCharacters(in: .whitespaces)

        if paragraphRange.length > 0,
           let token = textView.textStorage?.attribute(.richNoteBlockKind, at: paragraphRange.location, effectiveRange: nil) as? String,
           let kind = blockKind(from: token) {
            switch kind {
            case .bulletItem:
                if trimmedParagraph.hasPrefix("• ") || trimmedParagraph == "•" {
                    return kind
                }
            case .numberedItem(let depth, let ordinal):
                let expectedPrefix = "\(ordinal ?? 1) "
                let dottedPrefix = "\(ordinal ?? 1). "
                if trimmedParagraph.hasPrefix(expectedPrefix) ||
                    trimmedParagraph.hasPrefix(dottedPrefix) ||
                    trimmedParagraph == "\(ordinal ?? 1)" {
                    return .numberedItem(depth: depth, ordinal: ordinal ?? 1)
                }
            case .heading(let level):
                let markdownPrefix = String(repeating: "#", count: level) + " "
                if paragraphText.hasPrefix(markdownPrefix) {
                    return kind
                }
            default:
                return kind
            }
        }

        if paragraphText.hasPrefix("• ") {
            return .bulletItem(depth: 0)
        }
        if let markdownKind = markdownBlockKind(in: paragraphText) {
            return markdownKind
        }
        if let ordinal = numberedListOrdinal(in: paragraphText) {
            return .numberedItem(depth: 0, ordinal: ordinal)
        }
        return .paragraph
    }

    private func isEmptyCaretParagraph(in text: NSString, selection: NSRange) -> Bool {
        guard selection.length == 0 else { return false }
        let paragraphRange = paragraphRangeForCaret(in: text, selectionLocation: selection.location)
        let paragraphText = text.substring(with: paragraphRange).trimmingCharacters(in: .newlines)
        return paragraphText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func richContentRange(for paragraphRange: NSRange, in text: NSString, currentKind: RichNoteBlockKind) -> NSRange {
        let paragraphText = text.substring(with: paragraphRange)
        let effectiveLength = paragraphText.hasSuffix("\n") ? paragraphRange.length - 1 : paragraphRange.length
        let prefixLength: Int

        switch currentKind {
        case .bulletItem:
            let leadingSpaces = paragraphText.prefix { $0 == " " || $0 == "\t" }.count
            let trimmed = paragraphText.dropFirst(leadingSpaces)
            let markerLength = (trimmed.hasPrefix("• ") || trimmed.hasPrefix("- ")) ? 2 : 0
            prefixLength = min(effectiveLength, leadingSpaces + markerLength)
        case .numberedItem(_, let ordinal):
            let leadingSpaces = paragraphText.prefix { $0 == " " || $0 == "\t" }.count
            let trimmed = paragraphText.dropFirst(leadingSpaces)
            let dottedPrefix = "\(ordinal ?? 1). "
            let visiblePrefix = "\(ordinal ?? 1) "
            if trimmed.hasPrefix(dottedPrefix) {
                prefixLength = min(effectiveLength, leadingSpaces + dottedPrefix.count)
            } else {
                prefixLength = trimmed.hasPrefix(visiblePrefix)
                    ? min(effectiveLength, leadingSpaces + visiblePrefix.count)
                    : 0
            }
        case .heading(let level):
            let markdownPrefix = String(repeating: "#", count: level) + " "
            prefixLength = paragraphText.hasPrefix(markdownPrefix) ? min(markdownPrefix.count, effectiveLength) : 0
        default:
            prefixLength = 0
        }

        return NSRange(location: paragraphRange.location + prefixLength, length: max(0, effectiveLength - prefixLength))
    }

    private func paragraphStyle(for kind: RichNoteBlockKind) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        switch kind {
        case .bulletItem(let depth):
            style.firstLineHeadIndent = CGFloat(depth * 18)
            style.headIndent = CGFloat(18 + (depth * 18))
        case .numberedItem(let depth, _):
            style.firstLineHeadIndent = CGFloat(depth * 18)
            style.headIndent = CGFloat(22 + (depth * 18))
        default:
            break
        }
        return style
    }

    private func blockFont(for kind: RichNoteBlockKind, baseFont: NSFont) -> NSFont {
        switch kind {
        case .heading(let level):
            let sizeBoost = max(2, 8 - level)
            return NSFont.boldSystemFont(ofSize: baseFont.pointSize + CGFloat(sizeBoost))
        default:
            return baseFont
        }
    }

    private func displayedPrefix(for kind: RichNoteBlockKind) -> String {
        switch kind {
        case .bulletItem(let depth):
            return String(repeating: "  ", count: max(0, depth)) + "• "
        case .numberedItem(_, let ordinal):
            return ordinal.map { "\($0). " } ?? ""
        default:
            return ""
        }
    }

    private func blockKindToken(for kind: RichNoteBlockKind) -> String {
        kind.token
    }

    private func blockKind(from token: String) -> RichNoteBlockKind? {
        RichNoteBlockKind(token: token)
    }

    @discardableResult
    func applyLiveMarkdownTransformsIfNeeded() -> Bool {
        guard let textView, textView.isRichText else { return false }

        let originalSelection = textView.selectedRange()
        guard originalSelection.location != NSNotFound else { return false }

        let nsString = textView.string as NSString
        let paragraphRange = paragraphRangeForCaret(in: nsString, selectionLocation: originalSelection.location)
        let paragraphText = nsString.substring(with: paragraphRange)
        let transformedBlock = applyMarkdownBlockTransformIfNeeded(
            in: textView,
            paragraphRange: paragraphRange,
            paragraphText: paragraphText,
            originalSelection: originalSelection
        )

        let updatedNSString = textView.string as NSString
        let updatedParagraphRange = paragraphRangeForCaret(
            in: updatedNSString,
            selectionLocation: min(textView.selectedRange().location, updatedNSString.length)
        )
        let transformedInline = applyMarkdownInlineTransformsIfNeeded(
            in: textView,
            paragraphRange: updatedParagraphRange,
            originalSelection: textView.selectedRange()
        )

        if transformedBlock || transformedInline {
            updateSelectedRange(textView.selectedRange())
            syncTypingAttributesToCaret(preserveInlineTraits: true)
            refreshLayout(in: textView)
            syncFormattingState()
        }

        return transformedBlock || transformedInline
    }

    @discardableResult
    func applyAutoDetectedLinksIfNeeded() -> Bool {
        guard let textView, textView.isRichText, let storage = textView.textStorage else { return false }
        var changed = false
        storage.beginEditing()
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.link, in: fullRange, options: []) { value, range, _ in
            guard let url = self.linkURL(from: value), self.isAutoDetectedLink(url) else { return }
            storage.removeAttribute(.link, range: range)
            changed = true
        }

        let nsString = storage.string as NSString
        var location = 0
        while location < nsString.length {
            let paragraphRange = nsString.paragraphRange(for: NSRange(location: location, length: 0))
            let kind = currentBlockKind(in: textView, paragraphRange: paragraphRange)
            let contentRange = richContentRange(for: paragraphRange, in: nsString, currentKind: kind)
            if contentRange.length > 0 {
                let paragraphText = nsString.substring(with: contentRange)
                let links = autoDetectedLinks(in: paragraphText)
                for link in links {
                    let targetRange = NSRange(location: contentRange.location + link.range.location, length: link.range.length)
                    guard NSMaxRange(targetRange) <= NSMaxRange(contentRange) else { continue }
                    let newValue = self.targetValue(for: link.target)
                    storage.addAttributes([
                        .link: newValue,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .foregroundColor: NSColor.linkColor
                    ], range: targetRange)
                    changed = true
                }
            }
            location = NSMaxRange(paragraphRange)
        }
        storage.endEditing()

        return changed
    }

    @discardableResult
    private func applyMarkdownBlockTransformIfNeeded(
        in textView: NSTextView,
        paragraphRange: NSRange,
        paragraphText: String,
        originalSelection: NSRange
    ) -> Bool {
        guard let kind = markdownBlockKind(in: paragraphText) else { return false }
        guard paragraphUsesMarkdownSyntax(paragraphText, for: kind) else { return false }

        replaceParagraph(in: textView, range: paragraphRange, targetKind: kind, baseFont: editorBaseFont)

        let updatedNSString = textView.string as NSString
        let updatedParagraphRange = updatedNSString.paragraphRange(
            for: NSRange(location: min(paragraphRange.location, updatedNSString.length), length: 0)
        )
        let contentRange = richContentRange(for: updatedParagraphRange, in: updatedNSString, currentKind: kind)
        let rawPrefixLength = markdownPrefixLength(in: paragraphText, for: kind)
        let contentOffset = max(0, originalSelection.location - paragraphRange.location - rawPrefixLength)
        let caretLocation = min(contentRange.location + contentOffset, NSMaxRange(contentRange))
        textView.setSelectedRange(NSRange(location: caretLocation, length: originalSelection.length))
        pendingCaretTypingFont = blockFont(for: kind, baseFont: editorBaseFont)
        return true
    }

    @discardableResult
    private func applyMarkdownInlineTransformsIfNeeded(
        in textView: NSTextView,
        paragraphRange: NSRange,
        originalSelection: NSRange
    ) -> Bool {
        guard let storage = textView.textStorage, paragraphRange.length > 0 else { return false }

        let kind = currentBlockKind(in: textView, paragraphRange: paragraphRange)
        let paragraphString = (storage.string as NSString).substring(with: paragraphRange)
        let workingRange = NSRange(location: 0, length: (paragraphString as NSString).length)
        let paragraphNSString = paragraphString as NSString

        let boldRegex = try? NSRegularExpression(pattern: "\\*\\*([^*\\n][^\\n]*?)\\*\\*")
        let italicRegex = try? NSRegularExpression(pattern: "(?<!\\*)\\*([^*\\n]+?)\\*(?!\\*)")
        let matches = [
            boldRegex?.matches(in: paragraphString, options: [], range: workingRange) ?? [],
            italicRegex?.matches(in: paragraphString, options: [], range: workingRange) ?? []
        ]
        .flatMap { $0 }
        .sorted { $0.range.location > $1.range.location }

        guard !matches.isEmpty else { return false }

        let blockBaseFont = blockFont(for: kind, baseFont: editorBaseFont)
        let paragraphStyle = paragraphStyle(for: kind)
        let blockToken = blockKindToken(for: kind)
        var updatedSelection = originalSelection

        storage.beginEditing()
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let paragraphMatchRange = match.range
            let contentRange = match.range(at: 1)
            let globalMatchRange = NSRange(
                location: paragraphRange.location + paragraphMatchRange.location,
                length: paragraphMatchRange.length
            )
            guard globalMatchRange.location + globalMatchRange.length <= storage.length else { continue }

            let content = paragraphNSString.substring(with: contentRange)
            let styledFont: NSFont
            if paragraphMatchRange.length >= 4,
               paragraphNSString.substring(with: NSRange(location: paragraphMatchRange.location, length: 2)) == "**" {
                styledFont = self.font(byTogglingInline: .bold, on: blockBaseFont, blockBaseFont: blockBaseFont, enabling: true)
            } else {
                styledFont = self.font(byTogglingInline: .italic, on: blockBaseFont, blockBaseFont: blockBaseFont, enabling: true)
            }

            let replacement = NSAttributedString(string: content, attributes: [
                .font: styledFont,
                .paragraphStyle: paragraphStyle,
                .richNoteBlockKind: blockToken
            ])
            storage.replaceCharacters(in: globalMatchRange, with: replacement)

            let removedCount = globalMatchRange.length - replacement.length
            if updatedSelection.location > NSMaxRange(globalMatchRange) {
                updatedSelection.location -= removedCount
            } else if NSLocationInRange(updatedSelection.location, globalMatchRange) {
                let offset = max(0, updatedSelection.location - globalMatchRange.location - 2)
                updatedSelection.location = min(globalMatchRange.location + offset, globalMatchRange.location + replacement.length)
            }
        }
        storage.endEditing()

        textView.setSelectedRange(updatedSelection)
        pendingCaretTypingFont = textView.typingAttributes[.font] as? NSFont
        return true
    }

    private func markdownBlockKind(in paragraphText: String) -> RichNoteBlockKind? {
        let trimmed = paragraphText.trimmingCharacters(in: .newlines)
        if trimmed.isEmpty {
            return nil
        }
        let leadingWhitespaceCount = trimmed.prefix { $0 == " " || $0 == "\t" }.count
        let content = String(trimmed.dropFirst(leadingWhitespaceCount))

        let hashes = content.prefix { $0 == "#" }
        if hashes.count > 0, hashes.count <= 6 {
            let remainder = content.dropFirst(hashes.count)
            if remainder.hasPrefix(" ") {
                return .heading(level: hashes.count)
            }
        }
        if content.hasPrefix("- ") {
            return .bulletItem(depth: max(0, leadingWhitespaceCount / 2))
        }
        if let ordinal = numberedListOrdinal(in: content) {
            return .numberedItem(depth: max(0, leadingWhitespaceCount / 2), ordinal: ordinal)
        }
        return nil
    }

    private func paragraphUsesMarkdownSyntax(_ paragraphText: String, for kind: RichNoteBlockKind) -> Bool {
        let trimmed = paragraphText.trimmingCharacters(in: .newlines)
        switch kind {
        case .heading(let level):
            return trimmed.hasPrefix(String(repeating: "#", count: level) + " ")
        case .bulletItem:
            return String(trimmed.drop { $0 == " " || $0 == "\t" }).hasPrefix("- ")
        case .numberedItem:
            let content = String(trimmed.drop { $0 == " " || $0 == "\t" })
            guard let ordinal = numberedListOrdinal(in: content) else { return false }
            return content.hasPrefix("\(ordinal). ") || content.hasPrefix("\(ordinal) ")
        case .paragraph:
            return false
        }
    }

    private func markdownPrefixLength(in paragraphText: String, for kind: RichNoteBlockKind) -> Int {
        let trimmed = paragraphText.trimmingCharacters(in: .newlines)
        let leadingWhitespaceCount = trimmed.prefix { $0 == " " || $0 == "\t" }.count
        let content = String(trimmed.dropFirst(leadingWhitespaceCount))

        switch kind {
        case .heading(let level):
            return content.hasPrefix(String(repeating: "#", count: level) + " ") ? level + 1 : 0
        case .bulletItem:
            return content.hasPrefix("- ") ? 2 : 0
        case .numberedItem:
            guard let ordinal = numberedListOrdinal(in: content) else { return 0 }
            let dottedPrefix = "\(ordinal). "
            let prefix = "\(ordinal) "
            if content.hasPrefix(dottedPrefix) {
                return dottedPrefix.count
            }
            return content.hasPrefix(prefix) ? prefix.count : 0
        case .paragraph:
            return 0
        }
    }

    private func autoDetectedLinks(in text: String) -> [(range: NSRange, target: RichNoteLinkTarget)] {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        var results: [(range: NSRange, target: RichNoteLinkTarget)] = []

        Self.scriptureReferenceRegex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let nsText = text as NSString
            let bookToken = nsText.substring(with: match.range(at: 1))
            guard let bookNumber = self.bookNumber(forScriptureBook: bookToken),
                  let chapter = Int(nsText.substring(with: match.range(at: 2))) else { return }
            let verses: [Int]
            if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound {
                verses = self.expandVerseList(nsText.substring(with: match.range(at: 3)))
            } else {
                verses = []
            }
            results.append((
                range: match.range,
                target: .scripture(
                    ScriptureLinkTarget(
                        bookNumber: bookNumber,
                        chapterNumber: chapter,
                        verseNumbers: verses
                    )
                )
            ))
        }

        Self.strongsReferenceRegex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match else { return }
            let rawNumber = (text as NSString).substring(with: match.range(at: 1))
            let number = rawNumber.unicodeScalars
                .filter { $0.properties.generalCategory != .format }
                .map(String.init)
                .joined()
                .uppercased()
            results.append((
                range: match.range(at: 1),
                target: .strongs(
                    StrongsLinkTarget(
                        number: number,
                        isOldTestament: number.hasPrefix("H") ? true : number.hasPrefix("G") ? false : nil
                    )
                )
            ))
        }

        return results.sorted { $0.range.location < $1.range.location }
    }

    private func bookNumber(forScriptureBook rawBook: String) -> Int? {
        let normalized = Self.canonicalReferenceBookName(for: rawBook)
        if let exact = myBibleBookNumbers.first(where: { Self.normalizeReferenceBook($0.value) == normalized })?.key {
            return exact
        }

        let tokenWords = normalized.split(separator: " ")
        guard !tokenWords.isEmpty else { return nil }

        let matches = myBibleBookNumbers.compactMap { entry -> Int? in
            let candidate = Self.normalizeReferenceBook(entry.value)
            let candidateWords = candidate.split(separator: " ")
            guard candidateWords.count >= tokenWords.count else { return nil }
            for (index, tokenWord) in tokenWords.enumerated() {
                if !candidateWords[index].hasPrefix(tokenWord) {
                    return nil
                }
            }
            return entry.key
        }

        return matches.count == 1 ? matches[0] : nil
    }

    private static func canonicalReferenceBookName(for book: String) -> String {
        let normalized = normalizeReferenceBook(book)
        return scriptureBookAliases[normalized] ?? normalized
    }

    private static func normalizeReferenceBook(_ book: String) -> String {
        String(
            book.unicodeScalars
                .filter { $0.properties.generalCategory != .format }
                .map(Character.init)
        )
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func expandVerseList(_ text: String) -> [Int] {
        let normalizedText = String(
            text.unicodeScalars
                .filter { $0.properties.generalCategory != .format }
                .map(Character.init)
        )

        return Array(Set(normalizedText
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .flatMap { component -> [Int] in
                let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: "-–"))
                if parts.count == 2,
                   let start = Int(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                   let end = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                   start <= end {
                    return Array(start...end)
                }
                if let verse = Int(trimmed) {
                    return [verse]
                }
                return []
            }))
        .sorted()
    }

    private func targetValue(for target: RichNoteLinkTarget) -> URL {
        RichNoteLinkCodec.url(for: target) ?? URL(string: "about:blank")!
    }

    private func linkURL(from value: Any?) -> URL? {
        RichNoteLinkCodec.url(from: value)
    }

    private func isAutoDetectedLink(_ url: URL) -> Bool {
        url.scheme == "grapheone-scripture" || url.scheme == "grapheone-strongs"
    }

    func syncFormattingState() {
        guard let textView else {
            applyFormattingState(
                isBoldActive: false,
                isItalicActive: false,
                isUnderlineActive: false,
                isHighlightActive: false,
                isHeadingActive: false,
                isBulletActive: false,
                isNumberedActive: false
            )
            return
        }

        let isFocusedEditor = textView.window?.firstResponder === textView
        guard isFocusedEditor else {
            applyFormattingState(
                isBoldActive: false,
                isItalicActive: false,
                isUnderlineActive: false,
                isHighlightActive: false,
                isHeadingActive: false,
                isBulletActive: false,
                isNumberedActive: false
            )
            return
        }

        let selection = textView.selectedRange()
        if textView.isRichText {
            let nsString = textView.string as NSString
            let probeRange = selection.length > 0
                ? selection
                : paragraphRangeForCaret(in: nsString, selectionLocation: selection.location)

            let paragraphRange = paragraphRangeForCaret(in: nsString, selectionLocation: selection.location)
            let caretIsOnNewlineBoundary = selection.length == 0 &&
                selection.location < nsString.length &&
                nsString.substring(with: NSRange(location: selection.location, length: 1)) == "\n"
            let isEmptyParagraph = caretIsOnNewlineBoundary || isEmptyCaretParagraph(in: nsString, selection: selection)
            let kind = isEmptyParagraph ? RichNoteBlockKind.paragraph : currentBlockKind(in: textView, paragraphRange: paragraphRange)
            let paragraphText = nsString.substring(with: paragraphRange).trimmingCharacters(in: .newlines)
            let trimmedParagraph = paragraphText.trimmingCharacters(in: .whitespaces)
            let blockBaseFont = blockFont(for: kind, baseFont: editorBaseFont)
            let boldActive: Bool
            let italicActive: Bool
            let underlineActive: Bool
            let highlightActive: Bool

            let caretFont = pendingCaretTypingFont ?? (textView.typingAttributes[.font] as? NSFont)
            if selection.length == 0, let typingFont = caretFont {
                boldActive = inlineTrait(.bold, isPresentIn: typingFont, blockBaseFont: blockBaseFont)
                italicActive = inlineTrait(.italic, isPresentIn: typingFont, blockBaseFont: blockBaseFont)
                underlineActive = attributeValue(textView.typingAttributes[.underlineStyle], matches: NSUnderlineStyle.single.rawValue, for: .underlineStyle)
                highlightActive = attributeValue(textView.typingAttributes[.backgroundColor], matches: Self.noteHighlightColor, for: .backgroundColor)
            } else {
                let baseFont = textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                boldActive = selectionHasInlineTrait(.bold, in: textView, range: probeRange, baseFont: baseFont)
                italicActive = selectionHasInlineTrait(.italic, in: textView, range: probeRange, baseFont: baseFont)
                underlineActive = selectionHasAttribute(.underlineStyle, matching: NSUnderlineStyle.single.rawValue, in: textView, range: probeRange)
                highlightActive = selectionHasAttribute(.backgroundColor, matching: Self.noteHighlightColor, in: textView, range: probeRange)
            }

            let headingActive: Bool
            let bulletActive: Bool
            let numberedActive: Bool
            switch kind {
            case .heading:
                headingActive = !isEmptyParagraph
                bulletActive = false
                numberedActive = false
            case .bulletItem:
                headingActive = false
                bulletActive = !isEmptyParagraph && (trimmedParagraph.hasPrefix("• ") || trimmedParagraph == "•")
                numberedActive = false
            case .numberedItem:
                headingActive = false
                bulletActive = false
                numberedActive = !isEmptyParagraph
            case .paragraph:
                headingActive = false
                bulletActive = false
                numberedActive = false
            }
            applyFormattingState(
                isBoldActive: boldActive,
                isItalicActive: italicActive,
                isUnderlineActive: underlineActive,
                isHighlightActive: highlightActive,
                isHeadingActive: headingActive,
                isBulletActive: bulletActive,
                isNumberedActive: numberedActive
            )
        } else {
            applyFormattingState(
                isBoldActive: false,
                isItalicActive: false,
                isUnderlineActive: false,
                isHighlightActive: false,
                isHeadingActive: false,
                isBulletActive: false,
                isNumberedActive: false
            )
        }
    }

    private func applyFormattingState(
        isBoldActive: Bool,
        isItalicActive: Bool,
        isUnderlineActive: Bool,
        isHighlightActive: Bool,
        isHeadingActive: Bool,
        isBulletActive: Bool,
        isNumberedActive: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isBoldActive != isBoldActive {
                self.isBoldActive = isBoldActive
            }
            if self.isItalicActive != isItalicActive {
                self.isItalicActive = isItalicActive
            }
            if self.isUnderlineActive != isUnderlineActive {
                self.isUnderlineActive = isUnderlineActive
            }
            if self.isHighlightActive != isHighlightActive {
                self.isHighlightActive = isHighlightActive
            }
            if self.isHeadingActive != isHeadingActive {
                self.isHeadingActive = isHeadingActive
            }
            if self.isBulletActive != isBulletActive {
                self.isBulletActive = isBulletActive
            }
            if self.isNumberedActive != isNumberedActive {
                self.isNumberedActive = isNumberedActive
            }
        }
    }

    fileprivate func numberedListOrdinal(in paragraphText: String) -> Int? {
        let trimmed = paragraphText.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        guard digits.count < trimmed.count else { return Int(digits) }
        let suffixIndex = trimmed.index(trimmed.startIndex, offsetBy: digits.count)
        let remainder = trimmed[suffixIndex...]
        guard remainder.hasPrefix(". ") else { return nil }
        return Int(digits)
    }

    func updateSelectedRange(_ range: NSRange) {
        lastSelectedRange = range
        if range.length > 0 {
            lastNonEmptySelectedRange = range
            pendingCaretTypingFont = nil
        }
    }

    func syncTypingAttributesToCaret(preserveInlineTraits: Bool = false) {
        guard let textView, textView.isRichText else { return }
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return }

        let nsString = textView.string as NSString
        let paragraphRange = paragraphRangeForCaret(in: nsString, selectionLocation: selection.location)
        let kind = currentBlockKind(in: textView, paragraphRange: paragraphRange)
        let blockBaseFont = blockFont(for: kind, baseFont: editorBaseFont)
        let font: NSFont
        let sourceTypingFont = pendingCaretTypingFont ?? (textView.typingAttributes[.font] as? NSFont)
        if let currentTypingFont = sourceTypingFont {
            font = mergedInlineTypingFont(currentTypingFont, blockBaseFont: blockBaseFont)
        } else {
            font = blockBaseFont
        }
        textView.typingAttributes[.font] = font
        if preserveInlineTraits || pendingCaretTypingFont != nil {
            pendingCaretTypingFont = font
        }
    }

    private func mergedInlineTypingFont(_ currentTypingFont: NSFont, blockBaseFont: NSFont) -> NSFont {
        let currentTraits = currentTypingFont.fontDescriptor.symbolicTraits
        let blockTraits = blockBaseFont.fontDescriptor.symbolicTraits
        let manager = NSFontManager.shared
        var font = blockBaseFont

        if currentTraits.contains(.bold) && !blockTraits.contains(.bold) {
            font = manager.convert(font, toHaveTrait: .boldFontMask)
        }
        if currentTraits.contains(.italic) && !blockTraits.contains(.italic) {
            font = manager.convert(font, toHaveTrait: .italicFontMask)
        }

        return NSFont(descriptor: font.fontDescriptor, size: blockBaseFont.pointSize) ?? font
    }

    private func performFormattingAction(_ action: @escaping () -> Void) {
        guard let textView else { return }
        let liveSelection = pendingToolbarSelectionSnapshot ?? textView.selectedRange()
        pendingToolbarSelectionSnapshot = nil
        let hadCaretOnlySelection = liveSelection.length == 0
        let cachedTypingFont = hadCaretOnlySelection
            ? (pendingCaretTypingFont ?? (textView.typingAttributes[.font] as? NSFont))
            : nil
        let needsRefocus = textView.window?.firstResponder !== textView
        if needsRefocus {
            textView.window?.makeFirstResponder(textView)
            if hadCaretOnlySelection, liveSelection.location != NSNotFound {
                textView.setSelectedRange(liveSelection)
                updateSelectedRange(liveSelection)
            } else {
                restoreSelection(in: textView, preferLastNonEmptySelection: true)
            }
        } else if textView.selectedRange().location == NSNotFound {
            restoreSelection(in: textView, preferLastNonEmptySelection: false)
        }
        if let cachedTypingFont, textView.selectedRange().length == 0 {
            textView.typingAttributes[.font] = cachedTypingFont
            pendingCaretTypingFont = cachedTypingFont
        }
        action()
        guard hadCaretOnlySelection,
              let updatedTypingFont = textView.typingAttributes[.font] as? NSFont else {
            return
        }
        pendingCaretTypingFont = updatedTypingFont
        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self, let textView, self.textView === textView else { return }
            textView.window?.makeFirstResponder(textView)
            if textView.selectedRange().length == 0 {
                textView.typingAttributes[.font] = updatedTypingFont
            }
            self.syncFormattingState()
        }
    }

    private func restoreSelection(in textView: NSTextView, preferLastNonEmptySelection: Bool) {
        let currentRange = textView.selectedRange()
        let preferredRange: NSRange
        if currentRange.location != NSNotFound && (!preferLastNonEmptySelection || currentRange.length > 0) {
            preferredRange = currentRange
        } else if preferLastNonEmptySelection, lastNonEmptySelectedRange.location != NSNotFound {
            preferredRange = lastNonEmptySelectedRange
        } else {
            preferredRange = lastSelectedRange
        }
        guard preferredRange.location != NSNotFound else { return }
        let maxLength = (textView.string as NSString).length
        let clampedLocation = min(preferredRange.location, maxLength)
        let clampedLength = min(preferredRange.length, max(0, maxLength - clampedLocation))
        textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
    }

    private func refreshLayout(in textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            textView.needsDisplay = true
            return
        }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.invalidateDisplay(forCharacterRange: fullRange)
        layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        layoutManager.ensureLayout(for: textContainer)
        textView.needsDisplay = true
        textView.displayIfNeeded()
    }

    private func insertAtLineStart(_ prefix: String) {
        guard let tv = textView else { return }
        let nsString = tv.string as NSString
        let selection = tv.selectedRange()
        let lineRange = nsString.lineRange(for: selection)
        let originalBlock = nsString.substring(with: lineRange)
        let lines = originalBlock.components(separatedBy: "\n")

        let nonEmptyLines = lines.filter { !$0.isEmpty }
        let shouldRemove = !nonEmptyLines.isEmpty && nonEmptyLines.allSatisfy { $0.hasPrefix(prefix) }

        let updatedLines = lines.map { line -> String in
            guard !line.isEmpty else { return line }
            if shouldRemove {
                return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line
            } else {
                return prefix + line
            }
        }

        let replacement = updatedLines.joined(separator: "\n")
        tv.insertText(replacement, replacementRange: lineRange)
        tv.setSelectedRange(NSRange(location: lineRange.location, length: (replacement as NSString).length))
    }

    func normalizedPaste(_ attributedString: NSAttributedString) -> NSAttributedString {
        guard let textView, textView.isRichText else { return attributedString }

        var containsStructuredNoteFormatting = false
        attributedString.enumerateAttribute(.richNoteBlockKind, in: NSRange(location: 0, length: attributedString.length), options: []) { value, _, stop in
            if value as? String != nil {
                containsStructuredNoteFormatting = true
                stop.pointee = true
            }
        }
        if containsStructuredNoteFormatting {
            return attributedString
        }

        let selection = textView.selectedRange()
        let nsString = textView.string as NSString
        let probeLocation = max(0, min(selection.location, max(0, nsString.length - 1)))
        let paragraphRange = nsString.paragraphRange(for: NSRange(location: probeLocation, length: 0))
        let blockKind = currentBlockKind(in: textView, paragraphRange: paragraphRange)
        let blockBaseFont = blockFont(for: blockKind, baseFont: editorBaseFont)
        let typingFont = pendingCaretTypingFont
            ?? (textView.typingAttributes[.font] as? NSFont)
            ?? blockBaseFont

        let normalized = NSMutableAttributedString(string: attributedString.string)
        normalized.addAttributes([
            .font: typingFont,
            .paragraphStyle: paragraphStyle(for: blockKind),
            .richNoteBlockKind: blockKindToken(for: blockKind)
        ], range: NSRange(location: 0, length: normalized.length))
        return normalized
    }
}

private final class RichNoteTextView: NSTextView {
    private static let internalAttributedStringType = NSPasteboard.PasteboardType("com.scripturestudy.rich-note-attributed-string")

    weak var noteController: NoteEditorController?
    var suppressNextBulletContinuation = false
    private var linkTrackingArea: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        if let linkTrackingArea {
            removeTrackingArea(linkTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: visibleRect,
            options: [.activeInKeyWindow, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        linkTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let (link, characterIndex) = linkInfo(at: point),
           handleLinkActivation(link, characterIndex: characterIndex) {
            print("[NOTE DEBUG] mouseDown activated link at characterIndex=", characterIndex, "link=", String(describing: link))
            return
        }
        super.mouseDown(with: event)
    }

    override func copy(_ sender: Any?) {
        guard selectedRange().length > 0,
              let textStorage else {
            super.copy(sender)
            return
        }

        let selectedAttributedString = textStorage.attributedSubstring(from: selectedRange())
        super.copy(sender)
        writeInternalAttributedStringToPasteboard(selectedAttributedString)
    }

    override func cut(_ sender: Any?) {
        guard selectedRange().length > 0,
              let textStorage else {
            super.cut(sender)
            return
        }

        let selectedAttributedString = textStorage.attributedSubstring(from: selectedRange())
        super.cut(sender)
        writeInternalAttributedStringToPasteboard(selectedAttributedString)
    }

    override func paste(_ sender: Any?) {
        guard isRichText,
              let noteController else {
            super.paste(sender)
            return
        }
        let pasteboard = NSPasteboard.general
        let attributedPaste: NSAttributedString?
        if let archivedData = pasteboard.data(forType: Self.internalAttributedStringType),
           let restored = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: archivedData) {
            attributedPaste = restored
        } else if let rtfdData = pasteboard.data(forType: .rtfd) {
            attributedPaste = try? NSAttributedString(
                data: rtfdData,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil
            )
        } else if let rtfData = pasteboard.data(forType: .rtf) {
            attributedPaste = try? NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        } else {
            attributedPaste = nil
        }
        guard let attributedPaste else {
            super.paste(sender)
            return
        }

        let normalizedPaste = noteController.normalizedPaste(attributedPaste)
        let replacementRange = selectedRange()
        let replacedText = textStorage?.attributedSubstring(from: replacementRange) ?? NSAttributedString()
        textStorage?.replaceCharacters(in: replacementRange, with: normalizedPaste)
        let caretLocation = replacementRange.location + normalizedPaste.length
        setSelectedRange(NSRange(location: caretLocation, length: 0))
        didChangeText()
        registerUndoForReplacement(
            at: replacementRange.location,
            originalText: replacedText,
            replacementText: normalizedPaste,
            actionName: "Paste"
        )
    }

    private func writeInternalAttributedStringToPasteboard(_ attributedString: NSAttributedString) {
        guard let archivedData = try? NSKeyedArchiver.archivedData(withRootObject: attributedString, requiringSecureCoding: false) else {
            return
        }
        NSPasteboard.general.setData(archivedData, forType: Self.internalAttributedStringType)
    }

    private func registerUndoForReplacement(
        at location: Int,
        originalText: NSAttributedString,
        replacementText: NSAttributedString,
        actionName: String
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.applyUndoReplacement(
                at: location,
                originalText: originalText,
                replacementText: replacementText,
                actionName: actionName
            )
        }
        undoManager.setActionName(actionName)
    }

    private func applyUndoReplacement(
        at location: Int,
        originalText: NSAttributedString,
        replacementText: NSAttributedString,
        actionName: String
    ) {
        let replacementRange = NSRange(location: location, length: replacementText.length)
        textStorage?.replaceCharacters(in: replacementRange, with: originalText)
        let caretLocation = location + originalText.length
        setSelectedRange(NSRange(location: caretLocation, length: 0))
        didChangeText()
        registerUndoForReplacement(
            at: location,
            originalText: replacementText,
            replacementText: originalText,
            actionName: actionName
        )
    }

    private func linkInfo(at point: NSPoint) -> (value: Any, characterIndex: Int)? {
        guard let layoutManager, let textContainer else { return nil }

        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        guard containerPoint.x >= 0, containerPoint.y >= 0 else { return nil }

        let characterIndex = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard characterIndex < (string as NSString).length else { return nil }

        var effectiveRange = NSRange(location: 0, length: 0)
        guard let value = textStorage?.attribute(.link, at: characterIndex, effectiveRange: &effectiveRange) else {
            return nil
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: effectiveRange, actualCharacterRange: nil)
        var pointIsInsideLinkedGlyph = false
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, lineGlyphRange, stop in
            let intersected = NSIntersectionRange(glyphRange, lineGlyphRange)
            guard intersected.length > 0 else { return }
            let lineRect = layoutManager.boundingRect(forGlyphRange: intersected, in: textContainer)
            if lineRect.contains(containerPoint) {
                pointIsInsideLinkedGlyph = true
                stop.pointee = true
            }
        }
        guard pointIsInsideLinkedGlyph else {
            return nil
        }

        return (value, characterIndex)
    }

    private func handleLinkActivation(_ link: Any, characterIndex: Int) -> Bool {
        guard let delegate else { return false }
        return delegate.textView?(self, clickedOnLink: link, at: characterIndex) ?? false
    }

    private func updateCursor(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if linkInfo(at: point) != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }
}

// MARK: - NSTextView Representable

struct NoteTextEditor: NSViewRepresentable {

    let noteID:        UUID           // used only to confirm identity
    let initialText:   String         // loaded once on creation
    let initialAttributedText: NSAttributedString?
    var onTextChange:  (String) -> Void  // caller handles saving
    var onAttributedTextChange: ((NSAttributedString) -> Void)?
    var fontSize:      Double
    var fontName:      String
    var controller:    NoteEditorController
    var highlight:     String = ""
    var isEditable:    Bool   = true

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: .greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        let tv = RichNoteTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)

        tv.isRichText                          = initialAttributedText != nil
        tv.allowsUndo                          = true
        tv.isEditable                          = isEditable
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled  = false
        tv.isAutomaticLinkDetectionEnabled     = false
        tv.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        tv.delegate                            = context.coordinator
        tv.textContainerInset                  = NSSize(width: 12, height: 12)
        tv.drawsBackground                     = false
        tv.font                                = resolvedFont()
        tv.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.4),
            .foregroundColor: NSColor.selectedTextColor
        ]
        tv.minSize                             = NSSize(width: 0, height: contentSize.height)
        tv.maxSize                             = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable               = true
        tv.isHorizontallyResizable             = false
        tv.autoresizingMask                    = [.width]
        tv.textContainer?.containerSize        = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView  = true
        if let initialAttributedText {
            tv.textStorage?.setAttributedString(initialAttributedText)
        } else {
            tv.string = initialText
        }
        controller.textView = tv
        tv.noteController = controller

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.drawsBackground     = false
        scrollView.borderType          = .noBorder
        scrollView.documentView        = tv

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? RichNoteTextView else { return }
        // Since we use .id(note.id), this view is brand new per note.
        // Only handle editability and highlights here — never touch the text.
        tv.isEditable       = isEditable
        controller.textView = tv
        tv.noteController   = controller

        if !highlight.isEmpty && highlight != context.coordinator.lastHighlight {
            context.coordinator.lastHighlight = highlight
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.applyHighlight(highlight, in: tv)
            }
        }
    }

    private func resolvedFont() -> NSFont {
        if !fontName.isEmpty, let f = NSFont(name: fontName, size: fontSize) { return f }
        return NSFont.systemFont(ofSize: fontSize)
    }

    private func applyHighlight(_ term: String, in tv: NSTextView) {
        let nsStr = tv.string as NSString
        let range = nsStr.range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
        guard range.location != NSNotFound else { return }
        tv.layoutManager?.removeTemporaryAttribute(.backgroundColor,
            forCharacterRange: NSRange(location: 0, length: nsStr.length))
        tv.scrollRangeToVisible(range)
        tv.setSelectedRange(range)
        tv.layoutManager?.addTemporaryAttribute(.backgroundColor,
            value: NSColor.systemYellow.withAlphaComponent(0.55),
            forCharacterRange: range)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            tv.layoutManager?.removeTemporaryAttribute(.backgroundColor,
                forCharacterRange: NSRange(location: 0, length: (tv.string as NSString).length))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange, onAttributedTextChange: onAttributedTextChange)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        let onTextChange:  (String) -> Void
        let onAttributedTextChange: ((NSAttributedString) -> Void)?
        var lastHighlight: String = ""
        private var isApplyingLiveMarkdown = false

        init(
            onTextChange: @escaping (String) -> Void,
            onAttributedTextChange: ((NSAttributedString) -> Void)?
        ) {
            self.onTextChange = onTextChange
            self.onAttributedTextChange = onAttributedTextChange
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if tv.isRichText,
               !isApplyingLiveMarkdown,
               let controller = (tv as? RichNoteTextView)?.noteController {
                isApplyingLiveMarkdown = true
                controller.applyLiveMarkdownTransformsIfNeeded()
                _ = controller.applyAutoDetectedLinksIfNeeded()
                isApplyingLiveMarkdown = false
            }
            NoteCommandRouter.shared.activeController?.updateSelectedRange(tv.selectedRange())
            NoteCommandRouter.shared.activeController?.syncTypingAttributesToCaret(preserveInlineTraits: true)
            NoteCommandRouter.shared.activeController?.syncFormattingState()
            if let onAttributedTextChange {
                onAttributedTextChange(tv.attributedString())
            } else {
                onTextChange(tv.string)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            NoteCommandRouter.shared.activeController?.updateSelectedRange(tv.selectedRange())
            NoteCommandRouter.shared.activeController?.syncTypingAttributesToCaret()
            NoteCommandRouter.shared.activeController?.syncFormattingState()
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard textView.isRichText,
                  let replacementString,
                  replacementString.contains("\n") || replacementString.contains("\r") else {
                return true
            }
            if let richTextView = textView as? RichNoteTextView,
               richTextView.suppressNextBulletContinuation {
                richTextView.suppressNextBulletContinuation = false
                let storage = textView.textStorage
                let paragraphFont = (storage?.attribute(.font, at: max(0, min(affectedCharRange.location, max(0, (textView.string as NSString).length - 1))), effectiveRange: nil) as? NSFont)
                    ?? textView.font
                    ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                let newline = NSAttributedString(string: "\n", attributes: [
                    .font: paragraphFont,
                    .paragraphStyle: NSMutableParagraphStyle(),
                    .richNoteBlockKind: "paragraph"
                ])
                storage?.replaceCharacters(in: affectedCharRange, with: newline)
                let caretLocation = min(affectedCharRange.location + newline.length, (textView.string as NSString).length)
                textView.setSelectedRange(NSRange(location: caretLocation, length: 0))
                textView.didChangeText()
                return false
            }
            let nsString = textView.string as NSString
            let paragraphRange = nsString.paragraphRange(for: NSRange(location: affectedCharRange.location, length: 0))
            guard paragraphRange.length > 0,
                  let storage = textView.textStorage else {
                return true
            }
            let fullParagraphText = nsString.substring(with: paragraphRange)
            let paragraphText = fullParagraphText.trimmingCharacters(in: .newlines)
            let token = storage.attribute(.richNoteBlockKind, at: paragraphRange.location, effectiveRange: nil) as? String
            let visibleListText = paragraphText.trimmingCharacters(in: .whitespaces)
            let listKind: RichNoteBlockKind
            if let token,
               token.hasPrefix("bullet:"),
               visibleListText.hasPrefix("•"),
               let parsedDepth = Int(token.dropFirst("bullet:".count)) {
                listKind = .bulletItem(depth: parsedDepth)
            } else if visibleListText.hasPrefix("•") {
                listKind = .bulletItem(depth: 0)
            } else if let ordinal = NoteCommandRouter.shared.activeController?.numberedListOrdinal(in: paragraphText) {
                listKind = .numberedItem(depth: 0, ordinal: ordinal)
            } else {
                return true
            }
            let trimmed = visibleListText
            let indent = String(paragraphText.prefix { $0 == " " })

            let shouldExitList: Bool
            switch listKind {
            case .bulletItem:
                shouldExitList = trimmed == "•"
            case .numberedItem(_, let ordinal):
                shouldExitList = trimmed == "\(ordinal ?? 1)"
            default:
                shouldExitList = false
            }

            if shouldExitList {
                let replacement = NSMutableAttributedString()
                let paragraphFont = (storage.attribute(.font, at: paragraphRange.location, effectiveRange: nil) as? NSFont)
                    ?? textView.font
                    ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                replacement.append(NSAttributedString(string: "\n", attributes: [
                    .font: paragraphFont,
                    .paragraphStyle: NSMutableParagraphStyle(),
                    .richNoteBlockKind: "paragraph"
                ]))
                textView.textStorage?.replaceCharacters(in: paragraphRange, with: replacement)
                let caretLocation = min(paragraphRange.location + replacement.length, (textView.string as NSString).length)
                textView.setSelectedRange(NSRange(location: caretLocation, length: 0))
                (textView as? RichNoteTextView)?.suppressNextBulletContinuation = true
                textView.didChangeText()
                return false
            }

            let insertion: String
            let continuedToken: String
            switch listKind {
            case .bulletItem(let depth):
                insertion = "\n\(indent)• "
                continuedToken = "bullet:\(depth)"
            case .numberedItem(let depth, let ordinal):
                let nextOrdinal = (ordinal ?? 1) + 1
                insertion = "\n\(indent)\(nextOrdinal). "
                continuedToken = "numbered:\(depth):\(nextOrdinal)"
            default:
                return true
            }
            textView.textStorage?.replaceCharacters(in: affectedCharRange, with: insertion)
            let insertedRange = NSRange(location: affectedCharRange.location, length: (insertion as NSString).length)
            var attributes: [NSAttributedString.Key: Any] = [:]
            if let font = storage.attribute(.font, at: paragraphRange.location, effectiveRange: nil) {
                attributes[.font] = font
            }
            if let paragraphStyle = storage.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) {
                attributes[.paragraphStyle] = paragraphStyle
            }
            attributes[.richNoteBlockKind] = continuedToken
            storage.addAttributes(attributes, range: insertedRange)
            let caretLocation = min(affectedCharRange.location + insertedRange.length, (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: caretLocation, length: 0))
            textView.didChangeText()
            return false
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let target = RichNoteLinkCodec.target(from: link) {
                switch target {
                case .scripture(let scripture):
                    let request = PassageNavigationRequest(scriptureTarget: scripture)
                    NotificationCenter.default.post(name: .navigateToPassage, object: nil, userInfo: request.userInfo)
                    return true
                case .strongs(let strongs):
                    NotificationCenter.default.post(name: Notification.Name("switchToBibleTab"), object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        NotificationCenter.default.post(
                            name: Notification.Name("strongsTapped"),
                            object: nil,
                            userInfo: ["number": strongs.number]
                        )
                    }
                    return true
                case .note(let noteID):
                    NotificationCenter.default.post(name: Notification.Name("switchToNotesTab"), object: nil)
                    NotificationCenter.default.post(name: .navigateToNote, object: nil, userInfo: ["noteID": noteID])
                    return true
                case .url(let url):
                    NSWorkspace.shared.open(url)
                    return true
                }
            }

            if let url = RichNoteLinkCodec.url(from: link) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }
    }
}
#else
import SwiftUI
import UIKit

// MARK: - iOS stub (UITextView-based, to be implemented)

class NoteEditorController: ObservableObject {
    func bold()             {}
    func italic()           {}
    func underline()        {}
    func highlight()        {}
    func heading()          {}
    func bullet()           {}
    func numberedList()     {}
    func changeFontSize(by delta: CGFloat) {}
}

struct NoteTextEditor: UIViewRepresentable {
    let noteID:       UUID
    let initialText:  String
    let initialAttributedText: NSAttributedString? = nil
    var onTextChange: (String) -> Void
    var onAttributedTextChange: ((NSAttributedString) -> Void)? = nil
    var fontSize:     Double
    var fontName:     String
    var controller:   NoteEditorController
    var highlight:    String = ""
    var isEditable:   Bool   = true

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.text       = initialText
        tv.isEditable = isEditable
        tv.font       = UIFont.systemFont(ofSize: CGFloat(fontSize))
        tv.delegate   = context.coordinator
        tv.backgroundColor = .clear
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        tv.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTextChange: onTextChange) }

    class Coordinator: NSObject, UITextViewDelegate {
        let onTextChange: (String) -> Void
        init(onTextChange: @escaping (String) -> Void) { self.onTextChange = onTextChange }
        func textViewDidChange(_ textView: UITextView) { onTextChange(textView.text) }
    }
}

#endif

// MARK: - Shared Notes Editing Views

struct NoteFormattingToolbar<TrailingContent: View>: View {
    let controller: NoteEditorController
    @ViewBuilder var trailingContent: () -> TrailingContent

    var body: some View {
        HStack(spacing: 4) {
            Group {
                FormatButton(label: "B", help: "Bold (**text**)", isActive: controller.isBoldActive) { controller.bold() }
                FormatButton(label: "I", help: "Italic (*text*)", isActive: controller.isItalicActive) { controller.italic() }
                FormatButton(label: "U", help: "Underline", isActive: controller.isUnderlineActive) { controller.underline() }
                FormatButton(label: "HL", help: "Highlight", isActive: controller.isHighlightActive) { controller.highlight() }
                FormatButton(label: "H", help: "Heading (# line)", isActive: controller.isHeadingActive) { controller.heading() }
                FormatButton(label: "•", help: "Bullet list", isActive: controller.isBulletActive) { controller.bullet() }
                FormatButton(label: "1", help: "Numbered list", isActive: controller.isNumberedActive) { controller.numberedList() }
            }
            Divider().frame(height: 16).padding(.horizontal, 4)
            Text("Formatting")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            trailingContent()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.platformWindowBg)
    }
}

struct NoteEditorSurface<TrailingContent: View>: View {
    let noteID: UUID
    let initialText: String
    let initialAttributedText: NSAttributedString?
    let fontSize: Double
    let fontName: String
    let controller: NoteEditorController
    let highlight: String
    let isEditable: Bool
    let onTextChange: (String) -> Void
    let onAttributedTextChange: ((NSAttributedString) -> Void)?
    @ViewBuilder var trailingContent: () -> TrailingContent

    init(
        noteID: UUID,
        initialText: String,
        initialAttributedText: NSAttributedString? = nil,
        fontSize: Double,
        fontName: String,
        controller: NoteEditorController,
        highlight: String = "",
        isEditable: Bool = true,
        onTextChange: @escaping (String) -> Void,
        onAttributedTextChange: ((NSAttributedString) -> Void)? = nil,
        @ViewBuilder trailingContent: @escaping () -> TrailingContent = { EmptyView() }
    ) {
        self.noteID = noteID
        self.initialText = initialText
        self.initialAttributedText = initialAttributedText
        self.fontSize = fontSize
        self.fontName = fontName
        self.controller = controller
        self.highlight = highlight
        self.isEditable = isEditable
        self.onTextChange = onTextChange
        self.onAttributedTextChange = onAttributedTextChange
        self.trailingContent = trailingContent
    }

    var body: some View {
        VStack(spacing: 0) {
            NoteFormattingToolbar(controller: controller, trailingContent: trailingContent)
            Divider()
            NoteTextEditor(
                noteID: noteID,
                initialText: initialText,
                initialAttributedText: initialAttributedText,
                onTextChange: onTextChange,
                onAttributedTextChange: onAttributedTextChange,
                fontSize: fontSize,
                fontName: fontName,
                controller: controller,
                highlight: highlight,
                isEditable: isEditable
            )
            .id(noteID)
        }
    }
}

struct FormatButton: View {
    let label: String
    let help: String
    let isActive: Bool
    let action: () -> Void

    private var buttonWidth: CGFloat {
        label.count > 1 ? 34 : 26
    }

    var body: some View {
        MacFormatButton(label: label, help: help, isActive: isActive, action: action)
            .frame(width: buttonWidth, height: 22)
    }
}

private struct MacFormatButton: NSViewRepresentable {
    let label: String
    let help: String
    let isActive: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> ToolbarActionButton {
        let button = ToolbarActionButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.focusRingType = .none
        button.bezelStyle = .regularSquare
        button.toolTip = help
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        update(button)
        return button
    }

    func updateNSView(_ nsView: ToolbarActionButton, context: Context) {
        context.coordinator.action = action
        nsView.toolTip = help
        update(nsView)
    }

    private func update(_ button: ToolbarActionButton) {
        let font: NSFont
        if label == "•" {
            font = .systemFont(ofSize: 15, weight: .semibold)
        } else {
            font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        }

        let foreground = NSColor.labelColor.withAlphaComponent(isActive ? 1.0 : 0.85)
        let title = NSAttributedString(
            string: label,
            attributes: [
                .font: font,
                .foregroundColor: foreground
            ]
        )
        button.attributedTitle = title
        button.layer?.backgroundColor = (isActive ? NSColor.labelColor.withAlphaComponent(0.16) : NSColor.windowBackgroundColor).cgColor
        button.layer?.borderWidth = 0.9
        button.layer?.borderColor = (isActive ? NSColor.labelColor.withAlphaComponent(0.45) : NSColor.secondaryLabelColor.withAlphaComponent(0.3)).cgColor
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

private final class ToolbarActionButton: NSButton {
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        NoteCommandRouter.shared.activeController?.captureToolbarSelectionSnapshot()
        super.mouseDown(with: event)
    }
}
