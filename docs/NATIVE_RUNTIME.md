# Native Lua backend: feasibility and implementation status

The native blue computer is under implementation. No existing computer is routed
to this backend. Bounded source compilation and an isolated native block
dispatcher, coroutine transfers and protected boundaries are implemented and
tested. Milestone A's isolated sandbox, bounded execution and separate-process
persistence gate passes. The actual shipped OS/editors have structural fixtures.
The matched performance gate fails (milestone B blocked); blue prototypes,
graphical acceptance and multiplayer
acceptance are not yet complete. The original two-block probe remains independent;
the compiler fixtures execute actual compiler-produced blocks.

## Exact-engine probes

The test harness pins the official headless Factorio 2.0.77 engine and isolates
its config, mods, write directory and localhost server. Both server phases quit
through console `/quit`; a readable requested ZIP is required before shutdown.

Run the native-load probe:

```sh
python tests/run_engine.py --native --output "$TMPDIR/cc2-native-probe"
```

Verified in actual data and control stages:

- Text-only `load(source, name, 't', environment)` accepts an explicit restricted
  environment. The data-stage probe does not stand in for runtime acceptance.
- A restricted environment does not expose game, script, remote, storage, `_G`,
  debug, require, load, io or os. This tests global lookup, not a complete sandbox
  audit of the future runtime.
- Native coroutines are absent. Tuple pack/unpack, scalar math and string slicing
  required by the generated-code protocol are available.
- Binary source is rejected in text-only mode.
- A hand-generated block can retain its local value/program position as plain
  data, return an explicit nil-containing suspension tuple, save, rebuild its
  executable definitions in another process and resume without replaying its
  earlier effect. Executable functions are never persisted.
- `on_load` only sets an ephemeral flag; reconstruction/execution occurs at
  synchronized tick dispatch. The persisted frame retains its prior position and
  effect count before resumed work.

Initial probe: 15 checks before save, 18 cumulative checks after reload. Raw
logs and process shutdown evidence are in:
`/home/siredvin/.hermes/profiles/albina/cache/scratch/blue-native-load-probe/`.
Scratch evidence is ephemeral; retained behavior lives in the runnable fixtures.

## VM baseline measured on real simulation ticks

```sh
python tests/run_engine.py --vm-benchmark --output "$TMPDIR/cc2-vm-benchmark"
python tests/run_engine.py --guest --output "$TMPDIR/cc2-vm-regressions"
```

The benchmark calls the unchanged production guest scheduler once per actual
`on_tick`, using `game.tick`. It uses the shipped ROM and unchanged limits at
51 columns by 19 rows. It records instruction and collection work with every
phase, counts from the first serviced tick to completion, sends each measured
character separately, and preserves the suspended final editor through reload.
It has no GUI/client player and does not measure keyboard/client rendering.
Character completion currently requires matching display text and application
wait/queue drainage; it is stricter than text-only first-echo latency. Startup
measures `Boot.new` and runtime startup; the module-scope BIOS prototype compilation
is outside these simulation-tick measurements and must be reported separately in
full cold-compile acceptance.

Initial diagnostic sample, not the ten-launch/100-character acceptance matrix:

| Phase | Simulation ticks | Guest instructions | Collection work |
|---|---:|---:|---:|
| Each of three boot-to-prompt runs | 109 | 331648 | 51839 |
| Basic editor launch (paste + Enter through shell) | 16 | 65536 | 0 |
| Advanced editor launch (paste + Enter through shell) | 132 | 172032 | 179268 |
| Four individual shell characters | 4 each | 15347–15512 | 0 |
| Four basic editor characters | 2, 3, 2, 4 | 8192–16384 | 0 |
| Four advanced editor characters | 2, 4, 2, 4 | 8192–16384 | 0 |

Baseline benchmark: 17 checks before save, 18 after reload. Raw metrics/logs:
`/home/siredvin/.hermes/profiles/albina/cache/scratch/blue-native-vm-tick-baseline-v2/`.
The earlier baseline directory is an obsolete diagnostic run which counted the
queueing tick in phases begun after that tick's dispatch; do not use it for
comparisons. The unchanged VM regression suite passed 380 checks before save
and 512 cumulative after reload, recorded at
`/home/siredvin/.hermes/profiles/albina/cache/scratch/blue-native-vm-baseline-regression/`.

## Shipped-source support inventory

These are required shipped behaviors; structural shell/editor evidence is
recorded below, without claiming completed performance or playable acceptance.
The selected sources are the pinned Recrafted files in `vendor/manifest.json`,
including the repository's existing patches. Do not restore excluded peripherals,
network services or historical peer disk mounts to satisfy startup.

| Source path under `vendor/recrafted/` | Required behavior |
|---|---|
| `bios.lua:67-119` | Timer ID ownership, raw/normal event waits, nil-arity yield results, termination policy, simulation sleep |
| `bios.lua:172-201` | Deterministically sorted startup discovery, source-only `loadfile`/`dofile`, dynamic modules and root scheduler |
| `rom/modules/main/rc/thread.lua:62-97` | Source loading with an environment, closures, nested protected calls, coroutine creation and thread/tab-local state |
| `rom/modules/main/rc/thread.lua:360-399` | Root event yield, child resume/status, exact event tuples, errors, focused-input routing, resize reconciliation |
| `rom/programs/shell.lua:17-80` | `_ENV`, aliases, startup protected execution, sorted files, completion callbacks, terminal `read`, nested command execution |
| `rom/startup/15_term.lua` | Closure-backed terminal methods/windows, callback completion, mutable redirection, table `__index`, keyboard/char/paste/mouse processing |
| `rom/editors/basic.lua:15-256` | Live local/table state across nested waits, file iterators/colon calls, menu callbacks, paste string processing, line insert/remove, durable drafts |
| `rom/editors/advanced.lua:23-364` | Window methods, nested generic iterators and syntax closures, table/string helpers, delayed highlighting timers, menu and input waits |
| `rom/apis/window.lua` | Native-compatible display rows/palette/cursor, closure captures, optional forwarding, row-specific redraw |
| `rom/startup/10_package.lua` and `rom/modules/main/rc/io.lua:208-227` | Module caches and relative search, source loading and explicit guest environments; later IO definitions replace the early BIOS `loadfile` |
| `rom/apis/textutils.lua` and `rom/modules/main/rc/copy.lua` | Guest `type`/function identity, alias/cycle-safe copies, safe metatables, guest source deserialization with an isolated environment |

The Lua 5.1 `getfenv`/`setfenv` BIOS branch is conditional; the current Factorio
host is Lua 5.2.1. Do not introduce privileged host environment introspection to
support that inactive branch. Guest `_ENV` and explicit source environments are
still required. `debug.traceback` in the OS must remain a guest-only diagnostic,
never access the host registry/frames. Full CC:Tweaked compatibility is not a goal.

## Compiler/runtime boundary

`scripts/native/compiler.lua` now provides the host-only `analyze` front end.
It parses and validates jumps without generating or executing bytecode. It uses
the unchanged source-byte, parser-depth, parser-work and linker-work limits and
accepts an optional shared-admission callback. Phase metrics are written to a
host-owned sink; success returns only the ephemeral AST. Tests cover malformed
syntax, invalid jumps, binary/oversized input, exact parse/link exhaustion,
shared refusal, enclosing callback restoration and subsequent recovery.
The expanded native fixture passes 29 checks before save and 32 after reload at
`/home/siredvin/.hermes/profiles/albina/cache/scratch/blue-native-frontend-green/`.
Guest source APIs now use this front end in the isolated native fixture; the
playable backend remains gated on actual-OS and integration acceptance.

The front end must retain bounded Phobos scanner/parser/name resolution and jump
linking. ASTs are ephemeral host compiler data, not persistent program state or a
substitute for compiled execution. Source, nesting and phase work bounds must
apply to failures as well as successes; restore utility work callbacks afterward.
Native code generation must preserve evaluation/return order and produce bounded
blocks with source maps and explicit suspension records. Player `load` must go
through that compiler, never directly through host `load`.

Generated executable functions remain ephemeral. Persist descriptors/source
versions/upvalue cells/table identity/plain frames and tuples with explicit `n`.
Cache hit/miss cannot affect durable admission; reconstruction must charge the
same logical bundle-activation cost on warm and cold peers. Application yields
and internal budget preemption must be distinguishable: budget preemption cannot
return fake values from a guest `coroutine.resume` or consume a second event.

## Generated compilation and checkpoint contract

`compiler.compile` returns one versioned plain-data bundle or `nil, diagnostic`.
The bundle retains its source snapshot, generated text, prototype/cell bindings,
constants, entry labels and a source map for every block. ASTs, host functions and
symbolic bytecode instructions are not retained. `execution.executable` loads
only that generated text into an empty global environment. Guest source APIs
compile first and register a retained bundle; raw application source never
reaches this executable loader.

Limits currently shared with the VM front end: source 32768 bytes, parse work
262144, parse nesting 64, link work 32768, generation work 262144 and generation
nesting 64. Native emission additionally bounds generated text to 131072 bytes,
total blocks to 8192 and individual block bodies to 1024 bytes. Long string
literals live as plain scalar constants rather than oversized block bodies.
Expression lists and delivered tuples are bounded to 1024 values. Input-dependent
parser/link/lowering/emission work charges the optional host-owned admission
callback before updating phase counters or publishing a bundle. Refusal returns
no executable partial bundle. The shipped Lua ROM now fits these provisional
bounds; this is not proof of OS execution or worst-case compilation latency.

Each dispatcher quantum admits at most its supplied block/transfer credits.
Native arithmetic is emitted as Lua arithmetic, not an interpreted opcode.
Loops, branches, calls and straight-line operations transfer between explicit
block labels. Argument-list assembly is split across blocks rather than emitted
as one giant expression. Dynamic calls retain a result receiver; an application
suspension returns an explicit tuple, while exhausted execution credits retain
`running` state without supplying a fake yield/result. Credit zero executes no
block. The native fixture scheduler supplies the durable per-tick/shared ledger
and deterministic activation admission described below. Full weighted coverage
and production mixed-backend admission remain acceptance work; a bare dispatcher
quantum alone does not establish those guarantees.

Generated bundle ABI 4 compacts straight-line functions without erasing logical
continuation labels. Consecutive descending move labels can share one function,
capped at eight steps and 1024 body bytes including checkpoint guards. Branches,
loop headers and explicit call/index/set/return transfers remain boundaries.
An ephemeral checkpoint callback admits each matching logical label and updates
its error location before executing its effect; quantum exhaustion leaves that
interior label untouched and addressable in the shared function. The first label
uses the dispatcher's already-paid credit, never a second charge. A one-credit
quantum therefore still progresses one step, and quantum sizes produce identical
logical costs for the same computation. Reconstruction only builds the function
table; it does not run the application. The callback/functions are never stored.

Single-expression lists use their already-adjusted tuple directly, and multi-item
lists initialize from the first scalar instead of empty-plus-append scaffolding.
Fixed compact helper names are emitted by the compiler, not applied as string
rewrites to player literals. Evaluation order, colon prefixes, expanding final
calls/varargs, scalar adjustment and explicit nil arity remain fixture-verified.
`layout_checks.lua` additionally verifies interior-label zero-credit inactivity,
separate-process resume, unchanged logical costs across quantum sizes, current
failure locations, body/fanout caps and unchanged literal contents.

Verified language surface in `tests/native-mod/lowering_checks.lua`:

| Supported construct | Fixed-source reference case or native check |
|---|---|
| Scalars, arithmetic, numeric coercion, comparison, unary operations | `scalar arithmetic`, `numeric coercion`; source-located runtime refusal |
| Explicit nil tuple arity, varargs, parenthesized scalar adjustment | `nil tuple`, `varargs`, `single vararg`, `parenthesized call` |
| Multiple/empty returns and scalar call operands | `multiple returns`, `empty returns`, `scalar call positions` |
| Local/global/index assignments and left-to-right effects | `local assignments`, `order`, `index order`, `captured assignment` |
| Short-circuit values and object equality | `short circuit`, `short circuit identity` |
| Function declarations/expressions, shared captures and dynamic calls | `function valued table`, `function tail identity`, `captured assignment` |
| Colon calls and implicit method receivers | `method receiver`, `method evaluation` |
| Table constructors and last-field result expansion | `constructor tuples`, `keyed constructor` |
| Scalar concatenation operands and escaped string literals | `concat scalar calls`, `string escaping`; hostile long literal emission check |
| Lexical scopes, conditional branches and breaks | `scope shadowing`, `branches`, `nested loop break` |
| While/repeat/numeric/generic loops and per-iteration captures | `while loop`, `repeat scope`, `numeric for`, `generic for`, both loop-capture cases |
| Linked goto/label constructs | `goto`; front-end rejects invalid jumps |
| Suspension mid-expression/control flow | compiled nested expression saved/reloaded; loop-suspension check |
| Bounded hostile and long straight-line work | infinite-loop/zero-quantum/neighbor checks; 200 sequential increments |

Reference host `load` is confined to fixed, authored test strings in the fixture,
not player/ROM loading. The emission fixture temporarily guards `VM.run` to
assert zero guest-VM dispatch during native execution. It also verifies exact
literal data, empty global environment, generated-size/block/list/depth refusal,
shared emission refusal and subsequent recovery. Syntax errors name the source,
line and column; runtime failures retain source and mapped block line. The
source-location run passed 149 checks before save and 154 cumulative after
separate-process reload, with orderly server shutdown:
`/home/siredvin/.hermes/profiles/albina/cache/scratch/blue-native-locations/`.

