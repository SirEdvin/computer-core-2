# Guest runtime feasibility status

This is an isolated implementation prototype, not the computer's active OS.
The existing workbench, shell and callback runtime remain active. No terminal
cutover, upgrade migration, CraftOS compatibility, graphical acceptance or
multiplayer joining is claimed.

## Representation and execution

Prototype/execution format version 1 uses only plain Lua data. Instructions have
symbolic opcode names, constants contain only guest scalars, and compiler
metadata/validation functions are discarded. Guest objects have monotonically
assigned IDs. Tables, closures, upvalue cells and coroutine frames reference these
IDs rather than host functions or native Lua coroutines. Aliases and closed
upvalues retain their identity. Function return/yield/resume tuples carry an
explicit `n` so trailing/interior nils are not lost.

`VM.run` executes an explicit instruction quantum. It never evaluates player
source using Factorio's `load`. Guest calls, metamethods, protected boundaries and
nested coroutine resumers use serializable continuation records. The engine
fixture saves live instruction frames and resumes them in another process;
`on_load` changes only a local phase flag, not storage or guest execution.

## Current language/service boundary

- Source-only `load`, `loadfile` and `dofile` compile through the pinned Phobos
  compiler into guest closures. `load` accepts string source and an optional
  guest-table environment. Binary input and binary-only mode are rejected.
  Reader-function loading is not implemented. Source loads currently reject
  inputs larger than 32,768 bytes. Parser/linker/generation/normalization phase quotas and
  parser/generator nesting limits are described below; whole-compiler and aggregate
  host-work acceptance required by task 2.4 is still incomplete.
- `loadfile` reads the local-only guest filesystem or read-only `/rc`, never the
  existing peer-mount resolver. Paths are normalized/confined to those resources,
  reject NULs/oversized paths, and cannot read the host filesystem. The prototype
  copies admitted disk text rather than retaining host caller tables.
- Base helpers: assert/error, type, tonumber/tostring, select, next/pairs/ipairs,
  rawget/rawset/rawlen/rawequal and getmetatable/setmetatable.
- Virtual coroutine helpers: create/resume/yield/status/running. Yield through
  protected calls is supported. Returning errors containing nil, false or guest
  object references retains their values. Lua coroutine objects never enter
  Factorio storage.
- Safe scalar math helpers (abs through trigonometric/logarithmic/min/max
  operations), pi/huge, and bit32 operations use symbolically resolved host
  implementations with scalar-only input/result boundaries. No host random
  source or clock is exposed.
- String len/sub/byte/char/lower/upper/reverse/rep, bounded scalar format and
  guest-bytecode find/match/gmatch/gsub;
  table pack/unpack/concat plus guest-defined insert/remove/sort.
  String methods use a guest metatable. String helpers have input/result caps;
  string.byte and table.unpack reject oversized tuples. Pattern parsing,
  backtracking and replacements execute as guest instructions, not host pattern
  matching. Formatting bounds are documented in TERMINAL_SERVICES.md.
- `debug.traceback` currently returns the guest error message (or a guest marker),
  without invoking host debug or exposing host frames. Debug introspection,
  registry/upvalue access and hooks are absent.

Game/storage/script/remote/defines, native IO, native code/bytecode loading,
world/network APIs and host functions are unreachable from the guest environment.
The only function-like guest values are guest closures and symbolic services;
service object internals are not guest tables. Terminal/filesystem/event services
preserve this boundary; their isolated contracts are documented separately.
Full language compatibility, heap-byte and aggregate host-work accounting and
client acceptance remain pending. Actual upstream editor workflows pass in the
isolated engine; the baseline below is not a complete hostile-workload verdict.

## Resumable table helpers

Trusted stdlib definitions are compiled into a normalized prototype once per
control-script context. Each new VM queues their initializer above the user
entry frame, with the same guest environment and an ignore-result continuation.
Initialization and all helper bodies consume normal guest instruction quanta;
neither definitions nor comparisons run via a host loader or host table.sort.
Initialization frames themselves can survive collection and separate-process
reload before the user entry starts.

Insert/remove validate finite integer positions and the configured sequence
limit. Sort uses an iterative merge strategy with guest scratch tables, a maximum
of 8,192 sequence entries, optional guest comparison functions and normal guest
`__lt` handling. Its own mutations are staged until comparisons succeed. A
comparison may yield or wait for events; frames, scratch tables and aliasing stay
in the persisted execution graph. Comparator side effects are not rolled back.

The engine covers startup-filename ordering, ascending/custom/metatable order,
empty/tail removal, invalid positions and protected comparison errors. It saves
a sort waiting inside a comparison, reloads in another process and completes the
expected ordering. An infinite comparison still consumes only the scheduled
quantum while a neighboring computer finishes. This resolves a BIOS startup
dependency; its fixture alone is not a BIOS/shell/editor acceptance claim.

