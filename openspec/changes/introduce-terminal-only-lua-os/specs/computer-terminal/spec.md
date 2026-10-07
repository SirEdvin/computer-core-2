## Purpose

Provide a stable CC-style color character display which Lua programs can render independently of Factorio window layout.

## ADDED Requirements

### Requirement: Startup-configurable terminal geometry
The native terminal SHALL use mod-wide startup integer settings for columns and rows, defaulting to 51 and 19, with documented validated bounds and one-based cell coordinates. Physical and personal computers SHALL use the configured dimensions, shared by all viewers and fixed during play. Presentation scaling SHALL NOT change geometry or generate resize events.

#### Scenario: Configured dimensions on boot
- **WHEN** a computer boots with supported nondefault startup columns and rows
- **THEN** term.getSize() reports those dimensions and every viewer sees the same character grid

#### Scenario: Settings outside supported bounds
- **WHEN** a terminal dimension is configured outside its documented supported bounds
- **THEN** the configuration is rejected rather than allocating an unbounded grid

#### Scenario: Display scale changes
- **WHEN** a viewer changes display scale or available window space
- **THEN** term.getSize() remains equal to the startup-configured dimensions and the same character cells are shown without a synthetic term_resize event

### Requirement: Saved terminal dimension reconciliation
When startup dimensions change between loads, the system SHALL reconcile saved displays without rebooting guest execution or altering file/editor content. It SHALL preserve overlapping cells and palette/cursor state, initialize new cells with current colors, clip removed cells, and deliver one term_resize notification before new viewer input. Unchanged settings SHALL NOT generate a resize event.

#### Scenario: Reload with different dimensions
- **WHEN** a save with a suspended editor is loaded with different supported startup dimensions
- **THEN** the display is reconciled, its guest receives term_resize to redraw, and unsaved editor text and saved files remain intact

#### Scenario: Reload with unchanged dimensions
- **WHEN** the same startup dimensions are used on reload
- **THEN** the saved grid resumes without a geometry change or an additional term_resize event

### Requirement: Cell writing and blitting
The terminal SHALL implement write, blit, clear, clearLine, getSize, getCursorPos and setCursorPos with CC-style clipping and cursor advancement. Blit SHALL require equally sized text/foreground/background strings and valid hexadecimal palette indices; invalid arguments SHALL fail without partial mutation.

#### Scenario: Blit colors
- **WHEN** Lua blits three characters with distinct foreground and background indices
- **THEN** the corresponding cells retain their independent characters and colors and the cursor advances three columns

#### Scenario: Invalid blit is atomic
- **WHEN** text and color lengths differ or a color contains an invalid index
- **THEN** the call raises a guest error and no cell or cursor is changed

#### Scenario: Off-screen cursor
- **WHEN** a program writes from a cursor outside the visible grid
- **THEN** only intersecting cells are changed, the cursor advances according to the written length, and no implicit wrapping occurs

### Requirement: Scrolling and cursor blink
The terminal SHALL implement signed scroll and cursor blink getters/setters. Scrolling SHALL shift cells within the grid and clear exposed rows with current colors; an off-screen cursor SHALL not render outside the display.

#### Scenario: Scroll in both directions
- **WHEN** a program scrolls by a positive or negative row count
- **THEN** existing rows move in the documented direction and vacated rows are cleared without changing terminal dimensions

### Requirement: Colors and palette
The terminal SHALL provide a 16-color palette, color capability queries, text/background color getters/setters, RGB and packed-color palette access, and corresponding Color/Colour aliases. Palette mutation SHALL affect existing cells using that palette entry.

#### Scenario: Palette update changes existing cells
- **WHEN** Lua changes a palette entry already used by visible cells
- **THEN** those cells render with the new RGB color and palette reads return the updated values

### Requirement: Redirectable terminal helpers
The guest SHALL provide native/current/redirect terminal behavior and upstream colors/colours, window and paintutils helpers compatible with the selected OS. Redirecting to a window SHALL preserve parent display clipping and allow restoring the previous target.

#### Scenario: Invisible window redraw
- **WHEN** a Lua window is hidden, changed, and then shown
- **THEN** its buffered contents appear at its parent-relative location without leaking changes while hidden

### Requirement: Faithful bounded presentation
The display SHALL show independent per-cell foreground/background colors, readable glyphs and cursor blink in the actual Factorio client. Supported character encoding and fallback behavior SHALL be documented; presentation SHALL NOT alter stored file bytes.

#### Scenario: Unsupported glyph does not corrupt source
- **WHEN** a file contains text outside the supported display glyph set
- **THEN** presentation uses the documented fallback while saving and reopening preserves the original file content