## Persistent coroutine/protected/collection fixtures

### Active source and synchronized reconstruction

Each machine retains its compiler-produced bundle, including the exact source,
chunk name, compiler version 1 and generated ABI 4. This tuple identifies the
immutable active version, independently of later disk edits. Execution format 5
retains that bundle alongside the heap/frames and the versioned cell pool, while
compatible format-4 graphs remain supported (see task 5.8 below). Disk trees and
handles contain no executable functions; parser ASTs never enter the snapshot. Compilation admits
the additional bounded prototype snapshot pass before publishing its metadata.

`scripts/native/dispatch.lua` is the synchronized reconstruction entry point.
Its host-only weak-key cache is recreated when the process loads the mod; neither
cache functions nor the diagnostic cache-load count are durable. Before every
dispatch that runs generated code, its mandatory host admission callback reserves
the same provisional reconstruction cost on every peer:

    source bytes + generated bytes + chunk-name bytes
    + prototype count + total logical block count

Only after successful admission does it increment durable `activation_work` and
`activation_dispatches` and obtain/rebuild the executable table. A warm cache
does not skip admission. A failed reconstruction remains charged. Refused
admission leaves execution, guest outputs and activation counters unchanged;
zero execution credits, waiting/finished states and collection-only dispatches
need no activation. The generated builder registers functions, never invokes
guest module initializers. The low-level execution/emission probes can construct
executables directly; they are not a scheduling entry point or permission for
guest source-loading wrappers to bypass synchronized admission.

Unsupported machine/compiler/ABI versions or invalid reconstruction enter a
durable `recovery` status with the original status and a bounded explanation.
Heap, frames, pending boundaries, disk, open handles and drafts remain intact;
subsequent dispatch neither retries nor overwrites the original recovery record.
Nothing reconstructs or executes guest code in `on_load`.

`activation_checks.lua` compares cold/warm admission, exact output/logical costs,
refused activation, zero-credit inactivity, snapshot refusal/recovery and failed
host reconstruction. It saves a root/child/grandchild coroutine chain inside a
suspended protected error handler with shared closure cells, a cyclic aliased
table, a real durable file draft and collection in progress. The next engine
process verifies owner/frame aliases, handler phase, spent admission credits,
draft identity and a cold executable cache before resuming. Collection preserves
all live identities without activation; recovery then delivers the same table
error, shared function and nil-containing tuples exactly once. The initializer
runs once and the shared captured value becomes 12. An actual source-file edit
to `return 99` affects a fresh compilation only, not the suspended snapshot.
An incompatible recovery graph is also saved and remains recoverable after load.

These work units are conservative deterministic admission, not measured CPU
latency. The fixture's retained allowance is explicitly replenished to proceed;
production aggregate/per-machine simulation-tick ledgers remain task 4.2, and
OS loading/services, packaged/client/multiplayer acceptance and responsiveness
remain separate gates. No warm-cache scheduling or latency exception is implied.

### Heap and continuation invariants

Execution formats 4 and 5 keep heap objects in a dense live-identity inventory with
stable monotonically allocated IDs. Frames retain local-cell IDs and shared
upvalue IDs; closures refer to cells rather than copying captured values. An
uncaptured cell with explicit `captured = false` can be reused by a later local
declaration in the same slot. Closure creation marks every captured cell before
publication. Missing capture metadata is conservative: it never permits reuse.
The loop-capture and separate-process closure fixtures continue to pass.

Coroutine create/resume/yield/status/running/wrap and native tail transfers use
plain pending records and resumer ownership. Protected `pcall`/`xpcall` boundaries
retain depth, receiver, phase and handler identity. Handler suspension, including
a saved table-valued error, resumes without replay. Nil/false/reference-valued
errors retain identity and tuple arity. Numeric error values follow the exact
engine's level-zero identity versus source-prefixed positive-level behavior.
Deep exception unwind clears at most 256 temporary/local slots per paid step;
the dedicated 200-frame fixture verifies multi-step cleanup and zero-credit
inactivity. This does not establish weighted production return/tuple admission.

Supported metatable transfers are `__index`, `__newindex`, `__call`, `__tostring` and protected
`__metatable`. Table delegation and guest callbacks are explicit resumable
transfers; callback index results have scalar adjustment and setter results are
discarded. Unsupported metamethods are refused on installation or later mutation,
not silently ignored. This is a documented subset, not full Lua metatable support.

`scripts/native/collector.lua` freezes guest heap mutation during incremental
root/mark/sweep work. Each paid unit advances one cursor, object or field.
Roots include environment, root/active coroutines, published/yielded results,
reported errors, external roots, pending transfers and protected handlers.
Tables retain reference-valued keys, aliases/cycles and metatables; closures
retain cells, and wrapped coroutines retain their thread. Worklists and cursors
are plain data and survive a separate engine process. Sweep removes unreachable
IDs from the dense inventory instead of scanning every historical allocation.
This is a guest-object quota, not a physical host-memory guarantee.

The actual-tick heap-pressure probe exhausted the genuine 16384-object quota
and completed collection/recovery over 260 ticks with the compact emitter. It
recorded 16385 successful allocations including reclaimed identities, 106474
block/transfer steps and 461979 collection units. A neighboring native machine
received 128 execution steps on every tick (33280 total). Pressure work stays
within the existing execution cap and 2048 per-computer collection units; this
fixture does not yet use the unfinished production shared ledger or a VM neighbor.
Draft tests now use actual durable `w+` handles from the existing local-only
file module, which consumes plain disk/counter data without executing the VM.
They retain the open draft, offset, handle-byte quota and unchanged committed file
through genuine heap exhaustion/recovery. A credit-refused close preserves the
handle for an explicit successful retry. Separate-process collection/protected
recovery also preserves the same handle-table identity and earlier file-work
counter before resuming. Task 3.4 is complete for heap allocation/collection and
retained-resource recovery; guest filesystem wrappers and real editor workflows
remain tasks 4.5 and 5.3, not claimed by these host-side file-helper fixtures.
The native fixture duration was extended to permit this structural pressure
scenario; no production budgets or OS/input acceptance targets were raised.

Current native runs, both base and enabled expansion: 962 checks before save,
1092 cumulative after separate-process reload, with orderly engine shutdown.
Unchanged VM regression: 380/512 checks.
Python fixture/shutdown/resource/report tests: 27 passing. Both resource provenance sets pass.
Native serial evidence: `$TMPDIR/blue-native-sandbox-stress-final-serial/`; VM regression evidence:
`$TMPDIR/blue-native-sandbox-stress-vm/`.
Expansion evidence: `$TMPDIR/blue-native-sandbox-stress-expansion/`. These
runs use the source checkout, not the pending packaged/client acceptance matrix.

## Matched cold-process responsiveness: task 5.5, milestone B blocked

The required performance gate **fails**. Native-generated execution is not a
responsiveness improvement in the current implementation. Task 5.5 remains
unchecked; milestone A's semantics/sandbox/persistence result does not authorize
the blue model. Task 5.6 records this verdict and stops model/backend rollout,
without fallback to VM execution or relaxed resource/performance targets.

Run the serial paired matrix:

```sh
python tests/run_workflow_benchmark.py --trials 10 --characters 10 \
  --output "$TMPDIR/cc2-matched-workflows"
```

`tests/workflow-benchmark-mod/control.lua` uses the same trace for VM and native:
canonical empty local disk, pinned backend ROM, 51-by-19 geometry, one admitted
machine and one scheduler dispatch per actual simulation tick. Each backend/case
has ten fresh engine-server processes, each followed by a separate-process
snapshot check. There are ten basic and advanced launches per backend and one
hundred individually delivered measured characters per workflow/backend: ten
characters in each of ten cold processes. All trials run serially and are paired
by trial/case/backend; no competing benchmark servers run in parallel.

Each character is `x`, measured from its first serviced tick until the actual
terminal model first displays it. Subsequent unmeasured Backspace resets the line
after the application is suspended and non-timer ingress is drained, avoiding
horizontal viewport/scroll bias. This measures first visible model echo, not
the older VM baseline's stricter echo-plus-global-wait completion. Editor-ready
requires the authentic suspended editor source frame and real footer; shell
polling may leave the OS root busy or a timer queued, which is not proof that the
editor failed to launch. Initial false-deadline fixture traces are retained,
including their actual suspended editor/readiness diagnostic. No OS/helper
dependency is substituted and no dispatch is repeated inside a clock loop.

Completed base matrix, 60 workflow runs / 60 cold boots / 40 editor launches /
600 individually measured echoes; all workload and snapshot processes succeeded:

| Measurement (simulation ticks) | VM | Native | Required native result |
|---|---:|---:|---|
| Median cold boot-to-prompt (all three workflows) | 109 | 393 | At most half VM median |
| Median shell-to-basic-editor-ready | 15 | 65 | At most half VM median |
| Median shell-to-advanced-editor-ready | 130 | 302 | At most half VM median |
| Shell first-echo p95 (100 samples per backend) | 2 | 11 | At most 2 |
| Basic first-echo p95 (100 samples per backend) | 3 | 20 | At most 2 |
| Advanced first-echo p95 (100 samples per backend) | 4 | 25 | At most 2 |

Each cold boot reproduces 331,648 VM instructions / 28 collection ticks versus
759,302 native logical steps / 206 collection ticks. These are observed work
counts, not a claim that one native logical step equals one VM opcode. The native
basic echo tail spends twelve collection ticks on slow samples; advanced echoes
spend sixteen. Lowering granularity and retained-graph/allocation overhead are
optimization candidates, not established individual root causes. Changing
checkpoint/format strategy requires review and renewed semantic/persistence
acceptance; increasing the shared 4,096-unit allowance is not a valid speedup.

Every tick asserts existing aggregate execution/collection/service ceilings.
Metrics retain compiler, cold activation, collection, continuation, string,
table, filesystem, event, timer advancement and terminal work plus model dirty
rows/revisions. Whole scheduler `LuaProfiler` diagnostics include service and
collector work; separate module-import and machine-creation profiles include
the VM BIOS factory's module-scope compile and native entry compilation. Native
BIOS/module source compilation additionally occurs inside measured boot dispatch.
These ephemeral times are logged, never persisted or used for scheduling.

For the shell workflow, the median sum of cold module-import, creation and boot
scheduler durations is 1,210.842267 ms VM versus 3,014.692574 ms native. Tick counts
start with actual machine creation/first dispatch; module-scope compilation has
no simulation tick and is explicitly included in this separate cold duration,
not silently omitted. This is profiled script duration, not elapsed real boot
time including idle waits or engine map/prototype loading. The largest observed
native scheduler call across the matrix is 230.919215 ms during cold boot. Work
caps therefore do not establish a real-time CPU bound or acceptable compile
latency. Wall timings remain host-specific diagnostics, not deterministic credits.

The report uses median and nearest-rank p95, checks counted samples, rejects
duplicate cold-process identities and retains nonzero-exit runs as failures.
The matrix driver exits nonzero when a gate fails even if all processes succeed.
This run's exit 1 means failed performance gates, not a crashed engine. All first
and reload server phases acknowledged orderly console quit; no forced kill was
used. Raw logs, per-process JSON, all profiles/work samples and summaries are at:
`$TMPDIR/blue-native-workflow-matrix-10x10/`. `report.json` is the original complete
matrix; `complete-report.json` adds the derived cold-profile duration distribution
without replacing the original evidence. Earlier fixture diagnostics remain in
the separate `blue-native-workflow-probe-*` directories.

This is source-checkout, single-backend, terminal-model evidence. No graphical
presentation cost, authorized GUI path, physical power lifecycle or multiplayer
join is measured; mixed VM/native neighbor admission also remains unverified.
The report explicitly sets client/mixed-backend verification and rollout false.
Previous real shipped shell completion/copy/cd/wait tests and both editors'
editing/save/quota/identity/timer/resize/reload fixtures remain passing structural
evidence, not proof of these failed performance requirements. The new default-
geometry native regression passes 962/1090 (the earlier grow/shrink matrix adds
two resize checks, 962/1092); unchanged VM regressions pass 380/512.

## Allocation and retained-frame evidence: task 5.7

`tests/workflow-benchmark-mod/allocation_audit.lua` is a test-only ephemeral
observer. Enable it with `--benchmark-diagnostics` on the native workflow mode;
it is off by default, is not shipped as a runtime hook and changes no production
module. It forwards actual generated blocks and runtime calls, including arity,
protected errors and checkpoint callbacks. Weak-key machine/helper registries,
host wrappers and statistics never enter guest values or storage. Hooks install
during control parsing; a small trusted forwarding probe runs only at the first
synchronized fixture tick, before benchmark creation, never during cold reload.
The probe checks shared capture updates, protected errors, nil tuple arity,
unchanged counters and propagation of invalid-credit host errors. Its setup/CPU
cost is outside the benchmark's creation/scheduler profiles and is not acceptance.

Example instrumented/control pair (repeat with `basic` and `advanced`):

```sh
python tests/run_engine.py --workflow-benchmark --benchmark-backend native \
  --benchmark-case shell --benchmark-characters 4 --benchmark-diagnostics \
  --output "$TMPDIR/native-allocation-shell-observed"
python tests/run_engine.py --workflow-benchmark --benchmark-backend native \
  --benchmark-case shell --benchmark-characters 4 \
  --output "$TMPDIR/native-allocation-shell-control"
```

