import SwiftUI
import EventKit
import SQLite3

// MARK: - Organizer View

struct OrganizerView: View {

    @EnvironmentObject var notesManager:     NotesManager
    @EnvironmentObject var myBible:          MyBibleService
    @EnvironmentObject var calendarStore:    CalendarEventStore

    @AppStorage("organizerPlanStart") private var planStartISO: String = ""
    @AppStorage("selectedPlanPath")   private var selectedPlanPath: String = ""
    @AppStorage("completedDays")      private var completedDaysData: String = ""

    @State private var selectedDate:    Date = Date()
    @State private var showingPopover:   Bool = false
    @State private var popoverDay:       Date = Date()
    @State private var newEventText:     String = ""
    @State private var newEventType:     CalendarEventType = .prayer
    @State private var newEventRepeat:   CalendarRepeat = .once
    @State private var currentMonth:    Date = Date()
    @State private var dayDetail:       DayDetail? = nil
    @State private var isLoadingDetail: Bool = false
    @State private var completedDays:   Set<Int> = []
    @State private var organizerSaveTimer: Timer? = nil
    @State private var organizerNote: Note? = nil
    @StateObject private var editorController  = NoteEditorController()

    // Calendar colours
    let calRed    = Color(red: 0.90, green: 0.15, blue: 0.15)
    let calBlue   = Color(red: 0.20, green: 0.45, blue: 0.85)
    let calYellow = Color(red: 0.95, green: 0.75, blue: 0.10)
    let calGreen  = Color(red: 0.20, green: 0.72, blue: 0.35)
    let calBg     = Color.white

    var planModule: MyBibleModule? {
        myBible.modules.first { $0.filePath == selectedPlanPath && $0.type == .readingPlan }
        ?? myBible.modules.first { $0.type == .readingPlan }
    }

