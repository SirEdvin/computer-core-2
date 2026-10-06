# Bounded-runtime milestone checklist

This checklist consolidates task 2.4 rather than treating each helper as a new
milestone. OpenSpec acceptance remains authoritative. The existing workbench
stays active; neither this checklist nor headless success authorizes cutover.

## Implemented; retain regression coverage

- Compiler phase/recursion and shared runtime compile credits.
- Native strings, terminal methods, local filesystem/handles, guest events and
  host timer advancement: pre-admitted work with explicit-tick saved counters.
- Table-key encoding and native table scans: shared credits, indexed iteration,
  atomic legacy index reconstruction and cached first-hole sequence lengths.
- Explicit-tick instruction/collection credits: saved per-machine and aggregate
  counters, no same-tick refresh, cursor-preserving collection deferral and
  later-tick progress through separate-process reload. Untimed fixture dispatch
  remains a separate fresh-budget mode.
- Separate-process shell/editor/dirty-buffer, event/timer and handle reload.
- Numeric-string conversion/arithmetic, math/string-index coercion and string
  comparison byte work: admitted through existing shared string credits.
- Filtered event-name byte work: included in queue poll reservation, including
  compound sleep admission before retaining a timer. Refusals preserve queues
  and both weighted counters.
- Native coroutine failure ownership: use the active coroutine after resume,
  yield or return delivery switches execution; verify protected and unprotected
  native entries, reference-valued errors and nil-containing native yields.
- Continuation tuple limits after status/receiver prefixes, before protected
  boundary removal and before coroutine state transitions; native pcall/xpcall
  frames share the existing 256-frame ceiling. Compound-work/unwind admission
  and full-heap recovery remain unfinished, not covered by these size checks.
- Staged native call/delivery/finish/failure propagation: eight nested control
  operations per phase, plain pending records rooted through collection/reload,
  deferred chunks and saved-wait delivery charged to durable execution credits.
  Resumer chains admit at most 256 links, including legacy missing-depth graphs.
- Secondary guest-object-quota recovery: a failed parent error delivery queues
  the active owner's failure rather than making an unprotected fallback call.
  Full live-heap fixtures cover nested receivers, refused xpcall handlers,
  scheduler neighbours, disk preservation and reload before/during recovery.
- Shared ordinary continuation-copy admission: register/vararg extraction and
  delivery, frame setup, prefixes and native argument shifts. Protected prefix
  admission precedes boundary removal; mandatory recovery carries plain mode
  metadata and remains executable with exhausted ordinary credits.

## Required remaining implementation groups

1. Retained execution-memory admission and reclamation.
   Object count and individual table/string/content bounds do not account for
   the combined retained graph. Cover table records/key history, register/cell
   values, frames/tuples and normalized prototypes. Choose documented logical
   accounting rather than claim exact host allocator bytes. Include compatible
   old-graph reconstruction, collector release, recoverable refusal, and real OS
   measurements before finalizing the provisional quota.

2. Compound operation and error-recovery bounds.
   Tuple/prefix and native protected-frame size checks are implemented; bound
   remaining native copy bridges, weighted frame scans/cleanup and emergency
   recovery admission,
   not only bytecode instruction count. Recursive propagation/resumer depth now
   has staged/size bounds, but these do not measure total work inside each phase.
   Secondary guest-object-quota recovery is implemented for tested nested
   delivery/handler paths; retain broader allocation-site and emergency-memory
   coverage as part of retained-memory admission, without claiming physical
   host-memory failure recovery.

3. Remaining host-boundary coverage and measured envelope.
   Audit geometry reconciliation, ingress and remaining scalar/tuple helpers
   against existing size bounds and aggregate scheduling. Numeric conversion,
   string comparison and filtered event-name byte gaps identified by the audit
   are now metered, but remaining tuple/scalar bridges still need coverage review.
   Benchmark hostile
   workloads and actual shell/editor service using production-shaped dispatch,
   not many quanta pumped inside one engine event. Record observed tick/input
   latency and memory/work metrics separately from configured unit ceilings.

## Verification and review policy

- During implementation: focused regressions and one relevant engine scenario;
  retain separate-process reload for persistent state and a resize case when the
  changed behavior depends on geometry. No full matrix after every helper.
- Before the consolidated checkpoint: independent spec/quality review, fix
  important findings, then one packaged base/expansion/resize/workbench matrix.
- Checkpoint reviewed implementation with its explicit incomplete gates. Do not
  include local agent configuration, transient evidence or unrelated untracked
  files, and do not mark task 2.4 complete until every required group is verified.

