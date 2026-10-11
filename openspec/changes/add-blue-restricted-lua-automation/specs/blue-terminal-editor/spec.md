# Spec Delta

## Purpose

Let blue-computer users create and safely edit local Lua source in the terminal without running a VM-based editor or losing drafts on ordinary save/reload.

## ADDED Requirements

### Requirement: Native multiline editor
The blue terminal SHALL provide `edit PATH` for local text files up to 32 KiB, including creation in existing directories, without VM execution. It MUST support newline insertion, cursor navigation, deletion, normalized paste and viewport redraw using the existing authorized terminal input path.

#### Scenario: Edit an existing or new source file
- **WHEN** an authorized user opens a local file, inserts multiple lines, moves the cursor and pastes text in the middle
- **THEN** prefix/suffix bytes and cursor placement are preserved, CRLF paste normalizes to LF, and the terminal renders the draft without invoking any VM

#### Scenario: Refuse invalid or oversized targets
- **WHEN** edit targets a directory, protected /rom path, missing parent or file over 32 KiB
- **THEN** a clear error is shown and committed content and any other draft remain unchanged

### Requirement: Atomic saves and recoverable refusal
Ctrl+S SHALL save a draft through bounded validated atomic publication. Saving MUST preserve unrelated files, respect existing disk quotas and reject a target changed since the draft's base snapshot. Failed saves MUST retain editable dirty text and MUST NOT truncate the previous committed file.

#### Scenario: Successful replacement and file execution
- **WHEN** a user saves edited valid Lua source and subsequently runs that path
- **THEN** the complete saved source becomes committed once, the draft becomes clean only after publication, and execution uses those exact edited bytes

#### Scenario: Exhausted work or changed target
- **WHEN** credits or disk capacity prevent a save, or the target was externally changed
- **THEN** the previous committed disk is preserved, the failure is visible, and the dirty draft remains available for correction or deliberate reopen

#### Scenario: Reload around publication
- **WHEN** a save is persisted before or after its publication boundary and resumed in a cold process
- **THEN** unpublished changes never appear as committed data, a committed save is not duplicated, and unrelated files remain intact

### Requirement: Durable drafts and explicit dirty exit
Ctrl+Q SHALL exit clean drafts and offer save/discard/cancel for dirty drafts. GUI close/reopen and cold save/reload MUST preserve text, cursor, viewport and dirty status. Explicit reboot/shutdown MUST obtain dirty-exit disposition before discarding the draft; clones/blueprints MUST exclude it.

#### Scenario: Cancel leaving a dirty editor
- **WHEN** a user requests exit or reboot and chooses cancel
- **THEN** the draft and controller remain unchanged and editing continues

#### Scenario: Cold resume without input replay
- **WHEN** a dirty multiline draft with a mid-line cursor is loaded in another engine process
- **THEN** no edit or save executes on load, and the next authorized character inserts exactly once at the retained cursor

### Requirement: Shared responsive presentation
Editor interaction SHALL retain existing force/surface/range/research/opened-frame authorization and native capture. Background automation and edit/save jobs MUST share the original work caps. Resize MUST redraw the active editor without requiring a character and MUST NOT steal inactive GUI focus.

#### Scenario: Edit beside an active controller
- **WHEN** a controller runs at its allowed maximum cost while the user edits, pastes and resizes
- **THEN** input reaches only the active authorized editor, no second aggregate allowance is granted, and measured terminal-model echo meets the existing p95 two-tick target
