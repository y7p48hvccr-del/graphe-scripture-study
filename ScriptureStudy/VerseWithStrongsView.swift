import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var hSpacing: CGFloat = 3
    var vSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var height: CGFloat = 0; var rowWidth: CGFloat = 0; var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                height += rowHeight + vSpacing; rowWidth = 0; rowHeight = 0
            }
            rowWidth += size.width + hSpacing; rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: height + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + vSpacing; x = bounds.minX; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + hSpacing; rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Word Token

private struct WordToken: Identifiable {
    let id          = UUID()
    let text:       String
    let strongsNum: String?
    let footnote:   String?   // non-nil = this token is a footnote marker
}

// MARK: - Popover Item

private struct PopoverItem: Identifiable {
    let id      = UUID()
    let label:  String
    let icon:   String
    let enabled: Bool
    let action: () -> Void
}

// MARK: - Verse With Strongs View

struct VerseWithStrongsView: View {

    let verse:         MyBibleVerse
    let rawText:       String
    let strongsModule: MyBibleModule?
    let isSelected:    Bool
    let hasNote:       Bool
    let linkedNotes:   [Note]
    let onTapVerseNum:       () -> Void   // kept for compatibility, not used directly
    let onLongPressVerseNum: () -> Void   // kept for compatibility, not used directly

    @EnvironmentObject var myBible:      MyBibleService
    @EnvironmentObject var notesManager: NotesManager
    @EnvironmentObject var bmapsService: BMapsService

