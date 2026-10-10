# Design

## Context

See proposal.md for the approved shell-only scope. The existing physical and personal computers run the pinned Recrafted OS through the VM; they must remain unchanged. Runtime/lifecycle/GUI consumers currently depend on VM state and need a narrow model-aware facade for the additional blue model.

The previous native experiment retained arbitrary Lua calls, coroutine relationships, boxed values and a collected persistent heap. Its optimized matched matrix completed 60 workflows but still failed performance: VM/native median boot 109/201 ticks and shell echo p95 2/9 ticks. Full reports and compiler/editor experiments remain historical evidence in `docs/NATIVE_RUNTIME.md` and their retained fixtures. They neither implement nor accept the new event-driven shell.

This revision deliberately replaces the unshipped blue application contract. The original VM still supports its existing applications. The blue model runs only bundled shell commands; files containing Lua remain ordinary data and are never executable on it.

## Goals / Non-Goals

**Goals:** A directly executed native shell with small returning handlers; durable command-line and explicit job state; bounded deterministic service; faster measured boot/input; safe VM coexistence and actual client/save/join acceptance.

**Non-Goals:** General-purpose user Lua, coroutine emulation, suspended host stacks, a source compiler, generated continuation dispatch, a custom guest heap/collector, basic/advanced editors, tabs/application scheduling, dynamic plugins, pipelines/redirection/command substitution, retired world/network APIs, personal blue computers, publication or automatic conversion of existing execution.

## Decisions

### 1. Direct trusted handlers, not another application runtime

Use a fixed module-local registry of trusted bundled handlers for boot, key/character/paste/resize input, timer/job advancement and lifecycle operations. A handler uses ordinary Lua locals/tables and finishes its call stack before returning. The only state surviving a return is explicitly owned shell data or job data.

A job identifies a fixed bundled operation and carries its input, phase, bounded cursor, staged changes and completion/error status. It is not a generated program counter, suspended arbitrary Lua call or persisted callback. Advance large listings, file output and file operations in bounded chunks; do not recreate the continuation compiler under job terminology. No blue execution reaches the experimental compiler/dispatcher/heap or VM, including for a built-in command.

User input selects a validated built-in name and arguments, never a handler function or module name. Local files, command text, snapshot fields and job records cannot supply executable code. Keep host-only registries/capabilities outside storage and out of terminal/file output. This closed execution surface removes the need to preempt arbitrary user loops; it does not excuse unbounded loops in trusted code.

### 2. Small shell contract

Initial command names are `help`, `pwd`, `cd`, `ls`, `cat`, `mkdir`, `cp`, `mv`, `rm`, `clear`, `reboot` and `shutdown`. Publish accepted arguments, quoting, errors and destructive-operation behavior with the implementation. Provide literal/quoted path arguments, not Lua evaluation, shell substitutions, pipes or user scripts. Completion enumerates built-ins and confined local paths, including an empty path prefix, under bounded work.

Command-line editing provides insertion/deletion at the cursor, left/right/home/end navigation, bounded history with up/down navigation and Tab completion. Paste inserts bounded text without executing commands; normalize CR/LF to spaces and reject oversized input atomically. Enter alone submits the current line. Preserve command text/cursor across resize and reconstruct the prompt from terminal geometry, with deterministic immediate redraw or an admitted queued redraw.

The command line is capped at 8,192 bytes, accommodating existing maximum-length paths plus command names, quoting/escapes and two-path operations without reducing accepted disk limits. History retains at most 32 entries and 32,768 total bytes, dropping oldest entries when either bound requires it. Admit actual bounded line/token work and the history byte bound, not 32 times the new line maximum. Validate these bounds before oversized retention; keep all shared scheduler/service, queue, output and filesystem ceilings unchanged. Compatible shorter sessions remain valid without load-time conversion.

Long commands occupy an explicit foreground job. Retain subsequent input in a bounded ordered queue without mixing it into that job's arguments. The documented interrupt key cancels the foreground job at a bounded safe point, discards unpublished changes and returns to the prompt; already committed effects are not replayed or silently rolled back. Reboot and shutdown are explicit lifecycle operations with defined pending-input/job cleanup and committed-disk preservation.

Reuse existing cursor/palette/blink/geometry/dirty-row presentation and input authorization contracts, including existing mouse routing where supported. No editor buffers, application threads or window/tab hierarchy are required.

### 3. Plain-data session and versioned recovery

Store a separately identified/versioned shell state: running/status, current directory, command buffer/cursor/history, display data, bounded input/timer queues, foreground job/progress, staged filesystem changes and durable work counters. Ordinary data-only tables are sufficient; no functions, threads, host userdata, executable metatables or function descriptors enter storage.

