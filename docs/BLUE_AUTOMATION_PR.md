# Historical pre-publication handoff: native editor and restricted blue automation

Current 0.4.1 follow-up: the approved native key/input audit and restricted `lua`
REPL pass the exact archived base/expansion matrix, including published 0.3.0 and
0.4.0 save upgrades. See `RELEASE_0.4.1.md` for checksum, 12 cases / 40 clean
processes, 44 Python tests and retained failed fixture evidence. Tasks 1.3 and
2.6–2.8 are verified under their approved native-control requirements; publication
task 2.9 awaits readback. Tasks 5.2/5.3 remain client/real-peer blockers. Everything
below is the historical handoff, not the current publication/PR state.

Historical status at the pre-publication checkpoint: local PR handoff only. No commit, push, GitHub PR, release, merge or
OpenSpec archive has been performed for this implementation checkpoint.

Suggested title: Add native editor and restricted blue automation (client gates pending)

Head: `feat/blue-restricted-lua-automation`
Suggested stacked base: `feat/add-blue-native-lua-computer`
Predecessor: https://github.com/SirEdvin/computer-core-2/pull/4
OpenSpec change: `add-blue-restricted-lua-automation`

## Summary

- Native multiline `edit PATH`, recoverable drafts, dirty lifecycle disposition
  and admitted atomic conflict-safe saves.
- Committed local Lua execution via default-deny AST validation and trusted native
  emission, never player-text loading, a VM, an interpreter or continuation fallback.
- One background scalar controller with bounded state/print/circuit transactions,
  explicit run/stop, exact active source snapshots and cold revalidation.
- Owned left/right circuit ports and an example actually copied, threshold-edited,
  saved and run against a real chest/inserter network.
- Original/personal VM compatibility, unchanged shared quotas and deterministic
  source-only packaging retained. Ephemeral caches no longer pin replaced one-shot
  controllers; output FIFO validation rejects sparse saved inventories.

## Exact candidate evidence

Factorio 2.0.77 headless, base and expansion, 2026-10-10.
Two independent builds were byte-identical, 184 archive entries:

    SHA-256 f25ca6a03b60f911690832ba4229c6743113b6945fd9d7b0cc548bf6b38b0b7f

Archive:
`/home/siredvin/.hermes/profiles/albina/cache/scratch/blue-automation-package-verified-a/computer_core_2_0.3.0.zip`

Matrix evidence:
`/home/siredvin/.hermes/profiles/albina/cache/scratch/blue-automation-final-matrix/matrix.json`

All ten matrix cases passed, all 32 processes exited zero without forced kills.
Counts are cumulative after reload, not additional reload-only assertions.

| Suite | Initial | Cumulative reload | Third cold process |
| --- | ---: | ---: | ---: |
| Native programs, each configuration | 156 | 194 | — |
| Shell/configuration change, each configuration | 245 | 309 | — |
| Original VM/GUI, each configuration | 421 | 553 | — |
| Shell stress, each configuration | 11 | 50 | — |
| Released blue-save upgrade, each configuration | 1 | 6 | 10 |

Subsequent base/expansion GUI fixture runs against this same unchanged archive
also verify an actually suspended personal VM graph beside editor save/lifecycle
operations; their result.json files are under `blue-suspended-personal-gui-base`
and `blue-suspended-personal-gui-expansion` in the same scratch directory.

The upgrade first creates its save with the actual released shell-only ZIP,
SHA-256 `0fc551cdf4c4e563cbfcc45a05b842fe00e34eefc77dd8734505610bd36130d9`,
then switches to this candidate and cold-reloads a second snapshot containing a
pending save, dirty editor, exact controller source/state, queued print/input and
exhausted credits. A fixture version bump forces configuration reconciliation;
production release metadata is unchanged and no new release is implied.

41 Python tests, resource/provenance verification and strict OpenSpec validation
passed. Original VM ROM/vendor bytes are unchanged.

Responsiveness: 100 individual editor and 100 shell samples per configuration,
p95 terminal-model echo one tick; boot one synchronized dispatch. The accepted
maximum-work source is 16 KiB with 128 validated nodes and 23 statements. A real
original VM input neighbor also passes 100 samples within the two-tick target on
the factory's shared ledger. These are not rendered keyboard/client measurements.

Malformed recovery tests use synthetic admission clocks and actual cold saves.
Cap-wide cleanup uses 512 real port pairs with synthetic admission clocks.
Neither establishes many-computer real-time CPU or graphical latency bounds.

## Blocking acceptance / do not merge as fully accepted

- Task 5.2: licensed graphical editing/saving/running, visible ports/factory wiring,
  native focus/clipboard/shortcuts/resize and rendered latency. Only the installed
  headless engine and GUI mocks have been exercised.
- Task 5.3: a real joining multiplayer peer during dirty editing and pending,
  credit-exhausted controller/save work. Separate-process reload is not a peer join.

Preserve both unchecked tasks, predecessor unfinished client gates and historical
failed continuation performance evidence. No complete acceptance is claimed.
Keep the candidate restricted; it is not arbitrary Lua or CC:Tweaked compatibility.

## Reproduction

Use fresh output directories; keep failures rather than overwriting them.

    python -m unittest discover -s tests
    python tools/verify_guest_resources.py
    python tools/package.py --output /absolute/fresh/package-directory
    python tests/run_engine.py --programs --archive CANDIDATE.zip --output FRESH_DIRECTORY
    python tests/run_engine.py --shell --shell-config-change --archive CANDIDATE.zip --output FRESH_DIRECTORY
    python tests/run_engine.py --guest --archive CANDIDATE.zip --output FRESH_DIRECTORY
    python tests/run_engine.py --shell-stress --archive CANDIDATE.zip --output FRESH_DIRECTORY
    python tests/run_engine.py --blue-upgrade --baseline-archive RELEASED.zip --archive CANDIDATE.zip --output FRESH_DIRECTORY

Repeat each engine scenario with `--expansion`. Restore untouched backups for
rollback; never downgrade an upgraded save. Failed compiler-limit, reused-output,
upgrade-fixture and neighbor-fixture attempts remain in scratch with their logs.

Before publishing a PR, obtain authorization for the source checkpoint/publication,
include the intended new files, preserve unrelated untracked `.hermes`/OpenSpec
content, and verify the tested archive remains identical after any packaged edit.
Release/version publication, merge and archive require separate authorization.

## Authorized 0.4.0 publication checkpoint

The user subsequently requested publication of a new mod version. Release
metadata and current player-facing descriptions now identify 0.4.0 alpha;
`docs/RELEASE_0.4.0.md` records its distinct tested ZIP and exact acceptance.
The old candidate checksum above is not the release checksum. Source publication
and a draft stacked implementation PR are part of this release handoff; merging
and OpenSpec archiving remain unauthorized, with 5.2/5.3 still incomplete.
