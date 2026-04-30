# DECISIONS.md

## NEXT SESSION

**Status: cold-start work fully closed. Editor foundation landed. Ready for the next substantive thread.**

**Cold-start fixes shipped 2026-04-21 evening:**
- `BMapsService` and `InterlinearService` moved from ContentView to App level. Single shared instances, injected as `@EnvironmentObject`.
- Both services have an `isLoading` flag preventing concurrent-load races past the `isLoaded` guard during the detached parse `Task`.
- ContentView's duplicate outer `.onAppear` removed.
- `ScriptureStudyApp`'s `if readyToShow { ContentView() }` replaced with unconditional ContentView plus overlaid splash (cleaner identity model).

**7x ContentView reconstruction (resolved 2026-04-22 morning):**
- Root cause: commentaries module interfering with startup process. Fixed outside the `[STARTUP]`-print diagnostic path.

**Small items still on the list (optional, non-blocking):**
- `MyBibleService.loadChapter()` could get the same `isLoading` guard treatment as `BMapsService`/`InterlinearService`. Belt-and-braces, not causing observed problems.
- `ForEach` duplicate-ID console warning (IDs 1-57 "occur multiple times") — some file with `ForEach(..., id: \.someInt)` where the `Int` is not unique. Not `VerseWithStrongsView`. Needs grep hunt.
- Remove `[NOTE DEBUG]` prints once the editor has had a day or two of clean use.
- Remove `[STARTUP]` prints from `BMapsService`, `InterlinearService`, `LocalBibleView`, `CompanionPanel` now that the cold-start work is closed.

**Next editor sessions (queued):**
- **Session 2 — Live Markdown rendering.** As you type `**bold**`, the word renders bold and the asterisks grey out. Headings become bigger. Lists get bullets. Uses `NSTextStorage` delegate + `NSLayoutManager` attribute runs.
- **Session 3 — Strong's number + scripture reference auto-linking.** Inside notes, `G5485` and `John 3:16` become clickable. Hooks into existing `myBible` Strong's lookup and `navigateToPassage` notification.
- **Session 4 — Keyboard shortcuts & find/replace.** `Cmd-B/I/K/1/2/3`, `Cmd-F` inside note, word-count polish.
- **Session 5 — Note-to-note links, insert-passage, tags.**

**Possible next moves carried forward:**
- **Bring Bible bookmarks into the Books-tab unified panel.** Panel only surfaces EPUB and PDF bookmarks; Bible `BookmarksManager` is separate. Needs `LibraryBookmark.bible(...)` case + read path + click-to-switch-tabs.
- **Move Bible bookmark control to a window toolbar button** to match EPUB/PDF.
- `Cmd-Left` / `Cmd-Right` keyboard shortcuts for PDF prev/next.
- Clickable PDF page counter -> jump-to-page field for long PDFs.
- USPTO trademark search for "Graphē One" in class 9.

**File markers still accurate:**
- `EPUBReaderView.swift` -> `BOOKMARK_FIX_V9`
- `PDFReaderView.swift` -> `PDF_FIX_V9`

---

## 2026-04-21 (evening) · Cold-start performance — service ownership, load races, identity churn

Worked the "~10s cold start on M1" thread carried over from the afternoon session. Three independent bugs compounded; fixed two cleanly, surfaced a third as still-open.

### Diagnostic drop

Started with `[STARTUP]` prints in `BMapsService.init`, `BMapsService.loadIfNeeded`, `InterlinearService.init`, `InterlinearService.loadIfNeeded`, `LocalBibleView.onAppear`, `CompanionPanel.onAppear`. First cold-start capture showed:

- `BMapsService.init()` x 7
- `InterlinearService.init()` x 7
- `BMapsService.loadIfNeeded()` x 10 (every call saw `isLoaded=false`)
- `InterlinearService.loadIfNeeded()` x 10 (same)
- `LocalBibleView.onAppear` x 5
- `CompanionPanel.onAppear` x 7
- `[BMapsService] Loaded 15 maps, 358 places` x 14
- `[InterlinearService] Found 18 interlinear modules` x 14

14 parallel SQLite parses of the same modules on the main thread's cooperative queue. That was the 10 seconds.

### Fix 1: concurrent-load guard inside the services

