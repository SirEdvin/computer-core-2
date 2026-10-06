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