    @AppStorage("fontSize")      private var fontSize:      Double = 16
    @AppStorage("fontName")      private var fontName:      String = ""
    @AppStorage("themeID")       private var themeID:       String = "light"
    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    var theme: AppTheme { AppTheme.find(themeID) }
    var filigreeAccent:     Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }
    var resolvedFont: Font {
        guard !fontName.isEmpty else { return .system(size: fontSize) }
        return .custom(fontName, size: fontSize)
    }

    // Popover state
    enum ActivePopover { case verse, word, footnote }
    @State private var activePopover:      ActivePopover? = nil
    @State private var tappedToken:        WordToken?     = nil
    @State private var footnoteText:       String         = ""

    // Dictionary/encyclopedia availability (looked up async when popover opens)
    @State private var dictAvailable:  Bool? = nil
    @State private var encycAvailable: Bool? = nil

    // Commentary availability — checked async when verse popover opens
    @State private var commentaryAvailable: Bool = false

    // Cached tokens
    @State private var _cachedTokens: [WordToken]? = nil
    private var tokens: [WordToken] {
        if let cached = _cachedTokens { return cached }
        let parsed = buildTokens()
        DispatchQueue.main.async { self._cachedTokens = parsed }
        return parsed
    }

    private func buildTokens() -> [WordToken] {
        let segments = StrongsParser.parse(rawText)
        var result: [WordToken] = []
        for seg in segments {
            switch seg {
            case .text(let t):
                let words = t.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                for w in words { result.append(WordToken(text: w, strongsNum: nil, footnote: nil)) }
            case .word(let w, let num):
                result.append(WordToken(text: w, strongsNum: num, footnote: nil))
            case .footnote(let marker, let content):
                result.append(WordToken(text: marker, strongsNum: nil, footnote: content))
            }
        }
        return result
    }

    @State private var strongsFlash: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {

            // ── Verse number ──────────────────────────────────────────
            Text("\(verse.verse)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isSelected ? .white : filigreeAccent.opacity(0.7))
                .frame(minWidth: 18, alignment: .trailing)
                .padding(.horizontal, 3).padding(.vertical, 2)
                .background(isSelected ? filigreeAccent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .onTapGesture {
                    commentaryAvailable = myBible.visibleModules.contains {
                        $0.type == .commentary
                    }
                    activePopover = .verse
                }
                .help("Tap for options")

            // ── Verse text ────────────────────────────────────────────
            FlowLayout(hSpacing: 3, vSpacing: 5) {
                ForEach(tokens) { token in
                    if let footnoteContent = token.footnote {
                        // Footnote marker
                        Text(token.text)
                            .font(.system(size: fontSize * 0.7).weight(.semibold))
                            .foregroundStyle(filigreeAccent)
                            .baselineOffset(4)
                            .onTapGesture {
                                footnoteText  = footnoteContent
                                tappedToken   = token
                                activePopover = .footnote
                            }
                            .popover(isPresented: Binding(
                                get: { activePopover == .footnote && tappedToken?.id == token.id },
                                set: { if !$0 { activePopover = nil } }
                            ), arrowEdge: .top) { footnotePopoverContent }
                    } else {
                        // Normal word or Strong's word
                        Text(token.text)
                            .font(strongsFlash && token.strongsNum != nil
                                  ? resolvedFont.weight(.bold) : resolvedFont)
                            .foregroundStyle(strongsFlash && token.strongsNum != nil
                                             ? filigreeAccent : theme.text)
                            .onTapGesture {
                                tappedToken    = token
                                dictAvailable  = nil
                                encycAvailable = nil
                                activePopover  = .word
                                let word = token.text
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    Task {
                                        let dr = await myBible.lookupDictionaryWord(word: word)
                                        await MainActor.run { dictAvailable = dr != nil }
                                    }
                                    Task {
                                        let er = await myBible.lookupWord(
                                            word: word, in: myBible.selectedEncyclopedia)
                                        await MainActor.run { encycAvailable = er != nil }
                                    }
                                }
                            }
                            .popover(isPresented: Binding(
                                get: { activePopover == .word && tappedToken?.id == token.id },
                                set: { if !$0 { activePopover = nil } }
                            ), arrowEdge: .top) { wordPopoverContent }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("strongsFlashOn")))  { _ in strongsFlash = true  }
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("strongsFlashOff"))) { _ in strongsFlash = false }

            // ── Note indicator ────────────────────────────────────────
            if hasNote {
                Button {
                    NotificationCenter.default.post(
                        name: Notification.Name("showVerseNotes"),
                        object: nil,
                        userInfo: ["notes": linkedNotes]
                    )
                } label: {
                    Image(systemName: "note.text")
                        .font(.system(size: 10))
                        .foregroundStyle(filigreeAccent)
                }
                .buttonStyle(.plain)
                .help("View note")
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(isSelected ? filigreeAccentFill.opacity(0.20) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .popover(isPresented: Binding(
            get: { activePopover == .verse },
            set: { if !$0 { activePopover = nil } }
        ), arrowEdge: .leading) { versePopoverContent }

    }

    // MARK: - Verse Popover

    private var versePopoverContent: some View {
        versePopover
            .background(filigreeAccent.opacity(0.08))
    }

    private var versePopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Verse \(verse.verse)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            Divider()

            popoverButton(
                label: "Commentary",
                icon:  "text.quote",
                enabled: commentaryAvailable
            ) {
                activePopover = nil
                NotificationCenter.default.post(
                    name: Notification.Name("verseSelected"),
                    object: nil,
                    userInfo: [
                        "bookNumber": verse.book,
                        "chapter":    verse.chapter,
                        "verse":      verse.verse
                    ]
                )
                // Switch companion to commentary
                NotificationCenter.default.post(
                    name: Notification.Name("switchCompanionToCommentary"),
                    object: nil
                )
            }

            Divider().padding(.leading, 14)

            popoverButton(
                label: "Make a Note",
                icon:  "square.and.pencil",
                enabled: true
            ) {
                activePopover = nil
                NotificationCenter.default.post(
                    name: Notification.Name("createNoteForVerse"),
                    object: nil,
                    userInfo: [
                        "bookNumber": verse.book,
                        "chapter":    verse.chapter,
                        "verse":      verse.verse
                    ]
                )
            }

            Spacer().frame(height: 8)
        }
        .frame(width: 200)
    }

    private var wordPopoverContent: some View {
        wordPopover
            .background(filigreeAccent.opacity(0.08))
    }

    // MARK: - Word Popover

    private var wordPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tappedToken?.text ?? "")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            Divider()

            // Strong's — only enabled if token has a Strong's number
            popoverButton(
                label: "Strong's",
                icon:  "character.book.closed",
                enabled: tappedToken?.strongsNum != nil
            ) {
                if let num = tappedToken?.strongsNum {
                    activePopover = nil
                    NotificationCenter.default.post(
                        name: Notification.Name("strongsTapped"),
                        object: nil,
                        userInfo: ["number": num, "bookNumber": verse.book]
                    )
                }
            }

            Divider().padding(.leading, 14)

            // Dictionary — enabled once lookup completes with a result
            popoverButton(
                label: dictAvailable == nil ? "Dictionary…" : "Dictionary",
                icon:  "text.magnifyingglass",
                enabled: dictAvailable == true
            ) {
                if let word = tappedToken?.text {
                    activePopover = nil
                    NotificationCenter.default.post(
                        name: Notification.Name("dictionaryWordTapped"),
                        object: nil,
                        userInfo: ["word": word]
                    )
                }
            }

            Divider().padding(.leading, 14)

            // Encyclopedia
            popoverButton(
                label: encycAvailable == nil ? "Encyclopedia…" : "Encyclopedia",
                icon:  "books.vertical",
                enabled: encycAvailable == true
            ) {
                if let word = tappedToken?.text {
                    activePopover = nil
                    NotificationCenter.default.post(
                        name: Notification.Name("encyclopediaWordTapped"),
                        object: nil,
                        userInfo: ["word": word]
                    )
                }
            }

            Spacer().frame(height: 8)
        }
        .frame(width: 220)
    }

    private var footnotePopoverContent: some View {
        footnotePopover
            .background(filigreeAccent.opacity(0.08))
    }

    // MARK: - Footnote Popover

    private var footnotePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 11))
                    .foregroundStyle(filigreeAccent)
                Text("Footnote")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)

            Text(footnoteText)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: 300)
    }

    // MARK: - Popover Button Helper

    private func popoverButton(label: String, icon: String,
                                enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if enabled { action() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(enabled ? filigreeAccent : Color.secondary.opacity(0.4))
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.5))
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Actions

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - Note Preview Popup

struct NotePreviewPopup: View {
    let notes:      [Note]
    @Binding var isPresented: Bool
    @AppStorage("filigreeColor") private var filigreeColor: Int = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var filigreeAccent:     Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(note.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Text(note.verseReference)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }

                    if !note.content.isEmpty {
                        Text(note.content)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(3)
                    }

                    Button {
                        isPresented = false
                        NotificationCenter.default.post(
                            name: .navigateToNote, object: nil,
                            userInfo: ["noteID": note.id])
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            NotificationCenter.default.post(
                                name: Notification.Name("switchToNotesTab"), object: nil)
                        }
                    } label: {
                        Label("Open note", systemImage: "arrow.right.circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(filigreeAccentFill)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding()

                if index < notes.count - 1 { Divider() }
            }
        }
        .frame(width: 300)
    }
}