    var body: some View {
        HStack(spacing: 0) {
            // ── LEFT: Calendar top ~60%, people portraits bottom ~40%
            VStack(spacing: 0) {
                calendarSection
                Rectangle()
                    .fill(Color(red: 0.75, green: 0.65, blue: 0.35).opacity(0.5))
                    .frame(height: 1)
                PeoplePanel()
                    .frame(minHeight: 180)
            }
            .frame(width: 340)
            .background(Color(red: 1.0, green: 0.96, blue: 0.80))

            Divider()

            // ── RIGHT: Day detail ───────────────────────────────────
            dayDetailSection
                .frame(maxWidth: .infinity)
                .background(Color(red: 1.0, green: 0.96, blue: 0.80))
        }
        .onAppear {
            loadCompletedDays()
            loadDayDetail(for: selectedDate)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("noteCreatedFromVerse"))) { note in
            if let noteObj = note.userInfo?["note"] as? Note {
                organizerNote = noteObj
            }
        }
        .onChange(of: notesManager.selectedNote) { note in
            // When a note is newly created (selectedNote changes), update organizer editor
            if let note = note, organizerNote == nil || note.id != organizerNote?.id {
                // Only show notes that were created from a verse (have book reference)
                if note.bookNumber > 0 {
                    organizerNote = note
                }
            }
        }
    }



    // MARK: - Calendar section

    private var calendarSection: some View {
        VStack(spacing: 0) {
            calendarHeader
            Divider()
            weekdayRow
            Divider()
            calendarGrid
        }
        .background(Color.clear)
    }

    private var calendarHeader: some View {
        HStack(spacing: 0) {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(calRed)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            // "I'm organised!" + month title
            HStack(spacing: 8) {
                Text("I'm organised!")
                    .font(.system(size: 11, weight: .semibold))
                    .italic()
                    .foregroundStyle(calRed.opacity(0.7))
                    .fixedSize()
                Text(monthTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)

            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(calRed)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            Button("Today") {
                selectedDate  = Date()
                currentMonth  = Date()
                loadDayDetail(for: selectedDate)
            }
            .font(.system(size: 12, weight: .semibold))
            .help("Jump to today")
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(calRed)
            .clipShape(Capsule())
            #if os(macOS)
            HelpButton(page: "organizer", anchor: "calendar")
            .padding(.trailing, 12)
            #endif
        }
        .padding(.vertical, 6)
        .background(Color.clear)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { day in
                Text(day)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(day == "Sun" || day == "Sat" ? calRed.opacity(0.6) : Color(white: 0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .background(Color(white: 0.97))
    }

    private var calendarGrid: some View {
        let days = calendarDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date = date {
                    CalendarDayCell(
                        date:           date,
                        isToday:        Calendar.current.isDateInToday(date),
                        isSelected:     Calendar.current.isDate(date, inSameDayAs: selectedDate),
                        isCurrentMonth: Calendar.current.isDate(date, equalTo: currentMonth, toGranularity: .month),
                        hasReadingPlan: hasPlanEntry(for: date),
                        hasEvents:      calendarStore.hasEvents(on: date),
                        isComplete:     isDayComplete(date),
                        calRed:         calRed,
                        calBlue:        calBlue,
                        calYellow:      calYellow,
                        calGreen:       calGreen
                    ) {
                        selectedDate = date
                        loadDayDetail(for: date)
                    }
                    .popover(isPresented: Binding(
                        get: { showingPopover && Calendar.current.isDate(popoverDay, inSameDayAs: date) },
                        set: { if !$0 { showingPopover = false } }
                    ), arrowEdge: .bottom) {
                        DayPopoverView(
                            date:          date,
                            calendarStore: calendarStore,
                            newEventText:  $newEventText,
                            newEventType:  $newEventType,
                            newEventRepeat: $newEventRepeat,
                            calRed:        calRed,
                            calBlue:       calBlue
                        )
                        .frame(width: 300)
                    }
                    .onLongPressGesture(minimumDuration: 0.3) {
                        popoverDay     = date
                        newEventText   = ""
                        newEventType   = .prayer
                        newEventRepeat = .once
                        showingPopover = true
                    }
                } else {
                    Color.clear.frame(height: 52)
                }
            }
        }
        .background(Color.clear)
    }

    // MARK: - Day detail section

    private var dayDetailSection: some View {
        VStack(spacing: 0) {
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Day header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dayHeaderTitle)
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(.black)
                        Text(daySubtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(white: 0.5))
                    }
                    Spacer()
                    Text("I'm organised!")
                        .font(.custom("Chalkduster", size: 12))
                        .foregroundStyle(calBlue.opacity(0.8))
                        .fixedSize()
                    Spacer()
                    if isDayComplete(selectedDate) {
                        Label("Complete", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(calGreen)
                    } else {
                        Button {
                            markComplete(selectedDate)
                        } label: {
                            Label("Mark Complete", systemImage: "circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(calBlue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 14)

                Divider()

                if isLoadingDetail {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(40)
                } else if let detail = dayDetail {
                    // Reading plan card
                    DetailCard(color: calBlue) {
                        VStack(alignment: .leading, spacing: 10) {
                            // Plan picker
                            HStack {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(calBlue)
                                Text("Reading Plan")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(calBlue)
                                    .textCase(.uppercase)
                                Spacer()
                                planPicker
                            }
                            if let plan = detail.planEntry {
                                HStack(alignment: .center) {
                                    Text(plan.displayText)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.black)
                                    Spacer()
                                    Button {
                                        navigateToPlan(plan)
                                    } label: {
                                        Text("Read →")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(calBlue)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                Text("No reading plan entry for this day")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(white: 0.6))
                            }
                        }
                    }





                    // Prayer list card
                    daySummaryCard


                }

                Spacer().frame(height: 16)
            }
          }

          // ── Note editor below prayer list ──────────────────────
          Divider()
          noteEditorSection
        }
        .background(Color.clear)
    }


    // MARK: - Note editor (bottom of right panel)

    private var noteEditorSection: some View {
        VStack(spacing: 0) {
            // Note title header
            HStack {
                Image(systemName: "note.text")
                    .font(.system(size: 11)).foregroundStyle(calBlue)
                Text(organizerNote?.displayTitle ?? "No note selected")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(calBlue)
                    .lineLimit(1)
                Spacer()
                if let note = organizerNote {
                    Button {
                        notesManager.delete(note)
                        organizerNote = nil
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Permanently delete this note")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color(red: 1.0, green: 0.98, blue: 0.92))

            Divider()

            // Editor
            if let note = organizerNote {
                NoteTextEditor(
                    noteID:      note.id,
                    initialText: note.content,
                    onTextChange: { val in
                        var u = note; u.content = val
                        organizerSaveTimer?.invalidate()
                        organizerSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
                            Task { @MainActor in self.notesManager.save(u) }
                        }
                    },
                    fontSize:    16,
                    fontName:    "",
                    controller:  editorController,
                    isEditable:  true
                )
                .id(note.id)
                .background(calBg)
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "note.text")
                        .font(.system(size: 28)).foregroundStyle(Color(white: 0.85))
                    Text("Long-press a verse number\nto create a note here")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.6))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(calBg)
            }
        }
    }


    // MARK: - Day summary card (replaces prayer card)

    private var daySummaryCard: some View {
        let todayEvents = calendarStore.events(for: selectedDate)
        return DetailCard(color: Color(red: 0.55, green: 0.15, blue: 0.85)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("TODAY")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(red: 0.45, green: 0.1, blue: 0.75))
                    Spacer()
                    Button {
                        popoverDay     = selectedDate
                        newEventText   = ""
                        showingPopover = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(red: 0.45, green: 0.1, blue: 0.75))
                    }
                    .buttonStyle(.plain)
                    .help("Add a prayer request or reminder for this day")
                }

                if todayEvents.isEmpty {
                    Text("Nothing scheduled")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.65))
                } else {
                    ForEach(todayEvents) { event in
                        HStack(spacing: 6) {
                            Text(event.symbol)
                                .font(.system(size: 13))
                            Text(event.text)
                                .font(.system(size: 13))
                                .foregroundStyle(event.isDone ? Color(white: 0.6) : .black)
                                .strikethrough(event.isDone)
                                .lineLimit(1)
                            Spacer()
                            if event.repeatRule != .once {
                                Text(event.repeatRule.rawValue)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.6))
                            }
                            Button {
                                calendarStore.toggle(event)
                            } label: {
                                Image(systemName: event.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(event.isDone ? calGreen : Color(white: 0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Prayer card (legacy - kept for reference)

    // MARK: - Calendar helpers

    private var weekdaySymbols: [String] {
        ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: currentMonth)
    }

    private var dayHeaderTitle: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: selectedDate)
    }

    private var daySubtitle: String {
        if Calendar.current.isDateInToday(selectedDate) { return "Today" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "Yesterday" }
        if Calendar.current.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        return ""
    }

    private func shiftMonth(_ delta: Int) {
        currentMonth = Calendar.current.date(byAdding: .month, value: delta, to: currentMonth) ?? currentMonth
    }

    private func calendarDays() -> [Date?] {
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth))!
        let range = cal.range(of: .day, in: .month, for: startOfMonth)!

        // Monday-first weekday offset
        var firstWeekday = cal.component(.weekday, from: startOfMonth) - 2 // 0=Mon
        if firstWeekday < 0 { firstWeekday = 6 }

        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        for d in range {
            days.append(cal.date(byAdding: .day, value: d - 1, to: startOfMonth))
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    // MARK: - Plan helpers

    private func dayOfYear(for date: Date) -> Int {
        Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
    }

    private func hasPlanEntry(for date: Date) -> Bool {
        planModule != nil
    }

    private var planPicker: some View {
        let mods = myBible.modules.filter { $0.type == .readingPlan }
        let label = planModule?.name ?? "None"
        return Menu {
            Button("None") { selectedPlanPath = "" }
            Divider()
            ForEach(mods) { m in
                Button(m.name) {
                    selectedPlanPath = m.filePath
                    loadDayDetail(for: selectedDate)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(calBlue)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(calBlue)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(calBlue.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .menuStyle(.borderlessButton)
    }

    private func navigateToPlan(_ plan: PlanEntry) {
        NotificationCenter.default.post(
            name: .navigateToPassage, object: nil,
            userInfo: ["bookNumber": plan.bookNumber, "chapter": plan.startChapter])
    }

    // MARK: - Completion tracking

    private func isDayComplete(_ date: Date) -> Bool {
        completedDays.contains(dayOfYear(for: date))
    }

    private func markComplete(_ date: Date) {
        let d = dayOfYear(for: date)
        if completedDays.contains(d) { completedDays.remove(d) }
        else { completedDays.insert(d) }
        saveCompletedDays()
    }

    private func loadCompletedDays() {
        completedDays = Set(completedDaysData.split(separator: ",").compactMap { Int($0) })
    }

    private func saveCompletedDays() {
        completedDaysData = completedDays.map(String.init).joined(separator: ",")
    }

    // MARK: - Prayer helpers


    // MARK: - Day detail loading

    private func loadDayDetail(for date: Date) {
        isLoadingDetail = true
        let dayNum = dayOfYear(for: date)

        Task {
            // Load devotional title
            let devTitle: String?
            if myBible.selectedDevotional != nil {
                let entry = await myBible.fetchDevotionalEntry(day: dayNum)
                devTitle = entry?.title
            } else {
                devTitle = nil
            }

            // Load reading plan entry
            let planEntry: PlanEntry? = await loadPlanEntry(day: dayNum)

            await MainActor.run {
                dayDetail = DayDetail(
                    date:           date,
                    devotionalTitle: devTitle,
                    planEntry:      planEntry
                )
                isLoadingDetail = false
            }
        }
    }

    private func loadPlanEntry(day: Int) async -> PlanEntry? {
        guard let module = planModule else { return nil }
        return await Task.detached(priority: .userInitiated) {
            var db: OpaquePointer?
            guard sqlite3_open_v2(module.filePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
            else { return nil }
            defer { sqlite3_close(db) }

            var stmt: OpaquePointer?
            let sql = "SELECT book_number, start_chapter, start_verse, end_chapter, end_verse FROM reading_plan WHERE day=? AND book_number != 'day' LIMIT 1"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_int(stmt, 1, Int32(day))
            guard sqlite3_step(stmt) == SQLITE_ROW else { sqlite3_finalize(stmt); return nil }

            let bookNum    = Int(sqlite3_column_int(stmt, 0))
            let startCh    = Int(sqlite3_column_int(stmt, 1))
            let startVs    = sqlite3_column_type(stmt, 2) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 2)) : nil
            let endCh      = sqlite3_column_type(stmt, 3) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 3)) : nil
            let endVs      = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 4)) : nil
            sqlite3_finalize(stmt)

            let bookName = myBibleBookNumbers[bookNum] ?? "\(bookNum)"
            var display  = "\(bookName) \(startCh)"
            if let sv = startVs { display += ":\(sv)" }
            if let ec = endCh, let ev = endVs { display += " – \(bookName) \(ec):\(ev)" }

            return PlanEntry(bookNumber: bookNum, startChapter: startCh, displayText: display)
        }.value
    }
}

