# Direct event-shell runtime

The selected blue-computer design is a shell with trusted built-in commands,
not a general-purpose Lua computer. The earlier continuation compiler, Recrafted
editor integration and failed measurements in `NATIVE_RUNTIME.md` are preserved
experimental history, not implementation or acceptance of this design.

## Model choice, artwork and current availability

The additive `blue-computer-item`, `blue-computer-interface-entity` and
`blue-computer-recipe` are named **Blue computer (shell only)**. They inherit the
original body's geometry, health and power settings, and the original recipe's
costs and crafting time. The existing `computer-technology` unlocks both recipes;
initialization/configuration reconciles the added unlock for already-researched
forces without resetting other recipe/technology effects. Unresearched forces
remain locked. The original physical and personal VM models are not converted.

Choose the original computer for Lua applications, editors and existing
circuit/network APIs. The blue design supports only the twelve trusted commands
documented here: it cannot execute Lua files, user modules or editors. A copied
Lua-looking file is inert data, not an application.

**Implementation checkpoint, not rollout:** artwork/prototypes/research are now
registered and tested in real base/expansion maps. Discovery/build/backend binding,
blue clone/blueprint import and owned cleanup are integrated. The selected GUI
routes input and lifecycle controls to the shell; structural authorization and
presentation checks remain distinct from native graphical-client acceptance.
Do not treat this checkpoint as gameplay/release readiness. Headless prototypes,
PNG inspection and table-backed GUI checks are not graphical or multiplayer proof.

`tools/blue_artwork.py` uses the installed FFmpeg only for artwork regeneration;
the mod, resource verifier and packager need no new runtime dependency. Its fixed
luminance-to-blue transform retains the original sprite silhouette/dimensions and
verifies every decoded alpha byte. Original PNGs and repository license remain
unchanged. `resources/blue/artwork.json` pins source/output/license hashes and the
transform. Run `python tools/blue_artwork.py --verify` for stdlib-only verification,
or omit `--verify` to regenerate with FFmpeg. The package checks both original and
blue image bytes against that manifest.

`tests/shell-mod/data.lua` captures the frozen pre-blue constructor before vanilla
expansion data-updates change parent defaults; `data-final-fixes.lua` compares every
original prototype (only the additional shared unlock is allowed), and verifies
blue geometry/power/item/recipe defaults and artwork paths. The capture uses a
unique test-only global because module-cache values cannot be relied on across
data phases. Engine fixtures verify fresh forces, distinct actual entities and
separate-process entity identity. Run `python tests/run_engine.py --shell
--shell-config-change` and repeat with `--expansion` to upgrade only the isolated
test fixture between processes and prove actual configuration-change unlock
reconciliation. Ordinary `--shell` cold reload remains separate and confirms
`on_load` does not reconcile force effects. Both modes pass 186 initial / 234
reload checks in base and expansion; original pinned-engine logs, including the
failed late-phase speaker-heating oracle attempts, remain in scratch evidence.

## Direct handler and saved-state boundary

`scripts/shell/runtime.lua` owns a fixed module-local event/command registry.
Handlers execute as ordinary Lua and return normally. `Shell.handle` requires an
explicit host-only admission callback; a refused compound work request performs
no handler effects. No callback or executable registry is stored or supplied by
command text. The runtime imports the plain terminal model, local filesystem
validation and existing limits, not the VM or experimental compiler/dispatcher.

The isolated implementation has `boot`, character/paste, cursor/edit/history,
resize, termination and incremental-output handlers. Current built-ins are
all twelve specified commands, with actual Tab completion and atomic local file
jobs. Production model integration and blocking acceptance remain unfinished.

New state uses backend `event-shell`, format 2. Compatible format-1 initialized
sessions retain their original version/identity; there is no load-time upgrade.
Persisted fields are the owned local
disk, plain terminal, command/cursor/history, bounded event data, output job and
work count. No call frames, coroutine relationships, heap, generated source or
function descriptors exist. The fixed output job uses version/kind/text/cursor;
unknown versions/kinds/extra fields halt visibly with the original job retained.
An experimental format-5 graph is rejected, not converted or rebooted.

