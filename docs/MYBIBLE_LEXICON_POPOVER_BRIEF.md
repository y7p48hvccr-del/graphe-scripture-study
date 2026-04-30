# MyBible-Style Lexicon Popover — Architecture Brief

A reference specification for the lexicon popover surface in `Graphē One Codex`, derived from observation of MyBible (a daily-driver reference app) plus inspection of the bundled `Strong_Dictionary.SQLite3` and `SECE.dictionary.SQLite3` files in the `References/` folder.

This brief is intended to be pasted into an Xcode coding-assistant context as design reference. It is **not** a copy of MyBible's source; it is a description of behavior and structure to reproduce in native SwiftUI/UIKit.

---

## 1. Surface Type

A **floating panel popover**, anchored loosely to the reader area but free-floating (not glued to the tapped word). Behaviors:

- Appears on tap of a Strong's-tagged token in the verse text.
- Stays open until explicitly dismissed (down-chevron) or replaced by another entry.
- Has its own internal navigation history (back/forward).
- Can promote to a larger panel beneath the reader (alternate display mode — toggled by the swap-arrows icon).
- Background is a warm cream/parchment color, deliberately distinct from the blue Bible reading area, so the panel reads as a separate "scholarly aside" surface.
- Soft drop shadow; no visible title bar; no traffic-light controls.

## 2. Layout, Top to Bottom

### Header row

- **Left**: the Strong's key + gloss in parentheses, e.g. `H5797 (strength)`. Both underlined, both clickable (the number opens a dedicated entry view; the gloss likely re-runs lookup against the gloss).
- **Right**: the active dictionary's short identifier, e.g. `ETCBC+`. This is a button — tap to swap dictionaries from a list of installed lexicons.

### Lexeme block (the "title" of the entry)

A single line composed of:

- The original-language word in large type, properly rendered (Hebrew RTL with vowel points / Greek with diatonics): `עֹז`
- Then in parentheses, a pipe-separated metadata strip:
  - transliteration with diacritics, italic grey: `'ôz`
  - simple pronunciation, lighter grey: `oze`
  - part of speech, magenta: `noun`
  - grammatical gender / number / additional tags, magenta: `masculine`
  - canonical gloss, blue: `strength`

Each metadata token is rendered as a colored chip-of-text — color is the semantic indicator. Colors are consistent across all entries (so users learn that magenta = grammar, blue = gloss, grey = phonetics).

### Divider

Thin horizontal rule.

### Cross-reference index block

A wrapped paragraph composed of compact, color-coded reference tokens. Each grouping is `LABEL: value(s)` separated by spaces. Visible groupings in the screenshot include:

- `[Heb]` — language tag (square brackets, plain)
- Original word repeated (red, clickable)
- `ETCBC:` — alternate lexicon name (italic) followed by its variant glosses, e.g. `עֹז (subs | protection), עֹז (subs | power)`
- `OSHL:` — Open Scriptures Hebrew Lexicon code, e.g. `p.bx.ac`
- `TWOT:` — Theological Wordbook of the OT entry number, e.g. `1596b`
- `GK:` — Goodrick-Kohlenberger numbering, e.g. `H6437`
- `Greek:` — italic header introducing a list of LXX (Septuagint) Greek equivalents, comma-separated, each Greek word in red and clickable: `ἁγιωσύνη, αἶνος, ἀντίληψις, ἁρμόζω, βοήθεια, βοηθός, δόξα, δύναμις, ἰσχύς, κράτος, ὀχύρωμα, τιμή, ὑψηλός`

Visual rule: anything red is a navigable cross-reference (intra-dictionary or inter-dictionary). Black/grey text is non-interactive labelling. This block is the "scholarly bridge" that makes the popover useful beyond a single dictionary.

### Divider

Thin horizontal rule.

### Definition block

A series of labeled paragraphs:

- `Derivation:` (bold) followed by an etymology line with embedded Hebrew Strong's references (red, clickable): `or (fully) עוֹז; from עָזַז;`
- `Strong's:` (bold) followed by the canonical Strong's definition. The gloss keyword (`strength`) appears in red within the prose: `strength in various applications (force, security, majesty, praise)`
- `KJV:` (bold) followed by the comma-separated KJV translation gloss list: `boldness, loud, might, power, strength, strong.`
- `Cognate:` followed by a wrap-flowing list of related Strong's numbers, each in red and clickable. (These come straight from the `cognate_strong_numbers` table joined on `group_id`.)

### Footer controls

- **Bottom-left**: `<` and `>` chevrons — back/forward through entry navigation history.
- **Bottom-right** (small icon row):
  - `S#` — jump-to-Strong's-number search (opens an input).
  - `⇄` (swap arrows) — toggle popover-vs-panel display mode, or swap dictionary.
  - `v` (down chevron) — dismiss popover.