// MARK: - Portrait Panel

/// Stores portrait image data for 6 slots in UserDefaults
final class PortraitStore: ObservableObject {
    static let shared = PortraitStore()
    private let key = "organizerPortraits"

    @Published var images: [Int: NSImage] = [:]

    init() { load() }

    func set(_ image: NSImage, slot: Int) {
        images[slot] = image
        save()
    }

    func clear(slot: Int) {
        images.removeValue(forKey: slot)
        save()
    }

    private func save() {
        var dict: [String: Data] = [:]
        for (slot, img) in images {
            if let tiff = img.tiffRepresentation,
               let bmp  = NSBitmapImageRep(data: tiff),
               let png  = bmp.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                dict["\(slot)"] = png
            }
        }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: Data].self, from: data)
        else { return }
        for (k, v) in dict {
            if let slot = Int(k), let img = NSImage(data: v) {
                images[slot] = img
            }
        }
    }
}

struct PeoplePanel: View {
    @StateObject private var store = PortraitStore.shared
    private let slots = [0, 1, 2, 3, 4, 5]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width  / 2
            let h = geo.size.height / 3
            ZStack {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        PortraitSlot(slot: 0, store: store, w: w, h: h)
                        Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 0.5)
                        PortraitSlot(slot: 1, store: store, w: w, h: h)
                    }
                    Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 0.5)
                    HStack(spacing: 0) {
                        PortraitSlot(slot: 2, store: store, w: w, h: h)
                        Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 0.5)
                        PortraitSlot(slot: 3, store: store, w: w, h: h)
                    }
                    Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 0.5)
                    HStack(spacing: 0) {
                        PortraitSlot(slot: 4, store: store, w: w, h: h)
                        Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 0.5)
                        PortraitSlot(slot: 5, store: store, w: w, h: h)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
            }
        }
        .background(Color(red: 1.0, green: 0.96, blue: 0.80))
    }
}

