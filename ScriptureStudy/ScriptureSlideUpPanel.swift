import SwiftUI

struct ScriptureSlideUpPanel: View {

    let ref:           ScriptureRef
    let onDismiss:     () -> Void
    let onOpenInBible: (ScriptureRef) -> Void

    @EnvironmentObject var myBible: MyBibleService

    @AppStorage("themeID")       private var themeID:      String = "light"
    @AppStorage("filigreeColor") private var filigreeColor: Int   = 0
    @AppStorage("fontSize")      private var fontSize:     Double = 16
    @AppStorage("fontName")      private var fontName:     String = ""

    var theme:  AppTheme { AppTheme.find(themeID) }
    var accent: Color    { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var resolvedFont: Font {
        guard !fontName.isEmpty else { return .system(size: fontSize) }
        return .custom(fontName, size: fontSize)
    }

    @State private var verses:    [MyBibleVerse] = []
    @State private var isLoading  = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ref.bookName) \(ref.chapter)")
                        .font(.system(size: 15, weight: .semibold))
                    if let bible = myBible.selectedBible {
                        Text(bible.name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { onOpenInBible(ref) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "book.fill").font(.system(size: 11))
                        Text("Open in Bible").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            .background(Color.platformWindowBg)

            Divider()

            if isLoading {
                Spacer()
                ProgressView().padding()
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(verses) { verse in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(verse.verse)")
                                        .font(.system(size: fontSize * 0.75, weight: .semibold))
                                        .foregroundStyle(accent)
                                        .frame(minWidth: 24, alignment: .trailing)
                                        .padding(.top, 3)
                                    Text(ScriptureSlideUpPanel.cleanVerseText(verse.text))
                                        .font(resolvedFont)
                                        .foregroundStyle(theme.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 5)
                                .background(ref.verse > 0 && verse.verse == ref.verse
                                    ? accent.opacity(0.10) : Color.clear)
                                .id(verse.verse)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .background(theme.background)
                    .onAppear {
                        if ref.verse > 0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                withAnimation { proxy.scrollTo(ref.verse, anchor: .center) }
                            }
                        }
                    }
                }
            }
        }
        .background(theme.background)
        .onAppear { loadVerses() }
    }

    /// Strips Strong's numbers and all markup from verse text for clean display.
    static func cleanVerseText(_ raw: String) -> String {
        var t = raw
        // Remove <S>number</S> Strong's tags AND their numeric content
        if let re = try? NSRegularExpression(pattern: "<S>[^<]*</S>") {
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        }
        // Remove <WG.../WG> and <WH.../WH> prefix Strong's markers
        if let re = try? NSRegularExpression(pattern: "<W[GH][^<]*</W[GH]>") {
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        }
        // Strip remaining tags
        t = StrongsParser.stripAllTags(t)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadVerses() {
        guard let bible = myBible.selectedBible else { isLoading = false; return }
        let resolved = ScriptureReferenceParser.resolveBookNumber(ref, in: myBible)
        Task {
            let loaded = await myBible.loadChapterVerses(
                module: bible, bookNumber: resolved.bookNumber, chapter: resolved.chapter)
            await MainActor.run { verses = loaded; isLoading = false }
        }
    }
}
