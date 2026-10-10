# Upstream editor feasibility: recovered engine workflow

Tasks 4.1/4.2 now have passing headless engine evidence. The existing workbench
remains active. This does not authorize terminal cutover: graphical input/rendering,
multiplayer joining and production host-operation/latency gates remain open.

## Reproduction

    python3 tests/run_engine.py --guest
    python3 tests/run_engine.py --guest --expansion --columns 80 --rows 24

`tests/guest-mod/editor_checks.lua` drives actual ROM programs through the
BIOS/scheduler/shell using injected guest events. It does not replace editor logic
or claim graphical Factorio input acceptance. It uses pinned LWJGL3 Enter/leftCtrl
IDs, individual character events, ordinary editor menus, and unchanged normal
scheduler instruction/collection quanta and the 60-second process deadline.

## Initial failed gate (retained evidence)

In Factorio 2.0.77 base at 51x19, the real basic editor started and saved `b\n`.
The advanced editor started, but typing `print(7)` rendered only `prin` before
exhausting 40,000 dispatches and crossing the process deadline. The failure sample
reported 3,232,172 cumulative instructions, 5,779 live objects, four queued events
and collection phase `mark`. That single mark-phase sample did not identify a
root cause. Initial log:

    /home/siredvin/.hermes/profiles/albina/cache/scratch/cc2-tests-6mwkp8o8/bootstrap.log

The initial editor diagnostic ceiling was raised from 20,000 to 40,000 before this
review; that did not make the workflow pass. Resource quanta and the engine process
deadline were not raised. Implementation paused for user review; the user approved
profiling and optimization within the existing architecture and bounds.

## Measured bottleneck and correction

A harness-only profile separates collection work from noncollecting dispatches
and samples the top frame source before each dispatch. Source samples are not
exact instruction attribution or CPU timings. Baseline advanced typing consumed
37,137 collecting dispatches out of 40,000, performing 9,487,183 collection work
units and allocating 144,711 objects without completing the input. Window rendering
dominated sampled execution; register cells were allocated anew for ordinary calls.
Baseline profile log:

    /home/siredvin/.hermes/profiles/albina/cache/scratch/cc2-tests-_nkqqtnw/bootstrap.log

The VM now retains a deterministic pool of at most 256 uncaptured internal
register cells. They remain counted against the same 16,384-object heap quota,
keep their existing IDs, and have their values cleared before reuse. Capturing a
register marks it ineligible. Captured upvalues are never recycled; scope exits
still detach captured cells. Ordinary returns, tail calls and protected-error
unwinding release eligible cells. Cells without capture metadata in older graphs
are conservatively ineligible. The pool is plain data, rooted by the collector,
and persists through normal save/reload. No guest-visible object ID is recycled.

Collection also skips encoded scalar key-history metadata on actual guest table
records. Live table/function keys and values remain rooted through entries; guest
fields named kind/known/order do not bypass tracing. No ROM editor changes, quota
increases or alternate execution strategy were required.

## Verified workflow and packaged results

The rebuilt computer_core_2_0.1.2.zip passes Factorio 2.0.77 in these configurations:

- Guest base, 51x19: 80 initial checks and 111 cumulative checks after a genuine
  separate-process reload.
- Guest expansion, 80x24: 80 initial checks and 111 cumulative checks after reload.
- Existing workbench base and expansion: 154 initial / 155 cumulative reload checks.

Both guest configurations execute the real BIOS/shell/completion/settings probe,
start the basic editor and save `b\n`, launch the advanced editor via `edit`, type
`print(7)`, verify builtin/number foreground cells, and save the game with the
editor suspended and `/edited.lua` still absent. After another engine process
loads that save, the editor saves exact bytes `print(7)\n`, exits, reopens the file,
and the shell executes it, displays `7`, and returns after the command coroutine.
No first-process reload is accepted by the harness.

Packaged base advanced typing now completes in 7,083 dispatches with 5,333 new
objects and 1,251 collecting dispatches / 319,714 collection work units. Expansion
80x24 completes in 7,307 dispatches with 5,413 new objects and 1,201 collecting
dispatches / 306,762 work units. These complete-input results differ in workload
from the baseline's partially completed input; do not present them as an equal-work
speedup ratio.

Regression coverage includes shared/scoped/returned closures, protected-error
captures, tail-call nil tuples, coroutine captures, table keys, guest fields named
known/order, pool identity/value cleanup, collection quotas and existing hostile
loop/pattern/sort fairness. Vendor hashes and all 12 patches reproduce exactly.

These probes manually dispatch many scheduler quanta inside harness events. Their
passing process deadline does not establish an acceptable live tick budget or
interactive latency. Task 2.4 calibration and real-client gates must still pass
before section 5; editor success is not the complete feasibility verdict.
