# DECISIONS.md addition — 2026-04-21 evening session

Paste this block into `DECISIONS.md` immediately BEFORE the existing `## 2026-04-21 (late)` entry. Also update the NEXT SESSION block at the top (see bottom of this file for the replacement text).

---

## 2026-04-21 (evening) · Cold-start performance — service ownership, load races, identity churn

Worked the "~10s cold start on M1" thread carried over from the afternoon session. Three independent bugs compounded; fixed two cleanly, surfaced a third as still-open.

### Diagnostic drop

Started with `[STARTUP]` prints in `BMapsService.init`, `BMapsService.loadIfNeeded`, `InterlinearService.init`, `InterlinearService.loadIfNeeded`, `LocalBibleView.onAppear`, `CompanionPanel.onAppear`. First cold-start capture showed:

- `BMapsService.init()` × 7
- `InterlinearService.init()` × 7
- `BMapsService.loadIfNeeded()` × 10 (every call saw `isLoaded=false`)
- `InterlinearService.loadIfNeeded()` × 10 (same)
- `LocalBibleView.onAppear` × 5
- `CompanionPanel.onAppear` × 7
- `[BMapsService] Loaded 15 maps, 358 places` × 14
- `[InterlinearService] Found 18 interlinear modules` × 14

14 parallel SQLite parses of the same modules on the main thread's cooperative queue. That was the 10 seconds.

### Fix 1: concurrent-load guard inside the services

`isLoaded` was only flipping inside the detached Task's completion block, so every caller arriving before the first parse finished raced past the `guard !isLoaded` check and kicked off its own parse. Added synchronous `private var isLoading: Bool = false` (not @Published — avoids spurious re-renders) to both services. Set true before the Task launches, reset false in the MainActor completion block. Guard changed to `!isLoaded, !isLoading`. `@MainActor` isolation makes a plain Bool safe — no cross-thread race.

Result: parse count dropped from 14 to roughly 7 each (one per retained instance).

### Fix 2: service ownership moved from ContentView to App level

`BMapsService` and `InterlinearService` were the only two services declared as `@StateObject` on `ContentView`; the other eight live on `ScriptureStudyApp`. SwiftUI was reconstructing ContentView 7× during cold start, and each reconstruction allocated a fresh pair of services via `@StateObject`'s default expression. Moved both declarations up to `ScriptureStudyApp` alongside the other eight. Changed ContentView's declarations from `@StateObject` to `@EnvironmentObject`. Added matching `.environmentObject()` injections on the WindowGroup ZStack. Removed the now-redundant injections from ContentView's body.

Also found and removed a duplicate `.onAppear` on the outer VStack in ContentView — the inner ZStack's onAppear already called both services' `loadIfNeeded`.

Result: parse count dropped from ~7 to exactly 1 each. Single shared service instance across the app lifetime.

### Fix 3 (attempted — did NOT address the root cause): splash conditional

Diagnosed the 7× ContentView reconstruction as being caused by the `if readyToShow { ContentView() }` wrapper in `ScriptureStudyApp.body` losing SwiftUI view identity across body re-evaluations (any `@Published` change on an App-level service causes the WindowGroup body to re-evaluate, and the `if` wrapper was suspected of not preserving identity through those). Restructured to keep ContentView unconditionally in the tree with the splash overlaid on top (with `.transition(.opacity)`). Removed the now-unused `readyToShow` state variable.

**Result after deploy: no change. `LocalBibleView.onAppear` and `CompanionPanel.onAppear` still fire 7× on cold start.** The splash conditional was not the mechanism. Leaving this restructure in place anyway — it's a cleaner identity model and shaves an empty-frame flash between splash and content — but it does not solve the 7× problem.

### Net outcome

Cold-start dramatically faster than the starting ~10s. Beachball has not returned in post-patch runs. App is stable and user-visible behaviour is correct.

