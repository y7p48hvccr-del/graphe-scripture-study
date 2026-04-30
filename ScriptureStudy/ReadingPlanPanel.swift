import SwiftUI

/// Right-hand panel of the Devotional page. Shows the selected reading
/// plan's passage for today as a scrollable list of verses.
///
/// Stylistically matches DevotionalView exactly: same theme, same
/// filigree accent, same typography via @AppStorage.
///
/// The passage header ("Romans 8:1–30" etc.) is shown as plain text.
/// Individual verse numbers within the scrolling text are still tappable
/// and jump to that specific verse.
struct ReadingPlanPanel: View {

    @EnvironmentObject var myBible: MyBibleService

    @AppStorage("themeID")          private var themeID:          String = "light"
    @AppStorage("filigreeColor")    private var filigreeColor:    Int    = 0
    @AppStorage("fontSize")         private var fontSize:         Double = 16
    @AppStorage("fontName")         private var fontName:         String = ""
    @AppStorage("selectedPlanPath") private var selectedPlanPath: String = ""

    var theme:              AppTheme { AppTheme.find(themeID) }
    var filigreeAccent:     Color    { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color    { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }

    /// Plan module resolved from the stored path. Nil when no plan is
    /// picked or the chosen module is no longer installed.
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

    @State private var planEntry:    MyBibleService.PlanEntry? = nil
    @State private var planVerses:   [MyBibleVerse] = []
    @State private var isLoadingPlan = false

    var body: some View {
        VStack(spacing: 0) {
            titleStrip
            header
            Divider()

            if planModule == nil {
                emptyPlanState
            } else if isLoadingPlan {
                loadingState(text: "Loading today's reading…")
            } else if planEntry == nil {
                noEntryForToday
            } else {
                planReadingSection
            }
        }
        .background(theme.background)
        .onAppear(perform: loadTodaysPlan)
        .onChange(of: selectedPlanPath) { loadTodaysPlan() }
    }

    // MARK: - Title strip

    private var titleStrip: some View {
        HStack {
            Image(systemName: "calendar")
                .font(.system(size: 11))
                .foregroundStyle(filigreeAccent)
            Text("READING PLAN")
                .font(.caption.weight(.bold))
                .foregroundStyle(filigreeAccent)
                .tracking(1.2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(theme.background)
    }

    // MARK: - Header (plan picker + passage range label)

    private var header: some View {
        HStack(spacing: 10) {
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
            // Plain passage range label. Keep the text visible, but do
            // not make it interactive.
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

    // MARK: - Plan reading section
    //
    // Scrollable list of verses covered by today's plan entry. Each verse
    // number is tappable and jumps to that exact verse in the Bible tab.

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
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button {
                openVerseInBible(bookNumber: v.book, chapter: v.chapter, verse: v.verse)
            } label: {
                Text("\(v.verse)")
                    .font(.system(size: max(10, fontSize - 4), weight: .semibold))
                    .foregroundStyle(filigreeAccent)
            }
            .buttonStyle(.plain)
            .help("Open in Bible")

            Text(v.text)
                .font(resolvedFont)
                .foregroundStyle(theme.text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
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
    /// can span multiple chapters (e.g. Romans 1–3); we fetch each chapter
    /// and concatenate, filtering to the start/end verse range where given.
    /// Guards against inverted or zero ranges from third-party modules.
    private func loadPlanVerses(for entry: MyBibleService.PlanEntry,
                                 from bible: MyBibleModule) async -> [MyBibleVerse] {
        let startCh = entry.startChapter
        let rawEndCh = entry.endChapter ?? entry.startChapter
        let endCh    = max(rawEndCh, startCh)
        guard startCh > 0 else { return [] }
        var out: [MyBibleVerse] = []
        for chapter in startCh...endCh {
            let chapterVerses = await myBible.fetchVerses(module: bible,
                                                          bookNumber: entry.bookNumber,
                                                          chapter: chapter)
            for v in chapterVerses {
                if chapter == startCh, let sv = entry.startVerse, v.verse < sv { continue }
                if chapter == endCh,   let ev = entry.endVerse,   v.verse > ev { continue }
                out.append(v)
            }
        }
        return out
    }

    // MARK: - Navigation

    private func openVerseInBible(bookNumber: Int, chapter: Int, verse: Int) {
        NotificationCenter.default.post(
            name: .navigateToPassage, object: nil,
            userInfo: [
                "bookNumber": bookNumber,
                "chapter":    chapter,
                "verse":      verse
            ]
        )
    }

    // MARK: - Font

    private var resolvedFont: Font {
        guard !fontName.isEmpty else { return .system(size: fontSize) }
        return .custom(fontName, size: fontSize)
    }
}
