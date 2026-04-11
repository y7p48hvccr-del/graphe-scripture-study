import SwiftUI


struct ComparisonPanelView: View {
    let bookNumber:  Int
    let chapter:     Int
    let syncedVerse: Int
    var onClose: (() -> Void)? = nil

    @EnvironmentObject var myBible: MyBibleService

    @AppStorage("comparisonBiblePath") private var comparisonBiblePath: String = ""
    @AppStorage("fontSize")            private var fontSize:  Double = 16
    @AppStorage("fontName")            private var fontName:  String = ""
    @AppStorage("themeID")             private var themeID:   String = "light"
    @AppStorage("filigreeColor")       private var filigreeColor: Int = 0

    var theme:  AppTheme { AppTheme.find(themeID) }
    var accent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var resolvedFont: Font {
        guard !fontName.isEmpty else { return .system(size: fontSize - 1) }
        return .custom(fontName, size: fontSize - 1)
    }

    @State private var verses:   [MyBibleVerse] = []
    @State private var module:   MyBibleModule? = nil
    @State private var isLoading = false

    private var bibleModules: [MyBibleModule] {
        myBible.modules.filter { $0.type == .bible && $0.filePath != myBible.selectedBible?.filePath }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Picker is the header — no label needed
            HStack(spacing: 8) {
                BiblePickerButton(
                    modules: bibleModules,
                    selected: $module,
                    accent: accent,
                    textColor: Color.primary
                )
                .onChange(of: module) { _ in load() }
                .onAppear { if module == nil { module = bibleModules.first } }
                Spacer()
                if isLoading { ProgressView().controlSize(.mini) }
                if let close = onClose {
                    Button { close() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close comparison")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.platformWindowBg)

            Divider()

            if module == nil {
                VStack { Spacer(); Text("Select a Bible above").font(.caption).foregroundStyle(.secondary); Spacer() }
                    .background(theme.background)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(verses) { verse in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("\(verse.verse)")
                                        .font(.system(size: fontSize * 0.75))
                                        .foregroundStyle(accent)
                                        .frame(minWidth: 24, alignment: .trailing)
                                        .padding(.top, 2)
                                    Text(ScriptureSlideUpPanel.cleanVerseText(verse.text))
                                        .font(resolvedFont)
                                        .foregroundStyle(theme.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 3)
                                .background(verse.verse == syncedVerse ? accent.opacity(0.08) : Color.clear)
                                .id(verse.verse)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .background(theme.background)
                    // Sync scroll when user taps a verse in the main panel
                    .onChange(of: syncedVerse) { v in
                        if v > 0 { withAnimation { proxy.scrollTo(v, anchor: .top) } }
                    }
                    .onChange(of: chapter) { _ in load() }
                    // Sync scroll as user scrolls the main Bible panel
                    .onReceive(NotificationCenter.default.publisher(
                        for: Notification.Name("verseScrolledIntoView"))) { note in
                        guard
                            let bn = note.userInfo?["bookNumber"] as? Int,
                            let ch = note.userInfo?["chapter"]    as? Int,
                            let vs = note.userInfo?["verse"]      as? Int,
                            bn == bookNumber, ch == chapter
                        else { return }
                        proxy.scrollTo(vs, anchor: .top)
                    }
                }
            }
        }
        .background(theme.background)
        .onAppear { load() }
    }

    private func load() {
        guard let mod = module else { return }
        isLoading = true
        Task {
            let loaded = await myBible.loadChapterVerses(module: mod,
                                                          bookNumber: bookNumber,
                                                          chapter: chapter)
            await MainActor.run {
                verses    = loaded
                isLoading = false
            }
        }
    }
}
