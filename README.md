# Computer Core 2 — experimental 0.2.2 alpha

A terminal-only Lua computer for Factorio 2.0.77+, using a pinned Recrafted BIOS,
shell and editors inside a durable guest VM. Existing world artwork is retained.
This is an explicitly experimental playtest, not stable or full CraftOS compatibility.

**Back up saves. Prefer a fresh world or a separate upgraded-save copy. Never
load a migrated save with an older mod version. Client UI and multiplayer tests
are still unverified and belong to the playtester.**

## Install and use

1. Copy the supplied `computer_core_2_0.2.2.zip` into Factorio's `mods` directory.
   Do not enable the original `computer_core` simultaneously.
2. Research Personal Computer, then Computer. Supply power to a placed computer.
3. Stay within ten tiles and Ctrl+left-click its body, or Ctrl+G for the private
   personal gauntlet (requires research and a character).
4. Click the terminal itself to type or paste. Native capture is visually hidden; Enter
   submits. Use keyboard shortcuts for navigation; the fallback button row is removed.
5. Type `edit /hello.lua`. Enter `print("Hello")`; Ctrl+M opens
   the editor menu, then type **s** to save or **e** to exit. Run `/hello.lua`.

Close preserves the running OS. Reboot discards unsaved guest buffers, not saved
files. Shutdown stops dispatch until reboot. Power loss pauses execution; overdue
timers become due after power returns. Physical viewers share one input stream.

Read [playtest steps/checklist](docs/PLAYTEST.md) and [known limitations](docs/KNOWN_LIMITATIONS.md).
When updating from 0.2.0, save your files, then reboot each computer once to load
the optimized OS window code. Upgrading does not discard a running editor draft
or silently replace its suspended code; Reboot still discards unsaved buffers.
Printable ASCII is the initial render surface; other bytes show fallback glyphs
without altering file bytes. Synthetic releases, no drag, fixed background palette
and gradual large-grid redraw are documented alpha limitations. Boot/editor
responsiveness is provisional, not a measured latency guarantee.

## Breaking upgrade

0.1.x workbench, callback APIs, native editor and world/network programming APIs
are retired. Stored files and recoverable drafts are preserved, but programs are
not converted. Legacy startup files remain inert under `/legacy-startup*`; `/rc`
collisions and drafts recover under `/legacy-recovery`. Original data remains
archived if quota limits prevent a recovery copy. Do not downgrade migrated saves.

Older API/workbench documents and callback examples describe 0.1.x only; they are
historical, not instructions for this OS. Current guest contracts are documented in
[terminal services](docs/TERMINAL_SERVICES.md), [guest filesystem](docs/GUEST_FILESYSTEM.md)
and [guest runtime](docs/GUEST_RUNTIME.md). Guides/examples remain repository-only.

## Build and verify

Python tools use the standard library; install official Factorio 2.0.77 headless
separately. No engine executable is redistributed.

    python3 tools/verify_guest_resources.py
    python3 tools/package.py
    python3 tests/run_engine.py --guest
    python3 tests/run_engine.py --guest --expansion

Use `--archive <zip>` to test the package and `--output <directory>` to retain
isolated logs, saves and `result.json`. Guest checks exercise actual ROM programs,
separate-process reload and selected live lifecycle/migration fixtures, not native
GUI interaction or complete upgraded-save/client acceptance. The historical
non-guest test mode targets the retired 0.1.x API and is not alpha acceptance.

Source-only Phobos/Recrafted resources are pinned and attributed in
[vendor/README.md](vendor/README.md) and `vendor/manifest.json`. Original Computer
Core artwork/code provenance is retained under the repository MIT license;
reference revision `92e4ab616d385dfb0247ce2fc195c0e189b01efd`.
