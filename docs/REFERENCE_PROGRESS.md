# Reference Progress

This document records the current state of the reference-layer work, what has been completed, what has been validated, and the exact point where progress is currently blocked.

## Completed Architecture Work

The reader/runtime architecture has been extended beyond a simple structured document viewer into a document-scoped reference system.

### Document Runtime

- Introduced `StructuredDocumentRuntime` as the materialized structured runtime bundle.
- Moved document knowledge construction out of `ReaderState` and into the materialization layer.
- Removed the older `knowledgeProfile` fallback shape so structured runtimes now carry their own document-scoped knowledge directly.

### Knowledge and Resolution

- Added `ReferenceKnowledgeContext`.
- Added document-scoped provider composition through `ReferenceStore`.
- Preserved the architectural split:
  - token carries identity
  - provider carries knowledge
  - resolver composes them

### Runtime Attachments

`StructuredDocumentRuntime` now has typed runtime attachments rather than generic future-facing capability flags.

Implemented attachments include:

- search handle
- note store
- highlight store
- research trail store

## Completed Reader Features

### Notes

- Anchored notes persist separately from document content.
- Notes are scoped to the structured runtime.
- Notes can be created from existing reference interactions.
- Notes can be selected from outside the popover.
- Notes render as first-class reference targets.
- Notes support edit/delete.
- Notes appear in passage-level summaries and sidebar sections.
- In-context note indicators render subtly in the reader.

### Highlights

- Anchored highlights persist separately from document content.
- Highlight storage is range-capable via anchored overlay shape.
- Current reader interaction uses exact-anchor highlight toggles.
- Highlights render subtly in-context and participate in the existing reference path.

### Research Trails

- Added simple linear research trails.
- Trails store anchors only, not embedded passage payloads.
- Trails are attached to the structured runtime.
- Trail selection resolves through the existing anchor -> target -> link path.

### Search

- Added a structured runtime search attachment.
- Search is exposed through the existing sidebar surface without changing layout or navigation.
- Search includes passage results and anchored note/highlight results.

### Lexicon Inspection

- Kept the existing reference popover surface and made it more useful instead of introducing a new panel.
- Lexicon targets now surface:
  - gloss
  - lemma
  - Strong's identifier
  - transliteration / pronunciation when available
  - fuller lexical note text
- Token-level reference targets now also carry canonical cross-reference links when the enclosing passage has bundled reference coverage.

## Completed Dataset / Reference Work

### Cross-Reference Dataset

- Replaced the original tiny seeded reference map with a bundled dataset:
  - `References/BundledCrossReferences.json`
- Expanded the corpus into a more systematic thematic set, including:
  - creation / Word / cosmic origin
  - Abrahamic faith
  - Passover
  - wilderness bread
  - greatest command / neighbor-love
  - royal sonship
  - betrayed companion
  - shepherd imagery
  - enthronement / Psalm 110
  - tested foundation / cornerstone faith
  - suffering servant
  - new covenant
  - Spirit / Pentecost
  - resurrection / corruption
  - cornerstone
  - restored tent / Gentile inclusion
  - out of Egypt / son imagery
  - sign of Jonah
  - Son of Man
  - pierced one
  - struck shepherd
- Added reciprocal links where appropriate.

### Strong’s / Lexicon Identity

- Added `lexiconKey` to tokens.
- Ensured the resolver prefers provider-backed lexical identity instead of treating embedded lexicon data as the primary source of truth.
- Fixed a real mismatch where a token could keep an older embedded lexicon entry while receiving a newer `lexiconKey`.

## Validation and Test Work Completed

### Runtime and UI Validation

- Full project builds succeeded multiple times during this work.
- Unit tests were brought back to green after convergence work.
- UI tests were run directly and passed.
- The full test plan was brought back to:
  - 32 passed
  - 0 failed
  - 0 not run

### Test Coverage Added / Improved

Added or improved coverage for:

- bundled cross-reference dataset integrity
- canonical address resolution into the bundled Bible runtime
- cross-reference destination resolvability
- token-level reference targets carrying canonical cross-reference links
- Strong’s consistency across representative OT/NT passages
- search attachment presence
- note store / highlight store / trail store runtime attachment presence
- research trail persistence across recreated runtime materialization

### Swift 6 / Concurrency Cleanup

- Cleaned major warning clusters in:
  - `LibraryCatalogPersistence.swift`
  - `StructuredDocumentParser.swift`
  - `ReferenceStore.swift`
  - `ReaderMetadataSync.swift`
  - `BundledSQLiteBibleLoader.swift`
  - `DocumentLibrary.swift`

## Recent Integrity Work

A thin validation layer was introduced at the loader boundary using the existing project types:

- `BundledCorpusValidation.normalizeStrongKey(_:)`
- `BundledCorpusValidation.validateLexiconEntries(_:)`
- `BundledCorpusValidation.validateTokenLexiconResolution(in:entries:)`
- `BundledCorpusValidation.validateCrossReferenceDataset(_:)`