Disk construction copies validated canonical nodes, requires root/parents and
checks the existing content/node quotas separately from metadata. Player files
are data only; requesting a script/editor/module reports unsupported command.
Only Enter submits command text. Paste normalizes CR/LF to spaces without
submitting, and command input is capped at 8,192 bytes. History retains at most
32 entries AND 32,768 total bytes; oldest entries are evicted at either bound.
Presentation uses the existing
byte-cell/color/geometry model. The key IDs match the existing terminal capture:
Enter 257, Tab 258, Backspace 259, Delete 261, Left/Right 263/262, Home/End 268/269.
Backspace removes the byte preceding the zero-based input cursor; Delete removes
the byte at it. Empty Enter returns to the prompt, and ordinary built-in argument
errors print bounded output then restore the prompt. Submission and result output
use separate rows. The command-name/argument split scans the capped line linearly
rather than using a potentially backtracking whitespace pattern. Isolated input
tests cover middle insertion/deletion, navigation, session routing and exact
dirty-row/cursor/blink/color/palette state using real individual events.

## Verification and outstanding gates

### Production selection, shared dispatch and readback

`os_runtime.lua` now delegates file/display/status/running inspection to the
read-only backend facade. VM migration and VM tick traversal exclude shell and
unsupported records, including stale VM scheduler registrations, without
rewriting their retained graphs. Selected shell ingress and explicit lifecycle
events use its owned queue and existing shared ledger; unknown/incompatible or
unpowered records refuse ingress rather than choosing a VM fallback.

The remote `getComputer` response preserves prior fields and adds backend,
shell format version, physical/personal model, status and file-readback error.
Snapshot/blueprint export explicitly refuses an unfinished disk instead of
exporting stale host/VM files. The original VM-model clone path likewise refuses
unavailable source files or a different backend before allocating a computer;
it removes only the newly created, uncommitted duplicate and reports why.
Ready blue-to-blue admitted clone/import is implemented separately from this
original-model rejection path; see physical lifecycle below.

The existing terminal renders the selected backend's display/status and gives
shell-specific command/lifecycle help instead of advertising a VM editor.
Synthetic key-up remains VM-only because the shell does not accept that event.
`runtime_routing_checks.lua` exercises these production runtime/lifecycle consumers
with isolated storage and poisoned VM boot/execution, then separately tests the
actual production remote interface against a real original physical entity and
cold reload. The first public-metadata probe failed because the fixture compared
its requested coordinates rather than the engine's placement-adjusted position;
the corrected oracle uses the actual entity position. GUI mocks check selected
prompt rendering, initialization, key routing and close; they are not graphical
client or multiplayer proof.

Production `R.tick` now admits shell construction before retaining a session and
dispatches VM and shell through the existing single rotating scheduler. Its
optional plain `backends` index identifies only `event-shell`; absent entries
remain VM and scheduler format 1 is unchanged. The shell stepper is a fixed
host-only callback, not a saved function or executable identity supplied by a
computer. Both backends share the existing active-computer cap, execution,
collection and service ledgers. Repeated dispatch does not renew spent credits;
paused/stale registrations are removed before admission, preserving owned graphs
and counters. At most one new runtime is constructed per tick. Credit refusal
retains the initial source and initializing status for a later admitted retry.
Stopped shells leave the active set; explicit queued lifecycle controls can
readmit them without creating a new session/disk. VM timer-deferral diagnostics
accept the optional counters absent from shell-initialized format-1 ledgers.
Incompatible ledger clocks halt visibly before changing any work counter or
runtime/job graph; they do not escape as an unhandled script event failure.

`mixed_runtime_checks.lua` calls the production traversal on real simulation ticks
with isolated host records: a cap-consuming VM, an interactive VM, a 129-node
maximum-length empty-content import, partial command input and a pending copy.
It poisons VM boot/compiler/continuation entry points, restricts actual VM execution
to the two original VM records, checks every shared domain and saves exhausted
credits with input/import/file-job and scheduler aliases. Cold resumption verifies
no `on_load` work, exactly-once queued input/publication, power pause/readmission,
original personal/unknown/incompatible records and explicit shutdown/reboot.
The active-cap test uses synthetic registrations with an unexecuted shared VM
alias; it is an admission test, not 512 concurrently executing computers.
The first mixed probe failed because the first server `on_tick` was still the
bootstrap constructor's exhausted tick. The corrected fixture waits for an actual
new simulation tick, rather than refreshing budgets on load. This production
traversal evidence is distinct from the earlier explicit-step routing fixture.
Blue artwork/prototypes and physical-body lifecycle are now routed through the
selected backend, as described below. Neither these headless tests nor GUI mocks authorize
graphical/multiplayer acceptance or rollout.

### Physical blue lifecycle and committed-file copies

Discovery, raised build/revive events and entity cloning recognize both physical
models. New blue records have fresh computer identity, no VM/world peripheral
setup and a separately owned shell/import job. Original bodies and personal
computers retain the VM path. No source session, input queue, timer, display,
job or unpublished staging is copied into a blue clone or blueprint.