Bind the static registry outside saved state when scripts load. `on_load` performs no boot, command execution, job advancement, filesystem publication or durable migration. Synchronized events resume retained jobs at explicit phase/cursor boundaries. Update cursor/commit markers in the same admitted operation as their effects, preventing duplicate output or file mutations after reload. The game cannot save in the middle of a synchronous handler; all handler returns must leave a valid savable state.

Versions describe the bundled operation semantics as well as data shape. Compatible changes retain job progress; unsupported versions halt visibly with the original disk/session/staged data intact. Never interpret experimental continuation format 5 as shell state or automatically replay startup to manufacture a replacement session. Host cache/registry construction and joining-peer state do not change durable work or event order.

### 4. Bounded native work and confined atomic file services

Reuse existing per-machine/aggregate scheduling and service ceilings without increasing budgets to manufacture a speedup. Charge handler/event dispatch and job work with a documented mapping to the shared scheduler; bound every loop by input caps and paid item/byte work. Do not equate one handler invocation with unlimited work. Keep command/history, queue/timer, job/staging, string/output, terminal geometry and filesystem size limits explicit and checked before retention or publication.

Before accepting an event, reserve its copy/queue cost. Before mutating display/disk/job state, reserve its bounded work. At zero credits preserve the event/job and all existing data. Same-tick repeated dispatch and reload retain spent credits. Use deterministic fair scheduling for shell jobs beside VM computers; wall time and local caches are diagnostic only, never scheduling inputs. Measure accepted worst-case trusted operations and cleanup in the exact engine, not just nominal echo.

Paths use validated canonical local filesystem operations; no native host IO, peer mounts or world/network APIs. Keep bundled resources read-only. File mutations validate complete inputs/quotas before publication; large preparations stage bounded progress and commit atomically. Refusal preserves existing committed content, and temporary-credit refusal preserves retryable job state. Invalid or oversized job records fail visibly without executing their claimed operation. Existing content is not silently overwritten: document explicit overwrite policy and test refusal/cancellation before commit.

### 5. Additive blue model and narrow facade

#### Budgeted construction and boot/import

Construction is not a free-work exception. The current synchronous snapshot constructor is not an accepted implementation: accepted path metadata can exceed a per-machine filesystem quantum even with empty file contents. Keep existing node, path, content and shared work ceilings unchanged. Use a fixed, separately versioned plain-data boot/import job rather than a generic interpreter or persisted host iterator.

Admit bounded input-envelope inspection/retention, enumeration, canonical-path and node/parent validation, copying, inventory preparation, any sorting and cleanup before their effects. Do not front-load a whole-tree scan, defensive copy, key array or opaque sort into the constructor before creating the job. Bound source and staging metadata separately from file-content quota; retain support for the largest currently accepted committed disk, including maximum-length paths. A staged traversal must resume deterministically after serialization and on joining peers; an unindexed hash cursor or ephemeral cache is not proof of stable progress.

Persist only bounded storage-safe source data, phases/cursors, staging and durable work counters. Reject executable values, invalid envelopes and out-of-contract job fields without retaining them in storage. Install the complete validated disk, its authoritative metadata/index and a one-use completion transition atomically under admitted publication work. No prompt or command execution is available before installation; an empty source disk still takes the same admitted initialization path, which may finish within one tick if credits suffice.

Until the first successful installation, status is explicitly `initializing`, command input is rejected with that status, and file snapshot/clone/blueprint export reports not-ready rather than exporting an empty replacement, unvalidated source or partial staging. If a supported import has a previous committed disk, trusted readback continues to return only that disk until atomic replacement. Ordinary clones/rebuilt blueprints start fresh import jobs from committed content with fresh identity, never copied live import progress. Closing a viewer does not reset import; power loss pauses it. Reload/join performs no import work, restores progress and same-tick exhaustion, and resumes only at synchronized admitted dispatch. Failure, unsupported versions or interrupted initialization retain safe recovery/source data and any previously committed disk rather than silently booting an empty disk. Owned removal performs bounded cleanup.

Cold boot starts before construction/import, not after it. Report admission, validation/copy/index preparation, publication and presentation costs and retain the unchanged default-geometry 2x boot and two-tick warm-echo targets. Maximum-metadata imports beside an interactive VM, zero-credit refusal, power pause, mid-import cold reload and both sides of publication are required fixtures before the initialization work gate can pass.

Retain proposed identifiers `blue-computer-interface-entity`, `blue-computer-item`, `blue-computer-recipe`, existing geometry/power/recipe costs, blue artwork/localization and `computer-technology`. Reconcile already-researched forces as well as fresh research.

