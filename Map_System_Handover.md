# ScriptureStudy Map System Handover

## Purpose

This document hands off the proposed map-system direction for ScriptureStudy to another implementation team.

The goal is to move from static map images toward a structured system where:

- maps are treated as coordinate spaces
- places are stored as data
- scripture can link into maps
- author tooling can create and maintain coordinates

## Core Recommendation

Use a dedicated ScriptureStudy map-module schema as the canonical format.

Do not design the system around arbitrary third-party SQLite schemas first.

Instead:

1. define a clean internal map schema
2. build runtime support against that schema
3. add optional SQLite import adapters later if needed

This keeps the map system stable, authorable, and extensible.

## Architectural Position

The right conceptual model is:

> maps as coordinate systems + places as structured data

Avoid:

- OCR or label detection from images
- hardcoding coordinates in Swift
- depending on inconsistent external database layouts

Prefer:

- normalized coordinates
- module-driven map assets
- authoring tools that write to a controlled schema

## Canonical Module Format

Recommended canonical package structure:

```text
/maps/
    manifest.json
    maps.sqlite
    assets/
        master_map.webp
        exodus_route.webp
        jerusalem_second_temple.webp
```

The exact container can be a ScriptureStudy-specific module format or a `.GRAPHE` package variant, but the schema should be owned by ScriptureStudy.

## Why Not Generic SQLite First

Supporting general SQLite modules directly sounds flexible, but creates avoidable problems:

- schemas will vary
- place naming will be inconsistent
- map selection logic will become fragile
- author mode becomes much harder
- future features will be constrained by imported formats

A generic SQLite-compatible import layer is still possible later, but it should be secondary.

## Recommended Data Model

Do not store everything in a single `places` table.

Recommended minimum schema:

### `maps`

```sql
CREATE TABLE maps (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    asset_path TEXT NOT NULL,
    width INTEGER,
    height INTEGER,
    default_zoom REAL,
    notes TEXT
);
```

### `places`

Represents the canonical entity.

```sql
CREATE TABLE places (
    id TEXT PRIMARY KEY,
    canonical_name TEXT NOT NULL,
    category TEXT,
    aliases_json TEXT,
    notes TEXT,
    source TEXT
);
```

### `map_placements`

Represents where a place appears on a specific map.

```sql
CREATE TABLE map_placements (
    id TEXT PRIMARY KEY,
    place_id TEXT NOT NULL,
    map_id TEXT NOT NULL,
    x REAL NOT NULL,
    y REAL NOT NULL,
    zoom REAL,
    label TEXT,
    FOREIGN KEY(place_id) REFERENCES places(id),
    FOREIGN KEY(map_id) REFERENCES maps(id)
);
```

### `scripture_links`

Optional but strongly recommended.

```sql
CREATE TABLE scripture_links (
    id TEXT PRIMARY KEY,
    place_id TEXT NOT NULL,
    reference TEXT NOT NULL,
    priority INTEGER DEFAULT 0,
    FOREIGN KEY(place_id) REFERENCES places(id)
);
```

## Why `places` and `map_placements` Should Be Separate

This is important.

A single place may appear:

- on multiple maps
- at different zoom levels
- with different labels or emphasis
- in different contextual groupings

For example, Jerusalem may appear on:

- a Levant overview map
- a tribal-territory map
- a kingdom-period map
- a city detail map

Those are not separate places. They are separate placements of one place.

## Coordinate System

Use normalized coordinates:

- `(0,0)` = top-left
- `(1,1)` = bottom-right

Benefits:

- independent of rendered image size
- easy to author
- stable across device classes

Example:

```json
{
  "place_id": "jerusalem",
  "map_id": "southern_levant",
  "x": 0.52,
  "y": 0.34,
  "zoom": 3.5
}
```

## Runtime Behavior

Suggested runtime flow when a user activates a place link:

1. resolve the canonical place
2. select the best map placement
3. load the map asset
4. zoom to the placement coordinates
5. optionally show related scripture references

## Map Selection Rules

This needs explicit implementation logic.

When a place has multiple map placements, the system must decide which one to use.

Suggested priority order:

1. explicit requested map
2. scripture-context map if one is known
3. placement priority field
4. map default marked as preferred
5. fallback to the first valid placement

If this is not defined early, behavior will become inconsistent.

## Author Mode

Author Mode is strongly recommended and should be built early.

Suggested workflow:

1. enable author mode
2. open a map
3. tap or click a point
4. capture normalized coordinates
5. choose an existing place or create a new one
6. assign zoom and optional label
7. save to `map_placements`

This will drastically reduce the cost of building the dataset.

## Authoring Requirements

Author Mode should ideally support:

- crosshair or tap placement
- live normalized coordinate readout
- zoom preview
- create/edit/delete placement
- create canonical place records
- export/import module data

## Integration Options

The system can be integrated with:

- ScriptureStudy internal UI directly
- `.GRAPHE` link records
- scripture references
- search
- timeline and journey systems later

Example conceptual link payload:

```json
{
  "type": "map_link",
  "map_id": "southern_levant",
  "place_id": "jerusalem"
}
```

## Suggested First Implementation Scope

Phase 1 should stay small and controlled.

### Phase 1

- define canonical schema
- load one map asset
- resolve one place and zoom to it
- add minimal author mode

### Phase 2

- add multiple maps
- add place search
- add scripture-to-place linking
- add placement priority logic

### Phase 3

- import/export tooling
- journey/path animation
- thematic overlays
- map-to-scripture navigation

## Initial Dataset Recommendation

Start with a focused dataset rather than trying to cover everything.

Suggested first-pass set:

- ~50 to 100 major biblical places
- 1 overview regional map
- 1 to 3 secondary context maps

This is enough to validate the architecture without overcommitting.

## Key Risks

The main risks are not technical rendering risks. They are modeling and content risks.

### Risk 1: Weak schema

If the schema is too minimal now, later features will be expensive.

### Risk 2: External-format-first design

If the system is built around third-party SQLite structures, the app will inherit their limitations.

### Risk 3: No author tooling

Without author mode, dataset creation will become slow and error-prone.

### Risk 4: Undefined map selection behavior

Multiple placements per place are inevitable. The selection rule must be explicit.

## Final Recommendation

Build this as a ScriptureStudy-owned map module system with:

- canonical schema
- map assets + SQLite data
- separate `places` and `map_placements`
- early author mode
- optional import adapters later

That is the most stable route and the best base for future features.