Blue copies use admitted `Import.capture` on committed local files; immutable
strings may be shared, but node tables and job progress are newly owned. Source
validation and final installation advance in bounded import chunks. Before first
publication, snapshot/clone/remote files report not-ready, never an empty disk or
staging. A supported retained import with an earlier committed disk exposes only
that disk until replacement publication. This is retained-state compatibility,
not a user-facing reimport command or automatic backend conversion.

Public readback/snapshots reserve shared execution/table credits before the
bounded defensive envelope copy. `work deferred` is retryable on a later tick;
even metadata enumeration can consume those credits, so callers needing files
must inspect `file_error` and retry by saved computer identity rather than treat
an unavailable `fs` as an empty disk. Original VM copying remains unchanged.

Cloning an initializing source with no committed disk, an incompatible source or
an exhausted admission refuses before computer allocation and destroys only the
uncommitted duplicate. Already registered destinations are refused without
destroying their owned state. Invalid blueprint envelopes retain a visible error
and never boot an empty replacement. Temporary blueprint construction refusal
leaves the original blueprint unchanged; rebuild from it after the reported
error. Safe but invalid canonical paths discovered by the import job retain
recovery/source data without publishing any partial disk. Removal drops only the
selected runtime, direct unit/destroy registration and its owned resources;
same-tick budget history is not renewed.

`physical_lifecycle_checks.lua` exercises real engine bodies through production
lifecycle/runtime modules in isolated host storage, and separately exercises
actual control registration, public remote readback, `LuaEntity.clone` and tagged
ghost revival. It saves a suspended VM application, pending shell output/input/
timer, fresh clone imports and an admitted partially staged replacement with a
previous disk. Cold load asserts unchanged graphs/aliases/credits before work;
ordinary/configuration runs then verify publication, independent nodes and owned
cleanup. Malicious envelopes/executable node values and a real invalid-path ghost
are rejected, and exhaustion preserves source data. Explicit replacement setup is
a retained-state oracle, not evidence of a new interactive shell command.

The fixture freezes once prepared until the acceptance snapshot is actually
loaded, and retries budget-deferred public readback on later simulation ticks.
Headless physical lifecycle evidence is not graphical focus/rendering, an actual
joining peer, real-client mixed-model latency or completed milestone C.

The physical-lifecycle packaged checkpoint passes 205 initial and 260 cumulative
after-reload shell checks in both base and expansion, separately in ordinary and
actual configuration-change modes. The same archive passes original VM 384 / 516
and stress 11 / 50 initial / after-reload checks. These extend, rather than replace
or relabel, the earlier prototype-only and isolated traversal evidence below.

### Authorized GUI routing (structural verification, not native focus acceptance)

Opening and every subsequent input recheck the existing gauntlet research,
physical force/surface/ten-tile range and personal ownership rules. Elements must
belong to the current terminal frame, and that frame must still be `player.opened`;
stale-frame text, key and lifecycle events cannot mutate either backend. Display
resize cannot reopen an inactive terminal over another GUI or steal its focus.

Shell cell clicks restore the typing capture without synthesizing unsupported
mouse events. VM cell clicks retain the existing coordinate protocol and paired
key-up; shell keyboard events omit key-up. Character/paste capture feeds the real
selected shell handler, with CRLF normalized to one space, byte/cursor preservation
and no automatic submission. Refused reboot/shutdown (including no power or
initialization) is displayed instead of silently dropping the result.

Resolution/UI-scale resize rebuilds the presentation and redraws the cursor row
immediately without another character; it does not change runtime geometry or
reset command/history/job state. Startup geometry remains governed by the existing
runtime reconciliation. Closing/reopening preserves the shell and pending work.
Power pauses jobs; resumption continues the same job, and GUI terminate/reboot/
shutdown preserve committed disk according to the shell lifecycle contract.

`tests/guest-mod/terminal_presentation_checks.lua` runs the shipped GUI module with
table-backed players/elements and real shell/VM states. It checks every access
restriction, foreign/inactive elements, non-stealing resize, capture focus calls,
actual paste/insertion, immediate row redraw, separate VM/shell viewers, visible
refusal and pending-job close/power/interrupt/lifecycle behavior. Its explicit
synthetic tick steps are semantics oracles, not real-time latency measurements.
These mocks do not establish native focus/IME/clipboard behavior or real clients;
the blue checklist in `PLAYTEST.md` stays unchecked until actual client testing.

### Source provenance and packaged isolated verification