## External acceptance gates

Actual graphical Factorio input/rendering and two-client/join acceptance remain
unverified. The delegated client-discovery command was denied; no alternative
system-discovery route was used to bypass that decision. The previous known
installation is headless. A licensed graphical client and an approved display/
input path are needed for tasks 1.3, 4.3, 4.4 and the final acceptance verdict.
Runtime implementation can continue independently; client gates cannot be
replaced with mocks or inferred from engine checks.
Client access alone is insufficient: the diagnostic terminal view/input bridge
must first be implemented alongside the workbench. The old CLIENT_CHECKLIST.md
is not the new terminal's acceptance checklist; use this change's design/tasks.

## Audit provenance

The runtime coverage audit completed and its concrete dispatch-counter finding
was checked against scheduler.lua and fixed with focused reload regressions.
Its additional conversion/comparison findings were implemented with focused
zero/weighted-refusal and successful-result regressions, without raising limits.
The persistence audit did not complete a
final verdict; its preserved engine probes identified native coroutine failure
ownership, but are not review approval. Its collector-root probe also failed
because require was called during on_init, so that probe establishes no collector
result. Existing collector regression evidence remains separate.

## Scoped review checkpoint

Independent spec and code-quality reviews passed the completed table-work,
explicit-tick execution/collection-credit, native coroutine-error ownership,
scalar conversion/comparison and filtered-event byte-admission batches. These
were source reviews; reviewers did not independently rerun the engine.

Parent verification after review-suggested boundary regressions passed 284
initial checks and 368 cumulative checks after separate-process reload, with
clean bootstrap/first/reload exits. Added regressions cover independently
exhausted per-machine collection credits, retained conversion charges after
result refusal, aggregate arithmetic/for refusal, equal-length filter nonmatches
and later records, and raw/nonraw termination at byte-admission boundaries.
The subsequent tuple-admission batch adds targeted return-delivery overflow into
the protected parent, preserving the child's successful result. It also tests
yield refusal before suspension and protected-chain save/reload. Independent
scoped specification and code-quality reviews passed this tuple batch and the
subsequent staged-propagation batch, with no important findings. Both reviews
were static only, with no independent engine rerun, and do not approve full task 2.4.
Optional additional regressions are exact-maximum successful coroutine yield
with trailing nils and a native-only xpcall frame-ceiling case; no important
conformance gap was found.
The staged-propagation batch's final focused run passed 305 initial checks and 397 cumulative checks after
separate-process reload, with all three phases clean, no signals and no forced
cleanup. Seven shutdown tests, resource verification and diff checks passed.
Expected-red evidence for missing call staging is retained separately. Neither
newer batch completes task 2.4 or substitutes for the final packaged matrix.
The tuple-admission expected-red prefix regression failed before the fix. Its
focused engine verification passed 296 initial checks and 382 cumulative checks after
separate-process reload, with all three engine phases clean and no signals or
forced cleanup. Seven shutdown-controller tests, vendored-resource verification
and git diff --check also passed. The native boundary tests cover both the exact
256-frame maximum and refusal at the next push; resource limits were not raised.

The newer secondary heap-quota recovery fix passed 311 initial checks and 412
cumulative checks after separate-process reload, with three clean phases, seven
shutdown tests and resource/diff verification. Its expected-red nested receiver
escape is retained. Independent scoped specification and code-quality reviews
passed with no important findings. Both were source-only, without an independent
engine rerun. An optional follow-up is collection while the newly staged
secondary-failure record is pending, supplementing generic pending-root coverage.
This fix does not close retained-memory,
emergency-memory admission or weighted-copy/cleanup bounds.

The newer continuation-copy ledger passed 319 initial checks and 424 cumulative
checks after separate-process reload, with three clean phases, seven shutdown
tests and resource/diff verification. The first ledger fixture incorrectly used
an arithmetic-only loop with no copies; that failure was retained and the fixture
was corrected to exercise table-result delivery. This batch still awaits scoped
review and does not complete task 2.4.

A follow-up native-handler regression passed 321 initial / 426 cumulative reload
checks with three clean phases. It verifies that `xpcall` using native
`coroutine.resume` as its handler cannot pass recovery mode into the child's
guest bytecode, and that its copy-credit refusal preserves exhausted counters.
The initial fixture confused the boolean `failed` marker with the `error` value;
that failed run remains retained. No runtime change was needed for this check.

