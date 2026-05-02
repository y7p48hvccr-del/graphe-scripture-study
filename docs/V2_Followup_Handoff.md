## V2 Follow-up Handoff

### Status

Your branch should continue to be treated as the reference architecture proof for the `.graphe` runtime direction.

The current `ScriptureStudy` repo is aligning toward the same boundary structure and is using your engine work as the architectural reference point, not as a UI/design reference.

### Go Ahead

Yes, go ahead and surface the search modes in the sandbox UI.

Modes to expose:

- `global`
- `bibleFirst`
- `referenceFirst`
- `commentaryFirst`

### Constraint

The sandbox UI must remain an engine inspection surface, not a product UX pass.

That means:

- keep it thin
- do not expand it into an app shell
- do not spend effort on styling/product navigation
- do not let sandbox UI work outrun engine contract work

### What The Sandbox Should Expose

Minimum useful controls/output:

- query input
- mode picker
- scan limit
- per-result score
- route type
- snippet preview
- module kind / source

The purpose is to make engine behavior observable:

- ranking differences by mode
- route payload correctness
- snippet behavior
- bounded scan behavior
- cancellation/boundary effects

### What This Confirms

We are explicitly using the V2 branch as the reference architecture proof for:

- runtime-first layering
- normalized runtime records
- adapter-shaped result projection
- coordinator-owned aggregate ranking
- `.graphe` as the declared runtime format

### Main Open Question

Please continue treating this as an explicit platform decision, not an accidental implementation detail:

- is decrypted SQLite inside the `.graphe` runtime only a transitional proof mechanism
- or is decrypted SQLite acceptable as a long-term internal implementation detail of the proprietary runtime

This is currently the most important unresolved architectural question.

### Current Repo Alignment

The current `ScriptureStudy` repo has already been refactored toward your boundary shape with these extractions:

- `GrapheRuntimeStorage.swift`
- `ModuleCatalogService.swift`
- `ModuleContentService.swift`
- `StrongsLookupService.swift`
- `MyBibleRuntimeTypes.swift`

That repo is still transitional, but it is no longer being treated as a mixed-format target architecture.

### Continue Focusing On

- engine contracts
- runtime/search boundaries
- ranking observability
- route correctness
- module-loading/catalog design

### Do Not Prioritize

- product UI polish
- broad app-shell work
- design pass work that does not improve engine observability or runtime architecture

### Bottom Line

Proceed with sandbox mode surfacing, but keep it strictly in service of engine verification.

The architectural direction is confirmed.