`resources/shell/manifest.json` records SHA-256 hashes for the eight trusted shell
modules, five reused project modules and repository MIT license, plus the unchanged
vendor manifest/original VM ROM identities. The shell and `/rom/help.txt` data are
project-authored, not adaptations of the pinned Recrafted executable ROM. Existing
vendor attribution/licenses remain intact. The hashes are build/provenance checks,
not a runtime plugin registry or a replacement for execution/security fixtures.

After intentionally editing a recorded module, run `python tools/shell_resources.py`
to regenerate its manifest. `python tools/verify_guest_resources.py` then checks
the original VM, historical native resources and direct shell together; stale,
missing or extra shell sources fail verification. Nothing compiles, converts or
rewrites the original VM ROM in this process.

`tools/package.py` includes this document, the shell manifest and blue artwork
manifest while continuing
to exclude tests, examples, repository metadata and other development documents.
Two repeated builds produced byte-identical archives. Using `--archive` on the
blue-prototype ZIP, the base and expansion shell fixtures each passed 186 initial /
234 reload checks in both ordinary and actual configuration-change modes;
the original VM fixtures each passed 384 / 516 checks (the original 380 / 512
regressions plus four shell-presentation mocks). These are
prototype/artwork-provenance and isolated-host production traversal/runtime/package
regressions, not real mixed physical-model lifecycle, graphical or multiplayer
acceptance. Stress also passed 11 initial / 50 reload checks in base and expansion.
The later GUI-routing archive checkpoint separately passes shell 205 / 260 in
ordinary and configuration-change runs, VM plus GUI mocks 413 / 545, and stress
11 / 50, in both base and expansion. Repeated builds are byte-identical; all these
fixtures load the archive rather than source symlinks. This completes the scoped
headless packaging gate, not native graphical or real multiplayer acceptance.

Every advertised command has real event/Enter-driven engine fixtures:

- `help`: `tests/shell-mod/control.lua` (bounded output, separate-process resume).
- `pwd`, `ls`: `interaction_checks.lua` (history, sorted listing and path errors).
- `cd`, `cat`, `clear`: `file_checks.lua` and `interaction_checks.lua` (quoted paths,
  literal Lua-looking data, resources, large output and completed commands).
- `mkdir`, `cp`, `mv`, `rm`: `mutation_checks.lua` (atomic publication, protected
  paths/resources, quotas, interruption, retry and save/reload).
- `reboot`, `shutdown`: `mutation_checks.lua` (owned cleanup, retained disk and
  explicit restart only).

The shell exposes no editor, general Lua, coroutine application, user module,
CC:Tweaked compatibility, world/network API or hidden VM execution. The original
VM's existing editor/program instructions remain applicable only to that model.

Run `python tests/run_engine.py --shell` and repeat with `--expansion` for the
isolated Factorio 2.0.77 fixture. Its trusted observers poison VM execution and
both compiler/continuation entry points while boot/input/built-in tests run;
calling any of them fails the fixture. Every successful handler return is
checked for plain data and metatable/function absence. Fixtures also test code-
looking files, unknown commands/events, executable payload rejection, forged job
recovery, zero-credit inactivity and a separately loaded partial command.

These are foundation/structural tests, not performance, graphical, multiplayer
or production acceptance. Maximum-operation adversarial coverage,
model integration and all required
acceptance remain tracked by the current OpenSpec task list. No budgets or VM/
vendor bytes are changed, and no blue model rollout is approved.

### Isolated shell performance (milestone B, not rollout acceptance)

Run `python tests/run_workflow_benchmark.py --shell-only --trials 10 --characters 10 --output <scratch-directory>`.
This selects the original VM shell and the actual rewritten `event-shell`, with
identical empty-root disks, default 51-by-19 geometry, engine/settings and real
simulation ticks. It preserves the old continuation/editor matrix as the default
historical mode. These are different OS implementations, not identical-ROM tests.

The 2026-10-10 base-engine matrix completed ten independent cold boots and 100
individually delivered characters per backend. VM/direct-shell median boot was
109/1 ticks; character model-echo p95 was 2/1 ticks. Both numerical gates passed.
All 40 first/reload server phases acknowledged console shutdown without signals
or forced kills. The report contains every per-run result, counters and profiles.
The earlier probe's harness error is retained in scratch logs, not erased or
presented as a workload/performance result.

