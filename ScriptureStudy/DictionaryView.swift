import SwiftUI

struct DictionaryView: View {
    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("fontName") private var fontName: String = ""
    var resolvedFont: Font {
        guard !fontName.isEmpty else { return .system(size: fontSize) }
        return .custom(fontName, size: fontSize)
    }

    @EnvironmentObject var myBible: MyBibleService
    @AppStorage("selectedTab") private var selectedTab: Int = 0
    @State private var selectedDictionary: MyBibleModule?
    @State private var searchText     = ""
    @State private var selectedEntry: DictionaryEntry?
    @State private var searchTask:    Task<Void, Never>?
    @State private var clipboardTimer:  Timer?
    #if os(macOS)
    @State private var lastChangeCount: Int = NSPasteboard.general.changeCount
    #else
    @State private var lastChangeCount: Int = 0
    #endif

    var dictionaries: [MyBibleModule] { myBible.modules.filter { $0.type == .dictionary } }

    var body: some View {
        #if os(macOS)
        HSplitView {
            // Left: entry list
            VStack(spacing: 0) {
                // Dictionary picker
                if !dictionaries.isEmpty {
                    Picker("Dictionary", selection: $selectedDictionary) {
                        Text("Select…").tag(Optional<MyBibleModule>.none)
                        ForEach(dictionaries) { m in
                            Text(m.name).tag(Optional(m))
                        }
                    }
                    .padding(10)
                    .onChange(of: selectedDictionary) { triggerSearch() }
                    .onAppear { selectedDictionary = dictionaries.first }
                    .onAppear { startClipboardMonitor() }
                    .onDisappear { stopClipboardMonitor() }
                }

                // Search
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search topics…", text: $searchText)
                        .textFieldStyle(.plain)
                        .onChange(of: searchText) { triggerSearch() }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.platformWindowBg)

                Divider()

                // Entry list
                if myBible.dictionaryEntries.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "character.book.closed.fill")
                            .font(.largeTitle).foregroundStyle(.quaternary)
                        Text(selectedDictionary == nil
                             ? "Select a dictionary above"
                             : "No entries found")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    List(myBible.dictionaryEntries, selection: $selectedEntry) { entry in
                        Text(entry.topic)
                            .font(resolvedFont)
                            .tag(entry)
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 200, maxWidth: 260)

            // Right: definition
            Group {
                if let entry = selectedEntry {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(entry.topic)
                                .font(.title2.weight(.bold))
                            Divider()
                            Text(entry.definition)
                                .font(resolvedFont).lineSpacing(5)
                                .lineSpacing(5)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "character.book.closed")
                            .font(.system(size: 48)).foregroundStyle(.quaternary)
                        Text("Select a topic from the list\nto read its definition.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #else
        Text("Dictionary not available on this platform")
        #endif
    }

    private func startClipboardMonitor() {
        #if os(macOS)
        lastChangeCount = NSPasteboard.general.changeCount
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            let current = NSPasteboard.general.changeCount
            guard current != lastChangeCount else { return }
            lastChangeCount = current
            guard let text = NSPasteboard.general.string(forType: .string) else { return }
            // Only act on a single word (no spaces, reasonable length)
            let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let isOneWord = !word.isEmpty && word.count <= 40 && !word.contains(" ") && !word.contains("\n")
            guard isOneWord else { return }
            DispatchQueue.main.async {
                searchText = word
                selectedTab = 2   // switch to Dictionary tab
                triggerSearch()
            }
        }
        #endif
    }

    private func stopClipboardMonitor() {
        #if os(macOS)
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        #endif
    }

    private func triggerSearch() {
        searchTask?.cancel()
        guard let module = selectedDictionary else { return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            await myBible.searchDictionary(module: module, query: searchText)
        }
    }
}
