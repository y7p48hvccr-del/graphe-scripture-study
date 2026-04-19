import SwiftUI

struct CommentaryView: View {
    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("fontName") private var fontName: String = ""
    @AppStorage("themeID")  private var themeID:  String = "light"
    var resolvedFont: Font {
        guard !fontName.isEmpty else { return .system(size: fontSize) }
        return .custom(fontName, size: fontSize)
    }
    var theme: AppTheme { AppTheme.find(themeID) }

    @EnvironmentObject var myBible: MyBibleService
    @AppStorage("filigreeColor") private var filigreeColor: Int = 0
    var filigreeAccent:     Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }
    @State private var selectedCommentary: MyBibleModule?
    @State private var selectedBookNumber  = 470
    @State private var selectedChapter     = 1
    @State private var isNavigating        = false
    @State private var showSyncedBadge     = false

    var commentaries: [MyBibleModule] { myBible.visibleModules.filter { $0.type == .commentary } }

    var body: some View {
        Group {
        #if os(macOS)
        HSplitView {
            // ── Sidebar ──
            VStack(alignment: .leading, spacing: 14) {

                if commentaries.isEmpty {
                    Text("No commentary modules found.\nAdd them in the Archives tab.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("COMMENTARY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Picker("Commentary", selection: $selectedCommentary) {
                            Text("None").tag(Optional<MyBibleModule>.none)
                            ForEach(commentaries) { m in
                                Text(m.name).tag(Optional(m))
                            }
                        }
                        .labelsHidden()
                        .onAppear {
                            if selectedCommentary == nil { selectedCommentary = commentaries.first }
                        }
                        .onChange(of: selectedCommentary) {
                            guard !isNavigating else { return }
                            Task { await loadCommentary() }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("BOOK").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Picker("Book", selection: $selectedBookNumber) {
                            ForEach(myBibleBookOrder, id: \.self) { bn in
                                Text(myBibleBookNumbers[bn] ?? "\(bn)").tag(bn)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: selectedBookNumber) {
                            guard !isNavigating else { return }
                            Task { await loadCommentary() }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("CHAPTER").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Picker("Chapter", selection: $selectedChapter) {
                            ForEach(1...150, id: \.self) { ch in
                                Text("Chapter \(ch)").tag(ch)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: selectedChapter) {
                            guard !isNavigating else { return }
                            Task { await loadCommentary() }
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .frame(minWidth: 180, maxWidth: 220)

            // ── Content ──
            Group {
                if selectedCommentary == nil {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "text.quote")
                            .font(.system(size: 48)).foregroundStyle(.quaternary)
                        Text("Select a commentary module\nand passage to begin.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if myBible.commentaryEntries.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "text.quote")
                            .font(.system(size: 48)).foregroundStyle(.quaternary)
                        Text("Select a book and chapter\nto read commentary.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("\(myBibleBookNumbers[selectedBookNumber] ?? "") \(selectedChapter)")
                                    .font(resolvedFont.bold())
                                Spacer()
                                if showSyncedBadge {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.system(size: 10))
                                        Text("Synced")
                                            .font(.caption2.weight(.medium))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.green.opacity(0.8))
                                    .clipShape(Capsule())
                                    .transition(.opacity)
                                }
                            }
                            .padding(.bottom, 4)
                            if let name = selectedCommentary?.name {
                                Text(name).font(.caption).foregroundStyle(.secondary)
                                    .padding(.bottom, 20)
                            }
                            ForEach(myBible.commentaryEntries) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(verseRef(entry))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(filigreeAccentFill)
                                        .clipShape(Capsule())
                                    Text(entry.text)
                                        .font(resolvedFont).lineSpacing(6)
                                }
                                .padding(.bottom, 20)
                            }
                        }
                        .padding()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #else
        Text("Commentary not available on this platform")
        #endif
        } // end Group
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCommentary)) { note in
            handleNavigation(note)
        }
        // Sync with Bible tab when passage changes
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("biblePassageChanged"))) { note in
            guard let bookNum = note.userInfo?["bookNumber"] as? Int,
                  let chapter = note.userInfo?["chapter"]    as? Int,
                  !isNavigating else { return }

            // Auto-select first commentary if none chosen yet
            if selectedCommentary == nil {
                selectedCommentary = myBible.modules.first { $0.type == .commentary }
            }
            guard selectedCommentary != nil else { return }

            isNavigating       = true
            selectedBookNumber = bookNum
            selectedChapter    = chapter
            Task {
                await loadCommentary()
                isNavigating    = false
                withAnimation { showSyncedBadge = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { showSyncedBadge = false }
                }
            }
        }
    }

    // MARK: - Helpers

    private func verseRef(_ entry: CommentaryEntry) -> String {
        let book = myBibleBookNumbers[entry.bookNumber] ?? ""
        if entry.verseFrom == entry.verseTo {
            return "\(book) \(entry.chapterFrom):\(entry.verseFrom)"
        }
        return "\(book) \(entry.chapterFrom):\(entry.verseFrom)–\(entry.verseTo)"
    }

    private func loadCommentary() async {
        guard let module = selectedCommentary else { return }
        await myBible.loadCommentary(
            module: module,
            bookNumber: selectedBookNumber,
            chapter: selectedChapter
        )
    }

    private func handleNavigation(_ note: NotificationCenter.Publisher.Output) {
        guard let bn = note.userInfo?["bookNumber"] as? Int,
              let ch = note.userInfo?["chapter"]    as? Int else { return }

        // Suppress all onChange handlers while we set values
        isNavigating = true

        // Switch to the correct commentary module
        if let moduleName = note.userInfo?["moduleName"] as? String,
           let match = commentaries.first(where: { $0.name == moduleName }) {
            selectedCommentary = match
        } else if selectedCommentary == nil {
            selectedCommentary = commentaries.first
        }

        selectedBookNumber = bn
        selectedChapter    = ch

        // Now do a single load with all the correct values
        Task {
            await loadCommentary()
            isNavigating = false
        }
    }
}