Cold tick counting begins in the constructor's simulation tick; direct-shell
instruction totals include construction. Boot service totals include admitted
source retention, validation/copy/index preparation, atomic import publication
and prompt rendering. Whole scheduler dispatch and command jobs are profiled;
input ingress is separately profiled and its direct-shell event credits included.
Terminal-model revisions/dirty rows and all existing service domains are reported.
The cold CPU diagnostic sum includes module imports, construction and boot
dispatch; it is not wall-clock client latency. The VM/direct medians in this run
were about 982.57/2.44 milliseconds, diagnostic only. No guest collector or compiler
exists in the direct shell; zero collection/compiler/continuation counters mean
those paths are absent, not excluded work.

This matrix does not establish maximum-job neighbor service, production facade
behavior, graphical input/rendering or multiplayer joining. The report deliberately
keeps `rollout_allowed=false` even when headless speed gates pass. Milestone A and
the remaining production/client/package gates still control integration readiness.

## Shared accounting, queues and jobs

`scripts/shell/budget.lua` uses the existing VM scheduler's ledger field names
and counters, including its execution/collection machine records and all service
domains. A supplied ledger is the one allowance, not an additional native cap.
Compound admission checks every requested domain before updating any counter;
same-tick calls/reload retain exhaustion and backward ticks are rejected. The
production mixed-model traversal is still a facade task, not implemented here.

`scripts/shell/scheduler.lua` owns bounded ingress and dispatch. It reuses the
existing plain event/timer module and count/byte caps. A job advances before
ordinary queued input, so its arguments cannot absorb later typing. A dispatched
event reserves both handler work and FIFO compaction before queue removal. Credit
refusal preserves the event/job. Queue-full input is rejected with the existing
dropped counter; due timers remain pending rather than being lost on pressure.
Cancellation removes both pending and queued timer deliveries. Timer ownership
is the single shell session. Zero-duration timers start from their admitted
request tick and are due no earlier than the next tick. Unpowered dispatch does
no shell/job/timer work; on resumption elapsed simulation deadlines are delivered
in deadline/ID order. Maintenance deferral can update the clock but not lose a
pending timer or change a job. Completely exhausted execution performs no work.

The work mapping pays one existing execution unit per event/handler, plus one
per output byte processed. Input copy/FIFO movement uses event units; command
copy/parse/history bounds use string units; display effects use existing terminal
estimates; timer scans/sorting/publication use existing advancement units. Each
output invocation previews at most 128 bytes and counts actual writes/wraps/
newlines. A smaller chunk is selected when screen-scroll cost would exceed the
unchanged per-machine terminal ceiling. Plain jobs retain only bounded data; no
functions/host frames are needed between chunks. Cancellation releases the fixed
job and restores the prompt under admitted cleanup/display costs.

The fixture covers shared admission with an actual budget-preempted VM neighbor,
compound refusal, zero credits, repeated same-tick exhaustion, power pause,
maximum queues/timers, cancellation under pressure and maximum 65,536-byte
newline output at 160x60 geometry. Maximum-output and manually exhausted-budget
probes are explicitly synthetic structural/resource tests, not responsiveness
acceptance. A real `help` output job and a subsequent FIFO character are saved
with exhausted shared credits and resumed in another process; no load-time
effects, renewed same-tick credit or duplicated output/input are accepted.

## File reading and history behavior

`cd` and `cat` accept one local relative/absolute path, optionally enclosed in
matching single or double quotes. `cat` retains immutable file data, not loaded
Lua; file-sized output is capped by the existing disk-byte quota and emitted in
the same bounded chunks. Output without a final newline survives restoration of
the prompt. `clear` takes no arguments and preserves files. Missing paths and
invalid quoting produce bounded errors. Read-only resources, directory listing
and the full command surface are described below.

Up/Down (265/264) navigate history and restore the unsent draft/cursor on returning
past the newest entry. Tab completion is implemented as a bounded directory job. Resize
and interruption have priority over ordinary queued typing during output, without
evicting accepted input on a full queue. Resizing preserves the output cursor
and reconciles the display cursor without painting a prompt over unfinished
output. These are isolated behavior tests, not graphical acceptance.

## Admitted initialization/import

The unmetered constructor audit is resolved by `scripts/shell/import.lua`.
`Shell.new` requires admission; `Scheduler.new` supplies the existing shared
ledger. Refusal occurs before envelope traversal, retention or display creation.
The bounded envelope pass is paid in table units before inspecting at most
2,048 nodes/five primitive fields each and retaining immutable string references.
It performs no canonical path scan, whole-content copy or native sort. Unknown
payload fields, functions/metatables, invalid primitives and quota overflow are
rejected before an owned graph is returned. Metadata is capped separately at
2,048x1,024 path bytes; file content keeps the unchanged 1,048,576-byte quota.