The 7× ContentView reconstruction is still happening but no longer has the expensive consequences it did at session start — services are shared, parses are deduplicated, no user-facing symptoms. The mystery is intact but the cost is gone.

### Files changed

- `ScriptureStudyApp.swift` — added two @StateObject declarations for bmapsService/interlinearService, two matching .environmentObject injections; removed `readyToShow` state and the `if readyToShow { ContentView() }` wrapper; ContentView now lives unconditionally in the ZStack with splash overlaid above it.
- `ContentView.swift` — @StateObject → @EnvironmentObject for bmapsService and interlinearService; removed duplicate outer `.onAppear`; removed redundant `.environmentObject` injections.
- `BMapsService.swift` — added `isLoading` flag; updated `loadIfNeeded()` guard to `!isLoaded, !isLoading`; set/reset flag around the detached parse Task; added flag state to diagnostic print.
- `InterlinearService.swift` — same pattern as BMapsService, with flag set at both scan call sites (bookmark-resolved and fallback path) and reset in the MainActor completion block inside `scan(in:)`.

### File recovery incident

Mid-session, `VerseWithStrongsView.swift` was accidentally deleted and was not in the local Trash (iCloud Drive deletions route to "Recently Deleted" in iCloud, not Trash). Two timestamped copies were recovered from an iCloud snapshot (17:05:29 and 19:20:00); diff confirmed byte-identical content, so either could be restored without loss. No edits were lost because the file had not been touched during the session. Project was zipped as a safety backup afterwards.

---

## Still open — carry into next session

### 7× ContentView reconstruction (low user-facing impact)

`LocalBibleView.onAppear` still fires 7×. `CompanionPanel.onAppear` still fires 7×. `[MyBible] verses set: count=31` fires 14× (so 7 ContentViews × 2 loadChapter calls each — there's also a separate duplicate-load path inside LocalBibleView that this count exposes). The mechanism is not the splash conditional. Remaining candidates:

- Something in ContentView's own body or modifiers causing self-reconstruction. Would be exposed by adding a print statement inside ContentView's `init()` — if that fires 7× we're looking at struct-construction, if it fires 1× we're looking at onAppear firing multiple times on a single retained instance (different bug, different fix).
- The `WindowAccessor` in the `.background` modifier calls its callback inside `updateNSView`, which fires on every SwiftUI update. Not obviously causing reconstruction but worth ruling out.
- Something in `SummaryStatusStrip` or the `FiligreeDecoration` at the top of ContentView's body reacting to @Published churn.

**First thing to try next session:** add `print("[INIT] ContentView.init")` inside ContentView's `init()` method (add one if there isn't one), and `print("[BODY] ContentView.body")` as a side effect at the top of the body computed property. Re-run. Distinguishes struct construction from body re-eval from onAppear reentry — each points to a different fix.

### MyBibleService loadChapter isLoading guard (belt-and-braces)

Not observed causing problems, but the same concurrent-call race pattern that bit BMapsService and InterlinearService could exist in `MyBibleService.loadChapter()` — tab switches, history navigation, and multiple LocalBibleView instances all trigger it. Service file was uploaded but not yet inspected. If it uses an `isLoaded`-style pattern, apply the same `isLoading` guard treatment.

### ForEach duplicate-ID warning (cosmetic log noise, may mask real bugs)

Console emits `ForEach<Array<MyBibleVerse>, Int, ...> the ID 1 occurs multiple times within the collection` (and 2, 3, 4 ... 57) during rendering. The surrounding generic signature (`HStack<(HelpView<Button<Text>>, ModifiedContent<Text, ...>)>`) does NOT match VerseWithStrongsView's ForEach (which uses `UUID` ids on `WordToken` and `ForEach(Array(notes.enumerated()), id: \.element.id)`). Source is some other file — likely a chapter-level iteration that accidentally uses `id: \.someInt` where `someInt` isn't actually unique across the collection. `id: \.self` on a `MyBibleVerse` would fall back to `Int` via a `Hashable` witness that only hashes the verse number — plausible culprit. Hunt requires grepping the codebase for `ForEach(.*verses)` patterns.

