# Notes Editor Design

## Goal

Rebuild the notes subsystem deliberately without destabilizing the rest of the app.

Target architecture:

- `Notes` owns note editing
- `Companion` may surface note-specific views where appropriate
- `Organizer` is not a note editor

This document defines the intended direction before code changes.

## Current Baseline

Current stable implementation:

- `Note.swift` stores note body as plain `String`
- `NotesManager.swift` persists notes as text files in the local documents folder or iCloud container
- `NotesView.swift` is the main note-editing surface
- `CompanionPanel.swift` contains a second note-editing surface for verse-linked notes
- `NoteTextEditor.swift` is a plain-text `NSTextView` wrapper with markdown-style insertion helpers

Observed weakness:

- editing UI is duplicated across `NotesView` and `CompanionPanel`
- note formatting is only markdown insertion, not rendered formatting
- previous attempt to retrofit rich text directly into the live editor path destabilized the wider app

## Non-Goals

Not in the first redesign pass:

- full app rewrite
- reorganizing unrelated Bible/Companion/navigation architecture
- replacing iCloud note storage with Core Data or CloudKit-only storage
- live markdown rendering in the shipping editor path before the editor model is redesigned properly

## Desired User Experience

Users should be able to:

- create and edit notes in one primary place
- view verse-linked notes from Companion without needing a second divergent editing model
- apply formatting without dealing with raw markdown syntax
- trust that editing notes does not interfere with Bible navigation, popovers, pickers, or tab state

Longer-term desired editor capabilities:

- rich text formatting
- scripture and Strong's auto-linking
- keyboard shortcuts
- note-to-note links
- insert passage
- tags

## Rich Editor Foundation

This section is the concrete recommendation for the next editor generation.

### Core Decision

The next richer editor should **not** use raw RTF or `NSAttributedString` data as the only persisted source of truth.

Why:

- raw attributed-text blobs are opaque and hard to reason about
- they are poor for migration and testing
- study-specific semantics like scripture links, Strong's links, and note links should not depend on fragile editor-only attributes
- the previous failed rich-text pass showed that tying persistence too directly to editor internals is risky

Recommended split:

- the **editor runtime model** may still use `NSTextView` / `NSAttributedString` on macOS
- the **persisted note model** should be a structured rich-note document format
- plain text remains available as a compatibility/search/export fallback

### Recommended Persisted Model

Add an optional richer payload to `Note`, but keep plain text for compatibility.

Recommended conceptual model:

- `Note.title`
- `Note.content`
  - plain-text fallback, preview text, export fallback, search base
- `Note.richDocument`
  - optional structured payload

Recommended `RichNoteDocument` shape:

- `version`
- `plainText`
- `blocks`
- `inlineRuns`
- `links`

Recommended block model:

- paragraph
- heading levels
- bullet list item
- numbered list item
- quote block later if needed

Recommended inline style model:

- bold
- italic
- underline later if needed
- code later if needed

Recommended link model:

- scripture reference link
- Strong's link
- URL
- note link

This means the editor can render rich text visually while persistence stays explicit, migratable, and testable.

### Why Structured Document Beats Raw RTF

Structured rich-note JSON gives us:

- deterministic migrations
- easier validation
- future portability beyond AppKit
- explicit study semantics
- simpler plain-text derivation

Raw RTF can still exist as a temporary editor interchange format in memory if useful, but it should not be the long-term stored contract.

### Editor Runtime Model

The editor layer should have a dedicated runtime type, separate from `Note`.

Recommended runtime boundary:

- `RichNoteDocument`
  - persisted representation
- `NoteEditorState`
  - current editing state, selection state, dirty state
- `RichNoteBridge`
  - converts between `RichNoteDocument` and `NSAttributedString`

The `NSTextView` should be a rendering/editing surface, not the owner of note truth.

### Save Boundaries

The next rich editor should save using explicit boundaries rather than serializing all editor state on every change.

Recommended save strategy:

- plain text updates after a short debounce
- rich document updates after a slightly longer debounce or idle boundary
- final flush on losing focus / closing note / app lifecycle boundary
- skip save if both plain text and rich payload are unchanged

This is intentionally conservative.

### Search, Preview, and Word Count

These should continue to depend on plain text, not on rich rendering.

That means:

- search index uses `Note.content`
- preview snippets use `Note.content`
- word count uses `Note.content`
- rich formatting never becomes required for basic note operations

This preserves robustness even if rich payload is missing or partially migrated.

### Link Semantics

Study-specific links should be first-class note semantics, not only visual styling.

Recommended link payload fields:

- range
- kind
  - scripture
  - strongs
  - url
  - note
- target payload

Examples:

- scripture target: book/chapter/verse set
- Strong's target: number plus testament context if needed
- note target: note UUID

This allows:

- stable re-rendering
- future re-theming
- click behavior independent of editor internals

### Migration Strategy

Migration must be incremental and reversible.

Recommended rules:

- old notes with only `content: String` continue to load unchanged
- first rich edit generates `richDocument`
- plain text is always regenerated from the rich document on save
- notes without `richDocument` continue to behave as plain notes

So migration is:

- lazy
- per-note
- backward-compatible

### Recommended File Format Evolution

Do not replace the current line-based note format abruptly.

Recommended next step:

- keep current header fields for note metadata
- keep `---` separator
- after the separator, store a small structured body envelope instead of plain free text for rich notes

Conceptual body envelope:

- `mode: plain | rich`
- `plainText`
- `richDocument`

Plain notes can continue storing body text directly during transition if that keeps migration simpler.

