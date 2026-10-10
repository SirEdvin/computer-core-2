## Purpose

Provide a rewritten shell-only blue computer with trusted built-in commands, durable event-driven interaction and confined local file management, while proving responsiveness rather than general Lua application compatibility.

## ADDED Requirements

### Requirement: Shell-only command environment
The blue computer SHALL boot a rewritten event-driven shell, not the full pinned Recrafted BIOS/scheduler/application suite. It SHALL support only bundled built-in commands. Editors, arbitrary Lua programs, user modules, coroutine applications, shell pipelines/redirection/substitution and hidden VM fallback SHALL be excluded and explicitly unsupported.

#### Scenario: Actual shell workflow
- **WHEN** a user boots a blue computer, types/completes a command and reads/manages local files
- **THEN** the real bundled direct-handler shell performs the workflow and returns to its prompt without launching a general-purpose application runtime

#### Scenario: Unsupported editor or program request
- **WHEN** a user requests an editor, Lua execution, external script/module or excluded shell syntax
- **THEN** the shell reports unsupported/unknown syntax or command without executing a fallback or advertising transparent Recrafted/CC:Tweaked compatibility

### Requirement: Visible initialization before the prompt
The shell SHALL expose an initialization status until its bounded boot/import job atomically installs a validated disk. It SHALL reject command submission while initializing, preserve import progress across viewer closure, power pause and reload, and expose a usable prompt only after admitted completion. Cold boot measurements SHALL begin before construction/import and include all its work without changing responsiveness targets.

#### Scenario: Input during pending import
- **WHEN** a user opens or submits input while first disk initialization is pending
- **THEN** the terminal identifies initialization, input is rejected explicitly without execution, and reopening does not restart the import

#### Scenario: Import completes and is measured
- **WHEN** admitted validation/publication completes
- **THEN** the shell exposes its prompt exactly once with the installed files and cold-boot reporting includes construction/import rather than starting its clock after that work

### Requirement: Built-in command coverage
The shell SHALL provide documented `help`, `pwd`, `cd`, `ls`, `cat`, `mkdir`, `cp`, `mv`, `rm`, `clear`, `reboot` and `shutdown` commands with bounded literal/quoted argument parsing. Invalid commands/arguments SHALL report understandable errors without silently overwriting content or executing input as code.

#### Scenario: Navigate and manage files
- **WHEN** a user creates a directory, changes into it, lists/reads files and copies/moves/removes local content using documented arguments
- **THEN** each command affects only validated local content and reports results/errors matching its published argument and overwrite policy

#### Scenario: Quoted paths and help
- **WHEN** a user requests help or supplies a documented quoted path containing spaces
- **THEN** help identifies the built-in surface and the parser treats the path as data without command substitution or Lua evaluation

### Requirement: Durable command-line interaction
The shell SHALL provide prompt/cursor editing, insertion/deletion, left/right/home/end navigation, bounded up/down history and command/path completion. Partial input, cursor/history and current directory SHALL survive terminal close/reopen and separate-process reload without command resubmission or loss.
Command lines SHALL be bounded at 8,192 bytes. History SHALL retain at most 32 entries and 32,768 total bytes, evicting oldest entries when either limit is reached. Maximum accepted filesystem paths SHALL remain representable with documented literal escaping and two-path commands without increasing shared work, queue, output or filesystem ceilings.

#### Scenario: Maximum literal paths and bounded history
- **WHEN** a user supplies existing maximum-length paths with escaping in a file command and recalls commands after history reaches either bound
- **THEN** valid lines within 8,192 bytes can execute under unchanged shared ceilings, history stays within both bounds, and oversized input is rejected atomically

#### Scenario: Edit and recall a command
- **WHEN** a user inserts/deletes characters in the middle of a command and navigates history
- **THEN** suffix/cursor positions remain correct, history is bounded and Enter submits the selected line exactly once

#### Scenario: Empty-prefix filename completion
- **WHEN** a user types a file command and space, then requests completion with an empty path prefix
- **THEN** completion offers valid local candidates deterministically without corrupting the line or escaping its filesystem

#### Scenario: Partial input reload
- **WHEN** a server saves/restarts with a partially entered command and the user reopens the terminal
- **THEN** the same text, cursor/history and current directory remain available and no command executes merely because of reload

### Requirement: Safe paste and reconciled presentation
The shell SHALL retain existing terminal geometry, palette, cursor/blink and dirty-row contracts with authorized input routing. Paste SHALL insert bounded text without automatic submission and normalize CR/LF to spaces. Resize SHALL preserve command/job state and redraw for reconciled dimensions without requiring another character event.

