# Strong's Dataset Handoff

This note is the durable handoff for the Strong's dataset issue that affected the bundled Bible loader and validation layer.

It is intended for another agent or developer picking up the reference/lexicon work without replaying the original debugging loop.

## Short Version

The Strong's dataset problem was **not** a bad SQLite schema and **not** a simple duplicate-row cleanup task.

The real issue was:

- the loader introduced an integer-only Strong's normalization rule
- that rule collapsed distinct bundled dictionary IDs into the same canonical key
- validation then correctly reported collisions that were created by the normalization policy, not by duplicate semantic entries in the dictionary

The fix was:

- preserve distinct bundled extended dictionary IDs such as `G00311` and `G03111`
- keep verse-tag normalization separate from dictionary-key normalization
- continue normalizing standard keys like `g03056` to `G3056`

## What Failed

The first visible failure looked like this:

- `Duplicate Strong's key after normalization: G3111`

That surfaced during bundled Bible runtime materialization when the validation helper attempted to canonicalize dictionary entries.

At that stage, the working assumption was:

- the dictionary might contain duplicate logical Strong's entries
- examples looked like:
  - `G3111`
  - `G03111`
- the validator treated both as the same canonical key after integer normalization

## The Initial Incorrect Diagnosis

The first hypothesis was:

- `G00311` is just a padded version of `G311`
- `G03111` is just a padded version of `G3111`
- therefore the dictionary contains duplicate logical rows after stripping padding

That diagnosis led toward a possible SQL cleanup path:

- enumerate normalized duplicate `topic` values
- inspect representative groups
- delete or merge duplicates

This turned out to be wrong.

## The Evidence That Broke The Duplicate Theory

The critical SQLite table is:

- file:
  - `References/Strong_Dictionary.SQLite3`
- table:
  - `dictionary`
- key column:
  - `topic`

Two representative comparisons were inspected manually.

### Example 1

- `G3111`
  - lemma: `μάκελλον`
  - gloss: `shambles`
- `G03111`
  - lemma: `ἀνάγαιον`
  - gloss: `upper room`

These are clearly different lexicon entries.

### Example 2

- `G311`
  - lemma: `ἀναβολή`
  - gloss: `delay`
- `G00311`
  - lemma: `ἀγγέλλω`
  - gloss: `tell`

Again, clearly different entries.

So the collision was being caused by the normalization rule, not by actual duplicate semantic rows.

## What The Dictionary Actually Contains

The bundled dictionary contains a small set of zero-prefixed Greek keys like:

- `G00311`
- `G00321`
- `G00951`
- `G03111`
- and related forms

Observed properties:

- there are `21` confirmed `G0...` entries in the bundled project files
- they are valid lexicon entries
- they are distinct from nearby standard Strong's numbers
- they should not be collapsed into integer-only IDs

We did not prove a full external semantics for the `G0...` convention, but we did prove the operational rule that matters for the app:

- these keys are meaningful, bundled, and distinct
- the loader must preserve them as distinct dictionary identities

## Comparison Against `SECE.dictionary.SQLite3`

Two bundled dictionary files were compared:

- `References/Strong_Dictionary.SQLite3`
- `References/SECE.dictionary.SQLite3`

Confirmed results inside this project:

- same SQLite table layout
- same `dictionary` row count:
  - `14364`
  - `14364`
- same confirmed `21` `G0...` entries
- same lexemes for those confirmed `G0...` entries

So the comparison did **not** support this theory:

- one file is a clean original dictionary
- the other file is the only enhanced/extended outlier

At least in the bundled project files, both currently carry the same confirmed extended Greek forms.

## Hebrew Side

The Hebrew side was not the original source of the loader collision.

The normalization policy was updated to preserve extended zero-prefixed forms generically rather than only for Greek:

- standard example:
  - `H01200` -> `H1200`
- preserved extended-form example:
  - `H00031` -> `H00031`

This was added as test coverage so the policy is not Greek-only in code.

Important nuance:

- we did not fully inventory all Hebrew `H0...` forms yet
- but the implementation now avoids repeating the earlier mistake of collapsing every zero-prefixed dictionary key into an integer-only ID