Longer-term, a JSON body envelope is cleaner than trying to infer format from arbitrary text.

### Companion and Notes Responsibilities

With a richer editor, the ownership boundary should stay strict.

`Notes` should own:

- rich editing
- formatting commands
- migration of notes into rich form
- advanced insertions and note-linking

`Companion` should own:

- reading
- contextual opening
- verse-linked filtering
- handoff to `Notes`

This reduces the chance of future editor regressions spilling back into Bible interaction.

## Monetization Rule

This is an app-wide architectural rule, not only a notes rule.

The app should support:

- trials
- subscriptions
- one-time unlocks
- tiered premium capability gates

But those monetization choices must operate at the capability layer, not the data-survival layer.

Required rule:

- user content must remain readable and durable even when premium access expires

That means:

- premium can gate advanced editing
- premium can gate richer study intelligence
- premium can gate advanced export and workflow features
- premium should not make persisted user notes unreadable
- premium should not make core user data depend on an active entitlement

For notes specifically:

- plain-text fallback must remain readable
- rich-note payload must remain loadable
- premium may control whether the user can use richer editing tools
- premium may control enrichment features like scripture auto-linking, Strong's linking, tags, or note links

This same principle should apply across the rest of the app UI.

## Concrete Next Code Step

The next code step after this document is:

- add the concrete `RichNoteDocument` model types without replacing the current editor
- keep them isolated from the shipping editor path at first
- then build the bridge layer and migration logic on top of those types

## Architecture Direction

### 1. Editing Ownership

Primary rule:

- `NotesView` is the canonical editor surface

Supporting rule:

- `CompanionPanel` may show note drill-ins, but should not evolve a separate editor model or persistence path

Implication:

- editor logic should be shared from one subsystem, not copied into multiple view-specific implementations

### 2. Storage Strategy

Keep the current storage approach in the near term:

- continue using file-backed notes
- continue supporting iCloud container storage already present in `NotesManager`

Migration direction:

- add support for richer note content without breaking existing plain-text notes

Recommended model evolution:

- keep `content: String` as compatibility/search/export/plain preview text
- add an optional richer payload later, such as attributed-text data
- ensure old notes load unchanged
- ensure new notes can still derive plain-text fallback for preview/search/word count

This means storage should become dual-representation, not hard-switched in one step.

### 3. Editor Subsystem Boundary

Create a distinct notes editor subsystem with these responsibilities:

- editor view wrapper
- formatting commands
- conversion between editor content and persisted note model
- save policy
- shared toolbar/actions

Views like `NotesView` and `CompanionPanel` should consume this subsystem rather than each owning formatting behavior directly.

### 4. Save Policy

Save policy must be conservative and boring.

Requirements:

- no save loops
- no publishing changes during view updates
- no attribute-only churn that destabilizes SwiftUI state
- no synchronous heavy serialization on every keystroke

Recommended behavior:

- debounce plain content changes
- perform richer serialization only at clear boundaries
  - after idle period
  - on end editing
  - on explicit selection change if needed later
- skip no-op saves

### 5. Companion Role

Companion should support:

- showing notes for a selected verse
- opening a note in a drill-in view
- optionally editing via the shared editor subsystem only if stable

But Companion should not:

- carry a divergent note model
- own separate persistence logic
- become the primary note-management experience

## Phased Plan

### Phase 1. Stabilize and Consolidate

Objective:

- keep current plain-text behavior
- remove duplication and debug noise
- define one shared editor path

Tasks:

- remove temporary note debug logging
- normalize shared formatting toolbar/actions between `NotesView` and `CompanionPanel`
- document which view owns which note responsibilities

Success condition:

- no behavior change to the user beyond cleanup
- app remains stable

### Phase 2. Introduce Shared Editor Core

Objective:

- pull note editing behavior into a distinct subsystem without changing storage format yet

Tasks:

- centralize formatting actions
- centralize save/debounce behavior
- centralize editor wrapper ownership

Success condition:

- Notes and Companion use the same editor core
- fewer note-specific behaviors are view-local

### Phase 3. Add Rich Content Model

Objective:

- evolve note persistence to support rich content while keeping backward compatibility

Tasks:

- extend `Note` with optional richer content payload
- update `NotesManager` load/save to support old and new note formats
- derive plain-text fallback from richer content when needed

Success condition:

- existing notes still load
- new notes can persist richer content safely

### Phase 4. Replace Plain-Text Editing with Real Rich Editing

Objective:

- move from markdown insertion to true formatting behavior

Tasks:

- upgrade the editor wrapper to a real rich-text editing model
- make bold/italic/heading/list apply formatting, not literal syntax
- keep save boundaries conservative

Success condition:

- formatting does not leak syntax into the note body
- app stability remains intact

### Phase 5. Enrichment Features

Objective:

- add study-specific intelligence on top of a stable editor

Potential features:

- scripture auto-linking
- Strong's auto-linking
- find/replace
- note-to-note links
- insert-passage
- tags

## Immediate Next Step

The next implementation step should be:

- formalize the rich editor contract before implementation

Concrete immediate tasks:

- add concrete model types for the next rich-note phase on paper first
- decide exact persisted shape for `RichNoteDocument`
- decide how `Note.content` is regenerated from rich data
- decide which formatting features are in scope for v1
- keep the current markdown editor shipping until those decisions are complete

Only after those choices are fixed should code move into the next phase.

## Notes

This plan assumes:

- the current stable workspace remains the source of truth
- iCloud-backed file storage remains in use for now
- architecture improvement is iterative, not rewrite-based
