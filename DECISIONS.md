# ScriptureStudy / Graphē One — Decisions Log

A running record of architectural and product decisions. Add entries as decisions are made so context stays findable across chats.

Format: `YYYY-MM-DD · Topic · Decision · Rationale`

---
TEST
## 2026-04-19 · Interlinear parser: support all 18 modules

**Decision:** Replace the two format-specific parsers in `InterlinearService.swift` (`parseNT` hardcoded to the iESVTH format, `parseOT` hardcoded to IHOT) with a single unified parser that handles the eight distinct markup conventions found across the 18 interlinear modules in the library.

**Before:** Only 2 of 18 interlinears worked (iESVTH+ for English, Ana+ for Russian). The other 16 were detected by the scanner, shown in the picker, but produced no tokens because their markup didn't match the hardcoded regex patterns. The picker itself is context-aware and switches between Hebrew (OT) and Greek (NT) dropdowns based on the current book's number (`bookNumber < 470`) — so users see 12 in the NT and 6 in the OT, totalling 18.

**The eight formats encountered:**

- **A. iESVTH** — `English <n>Greek</n><S>n</S><m>morph</m>`
- **B. Spanish (iBY/iNA27/iTisch/inWH)** — `Greek <S>n</S> <m>morph</m> <n>Spanish</n>`
- **C. VIN-el** — `Greek <n>Russian</n><S>n</S><m>morph</m>` (Format A shape but original outside <n>)
- **D. Bare Greek (BHPk/BHPm/GNTTH/SRGNT/SRGNTk)** — `Greek<S>n</S><m>morph</m>` (no translation)
- **E. HSB+** — `<e>Hebrew</e> <S>n</S> <n>translit</n> English`
- **F. HSB2+** — `Hebrew <S>n</S> <n>English</n>`
- **G. IHOT+** — `Hebrew <S>n</S>English` (no delimiter at all)
- **H. Ana+ family** — `Hebrew <S>n</S><m>morph</m> <n><e>Russian</e></n>`, plus double Strong's like `<S>1254</S><m>..</m><S>8804</S>` where the second S is a secondary morphology code

**Approach — `<S>` tag as backbone:** Every token in every format has exactly one Strong's number tag. The parser anchors on those, strips `<m>` tags first (after recording each one's position so it can be re-associated with the nearest `<S>`), merges double Strong's pairs, splits the text on `<S>` boundaries, then for each zone identifies the original word and translation using these rules in order:

1. If `<n>X</n>` appears immediately before `<S>` — decide by script. If `X` contains more Greek/Hebrew characters than the non-`<n>` part, `X` is the original (Format A). If the reverse, `X` is the translation (Format C / VIN-el).
2. Otherwise `<e>X</e>` immediately before `<S>` — `X` is the original (Format E/H).
3. Otherwise the last whitespace-separated plain-text word before `<S>` is the original.
4. For translation: `<n>...</n>` at the start of the after-zone wins (Formats B/F). Failing that, plain text up to the next token's original word (Format G / IHOT).

A helper `isOriginalScript()` distinguishes Greek/Hebrew from Latin/Cyrillic by Unicode range counting — needed for the Format A vs. VIN-el ambiguity.

**Validation:** A Python mirror of the logic was run against live-decrypted John 1:1 and Genesis 1:1 samples from every one of the 18 modules before porting to Swift. All 18 now produce correct `(original, translation, strong's, morph)` tuples.

**Files changed:** `InterlinearService.swift` — parser section replaced; parseNT/parseOT kept as thin wrappers for source-compat. No changes needed to `InterlinearView.swift` or `CompanionPanel.swift`.

**Related scripts (on Desktop, not in repo):** `find_interlinear.py` (recursive scanner listing all interlinears with their `hyperlink_languages`), `dump_interlinear_samples.py` (pulls a sample verse from each module, needed for format discovery). Both rely on `pycryptodome` to decrypt `.graphe` AES-CBC payloads.
## 2026-04-19 · EPUB reader: TOC parsing, navigation, and chapter anchors

**Decision:** Fix three underlying EPUB parser bugs and add a scroll-to-anchor mechanism so nested TOCs, href fragments, and in-file navigation all work correctly for any EPUB — not just the KJV test file.

**Changes in `EPUBParser.swift`:**

1. **Preserve `#fragment` in TOC hrefs.** Removed the two `rawSrc = rawSrc[..<hash]` strips in `parseOLItems` and `parseNavPoints`. When multiple TOC entries share a content file (e.g. Joshua+Judges both in `h-5.xhtml`), stripping fragments made their hrefs identical — which broke highlight matching (`currentHref == item.href` lit up every sibling) and intra-file navigation (page always loaded at file top).
2. **Depth-aware TOC parsers.** Old regex-based `parseNavPoints` / `parseOLItems` matched every `<navPoint>` / `<li>` in the document including nested ones, flattening nested TOCs into one long list. New versions use small helpers (`topLevelTagBodies`, `outermostTag`, `firstTag`) that respect element nesting and only enumerate direct children at each level, then recurse into each child's body for grandchildren.
3. **Fragment scroll injection in `pageContent`.** Archive lookups still need the bare file path, so `pageContent` now splits the fragment off at the boundary, loads the file, then appends a small `<script>` that runs `getElementById(fragment).getBoundingClientRect().top + pageYOffset - 60` to scroll the target element ~60px below the top of the viewport. Retries up to 5 times over ~500ms to survive font/CSS layout shifts. Cache key uses file path only (not full href with fragment) so same file with different fragments doesn't cache twice.
4. **Parent rows in nav.xhtml can be `<span>` not `<a>`.** Parser now accepts either, so structural headers (Testament, Division) that aren't meant to be navigable still produce TOC entries with `href = ""` — shown in the sidebar but not clickable.
5. **HTML-entity decoding.** Titles containing `&amp;`, `&lt;`, `&quot;`, `&nbsp;` etc. now decode properly (so "Wisdom &amp; Poetry" reads as "Wisdom & Poetry" in the TOC).