struct PortraitSlot: View {
    let slot:  Int
    @ObservedObject var store: PortraitStore
    let w: CGFloat
    let h: CGFloat

    @State private var isTargeted = false
    @State private var showingPicker = false

    var body: some View {
        ZStack {
            if let img = store.images[slot] {
                // Filled — show photo
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: w, height: h)
                    .clipped()
                    .contextMenu {
                        Button(role: .destructive) {
                            store.clear(slot: slot)
                        } label: {
                            Label("Remove Photo", systemImage: "trash")
                        }
                    }
                    .onDrag {
                        // Allow dragging photo out (e.g. to Trash or Finder)
                        let provider = NSItemProvider()
                        if let tiff = img.tiffRepresentation,
                           let bmp  = NSBitmapImageRep(data: tiff),
                           let png  = bmp.representation(using: .png, properties: [:]) {
                            provider.registerDataRepresentation(
                                forTypeIdentifier: "public.png",
                                visibility: .all) { completion in
                                completion(png, nil)
                                return nil
                            }
                        }
                        return provider
                    }
            } else {
                // Empty — placeholder
                Rectangle()
                    .fill(isTargeted
                          ? Color.black.opacity(0.06)
                          : Color(red: 1.0, green: 0.96, blue: 0.80))
                    .frame(width: w, height: h)

                VStack(spacing: 6) {
                    FacePlaceholderIcon()
                        .frame(width: 44, height: 44)
                    Text("Drop here")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.5))
                }
            }
        }
        .frame(width: w, height: h)
        .contentShape(Rectangle())
        // Click to pick from file
        .onTapGesture {
            if store.images[slot] == nil { pickImage() }
        }
        // Drag & drop
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .help(store.images[slot] == nil ? "Click or drag a photo here" : "")
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff, .bmp]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url,
           let img = NSImage(contentsOf: url) {
            store.set(img, slot: slot)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // Try file URL first
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                else { url = nil }
                if let url, let img = NSImage(contentsOf: url) {
                    DispatchQueue.main.async { store.set(img, slot: slot) }
                }
            }
            return true
        }
        // Try raw image
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.image") }) {
            provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                if let data, let img = NSImage(data: data) {
                    DispatchQueue.main.async { store.set(img, slot: slot) }
                }
            }
            return true
        }
        return false
    }
}