Scoped specification review requested changes: mandatory recovery also exempted
guest-selected native `xpcall` handlers from ordinary copy admission. A native
file-flush receiver fixture reproduced that bypass. Handler invocation now
stages an ordinary pending call under a later execution credit, retaining its
error-handler boundary. Refusal preserves saved file content; collection/reload
preserves the ordinary mode and exhausted counters. Latest focused evidence is
324 initial / 431 cumulative reload checks with three clean phases; shutdown
unit tests and vendor verification passed on the preceding 323/428 run. The
failed reproducer remains retained. Scoped specification re-review is required;
no full task 2.4 or milestone approval is claimed.

Independent per-computer and aggregate native-handler refusal now use separate
exhausted counters, including collection/pending/reload for each. The expanded
fixture passed 327 initial / 436 cumulative reload checks with three clean
phases and diff verification. The full first review confirmed its sole finding
was the native-handler exemption; re-review verdict remains unconsumed.

Re-review requested changes for recovery-delivered concatenation resuming a
guest-selected native metamethod under the same exemption. A protected `pcall`
concatenation followed by a native file-flush metamethod reproduced it. The
exemption exit now lives in the shared call entry, covering both explicit error
handlers and continuation-driven calls, not an error-handler-specific patch.
Separate counter/collection/reload fixtures passed 333 initial / 446 cumulative
reload checks with three clean phases, seven shutdown tests and vendor/diff
verification. Both failed bypass reproducers remain retained; the initial
aggregate concat fixture also failed because its non-exhausted counterpart did
not cover the two-argument shift, and was corrected without changing limits.
The centralized-call-boundary specification re-review passed and code-quality
review approved, both with no important findings. Both were source-only, without
an independent engine rerun. These approvals cover ordinary continuation-copy
admission and the recovery-to-ordinary call boundary, not the remaining task 2.4
groups or client acceptance.

These earlier review records preceded the consolidated packaged baseline below.
They do not approve full task 2.4. The three implementation groups and all client
gates above remain open. The workbench stays active.

## Reviewed weighted exception-unwind batch

Boundary search and frame/register release now share a 256-unit allowance per
execution credit, even across secondary recovery in that step. Unfinished work
retains plain failure-cleanup cursors and error/boundary references in the
existing collector-rooted pending operation. The register pool, captured-cell
rules, object ceilings and ordinary guest-call recovery exit are unchanged.

Focused verification passed 338 initial / 457 cumulative separate-process reload
checks with three clean phases, seven shutdown tests and vendor/diff checks.
Fixtures cover deep protected unwind, zero-credit deferral, collection/reload
mid-cleanup and reference-valued errors. The pre-fix bulk-release reproducer is
retained. Scoped specification and code-quality reviews passed without blocking
findings. Both were source-only, without an independent engine rerun. The quality
review also approved the EOF-reap harness fix. Optional follow-up tests directly
covering EOF while a child remains alive and EOF timeout are not yet implemented.
Normal return/tail-call cleanup,
upvalue-close scans, retained/emergency memory and measured latency remain open.

## Consolidated packaged headless baseline

The current source built a 132-file deterministic archive and passed all six
packaged configurations: base/expansion guest, base grow reload, expansion shrink
reload, and base/expansion existing-workbench regressions. Guest checks were
338 initial / 457 cumulative reload, or 459 with changed geometry; existing
workbench checks were 154 / 155. Final selected evidence has 18 clean process
phases, no signals or forced kills, and all completion markers.

The initial matrix recorded one unacknowledged signal in each of two successful
bootstrap exits. The harness previously sent shutdown immediately on stdout EOF,
which can precede process exit; it now waits for natural exit within the original
deadline before invoking shutdown. Only those two cases were rerun, and original
evidence is retained alongside clean retries. Seven shutdown tests still pass.

Archive SHA-256: `64ae6206826bf34c80d6bc11b1b813237e3133acd28a6b75aca60184f705043a`.
The archive and combined initial/retry/final JSON evidence are stored outside the
repo in the `cc2-runtime-checkpoint-package` scratch directory. This establishes
a packaged headless baseline, not measured tick/input latency, full task 2.4,
client/multiplayer acceptance, cutover or release publication.

## Scoped source checkpoint

The reviewed source checkpoint includes the isolated guest runtime, pinned
resources/patches, upstream OS integration, engine/reload fixtures, packaging and
these implementation/specification records. It excludes local Hermes setup,
unrelated OpenSpec root configuration and generated verification evidence.
Vendor/patch and generated ROM whitespace is retained byte-for-byte; authored
code passes the staged whitespace check, and the resource verifier validates
the preserved upstream and installed hashes. Task 2.4 remains unchecked.
