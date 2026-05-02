# Repo Refactor Boundary Plan

## Purpose

This document turns the `.graphe`-only transition decision into a concrete refactor boundary for the current `ScriptureStudy` repo.

The goal is not to rewrite everything at once.

The goal is to:

1. stop deepening the legacy mixed runtime
2. extract the storage/runtime boundary cleanly
3. make the current repo a better transition branch
4. prepare the app to consume a future `.graphe`-only engine

## Current Pressure Points

The current runtime/storage coupling is concentrated in three places:

### 1. `MyBibleService.swift`

This file currently mixes:

- module scanning
- module classification
- SQLite access
- `.graphe` decryption
- metadata caching
- Bible lookup
- dictionary lookup
- commentary lookup
- cross-reference lookup
- selection state
- published UI-facing app state

It is both a storage driver and a UI-facing domain service.

That is the biggest architectural problem in the repo.

### 2. `SearchView.swift`

This file currently mixes:

- UI state
- scope/filter behavior
- raw SQLite search
- `.graphe` branching
- fallback scanning
- snippet normalization
- routing decisions

It is effectively a second storage/search service embedded in a view.

### 3. `ModuleLibraryView.swift`

This file currently mixes:

- runtime-facing module folder behavior
- legacy mixed-format import behavior
- external conversion tooling entry points

That makes the runtime boundary blurry.

## Refactor Rule

From this point forward:

- UI files should not perform raw storage access
- views should not know about `.sqlite3` versus `.graphe`
- runtime access should move behind a dedicated module engine boundary
- import/conversion should be treated as migration tooling, not runtime architecture

## First Extraction Order

Do the refactor in this order.

### Step 1. Extract runtime storage primitives from `MyBibleService`

Move out:

- `grapheDecrypt(...)`
- `query(db:sql:)`
- `col(_:_:path:)` / column-read helpers
- `getTableNames(db:)`
- module inspection helpers
- raw open/close/query utilities

These should move into a dedicated storage/runtime layer.

Suggested new files:

- `GrapheRuntimeStorage.swift`
- `LegacySQLiteInspection.swift`

Important:

- `LegacySQLiteInspection` is transitional only
- `.graphe` runtime access is the strategic path

### Step 2. Extract module scanning and classification from `MyBibleService`

Move out:

- `scanModules()`
- `inspectModuleWithBlob(at:)`
- cache loading/saving helpers
- sidecar display-name helpers

Suggested new file:

- `ModuleCatalogService.swift`

Responsibility:

- discover modules
- build module metadata
- classify runtime candidates versus legacy imports

This service should eventually prefer `.graphe` modules explicitly and demote raw SQLite imports to legacy/migration status.

### Step 3. Extract content lookup APIs from `MyBibleService`

Move out:

- Bible chapter/verse reads
- dictionary lookup
- linked dictionary/article lookup
- commentary lookup
- cross-reference lookup

Suggested new files:

- `BibleContentService.swift`
- `ReferenceContentService.swift`
- `CommentaryContentService.swift`
- `CrossReferenceService.swift`

These services should not publish UI state directly.

They should return domain data only.

### Step 4. Collapse `SearchView` into a thin consumer

Move out of `SearchView.swift`:

- `searchBible(...)`
- `searchBibleFallback(...)`
- `searchCommentary(...)`
- `searchCommentaryFallback(...)`
- `searchReference(...)`
- `searchReferenceFallback(...)`
- `openDatabase(at:)`
- `columnString(...)`
- text-decoding helpers that are runtime-driven

Suggested new file:

- `SearchEngineService.swift`

`SearchView` should be left with:

- query text
- scope/filter UI
- running a search task
- presenting grouped results
- routing selected results

## First `.graphe`-Only Runtime Interface

The current repo needs a target interface to converge toward.

Start with something like this conceptually:

```swift
struct GrapheModuleDescriptor: Hashable, Identifiable {
    let id: String
    let name: String
    let language: String
    let category: GrapheModuleCategory
    let fileURL: URL
}

enum GrapheModuleCategory {
    case bible
    case commentary
    case dictionary
    case encyclopedia
    case crossReference
    case strongs
    case devotional
    case readingPlan
    case atlas
    case unknown
}

protocol GrapheRuntimeProviding {
    func openModule(at url: URL) throws -> GrapheModuleDescriptor
    func search(_ request: GrapheSearchRequest) async throws -> [GrapheSearchResult]
    func bibleChapter(moduleID: String, book: Int, chapter: Int) async throws -> [MyBibleVerse]
    func article(moduleID: String, topic: String) async throws -> GrapheArticle?
    func commentary(moduleID: String, book: Int, chapter: Int, verse: Int?) async throws -> [CommentaryEntry]
}
```

This is not a final implementation requirement.

It is the boundary the current repo should start moving toward.

## Transitional Interface For This Repo

Because the current app still has legacy code, introduce a bridge layer rather than switching everything at once.

Suggested temporary façade:

- `RuntimeModuleEngine`

Responsibilities:

- expose domain operations to the UI
- internally delegate either to transitional legacy services or future `.graphe` services
- prevent views from knowing which backend is being used

This gives the current repo a controlled seam for migration.

## Methods To Move First

The first methods that should leave `MyBibleService` are:

- `grapheDecrypt(...)`
- `scanModules()`
- `inspectModuleWithBlob(at:)`
- `lookupDictionaryWord(word:)`
- `lookupWord(word:in:fallbackType:preservingMarkup:)`

Why these first:

- they sit closest to the runtime/storage boundary
- they are reused conceptually by multiple UI surfaces
- they currently hard-wire format and schema knowledge into a UI-facing service

The first methods that should leave `SearchView` are:

- `searchBible(...)`
- `searchCommentary(...)`
- `searchReference(...)`
- all fallback implementations

Why:

- they are the clearest example of storage/search logic being embedded in a view

## What To Leave In `MyBibleService` For Now

Temporarily keep:

- selected module state
- current passage state
- `@Published` UI-facing state
- convenience coordination that ties existing screens together

But treat `MyBibleService` as an orchestration shell, not the long-term runtime engine.

## What To Leave In `ModuleLibraryView` For Now

Temporarily keep:

- folder picking
- visible module listing
- user-facing selection and hiding behavior

But begin changing the language and assumptions:

- `.graphe` is the runtime format
- conversion/import is legacy ingestion support
- raw `.sqlite3` import is not the future contract

## Anti-Goals During Refactor

Do not:

- add new raw SQLite search code to views
- add new broad fallbacks to compensate for engine uncertainty
- strengthen `.sqlite3` support as a long-term runtime path
- mix conversion code into the new runtime interface

## Minimum Good Outcome

This refactor step is successful when:

- `SearchView` no longer contains raw search engine logic
- `MyBibleService` no longer owns low-level storage primitives
- module access begins to move behind a runtime boundary
- the repo becomes structurally ready to swap in a `.graphe`-first engine

That is the practical starting line for the declared transition.