Import job format 1 uses a captured dense numeric source array (never a saved
hash iterator), node/parent phases, a cursor, private per-record validation marks,
staging and byte/metadata totals. An admitted slice processes at most eight nodes
per phase; when phases meet, at most two slices occur. Per-slice charges reserve
table envelope/staging audits and copying, 32 units per maximum path byte for
filesystem work and 16 for string scan/copy/comparison work, plus fixed overhead,
existing terminal preparation costs and execution/item work. No limits increase.
Table-only shape/quota checks do not copy or scan file contents. Canonical/path
work is restricted to the slice. Prefix validation marks reject forged cursors
that attempt to skip earlier phases. Unknown format/operation/status combinations
halt with safe source/staging and any committed disk retained.

The first disk is absent until validated atomic installation; status is
`initializing` and ordinary input is refused explicitly. `committed_disk` returns
not-ready rather than an empty replacement or staging; if an old committed disk
is present it remains the readback until publication. Export/clone integration
still belongs to the facade/lifecycle tasks. Resize/control events can interrupt
initialization before another import slice; cancellation enters recovery with
source retained, never a silently booted empty disk. Power pause and on_load do
not advance or restart import. Completion installs the disk, drops the job and
paints the prompt in the same admitted dispatch. Cold timing must include both
constructor and slices; the isolated default-geometry performance gate is
reported above, separately from maximum-import resource/neighbor coverage.

The base/expansion fixture saves a real maximum-width pending import, source and
staging aliases and exhausted shared counters with a VM neighbor. Another engine
process checks exact load-time state, same-tick refusal and completes every path
under unchanged shared ceilings without republishing/rebooting. The continuation
loop uses explicitly synthetic scheduler ticks for structural/resource coverage,
not latency or graphical acceptance. The separate real-tick stress fixture below
adds shared-neighbor evidence; production and client acceptance remain open.

## Literal commands, completion and listing

The approved line/history policy is implemented without changing shared ceilings.
The 8,192-byte line represents maximum 1,024-byte paths with command prefixes,
two-path syntax and escapes. Key admission reserves the 32,768-byte history bound,
not 32 maximum-size lines. History/draft validation rejects malformed entries and
oversized total bytes; shorter compatible sessions need no load-time conversion.

Current command/argument matrix:

- `help`, `pwd`, `clear`: no arguments. Help states current commands and exclusions;
  pwd prints cwd; clear clears the model and restores the editable prompt.
- `cd PATH`: exactly one literal argument, existing local/read-only directory.
  Parent traversal clamps to the virtual root; no host or peer mounts exist.
- `cat PATH`: exactly one existing local/read-only file, streamed as data in
  admitted chunks. Lua-looking content is not executed; absence of final newline
  does not let prompt restoration overwrite its last displayed line.
- `ls [PATH]`: cwd by default or one existing directory, immediate children only.
  Sorted names use literal double-quoted escaping, with a trailing `/` for dirs.
  Whole inventories are not concatenated into an unbounded output string.
- `mkdir PATH`: one new local directory, existing parent required; no implicit
  parents or flags. Existing destination is refused.
- `cp SRC DST`, `mv SRC DST`: exact destination, recursively include source dirs;
  existing destination is always refused (no overwrite/merge). Destination parent
  must exist; destination inside source is refused. Copy can read bundled data;
  moving/removing bundled data cannot mutate it.
- `rm PATH`: recursive local deletion, with root, `/rom`, current directory and
  its ancestors protected. Missing sources are errors; no flags/globs are accepted.
- `reboot`, `shutdown`: no arguments; explicitly reset owned session/job/input/
  history/timers, preserve the committed disk and current directory, then boot a
  fresh prompt on the next paid dispatch or remain stopped, respectively.
  Ordinary input is refused while stopped. Trusted authorized reboot/shutdown
  events use the same closed operations; no ordinary boot/input silently restarts.
  Unknown programs/editors/modules/commands have no fallback.

`parser.lua` handles whitespace, single/double quotes and literal backslash
escapes. `\n`, `\r`, `\t` represent control bytes; other escapes quote the next
byte literally. NUL, unfinished escapes/quotes, too many arguments and unquoted
`| > < ; & $` or backticks are rejected. Quoted/escaped versions are ordinary
filename data, never executable syntax. No globs, expansion, pipes, redirection,
substitution, Lua evaluation or user modules are supported.

Tab scans command names or current local/read-only directory paths, including
empty prefixes. A unique candidate/common prefix changes the real line and
cursor; quoted names remain literal and an incompatible existing suffix is never
discarded. When ambiguity cannot extend a common prefix, all sorted candidates
are streamed before restoring the original line. Up/Down preserve an unsent
draft/cursor. Paste normalizes CRLF/CR/LF to spaces and does not submit. Oversized
ingress is refused without retention; overflow of the current line preserves its
text/cursor and reports refusal. Resize reconciles/redraws without new typing.