---

## NEXT SESSION block replacement (top of DECISIONS.md)

Replace the existing `## NEXT SESSION (2026-04-22+)` block with this:

```markdown
## NEXT SESSION (2026-04-22+)

**Status: editor foundation landed, cold-start dramatically improved, beachball eliminated. Session 1 of the serious notetaking project verified working. Session 2 of cold-start work landed three fixes and surfaced one open mystery.**

**Cold-start state — what landed 2026-04-21 evening:**
- `BMapsService` and `InterlinearService` now owned at App level (were at ContentView). Single shared instances, injected as @EnvironmentObject.
- Both services have an `isLoading` flag preventing concurrent-load races past the `isLoaded` guard during the detached parse Task.
- ContentView's duplicate outer `.onAppear` removed.
- `ScriptureStudyApp`'s `if readyToShow { ContentView() }` replaced with unconditional ContentView plus overlaid splash. (This change was deployed but did NOT resolve the 7× reconstruction; kept because it's a cleaner identity model regardless.)

**Still open — the 7× mystery:**
- `LocalBibleView.onAppear`, `CompanionPanel.onAppear` still fire 7× on cold start. `[MyBible] verses set` fires 14× (7 ContentViews × 2 loadChapter paths).
- Non-blocking: services are shared, parses are deduplicated, app works and feels fast. But the view-tree churn is real.
- **First move next session:** add `print("[INIT] ContentView.init")` and `print("[BODY] ContentView.body")` to distinguish struct reconstruction from body re-evaluation from onAppear re-entry. Different counts → different bugs → different fixes.

**Also carried forward:**
- `MyBibleService.loadChapter()` should get the same `isLoading` guard treatment as BMapsService/InterlinearService. Belt-and-braces; not causing observed problems.
- ForEach duplicate-ID console warning (IDs 1 through 57 "occur multiple times"). Not from VerseWithStrongsView — some other file with `ForEach(..., id: \.someInt)` where the Int isn't unique. Needs grep hunt.
- Remove `[NOTE DEBUG]` prints once the editor has had a day or two of clean use.

**Next editor sessions (queued from yesterday):**
- **Session 2 — Live Markdown rendering.** As you type `**bold**`, the word renders bold and the asterisks grey out. Headings become bigger. Lists get bullets. Uses NSTextStorage delegate + NSLayoutManager attribute runs.
- **Session 3 — Strong's number + scripture reference auto-linking.** Inside notes, `G5485` and `John 3:16` become clickable. Hooks into existing `myBible` Strong's lookup and `navigateToPassage` notification.
- **Session 4 — Keyboard shortcuts & find/replace.** ⌘B/I/K/1/2/3, ⌘F inside note, word-count polish.
- **Session 5 — Note-to-note links, insert-passage, tags.**

**Possible next moves carried forward from earlier:**
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

## 5-bullet recap for tomorrow's opening

Copy this into the first message of tomorrow's chat:

```
Picking up ScriptureStudy cold-start work. Yesterday evening:
1. Moved BMapsService + InterlinearService from ContentView to App level — single shared instance, no more multi-init.
2. Added isLoading guards to both services' loadIfNeeded to prevent concurrent parse races during detached Task.
3. Restructured ScriptureStudyApp to keep ContentView unconditionally in the tree (was behind `if readyToShow`). Did NOT fix the 7× problem but kept anyway for cleaner identity.
4. Cold start dramatically faster, beachball gone, app stable. 7× ContentView reconstruction still happening but no longer has costly consequences.
5. Open threads: figure out why ContentView reconstructs 7× (add [INIT]/[BODY] prints first), add isLoading guard to MyBibleService.loadChapter, hunt down ForEach duplicate-ID warning (not in VerseWithStrongsView).
```
