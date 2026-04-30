import SwiftUI
#if os(macOS)
import AppKit
#endif

struct NotesView: View {

    @EnvironmentObject var notesManager:     NotesManager
    @EnvironmentObject var myBible:          MyBibleService
    @EnvironmentObject var bookmarksManager: BookmarksManager

    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("fontName")      private var fontName:     String = ""
    @AppStorage("themeID")       private var themeID:      String = "light"
    var theme: AppTheme { AppTheme.find(themeID) }
    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0

    var filigreeAccent:     Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }

    @StateObject private var editorController = NoteEditorController()

    @State private var editingTitle  = false
    @State private var draftTitle    = ""
    @State private var saveTimer:    Timer?
    @State private var showingDelete = false

    private var activeNotes: [Note] {
        notesManager.notes.filter { !$0.isArchived && $0.deletedAt == nil }
    }

    var body: some View {
        Group {
            #if os(macOS)
            HSplitView {
                sidebar
                    .frame(minWidth: 190, maxWidth: 240)

                if let note = notesManager.selectedNote {
                    editorPanel(note: note)
                } else {
                    emptyState
                }
            }
            #else
            NavigationSplitView {
                sidebar
            } detail: {
                if let note = notesManager.selectedNote { editorPanel(note: note) } else { emptyState }
            }
            #endif
        }
        .onAppear { normalizeSelection() }
        .onChange(of: notesManager.notes) { _, _ in
            normalizeSelection()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {

            // Header
            HStack {
                Text("Notes")
                    .font(.headline)
                Spacer()
                // iCloud sync indicator
                if notesManager.isUsingiCloud {
                    Group {
                        switch notesManager.syncStatus {
                        case .idle:
                            Image(systemName: "icloud")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .help("Notes syncing with iCloud")
                        case .syncing:
                            Image(systemName: "icloud.and.arrow.up")
                                .font(.system(size: 11))
                                .foregroundStyle(filigreeAccent)
                                .help("Syncing…")
                        case .error(let msg):
                            Image(systemName: "icloud.slash")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .help("iCloud error: \(msg)")
                        }
                    }
                }
                Button {
                    notesManager.createNote()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("New note")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()

            Divider()

            if activeNotes.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "note")
                        .font(.largeTitle).foregroundStyle(.quaternary)
                    Text("No notes yet")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(activeNotes) { note in
                            let isSelected = notesManager.selectedNote?.id == note.id
                            NoteRow(note: note)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected
                                              ? filigreeAccent.opacity(0.18)
                                              : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isSelected
                                                ? filigreeAccent.opacity(0.4)
                                                : Color.clear,
                                                lineWidth: 0.5)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    notesManager.selectedNote = note
                                }
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        notesManager.delete(note)
                                    }
                                }
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            Text(notesManager.isUsingiCloud ? "iCloud" : "Local storage")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Editor panel

    private func editorPanel(note: Note) -> some View {
        VStack(spacing: 0) {

            // ── Top bar ──
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    // Title
                    if editingTitle {
                        TextField("Note title", text: $draftTitle)
                            .textFieldStyle(.plain)
                            .font(.title3.weight(.semibold))
                            .onSubmit { commitTitle(note: note) }
                    } else {
                        Text(note.displayTitle)
                            .font(.title3.weight(.semibold))
                            .onTapGesture { draftTitle = note.title; editingTitle = true }
                    }
                    Spacer()
                    Text("\(note.wordCount) word\(note.wordCount == 1 ? "" : "s")")
                        .font(.caption2).foregroundStyle(.secondary)
                    // Share
                    Button { exportNote(note) } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).help("Share note as text file")
                    // Delete
                    // Lock / unlock
                    Button {
                        var u = note; u.isLocked = !note.isLocked; notesManager.save(u)
                    } label: {
                        Image(systemName: note.isLocked ? "lock.fill" : "lock.open")
                            .foregroundStyle(note.isLocked ? filigreeAccent : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(note.isLocked ? "Unlock note" : "Lock note")

                    Button(role: .destructive) { showingDelete = true } label: {
                        Image(systemName: "trash").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).help("Delete note")
                }

                // Reference row
                HStack(spacing: 8) {
                    if !note.verseReference.isEmpty {
                        // Button — tap to jump to this passage in the Bible tab
                        Button {
                            myBible.navigate(to: note.verseReference)
                            if note.bookNumber > 0,
                               note.chapterNumber > 0,
                               let verse = note.verseNumbers.first {
                                NotificationCenter.default.post(
                                    name: Notification.Name("showNotesForVerse"),
                                    object: nil,
                                    userInfo: [
                                        "bookNumber": note.bookNumber,
                                        "chapter": note.chapterNumber,
                                        "verse": verse
                                    ]
                                )
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 10))
                                Text(note.verseReference)
                                    .font(.subheadline.weight(.medium))
                                Text("→ Open in Bible")
                                    .font(.caption)
                                    .opacity(0.75)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(filigreeAccentFill)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Open \(note.verseReference) in the Bible tab")

                        // Remove link
                        Button {
                            var u = note; u.bookNumber = 0; u.chapterNumber = 0; u.verseNumbers = []; notesManager.save(u)
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain).help("Remove verse link")
                    }

                    // Suggest linking to current passage
                    if !myBible.currentPassage.isEmpty &&
                       myBible.currentPassage != note.verseReference {
                        Button {
                            var u = note
                            // Parse currentPassage to bookNumber/chapter
                            let parts = myBible.currentPassage.components(separatedBy: " ")
                            if let ch = parts.last.flatMap(Int.init) {
                                let bookName = parts.dropLast().joined(separator: " ")
                                if let bn = myBibleBookNumbers.first(where: { $0.value == bookName })?.key {
                                    u.bookNumber    = bn
                                    u.chapterNumber = ch
                                }
                            }
                            notesManager.save(u)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "link").font(.system(size: 9))
                                Text("Link to \(myBible.currentPassage)")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(filigreeAccent.opacity(0.8))
                        .help("Attach this note to the current passage")
                    }

                    Spacer()

                    Text(note.formattedDate)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            NoteEditorSurface(
                noteID: note.id,
                initialText: note.plainTextContent,
                initialAttributedText: initialAttributedEditorText(for: note),
                fontSize: fontSize,
                fontName: fontName,
                controller: editorController,
                highlight: notesManager.searchHighlight,
                isEditable: !note.isLocked,
                onTextChange: { val in
                    guard !note.isLocked else { return }
                    notesManager.searchHighlight = ""
                    var u = note
                    u.content = val
                    scheduleSave(u)
                },
                onAttributedTextChange: { attributedText in
                    guard !note.isLocked else { return }
                    notesManager.searchHighlight = ""
                    scheduleSave(richNote(from: note, attributedText: attributedText))
                }
            )
        }
        .confirmationDialog("Delete \"\(note.displayTitle)\"?",
                            isPresented: $showingDelete) {
            Button("Delete", role: .destructive) { notesManager.delete(note) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This cannot be undone.") }
        .onChange(of: note.id) { editingTitle = false }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 44)).foregroundStyle(.quaternary)
            Text("No note selected")
                .font(.title3).foregroundStyle(.secondary)
            Text("Create a new note using the pencil icon,\nor select one from the list.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers

    private func commitTitle(note: Note) {
        editingTitle = false
        let trimmed = draftTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var u = note; u.title = trimmed; notesManager.save(u)
    }

    private func scheduleSave(_ note: Note) {
        notesManager.stage(note)
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in Task { @MainActor in self.notesManager.save(note) }
        }
    }

    private func richDocument(for note: Note) -> RichNoteDocument {
        note.richDocument ?? RichNoteBridge.document(fromPlainText: note.content)
    }

    private func richNote(from note: Note, attributedText: NSAttributedString) -> Note {
        #if os(macOS)
        let document = RichNoteEditorBridge.document(from: attributedText, baseFont: resolvedEditorFont())
        var updated = note
        updated.richDocument = document
        updated.content = document.plainText
        return updated
        #else
        return note
        #endif
    }

    private func initialAttributedEditorText(for note: Note) -> NSAttributedString? {
        #if os(macOS)
        return RichNoteEditorBridge.attributedString(from: richDocument(for: note), baseFont: resolvedEditorFont())
        #else
        return nil
        #endif
    }

    #if os(macOS)
    private func resolvedEditorFont() -> NSFont {
        if !fontName.isEmpty, let font = NSFont(name: fontName, size: fontSize) {
            return font
        }
        return NSFont.systemFont(ofSize: fontSize)
    }
    #endif

    private func exportNote(_ note: Note) {
        guard let url = notesManager.exportURL(for: note) else { return }
        #if os(macOS)
        let picker = NSSharingServicePicker(items: [url])
        if let window = NSApp.keyWindow, let view = window.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
        #else
        // iOS: use UIActivityViewController
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?
            .present(av, animated: true)
        #endif
    }

    private func normalizeSelection() {
        guard !activeNotes.isEmpty else {
            notesManager.selectedNote = nil
            return
        }

        if let selected = notesManager.selectedNote,
           activeNotes.contains(where: { $0.id == selected.id }) {
            return
        }

        notesManager.selectedNote = activeNotes.first
    }
}

// MARK: - Note Row

struct NoteRow: View {
    let note: Note
    @AppStorage("filigreeColor") private var filigreeColor: Int = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var filigreeAccent:     Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.displayTitle)
                .font(.body)
                .lineLimit(1)
            HStack(spacing: 6) {
                if !note.verseReference.isEmpty {
                    Text(note.verseReference)
                        .font(.caption2)
                        .foregroundStyle(filigreeAccent)
                        .lineLimit(1)
                }
                Text(note.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
