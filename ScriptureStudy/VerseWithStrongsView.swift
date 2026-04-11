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
    let id         = UUID()
    let text:      String
    let strongsNum: String?
}

// MARK: - Verse With Strongs View

struct VerseWithStrongsView: View {

    let verse:         MyBibleVerse
    let rawText:       String
    let strongsModule: MyBibleModule?
    let isSelected:    Bool
    let hasNote:       Bool
    let linkedNotes:   [Note]
    let onTapVerseNum:       () -> Void
    let onLongPressVerseNum: () -> Void

    @EnvironmentObject var myBible:      MyBibleService
    @EnvironmentObject var notesManager: NotesManager

    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("fontName") private var fontName:  String = ""
    @AppStorage("themeID")       private var themeID:      String = "light"
    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    var theme: AppTheme { AppTheme.find(themeID) }
    var filigreeAccent:     Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }
    var resolvedFont: Font {
        guard !fontName.isEmpty else { return .system(size: fontSize) }
        if !fontName.isEmpty {
            return .custom(fontName, size: fontSize)
        }
        return .system(size: fontSize)  // font not installed, use system
    }

    @State private var selectedStrongs:  String?
    @State private var strongsEntry:     StrongsEntry?
    @State private var loadingStrongs    = false

    private var tokens: [WordToken] {
        StrongsParser.parse(rawText).flatMap { seg -> [WordToken] in
            switch seg {
            case .text(let t):
                return t.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .map { WordToken(text: $0, strongsNum: nil) }
            case .word(let w, let num):
                return [WordToken(text: w, strongsNum: num)]
            }
        }
    }

    private var hasStrongs: Bool { tokens.contains { $0.strongsNum != nil } }

    @State private var strongsFlash: Bool = false
    var body: some View {
        HStack(alignment: .top, spacing: 8) {

            // ── Verse number: tap = select, long press = create note ──
            Text("\(verse.verse)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isSelected ? .white : filigreeAccent.opacity(0.7))
                .frame(minWidth: 18, alignment: .trailing)
                .padding(.horizontal, 3).padding(.vertical, 2)
                .background(isSelected ? filigreeAccent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .onTapGesture { onTapVerseNum() }
                .onLongPressGesture(minimumDuration: 0.4) { onLongPressVerseNum() }
                .help("Tap to select · Long-press to create a note")

            // ── Verse text ──
            if hasStrongs && strongsModule != nil {
                FlowLayout(hSpacing: 3, vSpacing: 5) {
                    ForEach(tokens) { token in
                        if let num = token.strongsNum {
                            Button { tappedStrongs(num, word: token.text) } label: {
                                Text(token.text)
                                    .font(strongsFlash ? resolvedFont.weight(.bold) : resolvedFont)
                                    .foregroundStyle(strongsFlash ? filigreeAccent : theme.text)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Copy '\(token.text)'") { copy(token.text) }
                                Button("Look Up in Dictionary") { lookUp(token.text) }
                                Divider()
                                Button("Show Strong's (\(num))") { tappedStrongs(num, word: token.text) }
                            }
                        } else {
                            Text(token.text).font(resolvedFont).foregroundStyle(theme.text)
                                .contextMenu {
                                    Button("Copy '\(token.text)'") { copy(token.text) }
                                    Button("Look Up in Dictionary") { lookUp(token.text) }
                                }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            } else {
                Text(verse.text)
                    .font(resolvedFont).foregroundStyle(theme.text)
                    .lineSpacing(5).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // ── Note indicator at end of verse ──
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
    }

    // MARK: - Actions

    private func tappedStrongs(_ number: String, word: String) {
        selectedStrongs = number
        NotificationCenter.default.post(
            name: Notification.Name("strongsTapped"),
            object: nil,
            userInfo: ["number": number, "bookNumber": verse.book]
        )
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    private func lookUp(_ word: String) {
        let clean = word.trimmingCharacters(in: .punctuationCharacters)
        if let url = URL(string: "dict://\(clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? clean)") {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
        }
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

    @State private var strongsFlash: Bool = false
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
                            .background(filigreeAccent)
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
