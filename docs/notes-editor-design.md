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

- continue Phase 1 and Phase 2 only

That means:

- do not attempt rich text yet
- do not change note storage format yet
- first consolidate the editing path and reduce duplication

## Notes

This plan assumes:

- the current stable workspace remains the source of truth
- iCloud-backed file storage remains in use for now
- architecture improvement is iterative, not rewrite-based
