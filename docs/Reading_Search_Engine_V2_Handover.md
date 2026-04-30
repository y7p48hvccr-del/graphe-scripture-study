# ScriptureStudy Reading/Search Engine V2 Handover

## Purpose

This document hands off a parallel rebuild effort for the reading/search engine layer while the current app remains active as the continuity path.

The goal is not to redesign the entire app. The goal is to rebuild the module access, reading, and search foundations cleanly enough that they can later be integrated back into the current product with minimal ambiguity.

## Recommended Naming

Use these names consistently:

- Current shipping codebase: `ScriptureStudy`
- Parallel rebuild effort: `ScriptureStudy Reading/Search Engine V2`
- If a separate sandbox app target is created: `ScriptureStudy Prototype`

Do not call the current app `ScriptureStudy Prototype` unless you are explicitly retiring it as the shipping branch. Right now it is better understood as the active product branch, even if parts of it remain underbuilt.

## Why This Parallel Effort Exists

Recent work exposed architectural problems in the current reading/search stack:

- dictionary content had been rendered as plain text rather than HTML
- global search behavior became unstable under real module load
- `.sqlite3` and `.graphe` modules are not handled through one clean search abstraction
- search scopes, result routing, and module filtering have been patched incrementally rather than built from a stable engine layer
- richer modules such as ISBE are now ahead of the viewer and search infrastructure

This does not mean the entire app is unsalvageable. It means the reading/search subsystem now merits a clean bottom-up rebuild.

## Scope of V2

Build only the following:

1. Module access layer
2. Search adapters per module type
3. Unified search result model
4. Dictionary/reference reading surface contract
5. Navigation/routing contract for results

Do not expand into unrelated product areas such as chat, notes, organizer, or maps unless directly required for integration testing.

## Principles

1. Build bottom-up, not top-down.
2. Prove one query against one module before composing aggregate search.
3. Treat `.sqlite3` and `.graphe` as first-class supported formats with explicit handling.
4. Separate engine concerns from SwiftUI concerns.
5. Use deterministic limits, cancellation, and time bounds for search.
6. Preserve module fidelity instead of flattening all content types into one vague “search everything” implementation.

## Proposed Architecture

### 1. Module Access Layer

Create a dedicated layer responsible for:

- opening module databases safely
- distinguishing plain SQLite from encrypted `.graphe`
- reading text/blob columns correctly
- normalizing text only after raw retrieval
- surfacing module metadata cleanly

This layer should be the only place that knows about:

- `sqlite3_open_v2`
- `grapheDecrypt(...)`
- schema differences at the storage level

### 2. Search Adapters

Create one search adapter per module class:

- Bible search adapter
- Commentary search adapter
- Dictionary/encyclopedia search adapter
- Notes search adapter

Each adapter should expose:

- input query
- optional filter constraints
- deterministic maximum result count
- sync or async execution contract
- structured result output

Each adapter must be testable independently of SwiftUI.

### 3. Unified Search Result Model

Define one stable result model that can represent:

- Bible passage hits
- Commentary hits
- Dictionary hits
- Encyclopedia hits
- Notes hits

That model should carry:

- result type
- module identity
- display title/reference
- normalized snippet
- routing payload

The UI should not need to infer search meaning from ad hoc combinations of fields.

### 4. Reading Surface Contract

Define how rich content is rendered:

- dictionary and encyclopedia content should be treated as HTML-capable content
- result routing should specify whether the destination is Bible, companion dictionary, encyclopedia, commentary, or another reader
- module-specific content assumptions should be explicit, not guessed in the view layer

### 5. Navigation Contract

Search results must route through a clean contract rather than posting loosely-typed notifications opportunistically.

If notifications are retained for integration compatibility, define a narrow navigation wrapper around them rather than scattering notification posting logic across the UI.

## Current Known Problems in the Existing App

These are important because V2 should explicitly avoid reproducing them:

- dictionary rendering was historically a plain `Text` view
- global search UI and underlying search execution were not consistently using the same module set
- Bible result deduping collapsed identical references across different versions
- reference search was not originally a first-class search scope
- `.graphe` search handling could not reliably depend on raw SQL `LIKE`
- fallback search logic became broad enough to create indefinite spinner behavior
- search orchestration and search primitives are too entangled

## Immediate Technical Goals for V2

### Goal A: Bible Search Primitive

Prove:

- one query against one plain SQLite Bible module
- one query against one `.graphe` Bible module
- correct snippet extraction
- correct result limiting
- bounded execution time

### Goal B: Reference Search Primitive

Prove:

- one query against one dictionary module
- one query against one encyclopedia module
- correct HTML/text normalization for snippets
- no garbled entity output
- correct article routing payload

### Goal C: Commentary Search Primitive

Prove:

- one query against one commentary module
- support for current schema variants already seen in the codebase
- reliable snippet output

### Goal D: Aggregate Search

Only after A-C are proven:

- aggregate multiple module adapters
- add scope control
- add result grouping
- add cancellation
- add UI progress behavior

## Recommended Delivery Order

1. Engine package or engine-focused folder
2. Bible adapter
3. Reference adapter
4. Commentary adapter
5. Result model
6. Routing model
7. Minimal test harness
8. Integration into a sandbox UI or prototype target

## Test Expectations

Minimum tests should include:

- plain SQLite text read
- `.graphe` text read/decrypt
- Bible search returns expected known term
- dictionary search returns expected known article
- HTML/entity normalization behaves correctly
- search limit enforcement
- result routing payload correctness

## Current Product Branch Expectations

The current app branch should remain focused on:

- keeping the shipping path usable
- improving dictionary rendering and reference handling where safe
- avoiding broad destabilizing rewrites while V2 is under construction

The parallel team should not assume the live app is the right architecture to copy. It should be treated as a source of requirements, module examples, and integration constraints.

## Recommended Framing for the Two Tracks

- `ScriptureStudy`: active product branch
- `Reading/Search Engine V2`: parallel subsystem rebuild

If a separate Xcode target is created for testing, then `ScriptureStudy Prototype` is a good target name. It is not the best name for the current app branch.

## Summary

This is a subsystem rebuild, not a full app restart.

The work is meaningful because:

- the app already has real module volume
- the module pipeline is advancing
- the current search/reading architecture is now the limiting factor

The parallel team should rebuild the reading/search engine from the bottom up, prove each primitive independently, and only then reconnect those primitives into a unified UI.
