# DECISIONS.md update — 2026-04-22 morning

Two small edits to make in DECISIONS.md.

---

## Edit 1: append a short closing note to yesterday evening's entry

Find the `## 2026-04-21 (evening) · Cold-start performance` section. At the very end of it (after the "File recovery incident" paragraph, before the `---` separator), add:

```markdown
### Follow-up 2026-04-22 morning: 7× mystery resolved

The 7× ContentView reconstruction was caused by a conflict with the commentaries module interfering with the startup process. Resolved outside the diagnostic path we'd been following (which explains why the [STARTUP] prints couldn't pinpoint it — the cause was in a code path we hadn't instrumented). No further action needed on this thread.
```

---

## Edit 2: replace the NEXT SESSION block at the top of DECISIONS.md

Replace the existing `## NEXT SESSION (2026-04-22+)` block with this cleaned-up version:

```markdown
## NEXT SESSION

**Status: cold-start work fully closed. Editor foundation landed. Ready for the next substantive thread.**

**Cold-start fixes shipped 2026-04-21 evening:**
- `BMapsService` and `InterlinearService` moved from ContentView to App level. Single shared instances, injected as @EnvironmentObject.
- Both services have an `isLoading` flag preventing concurrent-load races past the `isLoaded` guard during the detached parse Task.
- ContentView's duplicate outer `.onAppear` removed.
- `ScriptureStudyApp`'s `if readyToShow { ContentView() }` replaced with unconditional ContentView plus overlaid splash (cleaner identity model).

**7× ContentView reconstruction (resolved 2026-04-22 morning):**
- Root cause: commentaries module interfering with startup process. Fixed outside the [STARTUP]-print diagnostic path.

**Small items still on the list (optional, non-blocking):**
- `MyBibleService.loadChapter()` could get the same `isLoading` guard treatment as BMapsService/InterlinearService. Belt-and-braces — not causing observed problems.
- ForEach duplicate-ID console warning (IDs 1–57 "occur multiple times") — some file with `ForEach(..., id: \.someInt)` where the Int isn't unique. Not VerseWithStrongsView. Needs grep hunt.
- Remove `[NOTE DEBUG]` prints once the editor has had a day or two of clean use.
- Remove `[STARTUP]` prints from BMapsService, InterlinearService, LocalBibleView, CompanionPanel now that the cold-start work is closed.

**Next editor sessions (queued):**
- **Session 2 — Live Markdown rendering.** As you type `**bold**`, the word renders bold and the asterisks grey out. Headings become bigger. Lists get bullets. Uses NSTextStorage delegate + NSLayoutManager attribute runs.
- **Session 3 — Strong's number + scripture reference auto-linking.** Inside notes, `G5485` and `John 3:16` become clickable. Hooks into existing `myBible` Strong's lookup and `navigateToPassage` notification.
- **Session 4 — Keyboard shortcuts & find/replace.** ⌘B/I/K/1/2/3, ⌘F inside note, word-count polish.
- **Session 5 — Note-to-note links, insert-passage, tags.**

**Possible next moves carried forward:**
- **Bring Bible bookmarks into the Books-tab unified panel.** Panel only surfaces EPUB and PDF bookmarks; Bible `BookmarksManager` is separate. Needs `LibraryBookmark.bible(...)` case + read path + click-to-switch-tabs.
- **Move Bible bookmark control to a window toolbar button** to match EPUB/PDF.
- Cmd-Left / Cmd-Right keyboard shortcuts for PDF prev/next.
- Clickable PDF page counter → jump-to-page field for long PDFs.
- USPTO trademark search for "Graphē One" in class 9.

**File markers still accurate:**
- `EPUBReaderView.swift` → `BOOKMARK_FIX_V9`
- `PDFReaderView.swift` → `PDF_FIX_V9`
```

---

That's it — two small paste operations. Everything else in DECISIONS.md stays as it is.
