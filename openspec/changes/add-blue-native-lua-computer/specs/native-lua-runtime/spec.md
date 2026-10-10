## Purpose

Run trusted bundled shell event handlers directly as bounded native Lua, retaining explicit plain-data jobs and sessions without arbitrary user execution, coroutine emulation or a guest interpreter.

## ADDED Requirements

### Requirement: Direct trusted event execution
The blue backend SHALL execute only bundled trusted shell handlers directly through native Lua. Each invocation SHALL return normally after bounded work. It SHALL NOT route shell execution through a VM, generated continuation dispatcher or coroutine runtime, or accept player-supplied executable handlers.

#### Scenario: Actual execution path
- **WHEN** engine fixtures boot the shell, process a character and execute a built-in command
- **THEN** instrumentation verifies direct trusted-handler execution, no VM/continuation dispatch and a valid savable state at every handler return

### Requirement: Closed executable surface
Command input, local files and saved/snapshot data SHALL be treated as data, not source code. The blue backend SHALL NOT provide user `load`, `loadfile`, dynamic module/application loading, Lua evaluation or coroutine APIs. Unsupported execution requests SHALL fail explicitly without a compatibility fallback.

#### Scenario: Code-looking local file
- **WHEN** a user reads a Lua file and then requests its execution from the shell
- **THEN** reading returns data and execution is rejected without loading it into the host, compiler, continuation runtime or VM

#### Scenario: Forged executable identity
- **WHEN** input or a saved job record contains an arbitrary function/module name, unknown operation or executable host value
- **THEN** validation rejects or halts it with recovery data intact instead of resolving or executing that payload

### Requirement: Explicit bounded job progress
Long built-in operations SHALL advance as explicit data-only jobs through bounded chunks. They SHALL preserve deterministic operation order and exactly-once committed effects without suspended Lua calls, arbitrary frames or persisted callbacks. Cancellation SHALL preserve committed effects and discard only unpublished changes at a bounded safe point.

#### Scenario: Output spans ticks
- **WHEN** a file-reading command exceeds one tick's output allowance
- **THEN** each admitted chunk advances a retained cursor once, subsequent ticks continue the same job and no output is duplicated or lost

#### Scenario: Interrupt before file publication
- **WHEN** an interrupt cancels a file job before its atomic commit
- **THEN** bounded cancellation discards unpublished staging, preserves committed files and returns the shell to a usable prompt

### Requirement: Budgeted boot and snapshot import
Construction and snapshot import SHALL use a fixed versioned plain-data job with admitted bounded input retention, enumeration, validation, copying, inventory preparation and cleanup under the existing shared ceilings. Whole-tree scans/copies/sorts SHALL NOT occur as unpaid constructor work. The job SHALL support existing maximum node/path/content limits without reducing them, resume deterministically after serialization, and publish a complete validated disk and completion transition atomically before command execution. Unsupported or failed imports SHALL preserve safe recoverable data and any previously committed disk without silently booting an empty replacement.

#### Scenario: Maximum path metadata import
- **WHEN** an accepted disk contains the maximum supported node inventory with maximum-length canonical paths and empty file contents
- **THEN** metadata work advances in admitted chunks beside a VM neighbor without front-loaded whole-tree work, increased budgets or reduced accepted disk limits

#### Scenario: Import refusal and separate-process resume
- **WHEN** import credits are exhausted or a partial import reloads in another engine process or on a joining peer
- **THEN** bounded source/staging, deterministic progress and spent counters remain intact, loading performs no work, and publication occurs exactly once only after complete admitted validation

#### Scenario: Invalid import or publication deferral
- **WHEN** imported data is invalid or final publication lacks credits
- **THEN** no partial disk becomes authoritative, invalid data cannot supply executable values, and safe recovery or retryable job data and the previous committed disk remain intact

### Requirement: Ordered events and timers
Input/timer/job events SHALL have bounded queues and deterministic delivery. Timers SHALL use simulation ticks, stable ownership and documented powered-computer behavior; cancelled undelivered timers SHALL not fire. Events SHALL not be lost or applied twice because a job is pending or credits are unavailable.