## Guest patterns and real package startup

Patterns support byte literals/sets, deterministic ASCII character classes and
their complements, greedy/optional/minimal repetition, anchors, balanced and
frontier matches, captures/position captures and backreferences. Matching patterns
are capped at 4,096 bytes and 32 captures; malformed patterns are validated before
matching. Plain find is byte-oriented. Iterator state is captured guest data.

Gsub supports strings with percent/capture expansion, lookup tables and guest
replacement functions. Empty-match progression follows the pinned Lua 5.2
behavior. Nil/false replacement values retain the match; invalid values raise a
guest error. Accumulated output is capped at 65,536 bytes and fragments are
coalesced to avoid exhausting table key history for ordinary long results.
Backtracking and callbacks remain within normal guest instruction quanta and
object quotas; expensive patterns may take multiple ticks or exhaust guest
resources, but never enter opaque host pattern execution.

The engine verifies a replacement yielding through a virtual coroutine and a
replacement callback waiting across separate-process save/reload, preserving
output and replacement count. An adversarial optional-prefix pattern stays
scheduled while a neighboring computer finishes. A collector regression retains
guest data fields named kind/proto through collection.

The actual upstream 00_fs and 10_package startup sources now execute without a
targeted substitute searcher. The fixture verifies package search paths, cached
module identity, cc.expect/colors imports, local path resolution and normal
failure for excluded peripheral/network/native modules. This is package startup
evidence only; the full boot and editor probes below add BIOS/shell/editor
evidence. Both editors and the packaged dirty-editor workflow now pass;
EDITOR_FEASIBILITY.md retains the initial failure, profiling and recovery evidence.

## Actual BIOS and shell boot

`scripts/guest/boot.lua` compiles the allowlisted BIOS once per control-script
context and creates an isolated VM with root event-loop yielding enabled. It
passes the upstream explicit-ROM argument to avoid the external /.start_rc.lua
shim and supplies the truthful `_HOST` label `Computer Core 2 guest`. No live
workbench boot/migration path is changed. The BIOS itself remains unmodified.

The engine executes actual BIOS startup, package/filesystem/terminal/IO startup,
rc.thread, shell and registered local completions. It verifies the Recrafted
banner and shell prompt, submits guest paste/Enter tuples, and executes a local
probe as a forked shell command. The probe checks editor command and filename
completion, missing world/network modules, boolean settings save/load and
textutils round trips for strings, booleans, precise numbers and nonfinite values.

Tracing full startup showed rc.io already replaces the early BIOS loadfile with
its environment-aware loader; no additional BIOS patch is needed. The probe
checks an isolated environment, binary-only rejection and invalid environments.
VM regressions also cover scalar `%s` coercion and nil/NaN table reads (misses,
including __index fallback), while writes still reject nil/NaN keys.

The real shell returns to its event wait after the fork finishes. Its plain-data
execution graph is saved, reloaded in another engine process and resumes another
local command without rebooting. These injected guest events do not prove actual
Factorio keyboard/paste capture. Lifecycle adapters, graphical rendering/input
and client joining remain open gates. The actual basic editor saves typed content;
the advanced editor highlights, retains its dirty buffer across separate-process
reload, saves exact source bytes, reopens them, and returns to the shell, which
executes the edited source and displays its output. Source and packaged probes
pass at 51x19 base and 80x24 expansion with unchanged resource/process limits.

The complete BIOS boot probe has a separate 10,000-dispatch ceiling per phase;
the ordinary fixture ceiling and scheduler instruction/collection quanta are
unchanged. It logs BIOS instruction/object counts. Compilation is still
synchronous, so boot success does not resolve task 2.4 or establish acceptable
production boot latency.

## Compiler phase quotas (task 2.4 incomplete)

Each source compilation admits at most 32,768 source bytes and a 65,536-byte
diagnostic name. Parser work is capped at 262,144 units. Charges include source
admission bytes, consumed lexical bytes (including lookahead), token/scanner and
grammar iterations, AST/local/upvalue construction, scope/definition comparisons
and array shifts. Long-string delimiter comparisons are conservatively charged
their delimiter width before matching. Native token scans still operate on the
byte-capped source; this is not a host-Lua instruction counter or wall-time limit.

Blocks and recursive expression parsing share a maximum active depth of 64,
including right-associated operator chains and parentheses. The controlled
failure is `source parse nesting limit exceeded`, rather than relying on native
stack exhaustion. Parse-work exhaustion returns `source parse work limit exceeded`.