The runner rejects diagnostic VM mode and more than 100 characters. The observer
bounds allocation scans by the existing heap ceiling, capture scans by the tuple
ceiling, allocation groups to 8192 and snapshots to 128. Each resident snapshot
examines at most 1,048,576 nodes and emits at most 64 source/prototype frame groups;
truncated scans report `partial=1`, not invented complete totals. All final scans
here are complete. Captures count binding visits separately from transitions of
explicit `captured=false` cells; legacy/ENV cells with absent metadata are not
declared newly uncaptured. Snapshots count resident heap objects/frames, including
not-yet-collected garbage, not a proven reachable/live graph or dead-temporary
inventory. They expose retained temporary tuples/values/reference counts by
source/prototype as well as aggregate resident/captured-cell counts.

New identities are counted before/after generated blocks and after real runtime
dispatch, including parameter binding and service/control allocations. Generated
step counts include each paid merged checkpoint; remaining control/error work
is explicitly grouped under `<runtime-control>`. Allocation totals and execution
totals must exactly match the machine's real counters before the fixture saves.
Generated-block attribution is direct; allocations between blocks are attributed
to the next observed frame or final dispatch frame, not an exact service-call
allocation stack. This distinction matters for interpreting per-source rankings.
The parser rejects duplicate groups, unknown fields and negative counters, and
retains all `ALLOCATION`, `RESIDENT`, `FRAMES`, `AUDIT` and final `STATE` records.

Final base evidence consists of three serial instrumented/control pairs, four
characters per authentic workflow, each with a separate-process snapshot check.
Every phase/tick/execution/collection/service/activation/display counter and final
allocation/object/identity/revision/tick summary matches its uninstrumented pair.
Their boot/launch and first four echo records also match all ten original native
cold trials for each case. The forwarding probe appears in first-process logs
only, not reload logs. All phases quit with acknowledgement and no forced kill.
These are diagnostics, not a replacement for the original 100-character gate.

| Measured phase | Fresh cells | Other new heap objects | Explicit uncaptured-to-captured transitions |
|---|---:|---:|---:|
| Cold boot (each workflow) | 57,810 | 4,435 | 616 |
| Basic launch | 6,837 | 270 | 45 |
| Advanced launch | 16,947 | 4,272 | 801 |
| Four basic echoes, excluding settle/erase | 5,034 | 84 | 0 |
| Four advanced echoes, excluding settle/erase | 6,045 | 136 | 0 |

Cold boot attributes 41,685 cell allocations / 415,806 execution steps to the
generated pattern core, with nine observed uncaptured-to-captured transitions.
Its prototypes 9, 7 and 4 account for 12,434 / 10,197 / 9,855 cells respectively
with no observed new captures. The authentic expect module contributes 7,667
boot cells; window contributes 1,934. At prompt suspension, six resident frames
retain 717 temporary tuples and 341 reference occurrences, including 279 tuples
in the BIOS main frame and 198 in the shell main frame. Basic/advanced ready
snapshots retain 1,205/1,318 tuples. These counts justify prioritizing bounded
cross-call reuse of provably uncaptured cells, then liveness-safe temporary
release/reuse and redundant lowering. They do not prove that a slot is dead or
that pooling alone will meet the 2x/two-tick targets; captured identities and
pending receivers must still survive every optimized path.

Observer-inclusive scheduler sums (one cold four-character run, ms) are
3663.140828 / 3414.913543 observed/control for shell, 4174.459472 / 4340.840558
for basic and 5766.9594 / 5448.050797 for advanced. They include observer work
inside forwarded dispatch but exclude out-of-profile snapshots/logging/setup.
Single-pair host noise even reverses the basic timing delta; none is an isolated
overhead estimate or a speedup result. Cold compilation/activation work and the
original profiles remain available in each result; actual work/tick counters,
not noisy CPU subtraction, establish observer admission invariance.

Raw final observations: `$TMPDIR/blue-native-allocation-{shell,basic,advanced}-final3/`;
controls: the corresponding `-control/` directories. The aggregate/source/frame
evidence is `$TMPDIR/blue-native-allocation-final-evidence.json`. Preserve failed
`blue-native-allocation-shell-final/` and `-final2/` traces: the forwarding probe
initially required its compiler inside a tick (forbidden by the engine), then
incorrectly expected an unprefixed default-level guest error. Imports now occur
during control parsing and the probe explicitly uses `error(...,0)`; no runtime
semantics or budget was changed to pass it. Original native structural regression
remains 962/1090, VM 380/512, resources/provenance pass, and Python tests total 27.
This is the retained pre-optimization baseline. Task 5.8's first implemented
slice and its preliminary measurements follow; milestone B remains failed and
model rollout blocked under the unchanged acceptance requirements.

## Bounded cross-call cell reuse: task 5.8, first slice

`execution.lua` now reuses only explicitly uncaptured private local cells across
completed calls. The pool retains at most the existing `Limits.register_pool`
256 plain-data IDs; its cells remain part of the same 16,384-object heap quota
and dense identity inventory. Allocation pops a cleared cell in constant work
or follows ordinary allocation. Captured cells and legacy cells with missing
capture metadata are never eligible. All closure binding paths still mark the
same shared cell captured before its owner can be released.

Normal return, closure tail replacement, coroutine completion and exception
unwind use one bounded local-release function. Each visited slot costs four
cleanup units, so an admitted execution credit visits at most 64 slots within
the unchanged 256-unit cleanup ceiling. Wide release keeps a plain cursor in
the pending operation; zero credits neither detach cells nor publish a result.
On a full pool, remaining cells take the existing collector path without an
unbounded scan. Recycled values are cleared before their IDs are pooled.
Pending result tuples and receivers remain rooted until publication. Tail calls
construct the child before detaching the caller, preserving recovery on failed
construction, and root that child in the pending operation during sliced release.
Collection freezes pool mutation and marks its IDs through a separate root case.

Execution format is now 5; the pool has version 1. This first slice retained
generated ABI 4 and compiler version 1; the completed optimization below advances
the compiler to version 2 while retaining ABI 4. Format-4 graphs without a pool
remain compatible. Only admitted
synchronized release creates the optional pool and upgrades the machine marker;
read-only load and zero-credit dispatch do not migrate it. Old partial collectors
remain supported, and unknown execution/pool versions enter visible recovery
with their original graph/files/drafts intact. Downgrading to the old runtime
after creating a format-5 save is not supported.

`cell_pool_checks.lua` covers repeated reuse, a saturated pool and wide normal/
closure-tail releases under one-credit quanta, scoped/shared/error/coroutine
captures, zero-credit inactivity, collector rooting and legacy capture exclusions.
Separate-process saves occur during both normal and closure-tail release with
collection active; reload verifies pending result/child/pool aliases and work
counters before completing the same nil-containing tuple once. A deliberately
labelled legacy probe saves a format-4 machine without a pool or capture metadata,
then checks unchanged load state and conservative synchronized continuation.
Unknown pool versions are rejected without replacing the retained graph.

Full Factorio 2.0.77 native base and expansion regressions pass 974 checks before
save / 1108 cumulative after cold reload; original VM regressions pass 380/512.
All shipped-source compile/load, sandbox, heap-pressure/draft-recovery, service,
cache-admission and OS/editor tests remain included. Python tests pass 27/27,
resources/generated ROM and strict OpenSpec validation pass, and original vendor
and VM ROM bytes are unchanged. First/reload engine processes acknowledge console
shutdown without signals or forced kills. Raw runs are in
`$TMPDIR/blue-native-cell-pool-{final,expansion,vm}/`; the test-first failing run
is retained in `$TMPDIR/blue-native-cell-pool-red/`.

### Preliminary authentic-workflow result, not performance acceptance

Three serial instrumented/control pairs each drive the actual OS through four
individual characters and save/reload. Each pair has identical phase/work/display
metrics and final state, complete bounded snapshots and acknowledged clean
shutdown. Fresh boot cells fall from 57,810 to 710 (98.77% fewer); boot collection
falls from 206 to 20 ticks. This isolates a substantial allocation-pressure
improvement but does not establish sufficient native execution speed.

| Phase | Original native ticks | Cell-reuse probe ticks |
|---|---:|---:|
| Boot to prompt | 393 | 207 |
| Basic ready | 65 | 32 |
| Advanced ready | 302 | 166 |
| Shell, four individual echoes | 11 each | 5 each |
| Basic, four individual echoes | 14 / 14 / 20 / 14 | 8 each |
| Advanced, four individual echoes | 25 each | 9 each |

These are single cold four-character probes, not ten launches/100 characters,
medians, p95 acceptance, graphical presentation or mixed-backend neighbor proof.
Even their best timings do not meet the unchanged two-tick echo or 2x-VM startup/
launch gates. Observer-inclusive CPU measurements are not speedup acceptance.
Controls/observations are `$TMPDIR/blue-native-cell-pool-{shell,basic,advanced}-`
`{control,audit}/`; derived evidence is
`$TMPDIR/blue-native-cell-pool-probe-evidence.json`. Preserve original failed
matrix and probe logs. This first slice alone did not complete task 5.8; the
remaining temporary/lowering work and full rerun are recorded below. No blue
model/backend rollout or acceptance exception is enabled.

## Completed representation/lowering optimization: task 5.8

The compiler now leases temporary slots over structured continuation regions.
Nested expression/statement emission releases only its own slots after emitting
the complete region; caller-owned destinations, operands, assignment receivers
and loop controls remain reserved. Slots may then be reused by disjoint regions.
Lease release and reuse still charge compiler work, and source/generated-output,
block/body, activation, service, instruction and heap limits are unchanged.
Single-expression lists use their already-adjusted tuple instead of allocating
and copying an empty list. Scalar call results use the existing scalar result
publisher rather than a separate adjustment block. These changes do not combine
independent effects or remove their admission checks.

Compiler version 2 identifies the changed generated layout; ABI 4 and execution
format 5 remain unchanged. Dispatch explicitly accepts retained compiler-1/ABI-4
bundles without recompiling their frames against a different slot layout. The
genuine pre-change `legacy_temp_bundle.lua` snapshot is loaded and resumed after
a separate-process save with collection active. New-layout persistence tests
retain frame/temporary/receiver aliases, previous RHS values, nil arity and
side-effect counts across suspension, zero-credit dispatch and collected reload.
Reference cases cover nested numeric/generic loops, branches, goto, assignment,
short circuit, method calls and suspending metamethod paths through the existing
regression suite. No textual rewriting of guest literals is used.

The pre-scalar-publisher four-character observer/control pairs agree exactly on
workflow metrics and final state, with complete bounded snapshots and clean
shutdown. Retained boot temporary slots fall from 717 to 110; basic-editor launch
slots fall from 1205 to 258, and advanced-editor launch slots from 1318 to 274.
These are diagnostic slot counts, not proven live reachability or responsiveness
acceptance. Evidence is `$TMPDIR/blue-native-temporary-probe-evidence.json`.

The final native base and expansion suites each pass 991 checks before save and
1129 cumulative after cold reload. Original VM checks remain 380/512. All 27
Python tests, shipped-resource verification, native ROM generation checks and
strict OpenSpec validation pass. Vendor and original VM ROM bytes remain
unchanged. Raw runs are `$TMPDIR/blue-native-optimized-{final,expansion,vm}/`;
test-first failures and intermediate probes remain retained separately.

### Unchanged full matched rerun: performance gates still fail

The final lowering runs the same ten cold processes per workflow/backend and
ten individual characters per process: 60 completed cold runs, 100 character
samples per workflow/backend, zero workload failures. The original driver was
terminated by SIGTERM after 37 recorded runs. The remaining 23 runs were resumed
serially without replacing completed results; the incomplete attempt and its
logs remain separately recorded. The derived report is
`$TMPDIR/blue-native-optimized-workflow-matrix-10x10/resumed-report.json`;
the original partial report and original failed baseline are preserved.

| Phase | VM ticks | Optimized native ticks |
|---|---:|---:|
| Median boot to prompt | 109 | 201 |
| Median basic-editor launch | 15 | 31 |
| Median advanced-editor launch | 130 | 158 |
| Shell echo p95, 100 samples | 2 | 9 |
| Basic echo p95, 100 samples | 3 | 8 |
| Advanced echo p95, 100 samples | 4 | 23 |

Every unchanged native 2x-startup/launch and two-tick-p95 gate fails. In particular,
the short advanced-editor probe's nine-tick echoes did not predict its 23-tick
full-matrix p95. Successful execution, reduced retention and lower per-dispatch
CPU medians do not establish acceptance. Task 5.8's bounded optimization and
required rerun are complete, but task 5.5 and milestone B remain failed/open.
Graphical presentation and mixed-backend neighbor responsiveness remain
unverified. Blue production/model integration is still blocked; no budget
increase, VM fallback or exception to the acceptance requirements is enabled.

## Native events and shipped timer ownership: task 4.1

`scripts/native/events.lua` adapts the existing data-only ordered queue/timer
module to native heap identities; it never invokes the VM. Queued guest references
are validated public identities and use `native_ref` in durable records. The
incremental collector now roots event state, so a queued closure's captures and
aliased tables survive collection even after the originating result disappears.
Host functions, private native objects and nonfinite event numbers are rejected.
Queue count/byte limits and trusted-priority overflow policy remain unchanged.

Timer creation uses the retained simulation clock and monotonically allocated
IDs; even zero-duration timers wait for a later advancement. Due timers publish
in deadline/ID order, and cancellation removes queued undelivered tuples too.
Admission callbacks refuse before retaining a timer identity or mutating its
deadline. During collection the clock can advance but timer publication and root
delivery wait, preserving the scanner's frozen reference graph.