This validation layer is intended to enforce:

- one canonical internal Strong’s form
- no duplicate normalized lexicon IDs
- no unresolved token lexicon keys
- no malformed cross-reference dataset entries

## Current Status

The previous blocker has now been resolved.

The loader/validation failure was originally surfaced as:

- `Duplicate Strong's key after normalization: G3111`

Further inspection of the bundled dictionary data showed that the failure was **not** caused by duplicate semantic rows in the SQLite database.

Instead, the failure came from an over-aggressive normalization rule that incorrectly collapsed distinct dictionary identifiers such as:

- `G3111`
- `G03111`
- `G311`
- `G00311`

Those keys are not duplicates in the bundled dictionary corpus. They are distinct lexicon entries and must remain distinct in memory.

## Confirmed Dictionary Findings

Two bundled dictionary files were compared:

- `References/Strong_Dictionary.SQLite3`
- `References/SECE.dictionary.SQLite3`

The comparison established:

- same SQLite table layout
- same `dictionary` row count:
  - `14364`
  - `14364`
- the same `21` `G0...` entries are present in both databases
- those `G0...` entries carry the same lexemes in both databases

This means:

- the `G0...` entries are not a one-off corruption in one file
- the project should not treat them as malformed padded duplicates
- there is currently no evidence in the bundled project files that one dictionary is a clean original while the other is the enhanced outlier

## Important Design Decision Reached

The correct boundary rule is now:

- standard Strong's keys remain normalized in the expected way:
  - `g03056` -> `G3056`
- enhanced zero-prefixed dictionary keys that represent distinct bundled entries are preserved:
  - `G00311` stays `G00311`
  - `G03111` stays `G03111`
- verse-tag normalization remains separate from dictionary-key normalization
- dictionary-key normalization must not collapse distinct bundled lexicon identities into integer-only IDs

This is the rule now implemented in code.

## Temporary Failure-Surfacing Change

For bundled SQLite Bible materialization:

- debug/test behavior was changed so loader validation failure no longer silently falls back to the sample reference document
- this was done so bundled Bible tests stop giving false-positive runtime shape and instead surface the real loader problem
- the debug path was also changed from a hard assertion stop to a non-fatal debug print plus `nil` return, so failures no longer kill the entire test run

## Why The Runtime Loop Became Unreliable

The unstable runtime/debug loop was not caused by one single bug in the app architecture.

It became unreliable because several things started happening at the same time:

1. The validation layer became strict enough to surface a real integrity issue at the loader boundary.
   - This was intentional and correct.
   - The first visible symptom was a reported duplicate Strong's entry after canonical normalization.

2. The bundled Bible materialization path was still being exercised through tooling paths that assumed successful runtime creation.
   - When validation failed, the runtime path no longer behaved like a normal content load.
   - This produced confusing symptoms during test/debug runs.

3. Some helper tools proved unstable under this failure mode.
   - The runtime inspection helper crashed.
   - Some Xcode test/helper paths timed out instead of returning a clean failure.
   - That made the first real error harder to isolate quickly.

4. Earlier fallback behavior hid the real problem.
   - The bundled Bible loader could previously fall back to the sample reference document.
   - That created false-positive runtime shape in some tests.
   - Once failure surfacing was tightened, the real dataset problem became visible immediately.

So the unreliable loop was really:

- correct validation
- an incorrect normalization rule
- unstable helper tooling
- previously misleading fallback behavior

The important conclusion is:

- the architecture is not the main blocker
- the validator is not the main blocker
- the main blocker was the bundled Strong's normalization policy, not the architecture

That is why the correct next step was not dataset cleanup.
It was fixing the normalization boundary and rerunning loader validation against the existing bundled corpus.

## What Still Needs To Be Done

The immediate Strong's blocker work is complete:

1. preserve distinct bundled `G0...` dictionary keys during normalization
2. keep standard verse-tag normalization separate
3. rerun bundled Bible loader validation
4. rerun the bundled Bible reference/Strong's tests
5. rerun the full suite

The remaining optional work is documentary and product-facing:

1. record the `Strong_Dictionary` / `SECE.dictionary` comparison outcome in a long-lived project decision note if desired
2. decide whether both bundled dictionaries should remain in the project or whether one should eventually become the primary shipped lexicon
3. expand validation coverage later if further extended-key patterns appear beyond the currently confirmed `G0...` set

## Summary

The project is **not stuck in architecture**.

What has already been achieved is substantial:

- runtime materialization is cleaner
- reference-layer features exist and are integrated
- notes / highlights / trails / search are in place
- bundled cross-reference depth is much stronger
- validation and tests are much stronger
- the full suite is green again

The Strong's issue turned out to be a normalization-model bug, not a bundled-dataset cleanup problem.

That means the current state is straightforward:

- keep the revised validation
- preserve distinct enhanced dictionary IDs
- continue product work from a clean validation baseline