Jump linking permits 32,768 traversal/comparison units per invocation. Bytecode
normalization permits 8,192 records shared across all nested prototypes: each
prototype, instruction, constant and upvalue descriptor consumes one record
before allocation. Their errors are `jump linking work limit exceeded` and
`bytecode normalization work limit exceeded`. No partial prototype is returned.

Raw bytecode generation permits 262,144 work units shared across the root and
all nested prototypes. Charges precede instruction emission, register/constant
construction, and iterations over statements, historical/active registers,
expressions, branch chains, jump patches, upvalues and instruction parameters.
This includes quadratic historical-register scans at scope exit, not just final
instruction count. Work exhaustion returns `bytecode generation work limit exceeded`.
Recursive expression generation, scope generation, branch-chain construction and
nested function compilation share a maximum active generation depth of 64;
left-associated expressions therefore fail with
`bytecode generation nesting limit exceeded` before exhausting the native stack.
The temporary depth counter is restored through protected calls on both success
and failure, and is not part of a normalized prototype.

The host-only optional compiler metrics sink records phase counters as plain
data without changing success/failure return arity. Work callbacks and parser
temporary roots are ephemeral, released on success and quota exceptions; they
never enter stored prototypes. Nested work scopes restore the previous callback
even after an inner failure and preserve nil-containing return tuples.

Engine adversarial probes exercise quadratic name lookup, large long-string
delimiters, deeply nested expressions/blocks, quadratic jump linking, historical
register scans, left-associated generation and wide bytecode. Generation counters
stop exactly at their quota; nested prototypes share the same budget. The
name-search and jump counters stop exactly at their configured
quotas; weighted delimiter charges refuse work before exceeding the parser cap.
Guest `load` receives ordinary failures and successfully compiles/runs a valid
program afterwards. Actual BIOS/shell/editor workflows exercise the same compiler.
Every vendor change is reproduced from the pinned Git objects by the verifier.

Runtime `load`, `loadfile` and `dofile` additionally charge all admitted phase
work against a shared compiler budget before performing that work. Provisional
limits are 2,097,152 units per computer and 4,194,304 units across the scheduler.
An explicit simulation tick retains aggregate and per-machine counters across
repeated dispatches and separate-process reload; only a later tick renews them.
Backwards ticks are rejected. Untimed standalone scheduler calls define fresh
dispatch budgets, and standalone `VM.run` calls use a per-quantum budget unless
the caller supplies shared counters. Production integration must pass the real
simulation tick rather than use the untimed harness convention.

Refusals return `per-computer compiler work limit exceeded` or
`aggregate compiler work limit exceeded` through ordinary guest load failures;
`dofile` raises the same recoverable guest error. Weighted charges are atomic
across both counters. Failed compilations retain their already-consumed credits.
The compiler charge callback and VM budget scope are ephemeral and restored
after errors; persisted scheduler state contains plain counters, not callbacks.
Trusted module-context BIOS/stdlib compilation and host test setup use the phase
limits without runtime credits; they are not guest-accessible alternate loaders.

Four-machine repeated-load probes exhaust both shared limits, preserve same-tick
credits across reload, and regain bounded service on a later tick. File loaders
cannot bypass admission. Compilation remains synchronous: these work-unit caps
are not host-Lua instruction or wall-time limits, and the deliberately expensive
engine probes do not establish acceptable production tick latency. Aggregate
remaining non-string host-operation budgets and heap-byte accounting remain open;
do not mark task 2.4 complete from this evidence.

## Shared native string work (task 2.4 incomplete)

Native string helpers have additional provisional credits: 262,144 units per
computer and 524,288 across the scheduler. Explicit ticks retain the plain-data
credits across repeated dispatch and reload; later ticks renew them. Standalone
VM calls use per-quantum counters unless shared counters are supplied. Their
ephemeral active scope is restored even when a host/guest operation fails.

Charges precede opaque native work. Case conversion/reverse charge input and
output bytes, repetition charges its precomputed output, char/byte charge tuple
work, and substring/byte ranges charge clipped output rather than their full
input. Constant-time length and scalar-validation work consume small fixed
charges. Nonfinite indices cannot poison counters. Scalar `..` concatenation
charges each copied intermediate result; `table.concat` charges entry traversal,
piece bytes and final joining before performing that work. Guest-defined concat
metamethods still execute through ordinary guest instruction frames.

Formatting charges bounded template scanning first, then conservatively reserves
input and projected expansion bytes before each host conversion, and final join
bytes. Reservations include field widths, numeric precision and quoted-string
escape expansion; they are intentionally conservative, not exact memory sizes.
Invalid/oversized formatting still uses the existing scalar-only validation.
Pattern matching/backtracking remains guest bytecode, not a new host delegation.