## 3. Color and Typography Conventions

Adopt these as design tokens so behavior is consistent across all entries:

| Role | Color | Weight/Style |
|---|---|---|
| Strong's key + dictionary label (header) | red | regular |
| Original-language lexeme | black | large, language-appropriate font |
| Transliteration | dark grey | italic, smaller |
| Pronunciation | lighter grey | regular |
| Part of speech, gender, grammatical tags | magenta/purple | regular |
| Canonical gloss in lexeme block | blue | regular |
| Section labels (`Derivation:`, `Strong's:`, `KJV:`, `Cognate:`) | black | bold |
| Cross-reference Strong's numbers | red | regular, underlined on hover |
| Original-language inline references (within definitions) | red | language font |
| Body prose | black/dark | regular |
| Background | warm cream / parchment | — |
| Divider | thin grey rule | — |

Consistent color = consistent meaning. Once users learn the legend on one entry it transfers everywhere.

## 4. Data Mapping (Bundled Schema → UI)

The bundled MyBible-format SQLite schema in `Strong_Dictionary.SQLite3` and `SECE.dictionary.SQLite3` is a strict input. Mapping each visible UI field to its source:

| UI element | Source |
|---|---|
| Header Strong's key | `dictionary.topic` |
| Header gloss | `dictionary.short_definition` |
| Active dictionary label | `info.description` (shortened) or per-module identifier |
| Lexeme | `dictionary.lexeme` |
| Transliteration | `dictionary.transliteration` |
| Pronunciation | `dictionary.pronunciation` |
| POS / gender / grammatical tags | **Not in the bundled schema directly.** These appear to come either from a separate morphology lexicon (parsed from verse-token morphology codes via the `morphology_indications` lookup) or from a second lexicon module like ETCBC. Implementation should treat these as a separate optional data source, not as fields on `dictionary`. |
| Definition body | `dictionary.definition` (an HTML fragment) styled by `info.html_style` (CSS) |
| Inline `<a href='S:G2316'>` style links | Custom URL scheme `S:` — must be intercepted by the navigation layer, not followed as a URL |
| Cognates | `cognate_strong_numbers` joined on `group_id`; presentation template from `info.cognate_strong_numbers_info` (e.g. `Cognate: %s`) |
| Cross-references to other lexicons (ETCBC, OSHL, TWOT, GK, LXX Greek) | **Not in the bundled schema.** These are content embedded inside the `definition` HTML by lexicon authors who chose to include them. Treat the definition as authoritative HTML; render it; let the `S:` link interception handle navigation. |
| Footer back/forward | Internal stack maintained by the popover view model |
| Footer dictionary swap | List of installed dictionary modules; current selection persists |

**Architectural takeaway:** the bundled schema is intentionally minimal. The richness in the screenshot comes from (a) extra lexicon modules layered on top, and (b) HTML embedded in the `definition` field. The renderer should be schema-agnostic past `lexeme/transliteration/pronunciation/short_definition` and just trust the HTML in `definition` plus the `S:` link interception.

## 5. Interaction Model