#### Scenario: Pending job and subsequent input
- **WHEN** input arrives while a foreground command is advancing and its service credits are exhausted
- **THEN** accepted input remains bounded and ordered without entering that command's arguments, and subsequent admitted processing delivers it exactly once

#### Scenario: Timer cancellation and reload
- **WHEN** an owned timer is cancelled and the game saves/reloads before its deadline
- **THEN** cancellation remains effective and remaining timers retain deterministic ownership/deadline order

### Requirement: Durable plain-data sessions
The shell SHALL persist session/display, input/timers, job/staging and work counters as storage-safe plain data. It SHALL NOT persist functions, coroutines, host objects, executable metatables or generated bundles. Loading SHALL not boot, advance jobs, replay effects or mutate retained state.

#### Scenario: Separate-process partial session and job
- **WHEN** a save with partial command input or a pending filesystem/output job reloads in another engine process
- **THEN** command/cursor/history/current directory, job cursors/staging and spent counters remain intact and synchronized processing continues without duplicate effects or startup replay

### Requirement: Compatible versions and deterministic reconstruction
Shell/job format versions SHALL have explicit compatibility rules. Unsupported versions SHALL halt visibly with recoverable disk/session/staging intact. Reconstructed trusted-handler registries and host cache differences SHALL not affect durable work, event order or outcomes among existing peers, reloads and joining clients.

#### Scenario: Unsupported saved job version
- **WHEN** an update cannot safely continue a retained job's version
- **THEN** the shell reports recovery without discarding its data, converting experimental continuation state or silently rebooting

#### Scenario: Joining peer reconstructs handlers
- **WHEN** a player joins while a shell has partial input and a pending job
- **THEN** subsequent event delivery, work accounting, output and commits remain synchronized without join-time shell effects

### Requirement: Bounded shared work and retained quotas
Direct handlers/jobs SHALL enforce documented per-machine and aggregate tick work, queue, session/staging, output, geometry and filesystem limits without increasing existing shared ceilings. Trusted loops and opaque operations SHALL be bounded by admitted input/item/byte work. Repeated same-tick dispatch/reload SHALL not renew spent credits.
The shell command limit SHALL be 8,192 bytes and history SHALL be limited to 32 entries and 32,768 total bytes. Input/history work SHALL be admitted against these bounded data costs without charging a full 32 maximum-size lines for every key or increasing shared service ceilings. Compatible prior sessions SHALL retain identity/state without load-time migration.

#### Scenario: Maximum job beside a VM neighbor
- **WHEN** a shell runs the largest accepted listing/output/file job beside an interactive VM computer
- **THEN** each native chunk and cleanup stays within documented bounds, the VM receives fair service and shared work ceilings remain unchanged

#### Scenario: Zero-credit or repeated same-tick dispatch
- **WHEN** a handler/job has insufficient credits or is dispatched/reloaded again at the same exhausted tick
- **THEN** no unadmitted effect occurs, retained event/job state remains retryable and spent counters remain spent

#### Scenario: Oversized session or job input
- **WHEN** command/history/queue/job/staging input exceeds its documented limit
- **THEN** validation refuses it before oversized retention or partial mutation and ordinary later shell input can proceed

### Requirement: Confined atomic services and failure isolation
Terminal/filesystem/event effects SHALL reserve bounded work before mutation. Paths SHALL stay within the computer's validated local disk/read-only resources; no command SHALL expose host globals/IO, engine objects, peer disks or excluded world/network APIs. Refusal/errors SHALL preserve committed content and isolate other computers.

#### Scenario: File mutation refused and retried
- **WHEN** file publication is refused for insufficient credits or content quota
- **THEN** committed files remain unchanged, temporary-credit refusal retains a bounded retryable job, and no partial destination or destructive source removal is published

#### Scenario: Path or argument escape attempt
- **WHEN** an argument attempts host/peer access, code evaluation or mutation of read-only resources
- **THEN** it is rejected without exposing privileged values or modifying protected files

#### Scenario: Command failure isolation
- **WHEN** a trusted command reports an ordinary argument/service error
- **THEN** bounded failure handling preserves disk/session consistency and leaves a usable shell or visible recovery state without crashing Factorio or stopping a neighboring computer