`per-computer string work limit exceeded` and `aggregate string work limit exceeded`
are ordinary guest errors catchable with `pcall`. Each weighted admission updates
both applicable counters atomically, or neither; admitted work remains charged
when a later validation/conversion fails. No partial string result is returned.
The engine covers repeated full-size copies from four machines, zero-credit
rejection across the helper/concat entry points, tiny slices of large inputs,
same-tick reload, later-tick recovery and actual upstream editor workflows.
These counters do not account for heap bytes, filesystem/terminal work or complete
host-Lua instruction/time costs. Tick-latency calibration remains an open gate.

## Shared terminal host work (task 2.4 incomplete)

Every symbolic native `term` entry point, including Color/Colour aliases, now
admits a conservative work estimate before invoking its handler. Provisional
limits are 262,144 units per computer and 524,288 across the scheduler, shared
across all calls in an explicit simulation tick and preserved across reload.
Later ticks renew credits; untimed harness calls use per-dispatch budgets.

Write accounts for both generated color strings and bounded row copying; blit
accounts for full color validation and row copying. Clear/scroll reserve work for
the complete bounded grid and dirty-row bookkeeping; clearLine reserves one row.
Palette setters include palette validation and row invalidation. Remaining
bounded queries/setters receive fixed charges. These are conservative work units,
not exact allocations or render costs, and do not change terminal API results.

Refusals raise ordinary guest errors (`per-computer terminal work limit exceeded`
or `aggregate terminal work limit exceeded`) before cells, cursor, palette, blink,
dirty flags or revision can change. The engine exercises repeated operations on
160x60 model grids from four machines, zero-credit mutation refusal with complete
display snapshots, same-tick reload and later-tick recovery. Maximum model grids
here are headless resource probes, not evidence of supported client rendering.
The actual upstream terminal/window/editor workflows remain separate regressions.

Startup geometry reconciliation is a synchronized host lifecycle operation,
not a guest terminal service, and remains independently bounded by model limits.
This does not budget graphical dirty-cell uploads or other host work;
heap-byte accounting and measured production tick latency remain open gates.

## Shared directory host work (task 2.4 incomplete)

Filesystem metadata and directory services now share 1,048,576 work units per
computer and 2,097,152 across an explicit scheduler tick. Counters persist across
same-tick dispatch/reload; ordinary guest errors refuse additional work without
partial directory mutation. Path processing, candidate scans, sort comparisons,
result insertion, proposed-tree staging and quota scans are charged before work.
See `GUEST_FILESYSTEM.md` for coverage, exhaustion semantics and engine evidence.
Handle reads/seeks and guest source lookup share these same credits. Counted reads
bill clipped results; line reads bound the native probe to string_bytes + 1 and
admit the result copy before advancing offsets. Open/write/flush/close and iterator
services now also admit work before retention, reconstruction or publication.
Budget-refused close preserves its open draft for retry; content-quota-failed
close retains the nontruncating release contract. See the filesystem document for
copy-work units and per-operand semantics. Heap-byte accounting, remaining host
work, rendering updates and measured production latency remain open; this does
not complete task 2.4.

## Scheduling and reclamation baseline (task 2.4 incomplete)

Ordinary register cells are reused through a plain-data pool capped at 256,
included in the existing object quota and collector roots. Values are cleared
before reuse. Captured cells never enter the pool; scope exits still detach them.
Cells lacking the new capture metadata are conservatively not recycled. Pool
release follows normal/tail returns and protected-error unwinding; regression
fixtures cover upvalue aliasing, scoped locals, coroutine suspension and reload.
Object IDs remain stable; pooled internal cells are not guest-visible objects.
The collector omits reference-free encoded key history while tracing live keys
and values through actual table entries. Guest fields named known/order remain
ordinary rooted values. Profiling reduced allocator/collector churn without
modifying upstream editor logic or increasing quotas. Harness event loops are
not evidence of acceptable production tick/input latency.

The isolated scheduler uses deterministic machine IDs and a durable round-robin
cursor. Explicit simulation ticks cap guest execution at 256 instructions per
computer and 4,096 across the scheduler, with at most 512 admitted machines.
The plain-data `execution_budget` retains both aggregate and per-machine usage
across repeated same-tick dispatch and separate-process reload; only a later
tick renews credits. Older states begin tracking on their first synchronized
dispatch, without an on_load mutation. Untimed standalone fixture calls retain
their fresh per-dispatch budget. The original 64-loop untimed fixture still
checks equal service; an explicit-tick fixture verifies exhaustion, no refresh,
reload and next-tick service for previously unserved machines.