Scalar host input remains admissible during collection through bounded,
pre-charged copy-on-write of the queue array. Existing immutable records can be
shared with the collector's old snapshot, including conservatively retained
priority-evicted references. New heap-reference ingress is explicitly deferred
while collecting; guest code, including guest queue calls, is paused then. No
extra active queue/byte allowance is introduced. The separate-process fixture
saves the old queue in the collector worklist and a newer queue containing a
character, then delivers that character in order after reload, without loss.

Only a yielded root coroutine receives host input. Nested application yields
return to their Lua resumer, and a running continuation cannot take a later event
before it reaches another root wait. The bridge delivers events unfiltered:
the shipped Recrafted scheduler yields without filters, and its guest wait code
owns filtering and timer ownership. Source inspection confirms that normal waits
raise on termination before filtering, whereas raw waits apply their filter to
termination as well; timer routing uses Recrafted thread IDs, not native heap IDs.
The bridge must not substitute the shared module's filtered raw-wait semantics
or treat every nested yield as a host event filter.

`event_checks.lua` verifies symbolic queue/start/cancel services, exact nil arity,
deadline order, atomic refusal, queue pressure, queued-object collection, nested
yield delivery, zero-credit inactivity and separate-process ordered root waits.
Its explicit-clock timer cases are structural semantics tests, not real-tick
OS/editor latency measurements. The actual BIOS/shell boots and its suspended
readline survives cold reload; normal/raw waits, termination and application peer
timers alongside shell polling pass as recorded below. The additional authentic
editor cases below complete the remaining timer-ownership coverage for task 4.1.

`editor_timer_checks.lua` reuses the actual shell-launched editor sessions and
does not replace BIOS, `rc.thread`, either editor or their guest timer functions.
Ephemeral bounded observers forward the real native start/cancel services with
their original event admission, recording returned IDs, duration and executing
native coroutine. Trusted fixture readback locates actual OS thread records and
the shared ownership cell of the authentic BIOS start/cancel closures; it does
not expose host introspection to guests or manufacture ownership records.

The labelled maintenance-pressure setup consumes the existing timer-advance
allowance while ordinary admitted input/execution continues. This holds genuine
pending deadlines so six separately delivered characters can exercise all five
advanced-editor debounce cancellations before timer publication. Every earlier
ID is cancelled once and disappears from both timers and the ownership table,
with no queued event. The final 0.2-second timer belongs to the actual editor
coroutine/thread, while the real parent shell renews a distinct 0.05-second poll
timer. Timer lookup covers both pending and already-published queue records;
an already queued shell wakeup may legitimately be consumed and renewed during
typing even while later maintenance is exhausted.

Typing `local ` produces immediate white plaintext. Restoring ordinary timer
maintenance yields the genuine editor timer and syntax-highlights the keyword
orange, without another character event. Shell polling continues to renew its
own timer. The basic editor has no debounce timer, does not acquire shell timer
ownership, and retains the same dirty text/cursor/disk while shell polling runs.
The temporary prefix is then removed and saved through each editor's real menu.

Both dirty collected editor snapshots additionally retain authentic shell timer
ownership; the advanced snapshot retains its outstanding highlight timer too.
Separate-process reload checks exact timer deadlines and ownership records before
guest work, then resumes collection and the actual resize path. Original pending
IDs are consumed without losing dirty text/cursor, and shell polling obtains its
next owned ID. These are structural semantics/persistence checks with a synthetic
scheduler clock, not the real-tick responsiveness/performance gate. Production
budgets, timer semantics and VM resources are unchanged.

## Native tick scheduling: task 4.2

`scripts/native/scheduler.lua` retains a round-robin cursor and a plain-data
simulation-tick ledger. Execution, collection, compiler activation, event calls,
timer maintenance and saved-wait tuple movement use the existing per-machine and
aggregate limits. Each charge checks both allowances before updating either;
nonfinite/fractional charges and backwards ticks are rejected. Counters reset
only on a later tick, not on repeated dispatch, executable-cache reconstruction,
save/load or removal/readmission of the same machine identity.

Internal execution preemption leaves the running continuation in place. It does
not publish a guest yield/result or consume the next event. Root wait delivery
charges one execution credit and reserves `1 + 4 * tuple.n` continuation work
before removing the queue record or changing its saved receiver. Wait admission
refusal retains the queue and wait without a guest error. Timer-maintenance
refusal keeps simulation time current and services the selected guest; pending
timer publication remains deferred. Collection-only dispatch never activates
generated code, and aggregate collection exhaustion preserves the selected
cursor. Incompatible execution state enters retained recovery without preventing
an eligible neighbor from running.

`scheduler_checks.lua` verifies zero-credit inactivity, atomic machine/aggregate
refusal, same-tick reentry, cache-independent activation admission, ordered
mid-event continuation and exact nil arity. Separate-process reload retains
exhausted execution, collection, event and saved-wait movement allowances plus
queue/collector aliases. Direct collection/event/movement reservations isolate
those larger allowances from execution preemption; they are structural quota
tests, not measured workloads. A separate eight-real-tick fixture runs two hostile
loops under the unchanged aggregate execution cap and verifies alternating
neighbor progress without synthetic yields. No OS/editor latency claim follows
from these fixtures.

This module currently schedules isolated native machines. The production backend
facade must integrate native and VM admission into one shared live-game allowance,
not run two independent full-cap schedulers. Native scalar/table/string, terminal,
filesystem and ordinary compound-call/cleanup service integration remain covered
by the unfinished service and backend tasks; this scheduler is not a passed
milestone-A or playable-computer acceptance gate.

## Native helper foundation: task 4.3

`scripts/native/helpers.lua` installs only plain guest service identities. Its
ephemeral callbacks are supplied during synchronized scheduler dispatch and use
the same tick-keyed machine/aggregate ledger. String and table domains reuse the
existing limits; no allowance was increased. This foundation provides:

- Scalar `tonumber`, `tostring` and `select`; reference-valued `tostring` invokes
  supported guest `__tostring` callbacks through resumable transfers, otherwise
  reporting deterministic guest type/identity, never a host wrapper address.
- Native `ipairs` returns a stable plain service identity, the original input
  table and numeric control zero. Triple publication reserves 16 continuation
  units. Each iterator call validates its finite integer control and reserves
  eight table units before a raw next-slot read. False is a value, not an ending;
  the first nil terminates, returning one nil as verified in the actual engine.
  Calls read current slots rather than a sequence snapshot. Metatable iteration
  extensions remain explicitly unsupported by the existing metatable allowlist.
  The implicit iterator identity has its own collector root, independent of the
  replaceable `ipairs` global; no host closure is returned or persisted.
- Raw native `pairs`/`next`, with scalar/reference-key decoding, stable original
  iterator identity and a bounded durable engine-order key index. Table values
  are read live, not snapshotted. Deletion/overwrite preserves key positions;
  insertion invalidates the index for subsequent traversal. The original `next`
  service remains independently rooted after replacement/removal of globals.
  `__pairs` remains explicitly unsupported by the metatable allowlist.
- Raw native `table.pack` and `table.unpack`, preserving explicit maximum tuple
  arity and nil holes. Pack reserves work before allocation; unpack bounds its
  default border scan and reserves range readback before copying.
- Raw native `table.concat` bounds its default border scan and explicit range,
  reserves input reads/conversions and total output before opaque joining, and
  never mutates the input table. Numeric parts reserve a conservative 32-byte
  conversion allowance; maximum 65536-byte output remains accepted under the
  unchanged credits. Sparse invalid parts and excessive output fail explicitly.
- Raw native `table.insert`/`remove` use the existing dense-prefix border and
  8192-key limit. The read-only border scan pays one table unit per tested slot;
  shifts reserve `16 + 8 * moved_slots` table units before any write. Insert
  validates its item and final key capacity first. Nil insertion at a full key
  inventory frees the destination before shifting, retaining its original value
  explicitly so false/reference items are not lost or quota-refused mid-write.
  Insert returns no values; remove returns the removed value, except empty or
  just-past-end removal returns no values, as verified against the actual engine.
  Invalid positions and excessive sequence/key capacity fail explicitly.
- Byte-oriented `string.len`, `sub`, `byte`, `char`, `rep`, `lower`, `upper`,
  `reverse` and explicitly plain `find`. No UTF-8 character semantics are claimed.
- Scalar math helpers: abs, inverse/trigonometric/hyperbolic functions, ceil,
  floor, deg/rad, exp, fmod, frexp/ldexp, log/log10, min/max, modf, pow and sqrt;
  `pi` and `huge` are scalar constants. Numeric-only inputs consume no byte work.
  Unary/paired/variadic argument movement is admitted, and numeric-string bytes
  are reserved together before conversion. Multi-result frexp/modf retain arity.
- Private `math.random`/`randomseed` with a versioned per-machine numeric state;
  no host random function or host seed is called. Each accepted draw/reseed uses
  16 continuation units and publishes its state only after admission.
- Fixed-width `bit32` helpers: arshift, band, bnot, bor, btest, bxor, extract,
  lrotate, lshift, replace, rrotate and rshift. Every invocation reserves
  `1 + 4 * argument_count` continuation units before operand validation or native
  execution, with the unchanged 1024-value tuple cap. Operands must be finite
  numbers strictly between -2^53 and 2^53; numeric strings/references are rejected
  like the original VM's numeric-only wrapper. Supported normalization, fractional
  operands, rotations, negative/large shifts and extraction/replacement ranges
  follow the pinned engine's native fixed-width implementation.
- Scalar `string.format`, including colon calls through the original string
  library. It reuses `scripts/guest/format.lua` as a bounded host helper, not the
  VM or guest bytecode dispatcher. Templates are limited to 4096 bytes; validated
  conversions reserve input/width/precision/quoting estimates before opaque
  formatting and reserve final joining within the existing string ledger.
  Nil/boolean `%s` operands use the shared Lua-5.2-compatible scalar conversion.
  Reference operands are rejected instead of invoking host or guest tostring
  callbacks. Result quota remains 65536 bytes.
- Resumable dense-prefix `table.sort` in `scripts/native/sort.lua`: stable
  bottom-up merging, numeric/string default comparisons and guest comparators.
  Snapshotting and merging advance one bounded item/control step per execution
  credit. Every step reserves eight table units; string comparisons additionally
  reserve both operand byte lengths. Two work arrays are each bounded by the
  existing 8192-key limit. Active helper records per coroutine are capped by the
  existing continuation depth of eight, counting protected and direct service
  receivers as well as guest callback frames; the scan is precharged against
  continuation credits. No host `table.sort` processes guest elements.

Sorting stages its result without writing the input. Final preflight/publication
reserves `1 + 8 * size` table units together before validating staged identities,
checking key capacity and writing the bounded result. Comparator effects are
ordinary guest effects and are not rolled back, but sort's own writes are atomic
on refusal. An adjacent-order callback pass rejects demonstrably inconsistent
ordering; callback invocation counts are not promised to match host sorting.
Default reference/mixed-type ordering is explicitly unsupported rather than
calling host metamethods. Native pattern matching/replacement is described below;
actual shipped-OS pattern workflows remain unverified.

Execution format 4 adds private helper control/result receivers. These records
are plain data, not guest values or executable functions. Callback frames,
protected boundaries and saved root/child waits retain them; collection roots
both the machine wait receiver and thread wait receivers. Root resumption uses
the common result publisher, including direct protected/yielding services,
instead of indexing the temporary table with a receiver record. Format 3 states
halt with the existing recovery policy, retaining their state/files/drafts;
generated bundles now use ABI 4 for the metered operand preparation interface.
Older ABI 3 bundles likewise halt with retained recovery data. This does not
affect original VM saves.

`sort_checks.lua` verifies ordinary order, stable reference ordering, maximum
dense input, reference-valued callback errors, inconsistent comparators, atomic
credit/key-capacity refusal and bounded recursive callbacks, including direct
protected-service comparators. Separate processes resume a collected yielding
guest comparator and a maximum-size mid-copy sort beside a busy native neighbor;
the latter retains same-tick exhaustion, completes under unchanged shared caps
and allows no more than one consecutive tick without neighbor execution. Direct
root and child `coroutine.yield` comparators retain an un-compared staged identity
after its public input edges are deliberately removed, then finish after reload.
These are helper/resource fixtures, not actual shipped OS or client acceptance.

`table_checks.lua` compares insertion/removal and return arity with a fixed-source
engine reference, including empty removal, append, middle shifts, nil insertion
and false preservation. It verifies raw behavior without executing `__newindex`,
maximum-length shifts, full-key capacity refusal, full-key nil insertion and
credit refusal after the border scan but before publication. Guest protected
recovery retains the original sequence. A collected separate-process reload
preserves a removed reference, alias identity, false/trailing nil and exhausted
same-tick table credit, then continues editing without replaying initialization.

Formatting fixtures compare ordinary conversions and quoted strings against the
engine's fixed-source reference, exercise a maximum-size accepted result,
reject excessive widths and guest identity operands, and verify exhausted-credit
refusal through a native protected receiver. The collected separate-process
method/coroutine fixture also resumes a format colon call after replacing the
global string library, without reinstalling it or replaying initialization.

The random format is `{version = 1, seed = integer}`. Its next seed is
`16807 * (seed % 127773) - 2836 * floor(seed / 127773)`, adding 2147483647 when
nonpositive; split products keep arithmetic intermediates exact. The unseeded
default is 1. Explicit finite integer seeds normalize modulo 2147483647, mapping
zero to 1. A no-argument draw returns `(next_seed - 1) / 2147483646` in `[0,1)`;
one/two-argument draws map that unit into a finite integer interval with endpoints
inside `[-2147483646,2147483646]` and width at most 2147483646. This is predictable,
non-cryptographic randomness, not host-sequence compatibility or a security API.
Invalid input, unsupported retained generator versions and admission refusal
leave the generator unchanged. Missing legacy state initializes only at an
admitted draw; an explicit accepted reseed replaces state by user intent.

