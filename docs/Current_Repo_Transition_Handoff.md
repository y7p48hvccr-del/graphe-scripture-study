# Current Repo Transition Handoff

## Purpose

This document defines how the current `ScriptureStudy` repo should be treated now that the long-term product direction is a declared `.graphe`-only runtime environment.

The point is to stop drifting.

This repo is now a transition branch, not the architectural destination.

## Declared Rule

The long-term target is:

- proprietary runtime modules
- `.graphe`-only runtime support
- conversion as controlled ingestion
- removal of runtime SQLite dependence over time

That rule should guide decisions in this repo even before the full transition is complete.

## What This Repo Is For

This repo still has value, but its role is narrower:

- preserve useful product/UI/domain behavior
- document real requirements
- expose migration obstacles
- isolate legacy runtime assumptions
- avoid introducing new mixed-format complexity

It is not the place to deepen commitment to a split `.sqlite3` / `.graphe` runtime model.

## Immediate Working Assumption

Treat the current runtime stack as legacy compatibility code.

That means:

- SQLite-specific logic should be isolated, not expanded
- search patches that increase mixed-format coupling should be avoided
- new engine abstractions should move toward `.graphe`-first contracts where feasible

## Keep / Isolate / Remove Framework

### Keep

Keep and preserve:

- domain models that are independent of storage format
- useful routing and reading behaviors
- HTML-capable dictionary/article rendering
- UI concepts that can survive an engine replacement
- module metadata that remains valid regardless of backend

### Isolate

Isolate behind explicit boundaries:

- direct SQLite reads
- format detection branches
- decryption/column-read special cases
- mixed search fallback logic
- import/conversion-oriented code that is not truly runtime logic

### Remove

Plan to remove over time:

- broad mixed-format fallback searches
- assumptions that raw SQL `LIKE` is the universal search strategy
- view-layer code that knows too much about storage behavior
- new runtime dependencies on plain `.sqlite3` modules

## Practical Guidance For Work In This Repo

1. Do not build new features that depend on preserving mixed runtime support.
2. Do not add more UI orchestration to compensate for engine weaknesses.
3. If a change touches module access, ask whether it helps future `.graphe` convergence.
4. Prefer narrowing or isolating legacy logic rather than enriching it.
5. Document legacy assumptions when discovered.

## Search/Reading Guidance

The search/reading subsystem in this repo should now be treated as:

- useful for understanding current behavior
- not authoritative as future architecture

If changes are made here, they should aim to:

- reduce instability
- clarify responsibilities
- expose separable engine primitives

They should not aim to make mixed-format runtime support more sophisticated as a permanent solution.

## Relationship To The Parallel Team

The parallel team is building the destination architecture.

This repo supports them by providing:

- requirement examples
- known pain points
- representative module behaviors
- migration constraints

This repo should not try to compete with or duplicate that architecture effort.

## Concrete Output Expected From This Repo

Useful deliverables from this repo now include:

- notes on legacy storage assumptions
- lists of UI behaviors that must survive the transition
- lists of module classes and schema expectations already encountered
- identification of code that should be retired versus ported

## Anti-Goals

Avoid the following:

- recommitting to raw `.sqlite3` as a long-term runtime substrate
- adding new conversion logic into the live runtime path
- building more broad search fallbacks to patch over architectural uncertainty
- pretending the current mixed engine is the future architecture

## Summary

This repo still matters, but as a transition branch.

Its job is to:

- preserve what is valuable
- isolate what is legacy
- avoid deepening the wrong architecture
- help the `.graphe`-only runtime become achievable