`isLoaded` was only flipping inside the detached `Task` completion block, so every caller arriving before the first parse finished raced past the `guard !isLoaded` check and kicked off its own parse. Added synchronous `private var isLoading: Bool = false` (not `@Published` — avoids spurious re-renders) to both services. Set true before the `Task` launches, reset false in the `MainActor` completion block. Guard changed to `!isLoaded, !isLoading`. `@MainActor` isolation makes a plain `Bool` safe — no cross-thread race.

Result: parse count dropped from 14 to roughly 7 each (one per retained instance).

### Fix 2: service ownership moved from ContentView to App level

`BMapsService` and `InterlinearService` were the only two services declared as `@StateObject` on `ContentView`; the other eight live on `ScriptureStudyApp`. SwiftUI was reconstructing `ContentView` 7x during cold start, and each reconstruction allocated a fresh pair of services via `@StateObject`'s default expression. Moved both declarations up to `ScriptureStudyApp` alongside the other eight. Changed `ContentView`'s declarations from `@StateObject` to `@EnvironmentObject`. Added matching `.environmentObject()` injections on the `WindowGroup` `ZStack`. Removed the now-redundant injections from `ContentView`'s body.

Also found and removed a duplicate `.onAppear` on the outer `VStack` in `ContentView` — the inner `ZStack`'s `onAppear` already called both services' `loadIfNeeded`.

Result: parse count dropped from ~7 to exactly 1 each. Single shared service instance across the app lifetime.

### Fix 3 (attempted — did NOT address the root cause): splash conditional

Diagnosed the 7x `ContentView` reconstruction as being caused by the `if readyToShow { ContentView() }` wrapper in `ScriptureStudyApp.body` losing SwiftUI view identity across body re-evaluations (any `@Published` change on an App-level service causes the `WindowGroup` body to re-evaluate, and the `if` wrapper was suspected of not preserving identity through those). Restructured to keep `ContentView` unconditionally in the tree with the splash overlaid on top (with `.transition(.opacity)`). Removed the now-unused `readyToShow` state variable.

**Result after deploy: no change. `LocalBibleView.onAppear` and `CompanionPanel.onAppear` still fire 7x on cold start.** The splash conditional was not the mechanism. Leaving this restructure in place anyway — it is a cleaner identity model and shaves an empty-frame flash between splash and content — but it does not solve the 7x problem.

### Net outcome

Cold-start dramatically faster than the starting ~10s. Beachball has not returned in post-patch runs. App is stable and user-visible behaviour is correct.

The 7x `ContentView` reconstruction is still happening but no longer has the expensive consequences it did at session start — services are shared, parses are deduplicated, no user-facing symptoms. The mystery is intact but the cost is gone.

### Files changed

- `ScriptureStudyApp.swift` — added two `@StateObject` declarations for `bmapsService`/`interlinearService`, two matching `.environmentObject` injections; removed `readyToShow` state and the `if readyToShow { ContentView() }` wrapper; `ContentView` now lives unconditionally in the `ZStack` with splash overlaid above it.
- `ContentView.swift` — `@StateObject` -> `@EnvironmentObject` for `bmapsService` and `interlinearService`; removed duplicate outer `.onAppear`; removed redundant `.environmentObject` injections.
- `BMapsService.swift` — added `isLoading` flag; updated `loadIfNeeded()` guard to `!isLoaded, !isLoading`; set/reset flag around the detached parse `Task`; added flag state to diagnostic print.
- `InterlinearService.swift` — same pattern as `BMapsService`, with flag set at both scan call sites (bookmark-resolved and fallback path) and reset in the `MainActor` completion block inside `scan(in:)`.

### File recovery incident

Mid-session, `VerseWithStrongsView.swift` was accidentally deleted and was not in the local Trash (iCloud Drive deletions route to "Recently Deleted" in iCloud, not Trash). Two timestamped copies were recovered from an iCloud snapshot (17:05:29 and 19:20:00); diff confirmed byte-identical content, so either could be restored without loss. No edits were lost because the file had not been touched during the session. Project was zipped as a safety backup afterwards.

### Follow-up 2026-04-22 morning: 7x mystery resolved

The 7x `ContentView` reconstruction was caused by a conflict with the commentaries module interfering with the startup process. Resolved outside the diagnostic path we had been following, which explains why the `[STARTUP]` prints could not pinpoint it — the cause was in a code path we had not instrumented. No further action needed on this thread.