`random_checks.lua` verifies seed-1 vectors against independently calculated
modular arithmetic, interval and seed validation, isolation from another machine,
quota-refused draws/reseeds and compatible absent state. Its compiled fixture
saves after one draw with exhausted continuation credits and collection pending;
a new process retains the exact stream and then produces the next three draws
without replaying its initializer or seed operation. Table concatenation uses
fixed-source host-reference checks plus maximum-output and atomic input-retention
fixtures. These are helper semantics/resource checks, not shipped parallel-module
execution or OS latency acceptance.

String indexing and colon method lookup use the original installed guest string
library, not the current global `string`. The library identity is a ninth
collector root, so replacing the global does not invalidate literal methods.
Lookup proceeds through the ordinary resumable table-index/metamethod path;
guest method replacements and yielding library-index handlers remain guest
closures rather than opaque host callbacks. Missing methods return nil and string
mutation remains rejected. Older machines without this optional library root
continue to collect their existing roots; their library surface is not silently
reinstalled during load.

Numeric-string argument conversion is precharged. Slices charge clipped output
instead of the backing string; transformations reserve input/output work. Repeat
validates output size before opaque work and bypasses native iteration for empty
output with a huge count. Plain search uses a conservative suffix-length times
needle-length comparison estimate, rather than assuming linear native search.
Finite integer indices are validated and substring ranges clipped before native
calls. A false or throwing admission refuses work; same-tick refusal does not
refund already admitted work or renew counters. Helper failures follow the
existing resumable guest protected-call boundary.

`helper_checks.lua` compares fixed authored source with the engine's host scalar
and tuple reference, verifies maximum sparse nil arity, output/credit refusal,
small slices of maximum strings, conservative search refusal and protected
recovery. Separate-process reload collects a retained packed guest table while
its application waits, preserves exhausted string credits and plain service
identities, then resumes without repeating its initializer. Fixed-source scalar
math results are checked against the engine reference, including numeric-string
arguments and multiple returns. String-library replacement, yielding metamethod
lookup and a nested yielding method callback are exercised. The reload case
collects while that callback is suspended and the global library is replaced,
then validates original-library identity, later method lookup, math and exact
nil-containing coroutine results. The additional collector root changes the
pressure fixture's measured work, not its quotas or neighbor service allowance.

### Generated operator accounting

Generated ABI 4 retains direct Lua arithmetic and ordered comparisons. Its
compact operand-preparation helpers only validate/coerce/reserve operands; they
do not dispatch symbolic arithmetic opcodes. Numeric-string unary and binary
operands reserve their complete byte sum before parsing, with four continuation
units per operand. Numeric-for initialization reserves all three conversions
together before entering the loop. Numeric-only operands consume no byte work.
Ordered string comparisons and string equality/inequality reserve both input
lengths before the opaque Lua comparison. Reference equality remains identity
comparison, and numeric comparison remains constant-work generated Lua.

Concatenation estimates each string at its actual size and each numeric conversion
at 32 bytes, rejects excessive output before conversion, and reserves twice the
complete estimate for conversion/input plus final joining. It also reserves four
continuation units per part. Table length reads a deterministic dense-prefix
border with one table unit per probe, bounded by 8192 slots. A completed scan is
now retained as optional private `dense_length` metadata; cached reads reserve
one table unit. See the actual editor fixture below for mutation/reload rules and
the repeated-append root cause. String length is a constant-work byte length.
These operators use the same tick-keyed machine and
aggregate ledger as named helpers through an ephemeral host-only `native.work`
callback. That callback has no guest global/service identity. Bare untimed
`Execution.run` fixtures have dispatch-local ceilings only; they are not evidence
for tick scheduling and must not be used as the production admission boundary.

`scalar_checks.lua` verifies fixed-source reference values and exact nil arity,
all six string comparison operators, paired conversion refusal, maximum-size
concatenation, rejected target publication, bounded/partially refused table
length scans, numeric-for entry refusal and numeric-only byte-work exclusion.
An emission assertion checks direct arithmetic/comparison syntax. Collected
separate-process reload retains exhausted string/execution credits, performs no
same-tick operator/event delivery and resumes the expression on a later tick
without replaying initialization. Compiler/helper quotas are unchanged.

### Generated tuple and constructor accounting

Generated vararg copies reserve `1 + 4 * count` continuation units before copying.
List expansion/append reserves `1 + 4 * appended_count` before changing tuple
arity or slots. Single-value boxing remains constant bounded checkpoint work;
this does not claim complete weighted coroutine/protected-result movement.

Keyed constructor setters reserve eight table units before writing. Constructor
array ranges validate their bounded integer range and reserve `16 + 8 * count`
table units before preflighting every value and the complete final key count.
After preflight, nil holes are removed before nonnil writes so accepted
replacement cannot temporarily exceed the final capacity. No guest callback
runs inside this admitted publication. Constructor fragments may have produced
earlier private slots before a later fragment fails, but a rejected constructor
does not publish a replacement into its caller's target.

`construction_checks.lua` uses actual compiled source for reference-keyed tables,
maximum sparse vararg expansion, nil arity, false/reference identity and protected
constructor/list admission failures. Synthetic trusted executable blocks isolate
private API preflight on existing tables: credit/capacity refusal, full-key
replacement with holes, keyed overwrite refusal, append refusal and maximum
vararg-copy refusal. Those synthetic checks are not shipped-application evidence.
Collected separate-process reload retains both exhausted table/continuation
ledgers and aliases, then constructs another table without replaying its prior
initializer. Earlier helper refusal fixtures now finish setup before exhausting
constructor credits, rather than relying on unmetered fixture setup.

`iterator_checks.lua` compares raw generic-for/direct iterator behavior, exact
return arity, false values and hole termination against fixed engine reference
source. It verifies stable iterator identity, input mutation between calls,
invalid-control refusal, ordinary/protected admission failure and maximum dense
traversal spanning multiple dispatches under unchanged limits. Separate-process
reload resumes a collected generic-for after one completed iteration, retaining
reference identity and exhausted table credits without replay. A separate saved
factory removes the global before ever returning an iterator, proving the
implicit identity survives collection independently of previously returned
iterator values. General `pairs`/`next` are not implemented by this fixture.

### Durable raw pairs/next traversal

`iteration.lua` uses the exact engine's raw `next` to build an optional private
key-order index on the native table descriptor, one bounded step at a time.
The pinned library documentation describes insertion order except ascending
first-1024 numbered keys. Fixed-source engine comparisons cover that behavior
with mixed numeric, boolean, string, table and function keys. Guest strings such
as `r1` remain disjoint from encoded reference keys. No host iterator closure or
raw value-map table is returned to the guest.

The first direct-engine implementation passed deletion within one process but
failed the separate-process deleted-cursor fixture with `invalid key to 'next'`:
engine serialization did not retain that deleted key. The persistent index fixes
this without relying on engine hash tombstones. It holds at most 8192 encoded keys
and their ordinal map, not guest values or native reference wrappers. Overwrites
and deletions retain it; insertion discards it, preventing historical keys from
growing across insertion/deletion cycles. Adding previously absent keys during a
traversal is not advertised as a stable-order extension. Deleted reference-key
metadata intentionally does not keep an otherwise unreachable guest object alive;
the iterator skips deleted slots before decoding an identity. Ordinary live keys
and pending decoded outputs remain rooted through the existing heap graph.

Each opaque inventory lookup provisionally reserves
`16 + 4 * (8192 + 1024)` table units. Before recording a fetched string key in the
index, reserve twice its encoded byte length; a refused step retains its fetched
key and prepaid lookup. Cached traversal reserves eight table units per inspected
slot, including deleted positions. String controls reserve twice their encoded
length before encoding/lookup, and string output decoding reserves twice its
encoded length. Result tuples reserve five units for the final single nil or nine
for a key/value pair; `pairs` triple publication reserves 16. These conservative
work units and index memory bounds are not physical latency guarantees or shipped
OS performance evidence. Existing limits, execution format 4 and generated ABI 4
are unchanged; the new table field is optional and lazily constructed.

Raw helper admission now returns its scheduler result to resumable helpers;
existing ordinary helpers still use the asserting wrapper. Exhausted read,
inventory-byte or output credits retain private control rather than publishing a
guest yield/error/result. Previously paid phases are not charged again after
deferral, collection or reload. No mutation to input slots is needed to retain
this private progress.

`next_checks.lua` compares authored fixed-source behavior/arity in the engine,
including deletion of the current and another key, live overwrite, fresh
post-insertion traversal, invalid controls, false keys/values and nil termination.
A maximum 8192-slot inventory completes beside a busy native neighbor with
unchanged shared caps and no fake yield. These scheduler stress loops are not
real-tick editor or mixed-backend latency evidence.

Separate-process fixtures resume a collected loop after it deletes its current
key and removes both globals, without repeating initialization. A synthetic
host-only admission wrapper forces output deferral after a reference-key lookup;
the staged key/value survive collection and public input-edge removal. Another
forces inventory-byte deferral on a 65536-byte key: the prepaid opaque lookup,
partial index, exhausted same-tick ledger and later output survive reload without
replay. Raw direct-service tests independently cover read, input-byte, output-byte
and tuple-phase retention. Engine failure traces preceding the durable-index fix
remain outside git at `$TMPDIR/blue-native-next-checks/`,
`$TMPDIR/blue-native-next-reload-fixed/` and `$TMPDIR/blue-native-next-diagnostic/`.

### Native-generated resumable patterns and retained libraries

`scripts/native/patterns.lua` reuses the bounded matcher source already shipped in
`scripts/guest/patterns.lua`, without executing VM bytecode or opaque host pattern
matching on guest input. The original matcher source and VM resources are
unchanged. Compiling the entire matcher exceeds the unchanged 131072-byte generated
output cap. The adapter divides the fixed trusted source into a matcher core and
public API, each compiled through the normal bounded native compiler. Generated
frames call the original scalar/table services and share their weighted ledger.
The private initializer retains both source strings before compiling either part,
so suspended initialization does not select a changed module's API source later.

Patterned `string.find`, `match`, `gmatch` and `gsub` now enter plain private helper
continuations. The first call initializes the two libraries through generated
frames; later calls use the retained function table. Matcher locals, backtracking,
capture tables, returned iterator closures, replacement callbacks and replacement
table metamethods are guest execution, not host closures. Existing matcher bounds
include 4096 pattern bytes, 32 captures and 65536 output bytes. Execution credits
preempt searching and backtracking without a fake coroutine yield. Pattern and
sort helpers share the existing metered receiver/boundary nesting guard.

The only native source semantic adaptation makes an exhausted `gmatch` iterator
return zero values, matching actual Factorio 2.0.77 reference execution rather
than returning one nil. Empty-match behavior is also compared against that exact
engine: attempted newer-Lua empty-match suppression failed the reference fixture
and was removed. No newer interpreter's semantics are substituted for the pinned
engine. `string.dump` still fails explicitly; raw guest bytecode dumping remains
unsupported.

Closures and frames optionally record their owning `bundle_id`; absent IDs retain
primary-bundle behavior. The machine's optional `bundles` table retains immutable
plain source/compiler/ABI snapshots in a bounded sparse registry. Registration
is host-only, admits its cell
movement before allocating/publishing, and is capped at the existing call-frame
limit. Guest loading now reaches it only through the bounded source compiler.
Unreachable registry entries are reclaimed as described in task 4.5. Every
executed bundle
is admitted once per dispatch independently of warm/cold cache presence; changing
bundles does not renew untimed fixture helper ceilings. Frame cleanup, constants,
upvalue definitions and diagnostics resolve the owning bundle. Missing or
incompatible retained sources halt with the recovery graph intact. These optional
fields preserve primary-only execution-format 4 and generated-ABI 4 behavior.

`activation_checks.lua` additionally verifies equal cross-bundle warm/cold work
and outputs, secondary activation refusal/retry without initializer effects,
registration refusal before publication, bounded registry growth and recovery for
missing/incompatible secondary sources. `pattern_checks.lua` compares captures,
balanced/frontier/back-reference patterns, positional captures, replacement
strings/tables/functions, nil arity, empty matches and iterator termination with
fixed source in the exact engine. Malformed/oversized patterns, oversized callback
output and excessive nested helpers recover through guest protected boundaries.
Cold compilation credit refusal publishes no partial library. Pathological
backtracking is preempted beside a busy neighbor under unchanged shared caps.

Separate-process reload saves an in-progress collector while a replacement
callback is suspended inside a guest table `__index`. Core, API and application
sources, callback count, captured reference and a partially consumed `gmatch`
iterator remain aliased. Cold reconstruction resumes the metamethod and replacement
exactly once without replaying library or application initialization.

Failure traces are retained outside git. The original 65536-byte literal
replacement did not finish within the unchanged 500-dispatch fixture ceiling at
`$TMPDIR/blue-native-pattern-semantics/`. Its reproduced failure at
`$TMPDIR/blue-native-literal-red/` retained running API prototype 6 after 2052096
logical blocks. The expansion path copied each literal byte into a temporary
table, repeatedly scanning its dense prefix for length and coalescing pieces.

The native-only adaptation now probes for `%` using the existing metered plain
search. A replacement without escapes is already its expanded result and reuses
that immutable string, bypassing character expansion and temporary table scans.
Output validation and final joining remain unchanged and charged. Escaped
replacements continue through the original resumable expansion; no opaque host
pattern call or allowance/deadline increase was introduced. Nine fixed-source
engine comparisons cover literal/empty/numeric replacements, escapes and captures,
malformed escapes, no-match behavior and a zero replacement limit.

