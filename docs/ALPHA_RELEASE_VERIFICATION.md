# Experimental 0.2.0 playtest evidence

This is a user-authorized experimental terminal cutover, not full specification
acceptance. Client UI testing is assigned to the user. No graphical/multiplayer
pass or measured production latency/resource-envelope claim is made.

## Packaged verification

- Archive: `computer_core_2_0.2.0.zip`, 140 files.
- SHA-256: `6ac77dd64c9f859f2bbdea9fb3b76b1500b1621305f67d91ec7c220279c46e92`.
- Pinned Factorio 2.0.77, actual ZIP (not a source symlink), base and expansion.
- Each variant: 357 initial checks, 489 cumulative after separate-process reload.
- All six bootstrap/first/reload processes exited zero, completion markers present,
  no shutdown signal attempts or forced kills.
- Shutdown controller: seven tests passed.
- Resource verifier: 78 resources, 12 compiler modules, 64 guest files, 16 patches.
- Three new paste patches reproduce exact installed bytes with zero fuzz from
  HEAD originals whose hashes match pinned source hashes; generated ROM is current.

The guest workflow exercises actual vendored BIOS, shell, both editors, source
execution, dirty-buffer reload, quotas, events/handles and settings geometry.
New selected live-module fixtures exercise migration archives/draft/ROM recovery,
real entity snapshot/clone consumers after disk-table replacement, and dispatch
alias synchronization. These are not full previous-version upgrade acceptance or
native client rendering/input tests. Remote disk readback is source-reviewed,
not independently asserted through the remote interface.

## Review trail

`deleg_bfeff167` requested changes for stale disk snapshots/clones and lost/corrupt
paste input. Those findings were fixed, not waived. `deleg_bd649de0` approved both
focused re-reviews using source, archive bytes and recorded engine evidence;
reviewers did not rerun the engine. The initial findings remain part of the trail.

Machine-readable local evidence is `verification.json` beside the candidate ZIP;
base/expansion output directories contain individual logs/process records.
See PLAYTEST.md and KNOWN_LIMITATIONS.md for client checks and known alpha issues.
Remaining OpenSpec gates stay unchecked; the original complete gate applies to a
validated release rather than this explicitly authorized alpha.

## 0.2.1 responsiveness hotfix

- Archive: `computer_core_2_0.2.1.zip`, 141 files.
- SHA-256: `ea3650f2681667d1b8852b0502ef14eda837cb4800ec9bf02bb2bf0164e96335`.
- Exact packaged Factorio 2.0.77 base and expansion checks: 358 initial and
  490 cumulative checks per variant; all six phases clean, no signals or kills.
- Shutdown controller: seven tests passed. Resource verifier: the same 78 resources,
  12 compiler modules and 64 guest files, now 17 reproducible patches.
- Real nested-window regression asserts one row blit per write/clearLine, retained
  cursor/color/blink, hidden-write buffering/reveal and one propagated palette
  entry per palette mutation. The new window patch reproduces installed bytes
  exactly from the pinned original, with zero fuzz.
- The same basic-editor single-character fixture went from 1233 scheduler ticks /
  315648 instructions in the packaged 0.2.0 baseline to 40 ticks / 40960 instructions:
  30.825 times fewer dispatch ticks. This is a simulated scheduler fixture, not
  a graphical latency measurement. A geometry-scaled work regression guards it.
- Instruction/collection quanta are 1024 per computer; aggregate caps stay 4096.
  Shared-credit, same-tick/reload refusal and 64-busy-computer fairness checks pass.
  Queue flood tests now explicitly recover native event-work quota refusals rather
  than assuming instruction preemption always occurs first.
- The fallback key button row is removed. Unchanged GUI sweeps are skipped only
  after a complete revision/blink-consistent sweep; replacement guest displays
  invalidate the old sweep marker. These presentation changes are source-reviewed,
  not native GUI/client acceptance.
- Save files and reboot each computer after updating: existing suspended guests
  retain previously compiled OS modules until reboot. No automatic reboot discards
  unsaved buffers on upgrade.

Pre-fix 0.2.0 and row-only source evidence remain retained. Initial hotfix runs
failed outdated hard-coded scheduling assumptions, then the intentionally dense
queue-flood fixture encountered the unchanged native-event work quota. Both
failures remain failures in their original logs; corrected packaged reruns pass.
Compiler/resource and actual multiplayer/client responsiveness remain provisional.

## 0.2.2 terminal typing hotfix

- Archive: `computer_core_2_0.2.2.zip`, 143 files.
- SHA-256: `dce5d77a07513b4ba6c61f3a02f0f3e1272a36af394971d2f849e7e882dfb531`.
- Exact packaged Factorio 2.0.77 base and expansion: 377 initial and 509 cumulative
  checks each; all six phases exited zero with markers, no signals or forced kills.
- Shutdown controller: seven tests passed. Resources: 78 files, 12 compiler modules,
  64 guest files and 19 pinned-source patches.
- Basic-editor single-character fixture: 12 scheduler ticks / 16384 instructions,
  including eight collection ticks, versus 40 / 40960 in packaged 0.2.1. The new
  advanced-editor text-echo fixture takes four ticks / 16384 instructions before
  deferred syntax work. These are scheduler measurements, not client latency.
- Both editors cache unchanged rows/status. Advanced syntax refresh is deferred
  after a short typing pause; foreground highlighting is separately checked.
- Direct Recrafted timers now register thread ownership. Filter precedence cannot
  bypass ownership; consumed/cancelled routing entries are removed. Actual shell
  timer polling and deferred editor highlighting coexist through save/reload.
- Native text capture is visually hidden and terminal clicks restore focus.
  Table-backed GUI checks cover click focus, character/paste routing, native
  Backspace fallback/deduplication, bounded dirty-row refresh, foreground palette
  updates and same-size display replacement. These are not native client tests.
- Presentation runs every tick, prioritizes the cursor row and skips unchanged
  rows. Per-computer instruction/collection quanta are 4096/2048; both aggregate
  tick caps remain 4096. Shared-credit/reload/fairness regressions pass.
- Save files and reboot each computer once after updating; compiled guest ROM
  remains old until reboot. Unsaved buffers are not automatically discarded.

Earlier source failures remain in scratch logs, including timer integration
timeouts/forced cleanup and assumptions that every busy computer could consume
its full quantum beside a neighbour. Corrected archive reruns pass; failed runs
are not reclassified as passes. Graphical, clipboard/IME, multiplayer, hostile
workload responsiveness and full specification acceptance remain provisional.
