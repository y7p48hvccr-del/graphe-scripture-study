## V2 Alignment Note

### Purpose

This note maps the `ScriptureStudyRSEngineV2` handoff back onto the current `ScriptureStudy` repo.

The goal is not to merge UI work or duplicate sandbox work. The goal is to adopt the architectural boundaries that V2 has already proved while continuing to reduce legacy coupling in this repo.

### What This Repo Should Adopt

#### 1. Runtime-first layering

This repo should converge on the same stack V2 already proved:

- runtime access layer
- normalized runtime/domain records
- adapter layer
- coordinator / ranking layer
- thin UI consumers

The extractions already done here support that direction:

- `GrapheRuntimeStorage.swift`
- `ModuleCatalogService.swift`
- `ModuleContentService.swift`
- `StrongsLookupService.swift`
- `MyBibleRuntimeTypes.swift`

These should be treated as the beginning of the runtime/access boundary, not as temporary helper files.

#### 2. Search belongs below the views

V2 confirmed the right shape:

- matching belongs in the runtime/engine
- snippet generation belongs in the runtime/engine
- ranking belongs in the runtime/engine
- adapters should shape engine hits into UI-facing result contracts

Implication for this repo:

- `SearchView.swift` should stop owning storage-shaped search logic
- broad fallback SQL/mixed-format logic in the view layer should be retired
- future search work here should move toward explicit contracts and coordinators, not more view-side branching

#### 3. `.graphe` is the declared runtime boundary

V2 validates the strategic direction already chosen here:

- `.graphe` is the public runtime format
- raw `.sqlite3` runtime support is not the target model
- conversion/import is a controlled pipeline concern, not the runtime’s identity

Implication for this repo:

- module access should be expressed in `.graphe`-first terms
- legacy SQLite assumptions should not be carried forward into new APIs
- UI and settings language should continue moving away from presenting `.sqlite3` as the long-term supported runtime format

#### 4. Explicit routing/result contracts

V2 already proved explicit route payloads and search result contracts.

Implication for this repo:

- result routing should become explicit engine/domain data
- cross-reference, article, Bible, commentary, devotional, and future lexicon flows should converge on contract-first navigation rather than ad hoc UI reconstruction

### What Should Stay Isolated In V2 For Now

#### 1. Sandbox UI work

Do not port sandbox UI ideas first.

This repo does not need:

- interactive search-mode sandbox work
- UI experimentation around engine controls
- proof-shell duplication

Those are useful in V2, but they are not the next leverage point here.

#### 2. Fixture-driven proof code

V2 uses generated `.graphe` fixtures backed by SQLite for proof/testing.

That is appropriate there.

This repo should learn from the contract shapes, but not absorb fixture-generation concerns into product-facing code unless we deliberately add a dedicated test-support layer.

#### 3. Premature coordinator migration

V2 has `SearchCoordinator`, adapters, and search contracts already separated.

This repo should adopt that direction, but not by doing a rushed copy-over. The current repo still contains legacy state and routing assumptions that need staged extraction.

### What This Repo Should Stop Doing

#### 1. Stop reinforcing `SearchView` as engine code

No more major search behavior should be added directly into `SearchView.swift`.

If new search behavior is needed, it should be added behind extracted contracts/services.

#### 2. Stop treating mixed runtime support as the design target

Compatibility can exist during transition, but mixed `.sqlite3` / `.graphe` runtime support is no longer the architectural goal.

#### 3. Stop letting service shells also be parser/storage namespaces

`MyBibleService` has already been reduced substantially. The remaining helpers should continue moving outward instead of allowing the file to regrow as a general runtime dumping ground.

### Main Architectural Question Still Open

V2 proves a `.graphe`-only runtime boundary, but currently decrypts to temporary SQLite internally.

That leaves one unresolved strategic question:

- is decrypted SQLite an acceptable long-term internal implementation detail for `.graphe`
- or is even that internal SQLite dependency intended to disappear later

This repo should not answer that accidentally.

It should be treated as an explicit platform decision.

### Recommended Next Steps In This Repo

1. Define explicit search contracts for this repo, modeled after the V2 direction.
2. Introduce an engine/coordinator layer for search so `SearchView.swift` becomes a consumer.
3. Add a real module catalog/loading abstraction above the current scan result model.
4. Continue removing legacy `.sqlite3`-shaped assumptions from settings, module library flows, and search paths.
5. Decide whether internal decrypted SQLite is transitional or durable.

### Bottom Line

V2 should be treated as the reference architecture proof.

This repo should:

- adopt the boundary shapes
- continue extracting toward them
- avoid re-embedding runtime/search logic into views
- avoid copying sandbox/UI proof code before the contracts are in place