The formerly failing maximum-literal overflow fixture now reports the actual
pattern-result byte limit and preserves its caller's previous target. An exact
65536-byte accepted result completes under fresh credits after fixture setup;
a separate admission-refusal fixture exhausts the probe's string credits and
verifies no target publication. Separate-process reload additionally preserves
a maximum literal input, initialized library aliases and an in-progress collector,
then produces the exact output bytes/count and trailing nil without initializer
replay. Maximum callback-output refusal remains independently covered. These
results resolve the recorded literal fixture failure. Maximum escaped replacement
acceptance is recorded below; real OS latency remains unverified. Earlier semantic failures remain in
`$TMPDIR/blue-native-pattern-integration/` and `$TMPDIR/blue-native-pattern-final/`.
These are isolated helper/activation fixtures, not real-tick editor benchmarks,
graphical acceptance or mixed-backend scheduling evidence.

The subsequent bit32, resumable tostring, ordinary-key and escaped-expansion
fixtures below complete task 4.3's scoped helper acceptance. Actual BIOS/module
integration and complete allocation/cleanup/sandbox stress remain separate tasks
4.6 and 5.1-5.6. This is neither shipped-BIOS execution nor a native OS-ready verdict.

## Native terminal services: task 4.4

`scripts/native/terminal.lua` installs a guest table of symbolic `term.*` service
identities and retains a plain authoritative `machine.display`. It reuses
`scripts/guest/terminal.lua` as the existing byte-cell model, not any VM heap,
bytecode, function wrapper or execution state. Cursor/blink, palette, Color/Colour
aliases, text/foreground/background rows, geometry, dirty rows and revision
semantics therefore use the same handlers as the original backend. Guest returns
are scalar tuples only; no display or engine object enters the guest environment.
Installation is idempotent and does not reset a live display or replace captured
service identities.

The native scheduler now includes a durable terminal domain with the unchanged
262144 per-machine and 524288 aggregate per-tick work ceilings. Every terminal
call, including aliases, reserves `Display.work` before invoking its handler.
Admission refusal raises a protected guest error without modifying cells, cursor,
blink, palette, dirty rows or revision. Invalid handler arguments also retain the
existing atomic validation. Optional ledger fields retain zero defaults for older
scheduler snapshots; reload or repeated same-tick dispatch cannot renew credits.
Host geometry reconciliation remains the shared synchronized lifecycle operation,
not an unmetered guest resize API.

`terminal_checks.lua` exercises compiled native calls and compares their complete
display and tuple results to direct execution of the existing model contract.
It covers clipping, cursor/blink, palette channels/packed values, aliases, clear,
scroll, nil arity, repeated installation, all mutating service admission refusals
and representative invalid arguments. Trusted direct-service fixtures isolate
maximum 160-by-60 geometry, 65536-byte writes/blits, large signed scroll offsets,
palette invalidation, exact admission, repeated full clears and machine/aggregate
exhaustion. A native scheduler stress case verifies neighbor progress under the
existing execution and terminal caps. Geometry overlap and authoritative alias
retention are independently checked using the shared reconciliation function.

Separate-process reload retains display identity, revision, cursor, palette and
an exhausted tick ledger while the collector is active. A saved write service
survives removal of the global terminal table. Same-tick refusal leaves the
complete display unchanged; fresh-tick cold execution completes its write once
without replaying application initialization. Storage validation checks the full
fixture graph contains only plain data.

These results complete the isolated terminal-service adaptation in task 4.4.
Actual shipped windows/editors, startup-settings event ordering, production
mixed-backend admission, GUI focus/rendering and multiplayer remain their own
unverified integration/acceptance tasks. Maximum model geometry is not a claim
about client-supported dimensions or user-visible latency.

## Shipped-ROM compiler preflight: layout blocker resolved

`tests/native-mod/rom_inventory.lua` compiles every Lua source from the actual
shipped ROM table without executing its application code. The initial audit
refused four required sources at the 131072-byte generated-output cap. After the
approved layout revision, all 63 compile and their generated bundles load in
Factorio 2.0.77; every prototype retains all logical labels/source maps. The four
previously refused sources now fit without raising any production limit:

| Required source | Source bytes | Generated bytes |
|---|---:|---:|
| `/rc/apis/textutils.lua` | 8817 | 114305 |
| `/rc/apis/window.lua` | 9658 | 130605 |
| `/rc/editors/advanced.lua` | 9228 | 115935 |
| `/rc/modules/main/rc/thread.lua` | 8667 | 111520 |

The preflight now asserts zero compiler refusals in the native fixture, but is
deliberately not an OS acceptance check. Exact current records are in
`$TMPDIR/blue-native-scalar-final/rom-compile-audit.json` and engine logs; the
initial four-failure audit remains at `$TMPDIR/blue-native-rom-preflight/`.
Passing compilation/loading is not evidence that services or application behavior
work. No scheduler/window/editor source was dropped, patched or replaced with VM
execution to pass this gate.

Window is the largest generated ROM source at 130605 bytes, close to the existing
cap. Future ROM changes must rerun the full inventory rather than assume headroom.
The original 500-increment refusal stimulus became accepted after compaction;
the 600-increment fixture still proves the unchanged output-cap refusal. Full
service, activation-accounting, interactive OS and responsiveness gates remain
pending; smaller generated text alone is not measured startup/input performance.

## Native local filesystem, handles and source loading: task 4.5

`scripts/native/filesystem.lua` installs scalar symbolic directory/metadata
services and a plain authoritative `machine.disk`, reusing the bounded local/ROM
operations in `scripts/guest/files.lua`. It imports canonical snapshots only,
requiring a directory root, existing directory parents, plain nodes, string file
contents and unchanged node/content quotas. It copies accepted nodes, never
exposes host filesystem tables to guest code and does not resolve peer mounts.
Directory results are fresh guest tables; ROM lookup selects the shipped bytes.

The scheduler shares the unchanged per-computer and aggregate filesystem work
limits, retains spent counters for the tick, and installs this bridge only for
filesystem-enabled machines. Atomic copy/move/delete/directory operations retain
the original tree after zero-credit or final-charge refusal. Host consumers must
resolve `Filesystem.files(machine)` for each snapshot rather than hold a boot-time
tree alias: existing mutations deliberately replace the authoritative tree.

`filesystem_checks.lua` exercises compiled guest directory/metadata operations,
defensive list results, empty metadata, exact scalar arity, root/ROM/NUL/recursive
destination protection, malformed snapshots, maximum node inventory and quota
refusal. A separate process reloads a collected suspended machine with exhausted
credits and a captured move service after removing the public `fs` global. It
preserves the saved tree and ledger, refuses same-tick deletion, then moves once
through the retained service without replaying startup.

`scripts/native/file_handles.lua` additionally installs `fs.open`, `io.open` and
`io.lines`, with read/readAll/readLine, write/writeLine, seek, flush, close and
lines methods. It reuses the existing bounded local handle implementation and
all 15 accepted read/write/append/plus/binary mode spellings. Method bindings
retain private version-1 records and receiver identities as plain data; no host
closure is persisted or returned. Both dot and matching colon calls work.
Native IO supports the shared counted/all/line/keep-newline read formats, not
arbitrary standard-library IO or native host files.

Compound IO reads, iterators and writes stage offset/draft/accounting changes
until the complete operation succeeds. Credit-refused close retains the open
draft for retry; a content-quota failure instead preserves the previous file
and the existing nontruncating close-and-release semantics. Open preflights the
complete fixed heap binding before retaining quotas. Maximum draft construction
and commit fit unchanged fresh-tick filesystem credits.

The collector roots private handle edges from public tables and bound services,
including iterator formats/receivers. Capturing only a method preserves its
handle; collection of an unreachable open handle releases byte/count quotas
without committing its abandoned draft. These are additive plain fields and a
private heap kind in execution format 4; guest validation still refuses private
handle references. Guest code sees only the public table and symbolic functions.

`file_handle_checks.lua` exercises compiled FS/IO calls, all mode spellings,
binary bytes, append/seek/padding, multi-format reads, iteration/EOF, nil arity,
ROM refusal, heap/count/content limits and atomic service-credit refusals.
Separate-process reload preserves a collected private draft and its offset
with exhausted credits and removed public libraries. A same-tick close remains
retryable; next-tick captured methods read from the saved offset and commit once
without replay. The initial maximum-draft fixture correctly failed because
other saved files consumed disk space; the corrected fixture isolates a single
file rather than raising quotas. Failed logs remain outside the repository.

`scripts/native/loader.lua` provides source-only `load`, `loadfile` and resumable
`dofile`. The same bounded compiler charges real shared compiler credits for
parse/link/generation/snapshot work; file lookup separately charges filesystem
credits. Loaded functions capture a guest table environment, never a privileged
host environment. Reader-function and binary loading remain explicitly unsupported.
Syntax/byte/work/quota failures return bounded nil/error tuples; `dofile` propagates
failure through the guest protected-call path and retains nil arity through yields.

Loaded sources occupy the unchanged bounded retained-source inventory. The
collector tracks live closure/frame bundle IDs and reclaims unreferenced slots
incrementally after heap sweeping. Registration reserves the bounded slot scan
before publication, never uses array length on the sparse inventory, and requests
collection after quota refusal so abandoned sources cannot permanently exhaust
the machine. Legacy partial collectors without a source-mark inventory preserve
all sources until a subsequent full collection. Warm/cold activation still uses
the existing cache-independent reconstruction guard.

`loader_checks.lua` invokes the actual shipped ROM copy module through guest
`loadfile` and verifies shared/cyclic table semantics. It covers explicit shared
environments, invalid source/binary/reader/environment/file rejection, maximum
source bytes, independent exhausted admission domains, bounded source inventory
recovery and frame-only retention after a loaded tail call. Separate-process
reload inside `dofile` preserves source/table aliases and exhausted compiler
credits; cold resumption runs the saved source once despite edited disk bytes.
A later file load chooses the edit. The initial zero-credit mode check escaped
the load failure tuple; it now reports the same bounded failure convention as
compiler refusal, with the failed trace retained outside git.

Task 4.5 is complete for native local/ROM filesystem, handle and source primitives.
The Recrafted package/module search and actual startup sequence remain task 5.2.
No actual shell/editor workflow or production lifecycle consumer is claimed.
The original VM filesystem and ROM resources are unchanged.

## ROM helper audit: bit32 and remaining task 4.3 gaps

The actual shipped `colors.lua` requires bit32 operations that were absent from
the native environment. `bit32_checks.lua` now compares every installed bit helper
against fixed source in Factorio 2.0.77, checks maximum operand count, invalid
types/nonfinite values/field ranges and zero-credit refusal before native work.

The fixture loads the unchanged ROM `cc.expect` and `colors` sources through
guest `loadfile`, resolving only the authentic installed terminal/bit libraries
and the real expect module. It exercises color combine/subtract/test, RGB
packing/unpacking, blit conversion, aliases and real terminal palette writes.
This narrow fixture resolver is not the pending Recrafted package loader.
Separate-process reload resumes a collected module after removing the public
bit32 global, retaining palette aliases and exhausted continuation credits,
then invokes the module's captured bit library without replaying initialization.

The same source audit found `textutils.lua:214-225` installs `__tostring` for its
JSON sentinel objects. This required metatable transfer is now supported as
described below. This remains a helper audit, not proof of shipped OS execution.

## Resumable tostring and core table/metatable admission

Guest `tostring` reserves eight table units before consulting a reference's
private metatable. A nonnil `__tostring` invokes the existing bounded helper
transfer protocol after nesting admission and eight continuation units for its
argument tuple. The plain receiver retains callee, input identity and eventual
return values through collection/suspension. There is no host callback invocation,
host metatable installation or host closure in storage. Protected metatables do
not hide the callback from the runtime. A callback may itself be a guest callable
table. Only its first return value is used; it must be a string of at most 65536
bytes, admitted to the shared string ledger before one-value publication.
The numeric-result restriction matches the existing VM helper contract; this is
not a claim of every Lua version's tostring coercion rules.

`core.rawget` and `core.rawset` now reserve eight table units plus `1 + key_bytes`
string units for string keys before encoded lookup/mutation. `core.getmetatable`
reserves eight table units. `core.setmetatable` reserves `16 + 4 * metadata_keys`
table units before protection checking and scanning; each `s__` field separately
admits its encoded name bytes before allowlist lookup. No target metatable or
used-metatable flag changes until the entire scan succeeds. The host-only core
admission callback shares the generated operator ledger, including its untimed
ceiling; it introduces no guest service and changes no generated ABI interface.

`tostring_checks.lua` covers protected reference errors, invalid/nil results,
multiple-return adjustment, protected metatable visibility, replacement callbacks,
callable-table transfer, nested coroutine yields, recursive helper-depth refusal,
zero-credit lookup/output and exact maximum/oversized output. Compiled-source
fixtures exhaust table/name-scan credits after setup and verify unchanged table
content and metadata flags; an 8192-key metatable exercises the maximum scan.

A narrow guest loader fixture reads the unchanged shipped textutils source and
compiles only its actual immutable JSON sentinel constructor section, without
fabricating dependencies or modifying ROM bytes. It verifies `[]`, `null` and
rejected sentinel mutation. This is explicitly not execution of the complete
textutils module or BIOS/package loader. Separate-process reload saves inside a
protected callback with alias identity, collection active and string credits
exhausted; the public tostring global is removed. Cold resumption retains the
receiver, returns the original object name with a trailing nil and executes both
boot and callback effects exactly once.

