## Purpose

Present one Lua-driven terminal per computer with authorized shared input and durable lifecycle behavior inside Factorio.

## ADDED Requirements

### Requirement: Terminal-only computer view
The computer UI SHALL display the character terminal rather than the old workbench, custom shell, file browser or native editor panels. Minimal host window/lifecycle controls SHALL not replace Lua-owned application UI.

#### Scenario: Open computer
- **WHEN** an authorized player opens a booted computer
- **THEN** its existing terminal is displayed and file browsing/editing is performed by Lua programs rather than additional workbench panels

### Requirement: Shared input from all authorized viewers
A physical computer SHALL have one shared OS and terminal. All authorized viewers SHALL be able to submit input without an exclusive owner or input lock. Inputs SHALL enter the shared event stream in synchronized engine event order.

#### Scenario: Two viewers type
- **WHEN** two authorized players send input to the same physical computer
- **THEN** both inputs are admitted in synchronized order to the same session and both viewers observe the resulting shared terminal

### Requirement: Authorization for every input
The system SHALL recheck current research, force, surface and interaction-distance authorization for physical-computer input. Personal-computer input SHALL remain restricted to its owner.

#### Scenario: Viewer walks out of range
- **WHEN** a previously authorized viewer submits input after leaving interaction range
- **THEN** the input is rejected and cannot alter the shared terminal or guest program

#### Scenario: Personal computer isolation
- **WHEN** a different player attempts to submit input to a personal computer
- **THEN** the request is rejected without exposing or altering its private session

### Requirement: Focused keyboard and mouse events
A focused terminal SHALL deliver documented char, paste, key, key_up, mouse_click, mouse_up, mouse_drag and mouse_scroll events with modifiers/repeat semantics and one-based cell coordinates. Input SHALL not be duplicated or unintentionally activate conflicting world controls.

#### Scenario: Keyboard navigation and paste
- **WHEN** a player types, pastes, holds a navigation key or releases a modifier while the terminal is focused
- **THEN** the guest receives the corresponding ordered events exactly once with the documented key/repeat values

#### Scenario: Scaled mouse coordinates
- **WHEN** a player clicks or drags on a scaled terminal cell
- **THEN** the guest receives that cell's coordinates rather than screen-pixel coordinates

### Requirement: Per-viewer pressed state
Pressed input bookkeeping SHALL be isolated per viewer. Closing a view, losing focus or disconnecting SHALL release that viewer's held input without clearing another viewer's held state or stopping the computer.

#### Scenario: One viewer disconnects
- **WHEN** one of two typing viewers disconnects while holding a key
- **THEN** no stuck key remains for that viewer, the other viewer's input continues, and the shared OS is not rebooted

### Requirement: Safe legacy transition
The upgrade SHALL retire named-handler execution and old UI contracts without a legacy runtime. It SHALL preserve stored user files and recoverable editor drafts, avoid automatically executing legacy startup programs, and visibly explain the breaking change.

#### Scenario: Existing save upgraded
- **WHEN** a save containing callback programs, startup content or unsaved editor drafts is upgraded
- **THEN** their recoverable content is retained, callback processes are not resumed, and the terminal OS boots with a migration notice

### Requirement: Lifecycle independent of viewers
Closing a GUI SHALL not shut down or reboot the OS. Existing computer power/ownership lifecycle constraints SHALL remain effective without adding world API compatibility.

#### Scenario: Reopen computer
- **WHEN** the last viewer closes the window and later reopens the powered computer
- **THEN** the current OS session and terminal are shown rather than a new shell instance