`directory.lua` captures at most 2,048 local paths plus two bundled data entries
under pre-admitted table work. Its version-1 plain job scans eight paths or moves
at most 64 merge-sort items per advance, validates owned record arrays under table
credits, then streams one bounded name at a time. String/filesystem comparison,
scan/encoding and terminal work are reserved before effects. Work prices fit the
unchanged per-machine/shared caps, including long line completion. Source, sort
buffers/cursors and spent credits survive cold reload without a persisted hash
iterator, whole-inventory opaque sort, initializer replay or executable callback.

`/rom` and `/rom/help.txt` are bundled read-only data from `resources.lua`, not
the old Recrafted/experimental executable ROM. Actual runtime fixtures cover
individual-character command/path Tab followed by Enter/read, empty prefixes,
quoted suffixes, long escaped paths, both history bounds, normalized paste and
resize. They also save a genuine pending completion with exhausted shared credits
and resume its original input/aliases in another engine process. This does not
establish graphical focus or multiplayer. Maximum-inventory real-tick bounded
progress is checked separately by the stress fixture below.

## Atomic file jobs and lifecycle

`file_job.lua` version 1 has only mkdir/cp/mv/rm operations and prepare/publication
phases. It captures owned source records during paid table admission, processes
at most eight source records per slice and validates every generated descendant
path before staging. Original file strings are immutable references, not a free
disk-size concatenation. Content remains at 1,048,576 bytes and 2,048 local nodes;
candidate path metadata remains at most 2,048x1,024 bytes. The cached parent index
adds at most the same metadata bound; each parent substring is prepared in its
paid slice, not rescanned over the whole tree at publication. Source and staging
have explicit bounded inventories, with no saved hash iterator or callbacks.

Prepare reserves existing execution/table/filesystem/string credits before cursor
or staged mutations. Publication reserves a bounded table-only consistency/
index/parent/quota audit; no full-tree path scan or file-content copy is hidden in
that audit. Only the complete candidate disk replaces `state.disk`. The original
committed object stays authoritative through staging, credit refusal and cancel.
Ordinary errors discard unpublished staging into a bounded error-output job and
restore the prompt; no source deletion/truncation occurs on copy quota failure.
Format mismatches preserve the original job in visible recovery. Exact-engine
fixtures cover recursive copy/move/remove, authoritative replacement, overwrite
and read-only/root/current-directory refusal, full-content failure, credit retry,
cancel and cold reload immediately before publication plus after completed work.
The final index must be a one-to-one inventory of staged paths: duplicate entries
are rejected under the already reserved table audit, with the original committed
disk and malformed job/staging intact in visible recovery. A forged duplicate
index regression exercises zero-credit refusal and cold retained recovery in both
engine modes. Ordinary command/quota errors still restore the prompt; malformed
publication data cannot be mistaken for an ordinary error that discards its job.

Every filesystem advance first audits the complete retained source envelope under
its existing table admission: dense bounded indices, closed record/node fields,
scalar validation flags, local content/path-metadata quotas and fixed bundled
resource ownership. This inspects immutable string lengths, not whole-tree path
bytes or file-content copies. Unknown fields, sparse inventories and forged
resource markers enter visible recovery with the original job/staging and committed
disk preserved; they cannot hide behind an unvisited later source record. At zero
credits the audit performs no traversal or recovery mutation. Both engine modes
save/reload these malformed data-only records and verify retained recovery aliases.
The revised complete shell fixture passes 158 initial and 195 reload checks, and
the admitted real-tick maximum-workload fixture still passes in both modes with
the source audit enabled and no budget increases.

The host's authorized terminate event interrupts at a paid safe point. For normal
foreground jobs it drops unpublished progress, clears the current draft and
restores the prompt while preserving accepted FIFO input and all committed files.
For initialization it enters recovery with safe source/staging retained. Reboot
and shutdown deliberately clear pending input/timers as well; event ownership is
replaced atomically. Scheduler removal must target the old queue only if it is
still owned after the handler, preventing negative counters on the replacement.
Power loss pauses progress; closing the GUI does not cancel it. Structural GUI
routing checks are described above; real-client lifecycle remains a separate gate.

## Real-tick maximum-workload fixture