## Ordinary table keys and callable transfer admission

Ordinary generated index/set transfers now reserve encoded-key work, not merely
their single execution step. Each raw operation reserves eight table units and,
for a string key, `1 + key_bytes` string units before prefixing/hashing the key.
A write reserves both its prior-value read and proposed write together. Keyed
constructor initialization reserves one operation. Each table-delegation hop
pays separately; the cursor advances only after that hop's admission succeeds.
An attached metatable additionally reserves one fixed-name lookup for `__index`
or `__newindex`. Read/write callback tuples reserve `1 + 4 * arity` continuation
units before the pending call is published. Implicit string-library lookup uses
a local resolved identity, retaining the original pending object until transfer.

Callable-table transfer reserves one `__call` lookup, caches that result rather
than reading it twice, then reserves `1 + 4 * (argument_count + 1)` continuation
units before copying the implicit receiver prefix. Refusal leaves the callee,
argument tuple and depth unchanged; it does not execute the callback. These are
host-only runtime helper additions with no new emitted ABI identifier, persisted
host callback or increased work allowance.

`key_checks.lua` verifies exact maximum 65536-byte keys in normal writes/reads and
keyed constructors, both zero-byte and zero-table-credit refusal, and rejected
metamethod effects. A maximum-key delegated write is deliberately refused when
its second hop exceeds the unchanged shared byte limit; neither table is changed.
A callback-prefix fixture refuses immediately before implicit receiver copying
and verifies the exact retained callee, original nil-containing tuple and absent
effects. Separate-process reload saves a maximum-key `__newindex` callback with
target aliases, collection active and both table/string credits exhausted; cold
resumption commits one key, returns the original value and trailing nil, and
executes the callback/boot once.

Previously isolated helper-quota fixtures now capture their protected caller and
helper/input references before exhaustion. Reading `pcall` or a library field
from `_ENV` is itself an ordinary charged table operation; attempting it after
zero-credit setup fails before entering protection. Readback of unchanged content
is performed through trusted fixture inspection when no guest read credits remain.
Exact scalar/constructor ledgers include ordinary global-key lookup work rather
than omitting it. All prior native fixtures still pass under the same limits.

## Maximum escaped replacements and task 4.3 acceptance

The new maximum-input fixture exposed a real failure: a 65536-byte replacement
starting with `%%` was still running after the unchanged 500-dispatch deadline,
with 2052124 native execution steps recorded in `$TMPDIR/blue-native-escape-red/`.
The original VM matcher source and ROM bytes remain unchanged. Only the native
generated API adaptation now processes literal runs through at most 256-byte
clipped slices and admitted plain probes. Explicit expanded/piece occupancy
avoids repeated dense-prefix length scans. A repeated two-byte escape token in
one bounded probe is decoded once and expanded with the already admitted native
repeat helper after complete output-size preflight. This is not host pattern
matching, a bytecode fallback or a new opaque unbounded parser.

Both work arrays still coalesce at 1024 entries. Empty output fragments do not
create entries; an existing single final string is reused instead of performing
a second maximum-size join in the same tick. This resolved a separately observed
byte-credit refusal in `$TMPDIR/blue-native-escape-diagnostic/`; no limits,
execution quantum or deadlines changed. Invalid trailing escapes/captures and
oversized expanded output still fail through guest protection without target
publication. Repeat admission occurs only after expansion size is accepted.

`pattern_checks.lua` and `escape_checks.lua` compare 65536-byte sparse/dense escape
inputs, `%0`/`%1` expansion, a boundary-spanning token and exact 65536-byte output
against the pinned engine. Invalid repeated tokens, trailing `%` and expansion
overflow retain the caller's old target. Existing literal/empty/no-match/count,
iterator, callback/metamethod and malformed-pattern comparisons continue to pass.
An isolated, labelled single-step fixture stops at a bounded expansion probe
after normal scheduler warm-up, removes the public string global, exhausts byte
and execution credits and starts collection. Separate-process cold reload resumes
the retained original source/cursor, returns exact output plus trailing nil, and
does not replay the boot effect. That fine-grained fixture reuses trusted bundle
registrations; it is persistence evidence, not a production latency benchmark.

Task 4.3 acceptance is covered by the scalar/helper/bit32 suites; table/sort/
construction/iterator/next suites; pattern/escape suites; and tostring/key suites.
Together they verify the documented ROM-required helper surface, large input and
output bounds, shared pre-admission before helper-owned mutation, captured/yielding
callback and metatable transfers, protected refusals and explicit unsupported
helpers. Full shipped OS workflows, mixed-backend aggregate admission, sandbox/
maximum-cleanup latency and graphical/multiplayer acceptance are not inferred from
these fixtures and remain blocking tasks.

## Actual shipped BIOS, shell workflows and suspended readline: task 5.2

`scripts/native/boot.lua` creates an isolated native machine with symbolic safe
services, validated disk, authoritative terminal and guest `_G`/`_VERSION`/`_HOST`.
The trusted entry passes the existing pinned BIOS text as an explicit guest
argument; its guest `load` compiles through the metered source loader. BIOS text
is deliberately not a filesystem entry: the shared ROM hides `/bios.lua` from
guest filesystem access. No raw BIOS source reaches host `load`. The vendor,
shared VM ROM and resource manifest remain unchanged. Backend-specific resource
generation is still task 5.1; this fixture does not claim it implemented.

Actual startup/package/module loading, `rc.thread`, `rc.io`, terminal/window/
textutils/keys support and `rc.shell` reach the shipped Recrafted 1.6.0 prompt.
This exposed a missing `debug.traceback` service at the real scheduler's protected
spawn path. The added stub matches the existing VM: no argument returns `guest
traceback`; otherwise it returns the same value, including a reference-valued
error. It does not inspect host stacks or expose `getinfo`, `sethook`, registry,
native functions or other privileged debug state. Admission reserves continuation
5 and string bytes, capped at the unchanged string limit, before publication.
Fixtures cover identity/scalars, maximum message, oversized message and zero
credit; loader isolation explicitly checks the allowed stub and denied host APIs.

Simulation `os.clock`, scalar `os.getComputerID` and symbolic shutdown/reboot
requests reserve one event credit before result/request publication. A published
host request stops the current execution loop and later guest dispatch; no
instruction after the request executes. Actual lifecycle consumption remains task
6.1, not implemented model routing. Refused requests do not mutate the host flag.

`boot_checks.lua` types each character of `mkdir /native` through the real shipped
readline and saves at its OS-root wait after collection. A separate engine process
retains the displayed prefix, active sources/coroutines and no directory effect.
After individually delivering `-saved` and pinned lwjgl3 Enter (257), the shipped
directory command creates `/native-saved` and returns to a fresh shell wait. The
existing fixture's plain-storage audit rejects any persisted host closures/threads.
Executable caches are cold and load callbacks do not execute BIOS or guest code.

This is structural headless OS/persistence evidence, not a responsiveness gate.
Its controlled scheduler calls advance synthetic clock values within fixture
events; they are not one dispatch per real simulation tick. Input drains may take
hundreds of these clock steps, and the fixture explicitly waits for an actual root
wait rather than asserting fast echo. No production budgets changed and no 2x or
two-tick acceptance claim follows. Matched real-tick benchmarks remain task 5.5.
`os_workflow_checks.lua` now verifies actual shell completion, command execution
and shipped BIOS waits without replacement modules. Individual character events
type `copy `: the empty filename prefix displays `aaa.lua`, and Tab commits that
candidate into the real readline buffer. The shipped copy program creates a file
with the source's exact bytes. A nonempty `al` prefix similarly selects `alpha.lua`
from multiple candidates and copies it to a distinct destination. Builtin `cd`
changes the actual thread directory/prompt and restores root before loading a
local test application through the shell's real fork/protected-call path.

That local application is a caller of authentic `rc` and `rc.thread`, not an OS
stub. A nested private coroutine yields a nil-containing tuple to its own resumer
and resumes correctly without becoming a host event filter. Two application
threads receive only their own timer IDs alongside the real shell polling timer;
a zero-duration cancelled timer is neither pending nor queued. Normal filtered
waits reject an unrelated event, preserve false/trailing nil on a matching event,
and raise `terminated` before applying a nonmatching filter under guest protection.
Raw filtered waits ignore unmatched termination and preserve interior/trailing
nils on a match; raw unfiltered waits return termination. The parent shell remains
alive and reaches a distinct fresh prompt. All checks run against the shipped
BIOS/package/scheduler with its existing sources and unchanged budgets.

This completes task 5.2's structural OS/shell acceptance. Task 4.1's explicit
editor timer ownership now passes as recorded above. Both editors execute and
survive dirty cold reload, protected quota recovery and real settings-driven
resize as recorded below. Performance fails the matched matrix above; graphical
and multiplayer acceptance remain unverified. These OS workflow results alone
do not pass milestone B or
authorize playable-model rollout. Milestone A passes the separate audit below.

### Bounded native local/ROM glob service

The actual shipped copy command exposed an absent `fs.find` service: its startup
wrapper captured nil and the command raised `native object expected`. The native
filesystem now installs a symbolic `fs.find` using `scripts/native/glob.lua`.
It returns defensive guest arrays of sorted canonical absolute local/ROM paths.
`*` matches zero or more bytes and `?` one byte within a single path component;
other characters (including Lua pattern metacharacters) are literal. Component
boundaries never match across `/`. Exact paths use existing confined lookup;
wildcards traverse only validated local/read-only ROM directory listings. No
peer mount resolution or hidden BIOS exposure is introduced. This is the documented
native surface, not a claim of unrestricted CC:Tweaked API compatibility.

Path normalization, directory scans, result paths, sorting comparisons and final
guest array construction are charged to the existing filesystem ledger. The
iterative last-star matcher reserves `1 + 4 * (pattern_bytes + 1) * (name_bytes + 1)`
before its bounded byte comparisons, not a host pattern that may backtrack without
admission. Results are bounded by the guest table-key cap and path length. A
credit refusal publishes no guest array and leaves disk unchanged; the caller can
retry with later credits. Glob work is bounded atomic read work, not a newly
resumable guest matcher, and may refuse combinations exceeding fresh allowances.

`glob_checks.lua` covers exact/wildcard/nested/question/repeated-star/literal
metacharacter paths, hidden BIOS and absent peers, final-publication and zero-credit
refusal, maximum local node inventory, maximum-width quadratic reservation refusal
and compiled source calls. A finite labelled host-side property test compares
4,760 name-pattern pairs to an independent DP oracle; it is algorithm evidence,
not native guest throughput. Captured find services and old result arrays survive
collection after removal of the public fs global, protected refusal, separate-process
reload with spent same-tick credits, and successful later-tick continuation.

## Actual shipped editor workflows: tasks 5.3 and 5.4

`editor_checks.lua` boots the authentic BIOS separately for both editors. The
actual shell launches `/rc/editors/basic.lua /note.lua` for the basic editor and
`edit /note.lua` for the default advanced editor. Only the native save-error
adaptations below modify these editors; no syntax module, thread scheduler or
window implementation is substituted or host-loaded. Tests
require an actual suspended editor frame with its retained source name, not only
text resembling an editor. Both committed input files start as `abcTAIL` followed
by `second`. Individual right-arrow/character events insert in the middle while
preserving the suffix. A single paste containing CRLF, CR and LF expands to four
lines, preserving the old suffix and shifting the original second line. A further
character follows the pasted cursor rather than the original cursor. Disk remains
unchanged until the real Ctrl/S menu action saves exact normalized bytes. Dirty
exit confirmation protects the buffer, cancellation permits save, and reopening
through the actual shell/loader/file iterator reproduces the saved contents.

After reopening, both editors receive further unsaved input and cursor movement
to a different line. Each is saved with collection already active, its dirty draft
not committed, the root OS waiting and the existing display/cursor intact. In a
separate engine process the fixture checks no block replay, unchanged display,
cursor, committed disk and timer counter. Input admitted during collection is
then processed at that saved cursor. Unsaved exit protection still appears, and
the real save action commits the combined pre-save dirty draft and post-reload
character exactly once. The separate identity caller retains its own read handle
until editor exit, then verifies the saved offset and closes it. Executable caches are cold, and the
existing plain-storage audit includes both complete OS/editor snapshots.

This is synthetic-clock structural/persistence evidence. It does not measure
real-tick typing/launch responsiveness. Exclusive editor timer routing is covered
by the separate authentic timer fixtures above.
Task 5.3 includes the real protected quota checks below. Task 5.4 includes the
settings/geometry/identity checks below. Both are complete; no benchmark or
playable rollout gate is passed by these fixtures.

### Native resources and protected editor save failure: tasks 5.1 and 5.3

`tools/native_rom_source.py` applies three reviewed native-only editor/IO patches
to verified installed Recrafted baselines and generates `scripts/native/rom.lua`
plus `resources/native/manifest.json`. Vendor files, `vendor/manifest.json` and
`scripts/guest/rom.lua` are not rewritten. The native manifest records the pinned
upstream source/revision/hash, installed baseline hash, native patch/hash, adapted
source hash, license/copyright path and generated artifact hash for every resource.
Unlisted patches, duplicate resources, changed baselines and stale generated
ROM/provenance fail verification. `tools/verify_guest_resources.py` checks both
resource sets; regenerate the native set with `python tools/native_rom_source.py`
and verify without writing using its `--check` option.