## The Real Fix In Code

The fix was implemented in:

- [ReaderModels.swift](/Users/richardbillings/XcodeOffline/Graphē One Codex/Graphē One Codex/ReaderModels.swift)
- [BundledSQLiteBibleLoader.swift](/Users/richardbillings/XcodeOffline/Graphē One Codex/Graphē One Codex/BundledSQLiteBibleLoader.swift)
- [LibraryCatalogPersistence.swift](/Users/richardbillings/XcodeOffline/Graphē One Codex/Graphē One Codex/LibraryCatalogPersistence.swift)

### Boundary Rule Now In Force

Dictionary-key normalization:

- trim whitespace
- uppercase prefix
- preserve meaningful zero-prefixed bundled IDs when they represent distinct lexicon entries

Standard key normalization:

- `g03056` -> `G3056`
- `H01200` -> `H1200`

Preserved extended forms:

- `G00311` stays `G00311`
- `G03111` stays `G03111`
- `H00031` stays `H00031`

### Separation Of Concerns

Verse-tag normalization and dictionary-key normalization are separate concerns:

- verse tags:
  - numeric tag + testament prefix -> standard key like `G3056` or `H7225`
- dictionary keys:
  - preserve distinct bundled dictionary identities if the corpus uses them

That separation is important.

The original bug came from forcing both paths through the same lossy integer-only normalization.

## Why The Runtime Loop Became Unreliable During Debugging

The runtime/debug loop got noisy for four reasons:

1. validation became strict enough to surface the issue
2. bundled Bible runtime creation was still assumed to succeed in some helper paths
3. some tool runs crashed or timed out once validation failed
4. earlier silent fallback behavior had hidden the real issue

So the debugging loop looked worse than the underlying architecture actually was.

The issue was not a broad reader/runtime design flaw.

## How Failure Surfacing Was Changed

Previously, bundled SQLite Bible failure could fall back to the sample reference document in ways that obscured the real error.

That was tightened so debug/test behavior no longer silently pretends the bundled Bible loaded successfully.

Also:

- the hard assertion stop was replaced with a non-fatal debug print plus `nil` return

This matters because it lets tests report a bad load condition without killing the whole test process immediately.

## Test Coverage Added

Relevant validation/test coverage now includes:

- extended key normalization:
  - `G00311` stays `G00311`
  - `G03111` stays `G03111`
  - `H00031` stays `H00031`
- duplicate rejection still works for true collapsing standard keys
- bundled Bible representative Strong's mappings resolve correctly
- bundled Bible runtime still resolves canonical addresses correctly

The project also returned to a green full-suite baseline after the fix.

## What Another Agent Should Not Do

Do **not**:

- reintroduce integer-only normalization for all dictionary IDs
- assume zero-prefixed keys are malformed padded duplicates
- run SQL cleanup deleting `G0...` rows just because they collide after stripping zeros
- couple verse-tag canonicalization to dictionary-key canonicalization again

Those would recreate the original bug.

## What Another Agent Can Safely Do Next

Safe next directions:

- inventory Hebrew `H0...` entries more thoroughly if desired
- compare shared topic definitions between `Strong_Dictionary` and `SECE.dictionary`
- keep expanding passage-to-passage coverage in the cross-reference corpus
- improve the lexicon UI surface further without changing layout/navigation
- eventually design dictionary selection if `SECE` should become user-selectable

## Current Product Decision

Current documented policy is:

- keep both dictionary files in the repository for now
- continue shipping `Strong_Dictionary.SQLite3` as the active default runtime lexicon
- treat `SECE.dictionary.SQLite3` as a comparison/reference asset until a deliberate runtime switch or selection model is designed

See also:

- [DECISIONS.md](/Users/richardbillings/XcodeOffline/Graphē One Codex/Graphē One Codex/docs/DECISIONS.md)
- [REFERENCE_PROGRESS.md](/Users/richardbillings/XcodeOffline/Graphē One Codex/Graphē One Codex/docs/REFERENCE_PROGRESS.md)
