# Team Coordination Protocol

This branch is doing active engine/runtime refactoring. The goal of this protocol is to reduce collisions without adding heavy process.

## Scope

Use this protocol when touching engine or runtime boundary files, especially while multiple engineers are editing in parallel.

## High-Conflict Files

Treat these as high-conflict and announce before editing:

- `GrapheRuntimeStorage.swift`
- `ModuleCatalogService.swift`
- `ModuleContentService.swift`
- `MyBibleService.swift`
- `SearchCoordinator.swift`
- `StrongsLookupService.swift`

If a change will touch more than one of these, announce the whole set up front.

## Announcement Rule

Before editing a high-conflict file, post a short warning in the shared channel.

Recommended format:

- `High-conflict warning: editing ScriptureStudy/GrapheRuntimeStorage.swift next`
- `High-conflict warning: touching ModuleCatalogService.swift and SearchCoordinator.swift`

This is only required for high-conflict files. Do not create overhead for normal UI or leaf-file edits.

## If Someone Else Is Already There

If another engineer is already editing the same high-conflict file:

1. Stop before making the change.
2. Decide who owns that file for the current pass.
3. Either wait, switch to a different file, or agree on a narrow split.

Do not proceed with overlapping edits in the same high-conflict file unless the split is explicit.

## Default Rule For Other Files

For non-high-conflict files:

- proceed normally
- rely on git merge resolution if needed
- only escalate if both people are actively refactoring the same subsystem

## Handoff Expectations

When finishing a substantial pass, include:

- files changed
- architectural intent
- validation performed
- open risks or follow-up items

Keep handoffs short and concrete.

## Markdown And Docs Cleanup

Documentation files may be reorganized into `docs/`, but do not mix that cleanup with source refactors.

- move markdown separately
- do not move Swift files during docs cleanup
- do not combine file organization with runtime architecture changes

## Current Working Assumption

The parent-level Swift files under `ScriptureStudy/` are currently acting as engine or infrastructure files, while `ScriptureStudy/ScriptureStudy/` mostly contains app and UI files.

Do not normalize that source layout casually during active engine work. Revisit it only after the runtime boundary settles.