#### Scenario: Paste at the middle of a command
- **WHEN** multiline text is pasted at the cursor
- **THEN** normalized text is inserted with suffix preservation, no pasted line executes and oversized paste is refused atomically

#### Scenario: Resize while input or output is pending
- **WHEN** geometry changes during partial command input or incremental command output
- **THEN** dimensions are reconciled before redraw, retained text/job progress remains valid and the display updates without another character event

### Requirement: Confined local files and read-only resources
Shell file operations SHALL remain within validated local disk and read-only bundled resources under existing content quotas. File mutation SHALL have documented overwrite behavior and atomic commit; quota/credit refusal or pre-commit cancellation SHALL preserve committed content without exposing host or peer files.

#### Scenario: Copy or move cannot commit
- **WHEN** a file command cannot commit because of quota or temporary service credits
- **THEN** the original source/destination remain consistent, no partial destination is published and temporary-credit refusal preserves retryable bounded job state

#### Scenario: Read-only resource mutation
- **WHEN** a command attempts to overwrite/delete a bundled read-only resource
- **THEN** it reports refusal and both original VM ROM and blue resources remain unchanged

### Requirement: Foreground jobs and explicit lifecycle
Long commands SHALL retain bounded foreground progress and ordered subsequent input. Documented interruption SHALL cancel unpublished work safely and restore the prompt. Reboot/shutdown SHALL preserve committed disk, clean pending work/input according to documented policy and never silently reset a session on ordinary reopen/reload.

#### Scenario: Cancel a long command
- **WHEN** the user interrupts an incremental output/file command
- **THEN** cancellation completes within documented bounds, committed effects remain committed, unpublished staging is discarded and the shell becomes usable again

#### Scenario: Reboot and shutdown
- **WHEN** a user explicitly invokes reboot or shutdown
- **THEN** the documented lifecycle transition clears pending session/job work safely, preserves committed disk and either boots a fresh shell or remains stopped as requested

### Requirement: Honest compatibility and provenance
Documentation SHALL describe built-in commands, event/job/interrupt/lifecycle behavior, text encoding, limits and excluded functionality. Vendor/VM ROM bytes and provenance SHALL remain unchanged; borrowed shell material SHALL retain attribution. Historical continuation/editor support SHALL not be advertised as blue-shell functionality.

#### Scenario: Inspect supported behavior
- **WHEN** a user reads help or compatibility documentation
- **THEN** it describes shell-only behavior, identifies unsupported editors/scripts/world/network APIs and distinguishes historical experimental results from selected-shell acceptance

### Requirement: Measured shell responsiveness improvement
Matched default-geometry benchmarks SHALL show at least 2x lower median cold boot-to-prompt ticks than the original VM shell and native warm model-echo p95 at most two simulation ticks. Reports SHALL include initialization, scheduler/service/job/output and applicable collection/presentation costs without weakening shared limits. Editor-launch gates SHALL not apply to this shell-only scope.

#### Scenario: Matched cold boot and character traces
- **WHEN** each backend runs at least ten independent cold boots and one hundred individual characters with matched host/files/geometry/settings and real tick scheduling
- **THEN** medians/p95 meet the targets, all cold initialization costs and failures/interrupted attempts are reported, and differing rewritten/VM OS implementations are labelled rather than claiming identical ROM

#### Scenario: Native job beside a VM neighbor
- **WHEN** the largest accepted shell jobs run beside an interactive VM computer under existing shared limits
- **THEN** the report includes aggregate scheduler/service costs and neighbor responsiveness without a budget increase disguised as a speedup

### Requirement: Blocking acceptance gates
Readiness SHALL require exact-engine shell semantics/safety, bounded adversarial input/jobs, packaged base/expansion runs, separate-process session/job persistence, measured performance, graphical interaction and actual multiplayer joining. Failed or unavailable gates SHALL block readiness/rollout claims; headless results SHALL not substitute for graphical acceptance.

#### Scenario: Native handlers work but acceptance fails
- **WHEN** direct shell execution succeeds but performance, persistence, bounded-service or required shell behavior fails
- **THEN** the failed gate is recorded, model rollout remains blocked and neither VM fallback nor reduced acceptance targets are used to claim success

#### Scenario: Client acceptance unavailable
- **WHEN** headless tests pass but graphical or multiplayer checks cannot be run
- **THEN** those gates remain explicitly unverified and no publication or completed acceptance is claimed
