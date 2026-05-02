# V2 Profile-Driven Engine Alignment Handoff

## Purpose
This note hands back the architectural consequences of the latest V2 update to the parallel engine team.

The important change is not incremental feature progress. The important change is that V2 is now **profile-driven** rather than **schema-branch-driven**. That makes V2 more clearly the canonical engine architecture for future convergence.

## What Changed In This Repo Since The Last Alignment
This repo continued converging toward the V2 shape before the latest V2 profile-registry update arrived.

Recent convergence work completed here:

- Catalog/runtime boundary tightened further.
  - `ModuleCatalogService` no longer opens SQLite directly for module inspection.
  - module inspection now goes through `GrapheRuntimeModuleInspecting` / `GrapheRuntimeModuleAccessor` in `GrapheRuntimeStorage.swift`
- `MyBibleService` was reduced further toward a state/orchestration shell.
  - book metadata queries moved into `ModuleContentService`
  - selection restoration policy moved into `ModuleCatalogService`
  - passage-navigation parsing/state moved into shared runtime types
  - dictionary/reference fallback module-selection policy moved into shared runtime types
- Shared policy/helper types now exist in this repo for:
  - scripture book catalog
  - module selection resolution
  - module lookup fallback resolution
  - passage navigation resolution
  - passage state
- Hardening tests were added and are green for:
  - module selection resolution
  - module lookup fallback resolution
  - passage navigation parsing/state
  - search route construction
  - search mode ordering

## What The Latest V2 Update Changes Strategically
The new V2 handoff says the runtime engine is now:

- profile-driven
- registry-based for schema validation
- capability-aware for search/read filtering
- metadata-source-agnostic with embedded-first resolution
- explicit about validation states:
  - `ready`
  - `readableOnly`
  - `rejected`

That means the next convergence target is no longer “extract more helpers until things look cleaner.”

The next convergence target is:

- align this repo to the same **profile/registry/validation-state** concepts

## What This Repo Now Needs To Know From V2
Please confirm whether the following are now the intended canonical engine concepts:

1. `RuntimeModuleSchemaValidator` is the permanent registration point for supported runtime profiles.
2. validation state is a first-class runtime output, not just an internal detail.
3. capability-aware filtering should be treated as part of the engine contract, not just sandbox behavior.
4. embedded metadata remains preferred, sidecar fallback remains transitional compatibility.
5. the public engine should continue to hide the transient internal SQLite representation even if it still exists privately.

## Questions Back To V2 Team
Please answer these specifically so this repo can align cleanly:

1. Do you want this repo to adopt the same profile/validator terminology exactly?
2. Are the current V2 schema profile names now stable enough to reference externally?
3. Should validation-state concepts (`ready`, `readableOnly`, `rejected`) be mirrored into this repo next, or should this repo stop short and treat V2 as the sole canonical engine branch?
4. Has V2 made any new decision about where embedded metadata physically lives inside `.graphe`?
5. Do you want helper/policy names in this repo to move closer to V2 naming, or is looser conceptual convergence acceptable for now?

## Recommendation
Given the latest V2 update, my recommendation is:

- treat V2 as the canonical engine architecture
- do not invent a competing schema abstraction in this repo
- if more convergence work continues here, prioritize:
  - profile/registry concepts
  - validation state concepts
  - capability-aware module filtering

and **de-prioritize arbitrary local extraction work** unless it directly reduces drift from the V2 engine shape.

## Bottom Line
This repo is now materially cleaner and more test-hardened than it was:

- thinner `MyBibleService`
- cleaner catalog/runtime boundary
- shared policy helpers extracted
- green targeted hardening tests

But the latest V2 handoff raises the bar:

- V2 is no longer just a cleaner implementation
- it is now a more explicit engine model

That means future convergence should be guided by the V2 profile/registry/validation architecture, not just by general cleanup instincts.