Both sets contain the exact same 64 resources; only the basic/advanced editor
save bodies and the `rc.io` wrapper differ. All 63 native Lua sources compile and their generated bundles
load within unchanged caps in `rom_inventory.lua`. Native filesystem/loader/glob/
handle bridges share the existing bounded local disk implementation through a
host-only source-table factory, with a separate immutable native ROM map. VM
callers retain their original source map and filesystem behavior. Hidden BIOS,
read-only resource protection and excluded peer/world/network surfaces remain
unchanged. Active saved program bundles keep their own immutable source snapshots;
this does not replace old running editor code or reboot an existing session.

The native editor patches protect the entire line-write/close sequence and assert
each IO write result, so a returned nil/error cannot silently skip a line. A quota
failure reports a width-clipped status (preventing error wrapping from scrolling
the editor), leaves the buffer dirty and returns to editable input. The native
handle `abort` method discards an uncommitted staged handle without flushing it.
Calling ordinary `close` after a credit-refused partial write could otherwise
commit a prefix, so it is deliberately not used for failure cleanup. Abort is a
native extension, not a CC:Tweaked compatibility claim; its fixed admitted work
precedes closed/text/accounting mutation. Refused abort leaves its draft intact,
and unreachable handles retain the existing collector release-without-commit rule.

The actual editor fixtures label their external pressure setup: a filler file
uses the remaining real disk capacity. A dirty save stages earlier lines before
the final oversized write fails through the real handle and guest protected call.
Both applications report failure, retain the previous committed bytes, preserve
the entire dirty draft/cursor and release staged handles without committing a
prefix. Cleanup is checked immediately, not after eventual garbage collection.
A subsequent character proves the application remains editable; after
removing the labelled pressure and undoing those test characters, a real save
succeeds again. Independent abort admission/release fixtures and five Python
native-provenance/tampering tests also pass. These checks complete tasks 5.1/5.3,
not real-tick performance or packaged/client acceptance.

The shipped `rc.io` module replaces early native IO definitions. Its native-only
adaptation forwards `abort` without flushing, propagates close errors before
marking the wrapper closed, and guards the string-format prefix check so counted
numeric reads work. Earlier quota fixtures could reclaim an unreachable failed
handle during incidental collection and mask the missing wrapper abort method;
the default-geometry fixture exposed it. No VM resource is changed.

### Real settings-driven editor reload and identity: task 5.4

Both actual editors are additionally launched by a local guest caller through
the authentic shell/source loader. The caller opens a real IO handle, consumes
two bytes, retains an alias and records its actual coroutine, OS thread/tab,
thread-variable table, terminal window and size-method descriptor. These are
live application identities, not mock thread/window services. Both dirty editor
snapshots are saved with collection active. Cold reload checks the complete old
display, blocks, cursor, committed file, timer counter, all recorded identities,
and the private held handle's offset before any reconciliation or guest work.

The native engine harness now supports actual startup setting changes between
processes. The base run changes 51-by-19 to 61-by-24; the expansion run changes
51-by-19 to 43-by-16. `Display.dimensions()` reads the actual new startup settings,
not a substituted machine dimension. The admitted host-only native terminal
bridge validates geometry/version, reserves full old/new-grid work and priority
notification admission, and preserves the display object. No guest dispatch can
occur between notification admission and parent-model reconciliation. Authentic
`rc.thread` then reconciles its tab/window geometry before forwarding the resize
to the editor; the editor reconciles its child window against that new parent.
Both applications redraw the old dirty content and move the footer to the new
last row using only the resize event, before any character is injected. Cursor,
committed file and coroutine/tab/window/handle identities remain unchanged.

The next character continues at the saved cursor, the real menu commits exact
combined bytes, and editor exit returns to its retained caller. Reading through
the retained alias produces the next three bytes (`ndl`) at the saved offset,
then closes the handle without accounting leaks. Host bridge fixtures separately
check terminal/event credit refusal and invalid geometry against complete display
and queue snapshots, preserved display aliases and idempotent unchanged geometry.

Run the matrix with `tests/run_engine.py --native --reload-columns 61
--reload-rows 24` and `--native --expansion --reload-columns 43 --reload-rows 16`.
The enlarged structural suite uses a 180-second wall-clock server-phase timeout
instead of 60 seconds; initial expired runs remain in scratch failure traces.
No production work budget, simulated workflow deadline or performance gate was
raised. These are exact-engine structural/persistence checks, not real-tick echo,
graphical client, multiplayer or mixed-backend production acceptance.

### Dense-prefix length metadata and the advanced editor root cause

The initial actual advanced launch failed while its shipped syntax definition
recursively inventoried builtins and repeatedly appended to `syn.builtin` using
`syn.builtin[#syn.builtin + 1]`. The previous native `#` implementation scanned
the entire dense prefix on every append. Those quadratic scans combined with
bounded iteration inventory charges to exhaust the existing table-work allowance;
the subsequent shell/thread failure handling also ran out of credits. A compiled
ROM inventory alone had not exposed this execution-time failure.

`execution.lua` now caches only a successfully completed deterministic dense
prefix. Cached length reads cost one admitted table unit and return the same
border. All native numeric mutations pass through the existing setter. Deletion
within the prefix shortens it in constant work; append advances it only when the
following slot is absent. Filling a hole before an existing suffix invalidates
the metadata, leaving the next length read to perform its original fully charged
bounded scan. No input-dependent scan moves into unmetered mutation work. The
setter's existing reservation covers the additional constant checks. False values
remain present, and nonarray keys do not alter the prefix. Refused scans do not
publish a partial prefix. The metadata is private plain scalar state, never a
guest table key, executable cache or host reference. Old native snapshots lacking
it take the existing scan path; no generated ABI or execution-format change is
required and the original VM implementation/ROM remain unchanged.

`length_checks.lua` exercises a 400-element guest append loop under unchanged
credits, a labelled 144-mutation host-oracle property test with compiled guest
length reads, hole bridging/deletion/overwrite/false/nonarray cases, and rawset,
insert/remove/sort mutation routes. Separate-process collection/reload covers
both retained metadata and a snapshot with the optional field deliberately absent;
alias identities and repaired lengths survive without replay. Helper refusal
diagnostics now identify the exhausted work domain and requested charge. The
full native base/expansion and original-VM regressions pass with unchanged limits.

## Sandbox and maximum-workload audit: task 4.6, milestone A

Milestone A passes on the pinned Factorio 2.0.77 engine, base and expansion.
Its required generated nested suspension, shared upvalues, protected errors,
zero-budget deferral, hostile loops, bounded collection and separate-process
persistence are covered by the existing continuation/scheduler/collection tests.
`sandbox_checks.lua` and `stress_checks.lua` add the final adversarial API and
accepted maximum-payload/cold-cleanup evidence. This is isolated-backend
feasibility, not permission to bypass milestone B or deploy the blue model.

### Audited boundaries and adversarial guest paths

- `compiler.lua` parses all guest text; `loader.lua` retains versioned generated
  bundles and explicit guest environments. `Execution.executable` loads only
  bounded compiler-generated text, never raw guest source. Generated functions
  receive the native ABI, not engine globals or host `require`. Cold activation
  remains charged independently of ephemeral executable-cache availability.
- `execution.lua` validates scalar/public-reference values and tuples. Reference
  wrappers must have no Lua metatable or extra fields, name an existing positive
  integer identity and target a public table/callable/thread. Cells and other
  private objects are not public return values. Tuples reject extra fields and
  Lua metatables. The pre-existing guards already reject these attacks; no new
  privileged service, environment shortcut or production workaround was added.
- Guest metatables are heap descriptors with the explicitly supported handlers;
  they cannot install host Lua metatables. Protected metatables, raw accesses to
  function/handle methods and synthetic tables with a `native_ref` key expose no
  service name, private receiver data or engine identity.
- Native filesystem/handle modules route through validated local/read-only ROM
  trees and private symbolic handle IDs. Directory results are defensive guest
  arrays. Neither path traversal nor module names consult host/mod files, peer
  disks or a native C-module loader.

The compiled adversarial application probes engine-global absence, inherited and
private `load` environments, binary/function-reader/dump rejection, protected
metatables, callable field/raw access, forged reference-shaped guest tables,
handle methods, directory-result mutation and ROM writes. A real local file
executes the same probes through the shipped shell/package/late `rc.io` path,
then verifies `ffi`, `socket`, mod-qualified and parent-traversal module names
fail as guest errors. The shipped package's public `cpath` is the empty string;
`loadlib` is absent, not a fake successful native-module function.

Labelled host-boundary fixtures additionally attempt service returns containing
a raw host function, real engine object, raw host table, nonexistent reference,
genuine private cell, otherwise-valid reference with an engine-valued extra
field, reference metatable, and extra-field/metatable tuples. Each returns a
protected guest failure without retaining the hostile value. These are deliberate
service-ingress probes, not substituted OS helpers or guest-granted host access.

### Unchanged limits and real-tick stress evidence

The authority remains `scripts/guest/limits.lua`: source 32,768 bytes; strings
65,536 bytes; 256 call frames; 16,384 heap objects; 8,192 keys per table; 1,024
tuple values. Generated output remains 131,072 bytes, with 1,024-byte native
function bodies and at most eight merged logical steps. A computer and the
aggregate scheduler share the existing 4,096 execution units per real tick.
Collection is capped at 2,048 units per computer / 4,096 aggregate; each admitted
cleanup step releases at most 256 work units. Parser/generator work, service work,
pending continuation work and cold activation retain their existing independent
machine/aggregate ledgers. None of these caps or performance targets was raised.

The new stress matrix calls the native scheduler once per actual `on_tick`, with
one stressed machine and an interactive generated neighbor under the same
ledger. Both are armed before measured work, so a real character is pending
beside source loading, IO/display work and deep cleanup. Every tick asserts all
machine and aggregate execution, collection, compiler, continuation, event,
advance, string, table, terminal and filesystem ceilings. No clock-loop run inside
one event is advertised as a latency measurement.

Serial base sample (`blue-native-sandbox-stress-final-serial/first.log`):

| Accepted workload | Real ticks | Neighbor acknowledgments | Maximum acknowledgment ticks | Maximum scheduler time |
|---|---:|---:|---:|---:|
| Exact 32,768-byte loaded source; oversized source refusal | 2 | 1 | 1 | 1.432219 ms |
| 65,536-byte string, staged IO write/seek/read/close, 160-by-60 terminal write/clear | 4 | 3 | 1 | 1.605006 ms |
| 256 live frames, reference-valued protected error and bounded unwind | 3 | 2 | 1 | 6.631102 ms |

The IO case verifies every committed byte, empty handle/draft accounting and the
complete cleared final row. Cleanup reaches the actual 256-frame stack and spends
6,885 bounded cleanup units, returning the same error table. The source payload
fills the byte cap using whitespace plus a valid return; it proves accepted
maximum byte handling, not maximal syntax complexity or a worst-case CPU bound
over every accepted program. Existing compiler/output/pattern/heap tests cover
independent complexity limits and atomic refusal. The expansion matrix passes the
same real-tick assertions alongside all existing maximum-inventory/heap fixtures.

`LuaProfiler` surrounds the whole scheduler call, including generated execution,
its service handling, collection and cold bundle activation. Profilers are
ephemeral diagnostic `LocalisedString` log values; times never enter storage,
control flow or resource admission. Initial small fixture compilation and event
ingress setup occur outside this timer, and no GUI presentation is measured.
The sample above was rerun serially, not compared against concurrently running
matrix jobs. These nine measurements are diagnostic latency evidence, not a
ten-launch/100-character benchmark, a hard real-time guarantee or milestone B.
Neighbor acknowledgment updates guest state; it is not terminal-rendered echo
or a graphical keyboard measurement. Failed fixture runs remain in scratch.

### Cold recovery and refusal policy

The maximum-depth cleanup program also suspends at a real pending unwind with
its reference-valued error and collector active. A labelled one-credit fixture
dispatch reserves existing execution allowance; it does not fabricate frames or
increase a production budget. Separate-process reload checks the same pending
cursor/object identity, block count, collector and exhausted same-tick allowance,
then completes protected recovery once with the same error and intact neighbor.
The complete storage graph passes the existing no-host-function/metatable/thread
audit and the engine's real ZIP serialization, with no guest work in `on_load`.

Budget exhaustion defers generated execution invisibly. Bounded opaque helper,
source or mutation refusal is an explicit guest failure; compilation publishes no
callable on refusal, and mutating services reserve work before publication.
Protected callers can recover on later credits without a hidden VM fallback.
Committed files, offsets, admitted events and retained draft state follow their
documented atomic/retryable contracts. Abort discards a staged draft without
flushing; ordinary credit-refused close retains it for retry. The shipped editors
use their protected save/abort policy rather than committing a failed prefix.
Incompatible execution/generated formats preserve recoverable execution/files
and report recovery; they do not silently reboot or convert a live VM computer.
Unprotected application errors remain guest errors handled by the OS or halted
guest runtime, never permission to expose engine state or bypass admission.

## Remaining unsupported behavior and rollout gates

The isolated dispatcher has plain-data cells/table identities/closure bindings,
nested calls, coroutine/protected/metatable transfers, incremental collection
and fixture-owned symbolic services, durable tick ledgers and cache-independent
activation. Milestone A's bounded sandbox/persistence gate passes. Production
terminal/backend/model integration and packaged/client gates remain blocked by
the failed matched performance result. These are still
acceptance work. Isolated BIOS/shell and both shipped editors now execute and cold
reload with dirty drafts, but do not expose them
as a playable blue computer. The existing VM
backend and ROM remain intact. Remaining requirements and rollout gates are
tracked in `openspec/changes/add-blue-native-lua-computer/`.