**Why 60px offset:** 24px left the heading clipped by content padding; 60px gives clear breathing room on any reasonable screen. The constant is in `injectFragmentScroll` inside `EPUBParser.swift` and is the only knob if it ever needs tweaking.

**Universal vs specific:** Items 1–5 above are real parser bug fixes and benefit any EPUB. They are permanent improvements. The `nest_kjv_v2.py` script (on Desktop) is specific — it generates test files by injecting chapter headings based on the KJV `BB:CCC:VVV` verse pattern, and only works on Project Gutenberg-style Bibles. Kept around for regenerating test EPUBs, not part of the app.

**Test file:** `KJV_nested.epub` (on Desktop) — 4-level nested TOC (Testament > Division > Book > Chapter), 1,189 chapters with visible headings, used for verifying nested-TOC handling end-to-end.## 2026-04-19 · Module display names (sidecar approach)

**Decision:** Use `_ModuleInfo/<base>.txt` sidecar files to provide English display names for Bible modules. Do NOT translate the info table inside the SQLite database.

**How it works:**
- `sidecarDisplayName(forModuleAt:)` in `MyBibleService.swift` strips `.graphe` and any known type extension (`.bibles`, `.commentaries`, etc.) to derive a base name, then looks for `<modulesRoot>/_ModuleInfo/<base>.txt` and parses the first `Name:` line.
- Applied at BOTH construction sites: fresh inspection (~line 584) and cache-hit path (~line 408). The cache path was initially missed and is the reason the sidecar seemed not to be firing — the name had been cached from before the sidecar code landed.
- Falls back to `info["description"]` / `info["name"]` from the database when no sidecar exists.
- Module cache (`ModuleCache`) caches names based on file modification date; adding a new `.txt` file does NOT invalidate the cache, but the cache path now consults the sidecar anyway so new sidecars take effect immediately.

**Why:**
- Keeps the database untouched — reversible, non-destructive, preserves native identity for non-English users who won't have the sidecar files.
- Only helps Richard for now (only he has the `.txt` files). Future multilingual user base could use `Locale.current` to pick the right name per user; deferred.
- `module_info.py` script generates the sidecars; ~2367/2492 modules (95%) have matching sidecars as of today.

**Files:** `MyBibleService.swift`, `_ModuleInfo/*.txt` in `~/GrapheModules/`

---

## 2026-04-19 · Splash screen / onboarding logo animation

**Decision:** SwiftUI `LaunchScreenView` uses simple scale+fade animation timings:
- In: scale 0.3→1.0, opacity 0→1, duration 1.8s, easeOut
- Hold: ~0.4s
- Out: scale 1.0→1.6, opacity 1→0, duration 2.2s, easeOut

Background: `Color(red: 0.788, green: 0.843, blue: 0.894)` (sampled from logo PNG).

Logo asset name in `Assets.xcassets`: `GrapheOneLogo` (must match code exactly — previously caused blank splash when named `graphlogo`).

Ordering: app doesn't render `ContentView` until `launchDone && readyToShow`. Onboarding fires immediately when `readyToShow` becomes true (no blank gap).

**Related files available:** `GrapheOne_Splash.html` (1080p HTML version for recording), `GrapheOne_Splash.mp4` / `.mov` (rendered 1080p60 video).

---

## 2026-04-19 · Trademark / branding

**Decision:** Do NOT add ™ symbol to the app icon / splash screen logo for now. Circle would need to be redrawn larger to accommodate it without crowding "ScriptureStudy Pro" underneath.

**Status:** Using "Graphē One" as common-law trademark through use in commerce. Not filing with USPTO yet. Name may already be registered by another party — USPTO TESS search needed to confirm what class if so; a hit in an unrelated class (e.g., clothing, food service) wouldn't block software use in class 9.

**Developer identity for App Store Connect:** "Graphē One" as single-word brand (not "Studios" or "Studio") — cleaner and more confident, matches indie-dev convention (Panic, Flexibits, etc.).

---

## Open questions

- Extend sidecar approach to read `Locale.current` for multilingual user base? Deferred.
- Display format: English-only, or `和合本 (Chinese Union Version)` showing both? Not yet decided.
- Cache invalidation: should adding a new `.txt` file trigger a re-scan automatically? Currently no — sidecar is simply consulted live on each launch, which handles it without needing cache invalidation.
- USPTO trademark search for "Graphē One" in class 9 — pending.
