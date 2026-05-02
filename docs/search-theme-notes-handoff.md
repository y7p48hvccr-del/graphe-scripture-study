# Search, Theme, and Notes Handoff

## Current Stop Point

The current stopping point is the Search work. `SearchView.swift` and related search behavior have been reworked enough to form a clean commit boundary before starting theming.

Primary file affected:

- [SearchView.swift](/Users/richardbillings/XcodeOffline/ScriptureStudy2/ScriptureStudy/SearchView.swift)

Validation status at handoff:

- `SearchView.swift` has no live Xcode issues.
- The project builds successfully.

## What Changed In Search

### Search behavior

- Interlinear search is global and not restricted by language choice.
- Search language selection is single-select outside Interlinear.
- The old visible `All` behavior was replaced by staged scope probing.
- Scope pills can reflect hit presence without reintroducing a single mixed-results view.
- Search defaults were narrowed toward the current selected module instead of sweeping the whole category by default.
- Usage-priority ordering was added so large libraries search more sensibly.

### Search scope/category model

The Search scope set was refactored around these categories:

- `Bibles`
- `Interlinear`
- `Strongs`
- `Commentaries`
- `Encyclopedias`
- `Lexicons`
- `Dictionaries`
- `Notes`

`Cross-references` was hidden from Search after being evaluated as low-value in that surface.

### Search layout

- The scope pill strip sits under the main toolbar.
- The search box lives in the filter panel.
- Query type controls live in the filter panel.
- The right side uses three panels:
  - Filter
  - Modules
  - Languages
- Results and Preview were rebalanced and later equalized in width.
- The right sidebar width budget was adjusted several times to keep the language panel on-screen.
- Filter/module/language rails were given stronger outlines and explicit panel treatment.
- Module header text was simplified.
- `Current` and `Select All` module actions were moved under the module heading and rendered as pills.

### Scope pill state

- Scope pills are centered as a strip.
- Scope pills were simplified:
  - internal decoration removed
  - fixed-size footprint applied

## Large-Library Search Context

This Search work was tested under an unusually large corpus:

- roughly `560` modules
- about `6 GB` of module data

That means recent narrowing and prioritization work was driven by worst-case behavior rather than average-user conditions.

## Branding / Theme Next

The next task after committing Search is a cheap branded theme pass for `Studio Graphē One`.

Confirmed branding references:

- https://graphe.one/ScriptureStudy/
- https://graphe.one/support.html
- https://graphe.one/privacy.html

Assets to use:

- branding/colors from the website
- app/icon material already present in `Assets.xcassets`

Recommended scope for the cheap theme version:

- add a `Studio Graphe One` theme entry
- align core surfaces, accents, borders, and headings to the website branding
- keep it restrained and premium rather than performing a full visual redesign

Likely visual direction:

- pale restrained background
- cool blue accent / filigree
- editorial serif emphasis for major headings
- soft panel borders
- low-noise premium surfaces

## Notes After Theme

After the theme pass, focus should shift to `Notes`.

That next stage should be treated as a separate engineering phase from:

1. Search layout/search behavior work
2. cheap branded theme work
3. Notes engineering work

## Recommended Sequence

1. Commit the current Search work.
2. Start a separate `Studio Graphe One` cheap-theme pass.
3. Return to focused Notes engineering passes after that.

