# Spec Delta

## Purpose

Execute a documented finite Lua event-script subset on blue computers as bounded native handlers, retaining explicit state rather than virtual-machine instructions or suspended stacks.

## ADDED Requirements

### Requirement: Real local source execution without a VM
`run PATH` and direct local `.lua` path invocation SHALL compile and execute the exact committed file using native handlers only. No VM, opcode/AST interpreter, experimental continuation dispatcher or hidden fallback is permitted. Unsupported syntax MUST be refused with bounded source-position diagnostics before activation.

#### Scenario: Run edited source
- **WHEN** a user creates and saves a supported program with edit and runs its path
- **THEN** its actual saved statements execute, produce observable output/state or circuit effects, and guarded VM/continuation entry points are never reached

### Requirement: Finite event language
Programs SHALL return a literal descriptor containing a bounded tick interval and optional `on_start(event,state)`/`on_tick(event,state)` functions, with at least one handler. Supported handler statements SHALL be scalar locals/assignments, conditionals, do blocks, return and direct allowlisted service calls. No loops, recursion, nested functions, modules, dynamic code, method calls, callable aliases, computed indexing or metatables are permitted.

#### Scenario: Reject non-finite or escaping source
- **WHEN** a file includes while/repeat/for, goto, recursion, load/require, game access, aliased API calls, binary chunks or unlisted AST constructs
- **THEN** activation is rejected without running top-level effects, mutating a controller or consulting a fallback runtime

#### Scenario: Bounded scalar values
- **WHEN** accepted handlers use arithmetic, boolean expressions, finite numbers and bounded strings with literal state fields
- **THEN** normal scalar behavior is preserved, while nonfinite or oversized results fault visibly without leaking host values

### Requirement: Whole-callback shared admission
Every compile/reconstruction/callback/publication SHALL consume existing durable per-computer and aggregate work credits. A complete conservative callback cost MUST be admitted before any native handler executes. Programs exceeding a fresh allowed envelope MUST be refused; exhausted current credits MUST defer without partial handler execution or renewal on same-tick reload.

#### Scenario: Zero-credit inactivity
- **WHEN** a callback is due with insufficient credits, including after same-tick cold reload
- **THEN** its event, state, output and world effects remain unchanged and it runs at most once after legitimate later-tick admission

#### Scenario: Maximum accepted handler beside a neighbor
- **WHEN** maximum accepted programs compile and dispatch beside interactive original and blue computers
- **THEN** shared counters stay within their unchanged ceilings and the terminal-model p95 two-tick echo target remains verified rather than inferred from native inner-loop speed

### Requirement: Validated effects and fault handling
Handlers SHALL stage state, text and signal changes for bounded validated publication after successful return. Expected validation or admission failure MUST publish none of that callback's staged effects. A runtime/engine fault MUST stop the controller visibly, retain source/state recovery data and safely clear its owned automation outputs.

#### Scenario: Error after staging output
- **WHEN** a handler stages a signal/text/state update and then produces an invalid result
- **THEN** no staged update is committed and the controller faults with bounded diagnostics and owned-output fail-safe cleanup

### Requirement: Explicit background controller lifecycle
A blue computer SHALL run at most one controller with `ps` and `stop`, while the shell/editor remains usable. Replacing a running controller MUST require explicit stop. Stop/reboot/shutdown/removal or lost ownership MUST clear owned outputs; power loss MUST pause callbacks and clear outputs. Restoration MUST not replay on_start or trigger a catch-up storm.

#### Scenario: Source edits do not replace a live program
- **WHEN** a user edits the active path and attempts run before stopping
- **THEN** the existing controller keeps its source snapshot, replacement is visibly refused, and a subsequent explicit stop/run activates the new committed bytes

#### Scenario: Power and explicit stop
- **WHEN** power is lost or stop is requested with ordinary credits exhausted
- **THEN** bounded priority cleanup clears owned outputs, retained state survives the pause, and power restoration performs one fresh due evaluation without replaying completed startup effects

### Requirement: Deterministic plain-data persistence
Controller/draft state SHALL use separately versioned plain data, exact active source snapshots, event ownership and absolute deadlines. Native functions/caches MUST remain ephemeral. on_load MUST perform no compilation, migration or effects; cold/peer reconstruction MUST be equally admitted and cannot replay a committed callback. Incompatible records MUST retain recovery data.

#### Scenario: Cold and joining-peer reconstruction
- **WHEN** a supported controller with exhausted credits and pending work is reloaded or reconstructed by a joining peer
- **THEN** event/state/work identity is equal, no effects occur on load, warm/cold admission is equivalent, and later effects occur once

#### Scenario: Copies and unsupported versions
- **WHEN** a running blue computer is cloned/blueprinted, or an incompatible script record is loaded
- **THEN** copies contain committed files but no live program/draft/state/outputs, and incompatible originals remain inert with their source and recovery data preserved

### Requirement: Restricted native interactive Lua shell
`lua` SHALL enter a foreground REPL accepting finite statements and scalar expressions through the same validated native compiler, scalar math/print/circuit services, transactional effects and unchanged shared quotas. Locals SHALL be submission-local; literal `state.FIELD` values SHALL persist within a session. Entry MUST refuse an active background controller. Expressions and scalar returns MUST display false/nil correctly; unsupported syntax and runtime failures MUST leave the session usable without publishing staged effects.

#### Scenario: Interactive evaluation and recovery
- **WHEN** a user enters lua, submits expressions, scalar state assignments and allowlisted calls, then an invalid submission
- **THEN** valid submissions execute once and display bounded results, persistent state survives between submissions and the rejected submission leaves earlier state and signals intact

#### Scenario: Retained pending submission
- **WHEN** the REPL is closed/reopened or cold-loaded with partial input or an admission-deferred submission
- **THEN** input, scalar state and shared credits remain plain retained data, no code runs on load and later admitted execution publishes the pending submission exactly once

#### Scenario: Explicit exit and unsafe ownership
- **WHEN** Exit Lua, exit, Terminate, reboot/shutdown, power failure or ownership invalidation occurs
- **THEN** explicit exit stops the session and clears owned signals, unsafe outputs are cleared, copies exclude session data and no VM or continuation fallback is invoked