- **Tap a Strong's-tagged word in the verse** → popover opens with that entry. If the popover was already open, replace the content and push the previous entry onto the back stack.
- **Tap a red cross-reference (Strong's number, Hebrew word, Greek word, cognate)** inside the popover → resolve via the `S:` URL scheme; replace popover content; push old entry onto back stack.
- **Back / forward chevrons** → pop / re-push from the entry stack.
- **Dictionary swap (header right, or `⇄` footer icon)** → re-query the same `topic` against the alternate dictionary; preserves the user's current entry context.
- **`S#` search** → opens a small input; user types `H5797` or `G3056`; performs direct lookup.
- **`v` chevron** → dismiss popover, clear stack.
- **Promote to panel** (`⇄` may toggle this) → the same view migrates from a floating popover to a docked panel below the reader, retaining state.
- **Tap outside popover** → behavior choice: dismiss (mobile-typical) or stay open (scholarly-app-typical, what MyBible does).

## 6. Suggested SwiftUI Component Hierarchy

```
LexiconPopover                       // root view, reads LexiconPopoverViewModel
├── LexiconHeader                    // H5797 (strength)         ETCBC+
├── LexemeBlock                      // עֹז (...metadata strip...)
│   └── MetadataStrip                // pipe-separated, color-tagged spans
├── Divider
├── CrossReferenceIndexBlock         // wrapped flow of [Heb], ETCBC:, TWOT:, GK:, Greek:
├── Divider
├── DefinitionBody                   // WKWebView or AttributedString rendering
│   └── HTMLRenderer                 // injects info.html_style as CSS,
│                                    // intercepts S:XXXX taps via navigation delegate
└── LexiconFooter
    ├── HistoryControls              // < >
    └── ToolControls                 // S# ⇄ v
```

**View model responsibilities:**

```swift
final class LexiconPopoverViewModel: ObservableObject {
    @Published var current: LexiconEntry
    @Published var activeDictionaryID: DictionaryID
    private var backStack: [LexiconEntry] = []
    private var forwardStack: [LexiconEntry] = []

    func open(_ topic: StrongsKey)               // initial open from verse
    func navigate(_ topic: StrongsKey)           // from S: link inside body
    func swapDictionary(to id: DictionaryID)     // header-right tap
    func goBack()                                // < tap
    func goForward()                             // > tap
    func searchByStrongsNumber(_ raw: String)    // S# tap
    func dismiss()                               // v tap
    func promoteToPanel()                        // ⇄ tap
}
```

`LexiconEntry` should carry the resolved fields (`topic`, `lexeme`, `transliteration`, `pronunciation`, `shortDefinition`, `definitionHTML`, `expandedDefinitionHTML?`, `cognates: [StrongsKey]`, `sourceFlags`) — i.e. exactly the columns of your merged `dictionary` table.

## 7. Rendering Definition Body — Key Decision

The `definition` column in both bundled files is an **HTML fragment** (with tags like `<b>`, `<i>`, `<font color='5'>`, `<a href='S:G2316'>`, `<big>`, `&#x...;` entities). Two viable render paths:

**Option A — `WKWebView` with injected CSS.** Pros: faithful HTML rendering, easy to support inline navigation by intercepting `S:` URLs in `WKNavigationDelegate.decidePolicyFor`. Cons: heavyweight view, slower spin-up, harder to size dynamically inside SwiftUI.

**Option B — Convert HTML to `AttributedString` at load time.** Pros: lightweight, native, easy SwiftUI sizing. Cons: SwiftUI's `AttributedString` doesn't render arbitrary HTML well; you'd need a custom converter; intercepting `S:` links requires a custom `LinkAttribute` and tap handler.

Recommendation: **start with `WKWebView`** because the bundled HTML is non-trivial and `info.html_style` is literally CSS. Use `setUIDelegate` and `decidePolicyFor` to catch the `S:` URL scheme. If performance becomes an issue later, migrate to a custom `AttributedString` renderer.

## 8. What Your Current Schema Doesn't Cover (and what to do about it)

Looking at the screenshot vs. the bundled SQLite, the popover is showing several things your bundled `Strong_Dictionary.SQLite3` does **not** contain:

- **Grammatical tags** (`noun`, `masculine`) — these come from a morphology lexicon module, not the dictionary itself. Your `morphology_indications` table is the lookup for parsing verse-token codes; you'd need a separate enriched lexicon (or augment the merged dictionary with parsed POS data) to surface them inline in the lexeme block.
- **Multiple parallel lexicons** (ETCBC, OSHL, TWOT, GK) — these are separate dictionary modules in MyBible's library. Your project ships only Strong's and SECE today. Architecting the loader so it can register N dictionaries (not just 1 active) is the design move that unlocks this in the future without a rewrite.
- **LXX Greek equivalents** for Hebrew entries — embedded in lexicon modules with that data; not in your current files. Treat as a future-additive concern.

For now, your popover should render correctly with the data you have (header, lexeme, transliteration, pronunciation, short_definition, definition HTML, cognates) and degrade gracefully when optional fields are absent. The metadata strip in the lexeme block should simply omit color chips for missing data rather than show empty placeholders.

## 9. Acceptance Checklist for the Coding Agent

A correct implementation of this surface should:

- [ ] Render the popover floating above the reader on tap of any Strong's-tagged token.
- [ ] Show the header (Strong's key + gloss + active dictionary label).
- [ ] Show the lexeme block with original-language text and color-coded metadata strip.
- [ ] Render the `definition` HTML faithfully, including embedded original-language characters and `<font color='N'>` styling using `info.html_style` as CSS.
- [ ] Display cognates from `cognate_strong_numbers` as a clickable list under a `Cognate:` label.
- [ ] Intercept all `S:XXXX` URL taps and navigate within the popover (don't open a browser).
- [ ] Maintain a back/forward navigation stack, exposed via `<` `>` controls.
- [ ] Dismiss cleanly via the `v` chevron and clear the stack.
- [ ] Switch active dictionary via the header label or `⇄` icon, preserving current `topic`.
- [ ] Use the warm cream/parchment background for the popover surface.
- [ ] Size the popover so the user can read 4-6 lines of definition without scrolling, then scroll for the rest.
- [ ] Persist no state across app launches (popover is ephemeral); but persist active-dictionary choice.

---

*Prepared from observation of MyBible (Apple Silicon native build) on Psalm 29:5 / H5797, plus inspection of the bundled `Strong_Dictionary.SQLite3` and `SECE.dictionary.SQLite3` files in the project's `References/` folder.*
