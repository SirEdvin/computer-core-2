# Computer Core 2 — experimental 0.4.1 alpha

A terminal-only computer mod for Factorio 2.0.77+. Original/personal computers use
a pinned Recrafted BIOS, shell and editors inside a durable guest VM. A new blue
physical computer uses a trusted event-driven shell, native editor and restricted
Lua automation with owned circuit ports. Original artwork is retained.
This is an explicitly experimental playtest, not stable or full CraftOS compatibility.

**Back up saves. Prefer a fresh world or a separate upgraded-save copy. Never
load a migrated save with an older mod version. Client UI and multiplayer tests
are still unverified and belong to the playtester.**

## Install and use

1. Copy the supplied `computer_core_2_0.4.1.zip` into Factorio's `mods` directory.
   Do not enable the original `computer_core` simultaneously.
2. Research Personal Computer, then Computer. Supply power to a placed computer.
3. Stay within ten tiles and Ctrl+left-click its body, or Ctrl+G for the private
   personal gauntlet (requires research and a character).
4. Click the terminal itself to type or paste. Native capture is visually hidden; Enter
   submits. Select a terminal key and click **Send key** for completion, history,
   deletion or navigation; focused native text capture suppresses custom shortcuts.
5. On the original VM model, type `edit /hello.lua`. Enter `print("Hello")`; select
   **Editor menu**, click **Send key**, then type **s** to save or **e** to exit.
   Run `/hello.lua`. Blue editors instead provide **Save / Exit editor** buttons.

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

### 0.4.1 native input controls and interactive Lua alpha

The 0.4.1 alpha adds native key delivery and editor controls plus an interactive
`lua` shell: try `1+2`, `state.count=(state.count or 0)+1`, `state.count`,
`print("Hello")`, then `exit` or **Exit Lua**. It shares the saved event scripts'
finite scalar language and circuit API. Locals last for one submission;
`state.FIELD` lasts for the session, including GUI close/reopen and cold reload.
Use `stop` before entering when a background controller is active. No arbitrary
Lua, loops, user functions, modules or VM fallback is provided. Native `edit`,
event-script `run`, `ps`/`stop`, owned ports and stock-control example remain. Follow
[the blue automation guide](docs/BLUE_AUTOMATION.md) for exact controls, language,
limits and wiring. **Historical 0.4.0 input bug:** focused Factorio text fields suppress
Ctrl+S/Ctrl+Q custom shortcuts. 0.4.1 adds native Save / Exit editor controls and
a key selector for all models; these are not in the immutable 0.4.0 release ZIP.
In the released blue editor, click **Terminate**, then type **s** at the dirty
confirmation to save and return to the shell, or **c** to keep editing. No draft
is discarded unless you explicitly choose **d**.
The 0.3.0 description below is historical. Graphical/multiplayer acceptance
remains incomplete. Use `python3 tests/run_engine.py --programs` and repeat with
`--expansion`; `--archive <zip>` exercises an exact candidate package.

### Historical 0.3.0 shell-only alpha

The 0.3.0 alpha adds **Blue computer (shell only)**, unlocked by the same Computer
research. Craft the blue item, place/power it and Ctrl+left-click within ten tiles.
Try `help`, `pwd`, `mkdir /test`, `ls`, `cat /rom/help.txt`, `cp /rom/help.txt /test/help.txt`
and `cat /test/help.txt`. It supports twelve built-ins, editing/history/Tab/paste,
bounded local file jobs and committed-file clone/blueprint imports. Blue files
are data: it cannot run Lua files, editors, modules or the original Recrafted OS.
Original and personal VM computers keep their existing behavior and saves.

See [the shell reference](docs/SHELL_RUNTIME.md), also bundled in the ZIP, and the
blue checklist in [PLAYTEST.md](docs/PLAYTEST.md). This is a user-authorized test
release despite the still-blocking graphical/multiplayer acceptance gates, not
completed specification or stable-release acceptance.

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
