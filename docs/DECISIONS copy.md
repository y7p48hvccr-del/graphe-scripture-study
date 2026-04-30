# Decisions

## 2026-04-27 · Bundled Strong's Key Policy

- Preserve distinct bundled lexicon IDs exactly enough to avoid false collisions.
- Standard Strong's keys continue to normalize normally:
  - `g03056` -> `G3056`
- Confirmed bundled extended keys remain distinct:
  - `G00311`
  - `G03111`
- Verse-tag normalization and dictionary-key normalization are separate concerns.

Reason:

- The bundled dictionary corpus contains valid zero-prefixed `G0...` entries that are not malformed padded duplicates.
- Collapsing them into integer-only IDs incorrectly merged different lexicon entries and broke loader validation.

Consequence:

- Loader validation remains strict.
- Dictionary-key normalization must not erase meaningful zero-prefixed bundled identities.

## 2026-04-27 · Bundled Dictionary Runtime Policy

- Keep both bundled dictionary files in the repository for now:
  - `References/Strong_Dictionary.SQLite3`
  - `References/SECE.dictionary.SQLite3`
- Continue shipping `Strong_Dictionary.SQLite3` as the active default lexicon source.
- Treat `SECE.dictionary.SQLite3` as a comparison/reference asset until a deliberate runtime switch is designed.

Reason:

- The current bundled Bible loader, tests, and runtime validation are wired to `Strong_Dictionary.SQLite3`.
- The bundled project comparison established that both dictionaries currently expose the same table shape, the same `dictionary` row count, and the same confirmed `G0...` extended entries.
- There is no product need right now to switch the active runtime lexicon, and doing so would be a content decision rather than a stability fix.

Consequence:

- Runtime stays stable and validated against the existing default lexicon.
- Future lexicon selection work can remain product-facing rather than unblocker work.