Keep `scripts/os_runtime.lua` as the VM implementation. A small facade routes the existing lifecycle/input/geometry contract and authoritative files/display/running/backend metadata. Absent tags mean VM; new blue records receive a distinct event-shell backend identifier and shell format version. Unknown identifiers fail visibly instead of selecting VM or shell. Do not reuse a tag ambiguously across the continuation and event-shell architectures.

Closing the GUI leaves powered shell jobs running. Power loss pauses progress without refreshing credits; timer advancement/delivery follows the existing documented powered-computer policy and is verified across power transitions. Reopening preserves the session. Clones/blueprints copy validated committed disk content only, receive fresh identity and boot a fresh shell; they do not copy queues, jobs, staged changes, command buffers or VM execution. Removal cleans only owned state/resources. Validate force/surface/range/research/GUI ownership for input and inspection.

### 6. Provenance and historical work

The blue shell is new bundled code, not a claim that the full pinned Recrafted BIOS/scheduler/ROM executes directly. Preserve vendor bytes, original VM ROM, license/manifest provenance and original VM regression behavior. Record attribution for borrowed shell material and verify any new packaged resource inventory.

Keep the earlier compiler/coroutine/editor fixtures and failed measurements as superseded experimental evidence. The replacement task list tracks the event shell separately; previous 27/37 completion is historical and cannot be carried over without tests of the new requirements. This planning revision does not delete or refactor implementation files. Documentation updates during implementation must clearly distinguish the selected architecture from experimental historical support.

### 7. Blocking performance and client acceptance

Milestone A proves the actual direct-handler shell, bounded job/service behavior, input safety, separate-process session/job persistence and unchanged VM execution in Factorio 2.0.77. Milestone B proves shell performance before model rollout. Milestone C integrates the model and proves packaged base/expansion, graphical and multiplayer behavior.

Compare the rewritten shell with the original VM shell under the same host, geometry, files, settings, powered-machine count and input/command traces. The OS code necessarily differs; label that difference rather than claiming identical ROM or coroutine compatibility. Use at least ten independent cold boots per backend and at least one hundred individually delivered characters per backend, reporting medians/p95 and retaining failed attempts. Schedule through real simulation ticks, not synthetic repeated dispatch.

Keep at least 2x lower median cold boot-to-prompt and native warm model-echo p95 no more than two simulation ticks at default geometry. No editor-launch target remains. Report full scheduler/service/queue/job/output cost, initialization and any resource-loading cost, applicable collection and graphical presentation latency; a removed compiler/guest collector is genuinely absent, not omitted from timing. Separately stress maximum accepted output/file/completion jobs beside an interactive VM neighbor without raising shared ceilings.

Headless model echo is not graphical input/rendering proof. Actual client input, completion, paste/resize, mixed models, recovery and a real multiplayer join during partial input/pending job remain blocking. If a gate fails or cannot run, report it as failed/unverified and stop readiness/rollout claims; no fallback or publication exception is authorized.

## Risks / Trade-offs

- [Narrower functionality than the VM computer] -> Clearly advertise built-in commands only; reject editor/script requests explicitly and leave the VM model available.
- [Trusted native handler accidentally performs unbounded work] -> Cap inputs, pay per item/byte, slice jobs, audit loops/opaque helpers and exercise worst-case engine fixtures before rollout.
- [Plain-data jobs recreate a generic interpreter] -> Use only fixed built-in operation phases; no user code, call frames or generic instruction dispatch.
- [Filesystem staging consumes memory or loses data] -> Bound all staging, reserve quotas before publication and test refusal/cancellation/partial reload.
- [Registry/state version mismatch or joining-peer differences] -> Explicit compatibility, synchronized progress, no load-time effects and actual joining-client acceptance.
- [Facade disturbs old VM saves] -> Default absent tags to VM, preserve original states/ROM and run mixed-model regression/configuration fixtures.
- [Direct execution does not meet speed targets] -> Benchmark the real shell early; retain failures and stop rather than assuming that native execution guarantees improvement.

## Migration Plan

1. Implement the shell in isolated fixtures on the existing blue feature branch; preserve unrelated files and the superseded experimental work. Do not wire playable computers to it yet.
2. Establish direct handler/job/persistence evidence and matched shell-only performance with unchanged ceilings.
3. Integrate facade, blue model/research and lifecycle only after milestones A and B pass; test old VM saves beside partial shell input and pending jobs.
4. Validate packaged base/expansion artifacts, then actual graphical and multiplayer joins; record unavailable acceptance as blocking.
5. Preserve recoverable disks/state for unknown experimental/shell versions. No live cross-backend conversion, automatic reboot or in-place mod downgrade is a migration strategy.
6. Prepare the implementation PR when recorded acceptance is complete; no mod release or publication is part of this change.