Incremental mark/sweep begins after 1,024 allocations and examines at most 256
collection work units per computer and 4,096 per explicit tick, retained in the
same execution budget. Aggregate exhaustion preserves the cursor before a
deferred collector; repeated same-tick calls cannot rotate away its turn or
refresh its credits. An 18-collector fixture checks these bounds through reload
and verifies later-tick progress. Untimed calls have fresh dispatch credits.
A machine stays
paused throughout marking/sweeping (no write barrier is assumed), while other
machines remain eligible. The collector explicitly traces integer register-cell,
upvalue and coroutine-resumer IDs as well as ordinary guest references. Collector
state itself is plain data; a partial collection survives separate-process reload
before the diagnostic program resumes. IDs are never reused.

The collector skips normalized proto fields of actual closure/frame records:
their scalar constants and descriptors cannot root a guest object. The compiler
enforces scalar constants. Code metadata remains directly owned plain data, not
reclaimed guest allocations. Guest table entries named proto are still traced.
This avoids repeatedly walking large immutable bytecode trees at every collection
and lets real package startup finish within the unchanged fixture deadline.

Current enforcement caps live objects at 16,384, a table's tracked key history at
8,192, call argument and unpack tuples at 1,024, strings at 65,536 bytes and source
at 32,768 bytes. The allocation stress fixture logs its measured dispatch,
allocated-object and live-object counts under `CC2 GUEST RESOURCE METRICS`, while
preserving closure captures, table aliases and a suspended coroutine. These
counts include initialization overhead and change when trusted helpers change.

These are measured instruction/collection counts, NOT a maximum tick-duration
claim. Compiler phase and shared credits now include raw generation and repeated
loads, but compilation still runs synchronously. Heap-byte accounting, remaining
host-operation coverage and production latency calibration remain unfinished.
Task 2.4 must remain unchecked until those requirements are resolved.

Native coroutine resume/yield and return delivery can switch the active
coroutine inside one guest instruction. Error recovery resolves the current
owner after that switch, rather than unwinding the original caller. Fixtures
cover native entry errors carrying guest references, protected resume, trailing
nils in native yields and service-quota refusal both before and after reload.
This fixes incorrect parent failure and stranded running children; it does not
establish full-heap recovery or compound tuple/unwind bounds. The finite remaining
milestone groups are recorded in BOUNDED_RUNTIME_CHECKLIST.md.

## Continuation tuple and frame admission (task 2.4 incomplete)

The 1,024-value tuple ceiling includes implicit __call receivers and protected/
coroutine status prefixes, not only explicit arguments. Register extraction,
frame/constructor arguments, native result delivery and prefix construction
validate arity before publication. A protected return checks prefix growth before
removing its boundary, so pcall/xpcall catches refusal instead of losing its own
handler. Coroutine return/yield checks prefix growth before marking the child
dead or suspended; refusal cannot strand a yielded child. When an otherwise
successful child result overflows a protected parent's prefix, failure belongs
to the parent and the child's successful result is preserved.

Closure frames and native pcall/xpcall boundary frames share the existing 256-
frame ceiling, now named `call_frames` in limits.lua. Native boundary admission
occurs before the push. These checks do not replace bounds on resumer-chain depth,
compound copying or recursive host propagation by themselves; the staged control
operations below additionally bound mutual recursion and resumer depth. Weighted
compound-copy/cleanup admission and full-heap error recovery remain unfinished.

Focused fixtures check exact maximum/nil tuple arity, caught overflows, xpcall
handlers, metatable receivers, yield/return ownership and maximum native protected
depth. A 100-boundary protected wait survives separate-process reload and returns
the expected boolean prefixes plus an event with interior/trailing nils. No
on_load execution or state normalization was added.

## Staged native propagation (task 2.4 incomplete)

Calls, delivery, finish and failure use an ephemeral control dispatcher with an
eight-operation nesting ceiling. Crossing that ceiling defers the next operation
as one plain `pending_operation` record: symbolic kind, guest-owner reference and
up to three data arguments. The collector roots this record, including otherwise
unreachable closures/upvalues, result tuples and reference-valued errors. It
contains no host function and requires no on_load execution.

VM.run drains pending propagation before accessing guest frames; native-only
chains can legitimately have no bytecode frame. Each deferred chunk consumes one
execution credit, as does delivering an event/refusal into a saved wait even when
it finishes without further bytecode. Zero credits deliver/drain nothing. Existing
durable per-computer/aggregate instruction counters therefore also cover these
execution steps; `vm.instructions` is a step counter, not exclusively bytecodes.
The eight-operation ceiling bounds mutual recursion within a phase, not every
loop or all error-recovery work in an execution step.

Active coroutine resumer chains admit at most 256 links. Refusal returns
`false, "guest coroutine nesting limit exceeded"` before activating the child.
Cached depth is cleared on yield/death; compatible older active chains lacking
depth metadata are reconstructed with a bounded scan at synchronized resume.