// MARK: - Face Placeholder Icon

struct FacePlaceholderIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            let cx = s / 2, cy = s / 2
            let r = s * 0.46

            // Head outline
            var head = Path()
            head.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            ctx.stroke(head, with: .color(Color(white: 0.72)), lineWidth: 1.0)

            // Eyes
            let eyeY = cy - r * 0.18
            let eyeR: CGFloat = r * 0.10
            let eyeOff = r * 0.28
            for ex in [cx - eyeOff, cx + eyeOff] {
                var eye = Path()
                eye.addEllipse(in: CGRect(x: ex - eyeR, y: eyeY - eyeR, width: eyeR*2, height: eyeR*2))
                ctx.stroke(eye, with: .color(Color(white: 0.72)), lineWidth: 1.0)
            }

            // Nose — small vertical line
            var nose = Path()
            nose.move(to: CGPoint(x: cx, y: cy + r * 0.05))
            nose.addLine(to: CGPoint(x: cx, y: cy + r * 0.22))
            ctx.stroke(nose, with: .color(Color(white: 0.72)), lineWidth: 1.0)

            // Mouth — simple arc
            var mouth = Path()
            let mouthY = cy + r * 0.38
            mouth.move(to: CGPoint(x: cx - r * 0.22, y: mouthY))
            mouth.addQuadCurve(
                to:      CGPoint(x: cx + r * 0.22, y: mouthY),
                control: CGPoint(x: cx, y: mouthY + r * 0.14)
            )
            ctx.stroke(mouth, with: .color(Color(white: 0.72)), lineWidth: 1.0)

            // Shoulders / neck suggestion
            var neck = Path()
            neck.move(to: CGPoint(x: cx, y: cy + r))
            neck.addLine(to: CGPoint(x: cx, y: cy + r * 1.22))
            neck.move(to: CGPoint(x: cx - r * 0.55, y: cy + r * 1.5))
            neck.addQuadCurve(
                to: CGPoint(x: cx + r * 0.55, y: cy + r * 1.5),
                control: CGPoint(x: cx, y: cy + r * 1.28)
            )
            ctx.stroke(neck, with: .color(Color(white: 0.72)), lineWidth: 1.0)
        }
    }
}

