# Map System Approval Note

The `ScriptureStudy_Map_Final_Spec.md` document is approved for v1 implementation.

The architecture, schema, runtime flow, and module format are now concrete enough for the build team to begin work.

## Approval Scope

Approved to proceed with:

- module-based map assets
- SQLite-backed canonical map schema
- normalized coordinate placement model
- async repository layer
- map engine with programmatic zoom
- author mode for placement capture

## Non-Blocking Follow-Up Clarifications

The following should be treated as implementation notes, not blockers:

1. Add foreign keys and indexes to relational tables, especially `map_placements` and `scripture_links`.
2. Define runtime precedence if manifest defaults and database defaults ever disagree.
3. Decide whether `UNIQUE(place_id, map_id)` should be enforced for `map_placements`, unless multiple placements per place per map are intentionally supported.

## Recommendation

Proceed with implementation against the current final spec and resolve the above clarifications during early build-out.

