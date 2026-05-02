# `.graphe` Runtime V2 Handoff

## Purpose

This document replaces the earlier "improve the mixed-format search stack" framing for the parallel team.

The new mandate is explicit:

- build the future runtime architecture
- treat `.graphe` as the only supported runtime module format
- treat SQLite support as legacy migration infrastructure, not part of the target design

This is no longer a search-only refinement effort. It is an architecture transition effort.

## Declared Product Rule

Going forward, the intended runtime environment is:

- closed
- proprietary
- `.graphe`-only

That means:

- raw `.sqlite3` modules are not a long-term runtime target
- in-app mixed-format runtime support is not a goal
- conversion belongs to controlled tooling and ingestion pipelines
- search, reading, dictionary, commentary, and interlinear access must converge on one proprietary module contract

## What The Parallel Team Is Building

The team is not being asked to stabilize the current app's mixed architecture.

The team is being asked to define and prove:

1. a `.graphe`-first module contract
2. a proprietary runtime access layer
3. a unified reading/search engine
4. a routing contract that assumes one runtime module environment
5. the boundary between conversion tooling and runtime consumption

## What The Team Is Not Building

The following are explicitly out of scope for the target architecture:

- ongoing runtime support for raw `.sqlite3` modules
- ad hoc compatibility branches for legacy search paths
- a UI-first rebuild
- conversion utilities embedded into the runtime engine
- preserving the current app's storage assumptions for their own sake

## Revised Principles

1. Build bottom-up, not top-down.
2. Prove module access before building aggregate search.
3. Assume `.graphe` is the runtime format.
4. Keep conversion outside the runtime layer.
5. Keep engine logic separate from SwiftUI.
6. Every architectural choice must be tested against one question:
   - does this move the system toward a closed `.graphe` runtime, or does it drag legacy assumptions forward?

## Architecture Target

### 1. Module Contract

Define a stable module identity that does not leak storage details into higher layers.

The module contract should include:

- module id
- module category
- module display metadata
- supported content surfaces
- routing capabilities

Higher layers should not care whether content was once imported from SWORD, MySword, or another source.

### 2. Runtime Access Layer

Create a dedicated access layer for `.graphe` modules only.

This layer should be responsible for:

- opening modules
- reading structured content safely
- handling decryption or transformation if required
- exposing normalized content records to the engine

It should be the only layer allowed to know proprietary storage internals.

### 3. Search Engine Layer

Build search against the proprietary runtime contract, not against mixed legacy schemas.

Required characteristics:

- deterministic limits
- bounded execution
- cancellation-aware behavior
- stable result ordering
- structured snippets

### 4. Unified Result Model

Define one result model that can represent:

- Bible passage hits
- commentary hits
- dictionary hits
- encyclopedia hits
- interlinear-linked hits if applicable

The result model should carry:

- result kind
- module identity
- display label
- snippet
- route payload

### 5. Routing Contract

Do not let the UI infer navigation behavior from fragile field combinations.

Define explicit routing payloads for:

- open Bible location
- open article
- open commentary section
- open interlinear/lexicon destination

## Conversion Boundary

The product intends to remain closed at runtime, but imported ecosystems may still matter operationally.

Therefore:

- conversion from SWORD / MySword / other sources may continue to exist
- conversion should be treated as controlled ingestion
- converted output should target the proprietary `.graphe` runtime format
- the runtime engine should not depend on source-format conversion code

The clean boundary is:

- tooling converts inbound sources into `.graphe`
- app runtime consumes `.graphe`

## Suggested Delivery Order

1. Define `.graphe` module contract
2. Prove one module open/read path
3. Prove one Bible query primitive
4. Prove one dictionary/article query primitive
5. Prove one commentary query primitive
6. Define unified result and routing models
7. Add tests around all primitives
8. Add a thin sandbox UI only after the engine is credible

## Test Expectations

Minimum tests should prove:

- `.graphe` module open
- `.graphe` content read
- snippet generation
- query limiting
- route payload correctness
- cancellation boundaries
- dictionary/article HTML-capable rendering contract

## Relationship To The Current Repo

The current `ScriptureStudy` repo should be treated as:

- a source of requirements
- a source of sample modules and behaviors
- a source of migration constraints

It should not be treated as the target architecture.

## Success Condition

The team succeeds when it can show:

- a credible `.graphe`-only runtime module engine
- clean separation between conversion and runtime
- unified search/reading behavior without legacy mixed-format branching

That is the actual V2 target.