Fixtures save pending calls, returns and protected reference-valued errors during
incremental collection, then complete collection and propagation in a separate
engine process. They also cover maximum/rejected resumer chains, legacy missing
depth metadata, nil-containing saved-wait delivery and scheduler credit usage.
These are headless correctness/resource checks, not production latency evidence.
Tuple/metamethod copying and frame scans/cleanup still require weighted admission
or further staged bounds; secondary quota failures now use the recovery below.

## Secondary allocation-quota recovery (task 2.4 incomplete)

Delivering an error into a parent's result registers can itself exhaust the
guest-object quota. The previous unprotected fallback delivery could then escape
VM.run into Factorio. Both saved-wait and ordinary execution failure paths now
share recovery: catch the secondary failure, retain its current owner/error in
one existing plain pending-failure record, and unwind under a later execution
credit. This requires no additional quota-counted guest object, preserves error
values as data and does not relax the heap ceiling. Failed receivers are unwound
instead of leaving normal/running resumers stranded.

The full-heap fixture is explicitly synthetic setup in the actual engine: it
marks existing register cells conservatively captured, pads the environment with
valid rooted guest tables up to the real object ceiling, collects preexisting
garbage, and refills the remaining live space. It does not forge object_count.
Tests verify nested secondary delivery, refused xpcall-handler allocation, healthy
scheduler-neighbour service, unchanged disk content, separate-process reload both
before and during secondary recovery, and reclamation of failed frames while
live padding remains rooted. The initial expected-red escape is retained.

This establishes recovery for configured guest-object quota exhaustion, not
physical host-memory exhaustion or exhaustive allocation-site coverage. Retained
byte accounting, emergency-memory admission, weighted copying/cleanup and measured
production latency remain required before task 2.4 can be checked.

## Weighted exception unwind (task 2.4 incomplete)

Exception boundary search and register cleanup now share a provisional 256-unit
allowance per execution credit, including secondary recovery in that same step.
Boundary probes, frame removal and error publication cost one unit; each
register probe reserves four units for lookup and possible value clear, pool
append and register removal. A partial scan/release retains its error value,
boundary and cursors in a plain `failure_cleanup` pending record. Remaining
frames and the pending record stay collector roots. No guest instruction runs
until that control operation completes, and no cleanup allowance is renewed by
a zero-credit call. The ephemeral allowance is restored after `VM.run` exits;
the cumulative `vm.cleanup_work` counter and pending cursors are durable.

Cleanup never recycles captured cells or legacy cells with missing capture
metadata, and retains the existing pool/object ceilings. Error publication uses
the existing recovery path; any guest-selected handler/metamethod still leaves
recovery at the shared call boundary. Fixtures reproduce an 81-call unwind,
bound each one-credit delta, retain reference-valued errors through collection
and separate-process reload, and verify no load-time execution or zero-credit
progress. Existing heap-quota, coroutine and handler regressions remain active.

This slices exception cleanup only: normal return/tail-call frame release and
upvalue-close scans still require weighted admission. It does not account for
physical allocator bytes or establish measured production latency.

## Shared continuation-copy work (task 2.4 incomplete)

Ordinary tuple/register movement shares provisional credits of 262,144 units
per computer and 524,288 per explicit scheduler tick. Counters persist across
repeated dispatch and reload; untimed standalone calls retain fresh-quantum
semantics. The eleventh scheduler result reports admitted continuation work.

Quotes precede register extraction (`1 + count`), frame parameters/varargs
(`1 + 3 * parameters + varargs`), register/vararg delivery (`1 + 3 * count`),
status/receiver prefix construction (`2 + old count`) and native protected/
coroutine/file receiver argument shifts (`1 + copied count`). Both computer and
aggregate credits are checked before either counter changes. Protected return
prefix work is admitted before boundary removal, and its plain continuation
carries a one-use admission flag through deferral instead of charging twice.

Mandatory recovery bypasses ordinary copy credits so exhaustion can still report
a protected error. Its ephemeral scope is restored after errors, and a deferred
record carries a boolean recovery marker across collection/reload. Guest bytecode
resumes outside that scope. The shared call entry stages every guest-selected
call reached during recovery as ordinary pending work (`recovery = false`) under
a later execution credit. This includes native `xpcall` handlers (retaining their
error-handler boundary) and metamethods reached when a protected result resumes
a concatenation continuation. Handler
admission failure therefore returns `false, "error in error handling"` rather
than exempting receiver shifts or other guest-directed work. Recovery control
remains subject to size/depth and
execution credits. This is not yet weighted emergency-memory/cleanup admission.
Other native result-building loops retain their existing string/table/filesystem
admission; broader bridge coverage and frame cleanup remain open.