Run `python tests/run_engine.py --shell-stress` and repeat with `--expansion`.
The separate fixture uses actual `on_tick` events and the original shared VM ledger,
not a synthetic clock or a second allowance. It cold-reloads a partial admitted
import of 2,048 nodes with maximum-length paths and a 1,048,576-byte file. It then
completes the import, maximum ambiguous completion/candidate output, full file
output, staged move/removal, maximum newline output, event byte/count envelopes,
owned timer inventory, and independent history byte/entry bounds. Every tick checks
aggregate and shell service counters against unchanged limits while an actual VM
program receives characters and writes its terminal model.

The expanded fixture also creates a separate maximum-width, maximum-inventory
import with zero content bytes under shared admission. It saves actual pending
import/output/listing/file-publication jobs with seven safe malformed variants:
unknown import/source fields, sparse import indices, unsupported import/output
versions, duplicate publication indices and unknown directory item fields. All
records and their source/staging/committed aliases survive cold load unchanged.
After reload, each refuses at zero execution credits without state/counter changes,
then halts under admitted work with the original graph preserved. The empty-content
import independently pauses on power loss, resumes in real ticks, installs every
maximum path exactly once and preserves its disk identity when idle. Function-valued
ingress/snapshot probes are rejected without retaining executable values.

Base and expansion packaged runs pass 11 initial and 50 reload checks. Each observes
4,791 real VM character echoes with at most one simulation tick of delay. These are
terminal-model service observations, not graphical input/rendering latency. Fixture
speed is 8, explicitly a simulation-tick resource oracle, unlike the matched boot/
echo performance matrix. Source generation, neighbor compilation and assertions are
trusted setup/observers rather than metered production work. Shell construction,
import, ingress and every dispatched job use actual shared admission.

Every service-domain aggregate and every participating machine are checked against
the unchanged ceilings each tick. Observed aggregate peaks include filesystem
524,544, string 262,426, table 787,840 and terminal 245,257 work units. The constructor,
retained-source audits and both publication consistency passes fit the existing
reservation; no budget or accepted filesystem limit was increased.

The initial cold-malformed attempt failed at the duplicate publication-index
oracle: it exposed the ordinary-error path discarding malformed staging. Reusing
the publication validator in the pre-effect, admitted filesystem audit now routes
that case to retained recovery. The failed attempt and passing retries remain in
scratch logs; retries do not erase the discovered failure.

A later packaged retry exposed a fixture save race: the first process could run
another tick after its save request/marker but before queued persistence, changing
the expected ledger. All fixture participants now freeze after requesting the save
until an actual cold `on_load`; only the new process resumes work. The failed load
oracle remains in scratch logs rather than being dismissed as a runtime pass.

Together with the complete base/expansion shell semantics/persistence suites and
unchanged 380 initial / 512 reload VM regressions, this establishes the isolated
milestone-A resource/security gate. It does not complete the backend/blue-model,
different-peer integration, graphical or actual multiplayer acceptance tasks.

The first base attempt retained a failed observer assertion: it expected completion
to extend an empty prefix even though `/rom` prevents a common prefix. Correct
behavior streams all candidates and restores `cat ` unchanged; the corrected
fixture tests this rather than changing shell behavior. Logs remain outside git.
These fixtures do not prove production mixed-model discovery/fair traversal,
graphical focus/rendering, actual joining-peer reconstruction or packaged rollout.

## Backend readback facade (isolated integration preparation)

`scripts/backend.lua` provides read-only `kind`, `files`, `display`, `status` and
`running` inspection. It neither executes a backend nor mutates/migrates saved
records. Missing tags and explicit `vm` use the original VM disk/display; personal
computers remain VM-only. Physical `event-shell` records select only their separately
identified, compatible `c.shell` session. Unknown tags, incompatible shell versions
and unsupported personal-shell tags report recovery without choosing another
backend or changing the retained record.

Before first disk publication, shell files return nil with an explicit not-ready
reason, never stale `c.fs`, a coexisting VM disk or import staging. Compatible shell
readback resolves its current committed disk on every call, so atomic replacement
is visible before reboot. Initialization/stopped/recovery states remain distinct;
stopped shells still expose committed files, not a replacement empty disk. Like
the existing internal VM readback, these references are trusted host-only: public
remote/snapshot consumers must retain their defensive data-copy boundary.

At the earlier isolated-facade checkpoint, the base/expansion shell fixture exercised real VM and shell objects, stale aliases,
atomic replacement, stopped readback, incompatible/unknown records and unchanged
separate-process reload identities (147 initial / 178 reload checks). Production
lifecycle/control/GUI and shared mixed scheduling are now wired through this
facade; the integration and remaining real-client gates are described above.
No playable-model rollout is implied by the isolated checkpoint.