// MARK: - Supporting models

struct DayDetail {
    let date:            Date
    let devotionalTitle: String?
    let planEntry:       PlanEntry?
}

struct PlanEntry {
    let bookNumber:   Int
    let startChapter: Int
    let displayText:  String
}

struct PrayerItem: Identifiable, Codable {
    var id:     UUID   = UUID()
    var text:   String
    var isDone: Bool   = false
}

// MARK: - Calendar day cell

struct CalendarDayCell: View {
    let date:           Date
    let isToday:        Bool
    let isSelected:     Bool
    let isCurrentMonth: Bool
    let hasReadingPlan: Bool
    let hasEvents:      Bool
    let isComplete:     Bool
    let calRed:         Color
    let calBlue:        Color
    let calYellow:      Color
    let calGreen:       Color
    let onTap:          () -> Void

    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(isToday ? calRed : Color(white: 0.88))
                            .frame(width: 32, height: 32)
                    } else if isToday {
                        Circle()
                            .stroke(calRed, lineWidth: 2)
                            .frame(width: 32, height: 32)
                    }
                    Text("\(dayNumber)")
                        .font(.system(size: 14, weight: isToday || isSelected ? .bold : .regular))
                        .foregroundStyle(
                            isSelected && isToday ? .white :
                            isToday ? calRed :
                            isCurrentMonth ? .black : Color(white: 0.75)
                        )
                }

                // Indicator dots
                HStack(spacing: 3) {
                    if isComplete {
                        Circle().fill(calGreen).frame(width: 5, height: 5)
                    } else {
                        if hasReadingPlan {
                            Circle().fill(calBlue).frame(width: 5, height: 5)
                        }

                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                isSelected && !isToday
                ? Color(white: 0.93)
                : Color.clear
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail card

struct DetailCard<Content: View>: View {
    let color:   Color
    let content: () -> Content

    init(color: Color, @ViewBuilder content: @escaping () -> Content) {
        self.color   = color
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(height: 3)
            content()
                .padding(16)
                .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}
