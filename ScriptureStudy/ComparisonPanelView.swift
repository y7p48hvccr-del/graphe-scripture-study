import SwiftUI

// MARK: - Comparison Panel View
// Shows a second Bible translation below the main reading view for side-by-side comparison

struct ComparisonPanelView: View {
    let bookNumber:  Int
    let chapter:     Int
    let syncedVerse: Int
    let onClose:     () -> Void

    @EnvironmentObject var myBible: MyBibleService

    @State private var comparisonModule: MyBibleModule? = nil
    @State private var verses:           [MyBibleVerse] = []
    @State private var isLoading = false

    @AppStorage("fontSize")      private var fontSize:      Double = 16
    @AppStorage("fontName")      private var fontName:      String = ""
    @AppStorage("themeID")       private var themeID:       String = "light"
    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0

    var theme:         AppTheme { AppTheme.find(themeID) }
    var filigreeAccent: Color   { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var resolvedFont:  Font {
        fontName.isEmpty ? .system(size: fontSize) : .custom(fontName, size: fontSize)
    }

    private var availableBibles: [MyBibleModule] {
        myBible.visibleModules.filter {
            $0.type == .bible &&
            $0.filePath != myBible.selectedBible?.filePath &&
            (myBible.selectedLanguageFilter == "all" || myBible.selectedLanguageFilter.isEmpty ||
             $0.language.lowercased() == myBible.selectedLanguageFilter)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 10) {
                Text("Compare")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Picker("", selection: $comparisonModule) {
                    Text("Choose translation…").tag(Optional<MyBibleModule>.none)
                    ForEach(availableBibles) { m in
                        Text(m.name).tag(Optional(m))
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 12))
                .frame(maxWidth: 240)

                Spacer()

                if isLoading {
                    ProgressView().controlSize(.small)
                }

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close comparison")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.platformWindowBg)

            Divider()

            // Verse list
            if verses.isEmpty && !isLoading {
                VStack {
                    Spacer()
                    Text(comparisonModule == nil
                         ? "Select a translation to compare"
                         : "No verses found")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(verses) { verse in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(verse.verse)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(
                                            verse.verse == syncedVerse
                                            ? .white
                                            : filigreeAccent.opacity(0.7)
                                        )
                                        .frame(minWidth: 18, alignment: .trailing)
                                        .padding(.horizontal, 3).padding(.vertical, 2)
                                        .background(
                                            verse.verse == syncedVerse
                                            ? filigreeAccent : Color.clear
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                    Text(verse.text)
                                        .font(resolvedFont)
                                        .foregroundStyle(theme.text)
                                        .lineSpacing(4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(
                                    verse.verse == syncedVerse
                                    ? filigreeAccent.opacity(0.08) : Color.clear
                                )
                                .id(verse.verse)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .background(Color.white)
                    .onChange(of: syncedVerse) { v in
                        if v > 0 {
                            withAnimation { proxy.scrollTo(v, anchor: .center) }
                        }
                    }
                    .onChange(of: verses) { _ in
                        if syncedVerse > 0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation { proxy.scrollTo(syncedVerse, anchor: .center) }
                            }
                        }
                    }
                }
            }
        }
        .background(theme.background)
        .onChange(of: comparisonModule) { _ in
            Task { await loadVerses() }
        }
        .onChange(of: bookNumber) { _ in
            Task { await loadVerses() }
        }
        .onChange(of: chapter) { _ in
            Task { await loadVerses() }
        }
        .onAppear {
            // Auto-select second Bible if available
            if comparisonModule == nil {
                comparisonModule = availableBibles.first
            }
            Task { await loadVerses() }
        }
    }

    private func loadVerses() async {
        guard let module = comparisonModule else { verses = []; return }
        isLoading = true
        let loaded = await myBible.loadChapterVerses(
            module: module,
            bookNumber: bookNumber,
            chapter: chapter
        )
        verses = loaded.map { v in
            MyBibleVerse(
                book: v.book,
                chapter: v.chapter,
                verse: v.verse,
                text: StrongsParser.stripAllTags(v.text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        isLoading = false
    }
}