Focused fixtures verify protected per-computer/aggregate refusal with atomic
counters, retained prior vararg work, zero-credit recovery through collection and
reload, and explicit-tick reporting/renewal. These copy units are conservative
accounting, not measured CPU or allocator bytes.
An additional fixture transfers ownership into a guest child through native
`coroutine.resume` as an `xpcall` error handler: the child's bytecode still refuses
ordinary copying at zero credits, without consuming either exhausted counter.
A native file-flush handler fixture reproduces the formerly exempt receiver
shift and verifies refusal preserves the previous file; the ordinary pending
handler also survives collection and separate-process reload without gaining
new credits or executing during load.
Concatenation fixtures also combine a protected native `pcall` metamethod with a
later native file-flush metamethod, separately exhaust each copy counter, and
verify unchanged files/counters before and after collection/reload.

## Scalar byte work (task 2.4 incomplete)

Numeric-string conversion now shares native-string credits: `tonumber`, numeric
`select`, arithmetic/unary coercion, numeric-for setup, scalar math arguments and
string-helper numeric indices/char arguments reserve `1 + bytes` per string
before opaque conversion. Paired arithmetic and three numeric-for conversions
reserve together; unary conversion is performed once. Numeric-only operands do
not spend byte credits. Slice/byte indices reserve conversion separately from
the clipped result-copy estimate; already admitted conversion work stays charged
if later result work is refused.

Guest equality/rawequal reserves `1 + 2 * bytes` for equal-length string pairs;
different lengths require no byte scan. Lexicographic comparisons reserve
`1 + 2 * min(left_bytes, right_bytes)` before the host comparison. These are
conservative scan units, not measured CPU instructions. Focused regressions cover
zero/aggregate refusal, unchanged weighted counters, admitted numeric semantics,
string-index tuples and a maximum-sized whitespace-padded numeric argument.
Existing shared-counter reload tests and actual shell/editor workflows remain
part of the same engine run. Compound tuple/unwind and retained-memory bounds
are still separate unfinished groups.

## Shared guest event-service work (task 2.4 incomplete)

Guest queueEvent, startTimer, cancelTimer, clock, pullEvent/pullEventRaw and sleep
share provisional credits of 32,768 units per computer and 65,536 across the
scheduler. Explicit simulation ticks preserve counters across repeated dispatch
and separate-process reload; later ticks renew them. Standalone VM calls use
per-quantum credits unless the caller supplies persistent counters. The eighth
scheduler result reports admitted event-service work for that dispatch.

Queue admission reserves tuple validation/copy work before retaining its payload.
Polling reserves the bounded queue scan and compaction before consuming even
filtered events. Cancellation reserves scan/compaction before changing active
timers or undelivered timer tuples. Both queue operations compact once in linear
time instead of repeatedly shifting a queue. Survivor order, nil arity, guest
reference identity, bytes and termination/filter behavior remain unchanged.
Sleep reserves creation plus its initial poll together, so budget refusal cannot
leave a newly allocated timer behind. Resuming a saved wait routes a refused
poll through the ordinary guest protected-call/error machinery.

Filtered polling uses a bounded queue-metadata preflight and reserves
`1 + 4 * queued_records`, plus `1 + 2 * name_bytes` for each name whose length
matches the filter. The latter covers opaque equality scans and is included even
for records after an earlier potential match. Different-length names need no
byte scan; raw unfiltered polling does not charge arbitrary paste payload bytes.
Sleep includes the same byte estimate in its compound reservation before timer
creation. Tests verify per-machine/aggregate refusal without queue mutation,
exact matching-name charges and no orphan timer after byte-work refusal.

The recoverable errors are `per-computer event work limit exceeded` and
`aggregate event work limit exceeded`. Each reservation updates both counters or
neither. Tests cover zero-credit atomicity, partial sleep reservation, refusal
inside a resumed protected wait, full filtered discard, timer survivor order,
repeated cancellation, same-tick reload and bounded later-tick recovery.

Host lifecycle/input admission deliberately does not use guest credits: priority
resize remains admissible when guest work is exhausted. Geometry reconciliation
and ingress retain their existing per-call size bounds but do not yet use shared
credits. Host timer advancement uses the separate maintenance credits below.
These event-service caps do not establish full host-work or latency acceptance.

## Shared host timer advancement (task 2.4 incomplete)

Explicit scheduler ticks meter timer maintenance separately from guest services:
131,072 provisional units per computer and 262,144 across the scheduler. Scan and
temporary due-record construction reserve `1 + 2 * timer_count` units; each
native-sort comparison consumes one unit before comparing. Delivery reserves
12 units per due timer before admitting tuples or removing active timers.
Sorting and partially admitted scans affect temporary data only. Failed work
retains consumed credits but leaves pending timer IDs/deadlines and queued tuples
unchanged. Simulation time still advances, so clock does not stall when due-timer
processing must defer.

