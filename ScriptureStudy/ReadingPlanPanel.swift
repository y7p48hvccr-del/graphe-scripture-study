import SwiftUI

/// Right-hand panel of the Devotional page. Three stacked sections:
///
///   1. Plan picker (Menu)
///   2. Today's reading — the plan's passage for today, with tappable
///      verse references that load into the bottom preview
///   3. Verse preview — the whole chapter for the tapped reference,
///      scrolled so the tapped verse sits at the top. "Open in Bible →"
///      button jumps to the Bible tab at that exact passage.
///
/// Stylistically matches DevotionalView exactly: same theme, same
/// filigree accent, same typography via @AppStorage.
struct ReadingPlanPanel: View {

    @EnvironmentObject var myBible: MyBibleService

    @AppStorage("themeID")           private var themeID:      String = "light"
    @AppStorage("filigreeColor")     private var filigreeColor: Int   = 0
    @AppStorage("fontSize")          private var fontSize:     Double = 16
    @AppStorage("fontName")          private var fontName:     String = ""
    @AppStorage("selectedPlanPath")  private var selectedPlanPath: String = ""

    var theme:              AppTheme { AppTheme.find(themeID) }
    var filigreeAccent:     Color    { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color    { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }

    /// Plan module resolved from the stored path. Nil when no plan picked
    /// or when the user's chosen module is no longer installed.
    private var planModule: MyBibleModule? {
        myBible.modules.first { $0.filePath == selectedPlanPath && $0.type == .readingPlan }
    }

    private var availablePlans: [MyBibleModule] {
        myBible.modules.filter { $0.type == .readingPlan }
    }

    private var todayDayOfYear: Int {
        Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
    }

    // MARK: - Loaded state

    /// Today's plan entry. Loaded when the plan is chosen or on appear.
    @State private var planEntry:    MyBibleService.PlanEntry? = nil
    /// Verses of the plan's passage, rendered as a tappable list at the top.
    @State private var planVerses:   [MyBibleVerse] = []
    @State private var isLoadingPlan = false
    /// The chapter loaded into the bottom preview panel (nil = nothing yet).
    @State private var previewVerses: [MyBibleVerse] = []
    @State private var previewBook:   Int = 0
    @State private var previewChapter: Int = 0
    /// Verse number that was tapped — the panel auto-scrolls to align it to
    /// the top. No highlight is applied, per preference.
    @State private var previewTargetVerse: Int = 0
    @State private var isLoadingPreview = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if planModule == nil {
                emptyPlanState
            } else if isLoadingPlan {
                loadingState(text: "Loading today's reading…")
            } else if planEntry == nil {
                noEntryForToday
            } else {
                // Plan reading (top) + preview (bottom) in a vertical split.
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        planReadingSection
                            .frame(height: geo.size.height * 0.5)
                        Divider()
                        verseExpansionSection
                            .frame(height: geo.size.height * 0.5)
                    }
                }
            }
        }
        .background(theme.background)
        .onAppear(perform: loadTodaysPlan)
        .onChange(of: selectedPlanPath) { loadTodaysPlan() }
    }

    // MARK: - Header (plan picker)

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 12))
                .foregroundStyle(filigreeAccent)
            Menu {
                Button("None") { selectedPlanPath = "" }
                if !availablePlans.isEmpty { Divider() }
                ForEach(availablePlans) { plan in
                    Button(plan.name) { selectedPlanPath = plan.filePath }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(planModule?.name ?? "Choose a reading plan")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(filigreeAccent)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            Spacer()
            if let entry = planEntry {
                Text(entry.displayText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(filigreeAccent)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(theme.background)
    }

    // MARK: - Plan reading (top half)
    //
    // Renders today's passage as a scrolling list of verses. Each verse
    // number is a tap target that loads the whole chapter into the bottom
    // preview and scrolls to that verse.

    private var planReadingSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if planVerses.isEmpty {
                    Text("This plan entry has no loaded text.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.top, 12)
                } else {
                    ForEach(planVerses, id: \.verse) { v in
                        verseRow(v)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
        .background(theme.background)
    }

    @ViewBuilder
    private func verseRow(_ v: MyBibleVerse) -> some View {
        // Two elements in one line: tappable verse number (opens preview),
        // then the verse text. Kept inline so reading flows naturally.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button {
                loadPreview(bookNumber: v.book, chapter: v.chapter, verse: v.verse)
            } label: {
                Text("\(v.verse)")
                    .font(.system(size: max(10, fontSize - 4), weight: .semibold))
                    .foregroundStyle(filigreeAccent)
            }
            .buttonStyle(.plain)
            .help("Load Romans \(v.chapter):\(v.verse) below")

            Text(v.text)
                .font(resolvedFont)
                .foregroundStyle(theme.text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Preview section (bottom half)

    @ViewBuilder
    private var verseExpansionSection: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                expansionHeader
                Divider()
                if isLoadingPreview {
                    loadingState(text: "Loading chapter…")
                } else if previewVerses.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18))
                            .foregroundStyle(.quaternary)
                        Text("Tap a verse number above to load it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(previewVerses, id: \.verse) { v in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(v.verse)")
                                        .font(.system(size: max(10, fontSize - 4), weight: .semibold))
                                        .foregroundStyle(filigreeAccent)
                                    Text(v.text)
                                        .font(resolvedFont)
                                        .foregroundStyle(theme.text)
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .id(v.verse)   // enables scrollTo
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                    }
                    .onAppear { scrollToTarget(proxy: proxy) }
                    .onChange(of: previewTargetVerse) { scrollToTarget(proxy: proxy) }
                }
            }
        }
        .background(theme.background)
    }

    private var expansionHeader: some View {
        HStack(spacing: 10) {
            if !previewVerses.isEmpty {
                Text(previewHeaderText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !previewVerses.isEmpty {
                Button {
                    openInBibleTab()
                } label: {
                    HStack(spacing: 4) {
                        Text("Open in Bible")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(filigreeAccent)
                }
                .buttonStyle(.plain)
                .help("Jump to this passage in the Bible tab")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var previewHeaderText: String {
        let bookName = myBibleBookNumbers[previewBook] ?? "\(previewBook)"
        return "\(bookName) \(previewChapter)"
    }

    // MARK: - Fallback states

    private var emptyPlanState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "calendar")
                .font(.system(size: 40)).foregroundStyle(.quaternary)
            Text("No reading plan selected")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Pick a plan from the menu above.")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noEntryForToday: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 32)).foregroundStyle(.quaternary)
            Text("No entry for day \(todayDayOfYear)")
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text("This plan doesn't include a reading for today.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadingState(text: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView().controlSize(.small)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data loading

    private func loadTodaysPlan() {
        planEntry   = nil
        planVerses  = []
        guard let planModule = planModule else { return }
        guard let bibleModule = myBible.selectedBible else { return }

        isLoadingPlan = true
        let day = todayDayOfYear
        Task {
            let entry = await myBible.loadPlanEntry(day: day, from: planModule)
            var verses: [MyBibleVerse] = []
            if let e = entry {
                verses = await loadPlanVerses(for: e, from: bibleModule)
            }
            await MainActor.run {
                planEntry      = entry
                planVerses     = verses
                isLoadingPlan  = false
            }
        }
    }

    /// Expands a PlanEntry into the list of verses it covers. A plan entry
    /// can span multiple chapters (e.g. Romans 1-3); we fetch each chapter
    /// and concatenate, filtering to the start/end verse range where given.
    private func loadPlanVerses(for entry: MyBibleService.PlanEntry,
                                 from bible: MyBibleModule) async -> [MyBibleVerse] {
        let startCh = entry.startChapter
        // Some reading plan modules store an end chapter that's lower than
        // the start (data quirk / review-day row / malformed entry). Clamp
        // to at least startCh so the range below never inverts.
        let rawEndCh = entry.endChapter ?? entry.startChapter
        let endCh    = max(rawEndCh, startCh)
        guard startCh > 0 else { return [] }
        var out: [MyBibleVerse] = []
        for chapter in startCh...endCh {
            let chapterVerses = await myBible.fetchVerses(module: bible,
                                                          bookNumber: entry.bookNumber,
                                                          chapter: chapter)
            for v in chapterVerses {
                // Trim to start/end verse when specified on the first/last chapter.
                if chapter == startCh, let sv = entry.startVerse, v.verse < sv { continue }
                if chapter == endCh,   let ev = entry.endVerse,   v.verse > ev { continue }
                out.append(v)
            }
        }
        return out
    }

    private func loadPreview(bookNumber: Int, chapter: Int, verse: Int) {
        guard let bibleModule = myBible.selectedBible else { return }
        isLoadingPreview   = true
        previewBook        = bookNumber
        previewChapter     = chapter
        previewTargetVerse = verse
        Task {
            let verses = await myBible.fetchVerses(module: bibleModule,
                                                    bookNumber: bookNumber,
                                                    chapter: chapter)
            await MainActor.run {
                previewVerses    = verses
                isLoadingPreview = false
            }
        }
    }

    private func scrollToTarget(proxy: ScrollViewProxy) {
        guard previewTargetVerse > 0 else { return }
        // Small delay so the ForEach has rendered before we scroll.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation {
                proxy.scrollTo(previewTargetVerse, anchor: .top)
            }
        }
    }

    private func openInBibleTab() {
        guard !previewVerses.isEmpty else { return }
        NotificationCenter.default.post(
            name: .navigateToPassage, object: nil,
            userInfo: [
                "bookNumber": previewBook,
                "chapter":    previewChapter,
                "verse":      previewTargetVerse
            ]
        )
    }

    // MARK: - Font

    private var resolvedFont: Font {
        guard !fontName.isEmpty else { return .system(size: fontSize) }
        return .custom(fontName, size: fontSize)
    }
}