The scheduler catches only its private, ephemeral quota-refusal identity; other
host failures still propagate. A selected VM keeps its instruction/collection
quantum on deferral, allowing admitted input to run. Aggregate refusal ends that
dispatch with the cursor already advanced, rather than repeatedly servicing the
same prefix. Deferred timers retry under renewed credits on a later tick. Explicit
same-tick dispatch and separate-process reload preserve the plain counters;
untimed scheduler calls do not advance timers. Standalone VM.advance calls use
the existing bounded-per-call behavior unless a spend callback is supplied.

The ninth scheduler result reports maintenance work. Per-computer and aggregate
deferral counts are plain diagnostic counters, not saved error objects or host
closures. Engine probes exercise refusal before scan, during sorting and after
sort/before delivery; repeated maximum timer sets under full event queues;
same-tick/reload preservation; input service despite aggregate deferral; and
later-tick delivery in original deadline/ID order. Metrics are logged as
`CC2 GUEST TIMER ADVANCE METRICS`. These work units are not host instruction or
wall-time measurements; heap-byte accounting, remaining host coverage and
production latency calibration remain open before task 2.4 can be completed.

## Shared table primitive work (task 2.4 incomplete)

Guest table operations now share provisional work credits: 1,048,576 per
computer and 2,097,152 per explicit scheduler tick, persisted across same-tick
dispatch and reload. The tenth scheduler result reports table work. Encoded
string keys reserve `1 + 2 * (bytes + 2)` before prefix copying/hash lookup;
numeric/reference keys reserve 65 units before formatting/copying, and boolean
keys reserve one. Native iteration charges visited history records. Refusals
raise ordinary `per-computer table work limit exceeded` or
`aggregate table work limit exceeded` errors before primitive mutation; admitted
work remains charged. Trusted VM construction is outside runtime credits.

Iteration membership stores stable history positions rather than repeatedly
re-encoding/scanning the preceding key. Compatible older membership booleans are
upgraded only during synchronized execution, with all metadata writes reserved
first. Deleted/reinserted keys retain their original positions. Native length
retains the existing first-hole sequence semantics using a private cached prefix;
insert/delete updates it and extension probes are admitted before publication.
Older graphs lazily reconstruct the prefix, never during on_load. This removes
quadratic repeated prefix scans without increasing limits. Tests exercise long
keys, protected quota failures, atomic extension/legacy upgrades, sparse prefix
updates, and separate-process compatibility. This is host-work accounting, not
heap-byte accounting or calibrated production latency; task 2.4 remains open.

## Verification

    python3 tools/verify_guest_resources.py
    python3 tests/run_engine.py --guest
    python3 tests/run_engine.py --guest --expansion

The guest scenario performs actual guest execution, not host evaluation of the
fixture source. It covers arithmetic/control flow, closure aliasing and loop
captures, metatables, right-associated concatenation, recursive tail calls,
nil tuples, nested/protected coroutine suspension and sandbox escape attempts.
The harness independently requires first-run and separate-process reload markers
and rejects reboot/reload acceptance in the wrong process. Logs/results/saves
are outside the repository in the printed scratch directory.

Each phase also writes `<phase>.process.json` and includes process evidence in
the final result: marker presence, whether completion requested shutdown, signals
sent, console quit request, shutdown acknowledgement, forced-kill status and exit
code. Completed server phases request `/quit` through the process console, after
the snapshot ZIP is readable in the first phase. Unacknowledged requests fall
back to SIGINT after one second, with at most two interrupt attempts. An
acknowledged shutdown receives no further interrupt; the original 15-second
cleanup deadline still applies. The console pipe is closed after process exit.
Nonzero exit, missing markers or forced kill remain failed gates, regardless of
workflow completion. Earlier failed runs remain failed evidence, not successes
retroactively repaired by retries. This is bounded shutdown hardening; the exact
cause of earlier unacknowledged Factorio interrupts is not established.

`python3 -m unittest discover -s tests -p test_engine_shutdown.py` exercises seven
real subprocess shutdown cases: clean acknowledgement, ignored first interrupt,
acknowledged-but-stuck shutdown, ignored interrupts, already-exited children,
console quit and unacknowledged console fallback. A separate real-engine probe
verified `/quit` produces `Quitting: remote-quit.` and clean exit in pinned 2.0.77.
These are harness tests, not Factorio gameplay or graphical acceptance.

Actual guest shell/editor and suspended dirty-editor reload workflows are covered
by the isolated scenario. Whole-compiler/aggregate hostile-workload bounds,
production latency, graphical input/rendering and joining clients remain open
gates; the workbench must not be removed.
