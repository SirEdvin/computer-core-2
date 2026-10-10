# Known limitations — 0.3.0 alpha

This is an experimental, breaking terminal-OS playtest, **not full CraftOS** and
not a stable release. This document does not certify completed source integration,
a published archive, migration acceptance or graphical/multiplayer acceptance.
Follow [PLAYTEST.md](PLAYTEST.md) on a fresh world or backed-up save copy.

## Compatibility boundary

- The new blue model is a built-in-only event shell. It cannot run Lua source,
  editors, modules or the Recrafted OS. Its local files are data; `/rom/help.txt`
  is read-only data, not executable ROM. Original/personal VM computers retain
  the source-program/editor behavior described below. The blue model is released
  for explicitly authorized alpha testing; graphical and joining-peer acceptance
  remain blocking and are not inferred from the packaged headless tests.

- The new direction replaces the old workbench and named-handler/callback runtime
  with a vendored Recrafted shell/editor running Lua source in an isolated guest.
  Old examples and API/workbench instructions may describe **0.1.x**, not this OS.
  Preserved source is not automatically converted into a compatible program.
- **No guest peripheral, world, circuit, wireless, speaker or HTTP API.** Existing
  physical hardware and artwork may remain in the world, but those entities do
  not expose these services to guest programs. Legacy `/mnt/<label>` peer mounts
  are not guest mounts; `/mnt` is only a local filesystem path.
- Only source code is loaded/compiled; **binary Lua bytecode is rejected**.
  Native IO/code loading and host Factorio objects are not available to the guest.
  A CC-style API name does not establish complete ComputerCraft compatibility.
- `/rc` is the read-only vendored OS. Local disk and open-file contents are
  quota-limited; writes/copies can fail. Keep independent backups of important
  source, and check save errors rather than assuming edits reached disk.

## Input, presentation and shared sessions

- Clicking the terminal focuses a visually hidden native capture widget. Enter
  uses GUI confirmation; navigation uses custom inputs. The fallback button row
  is removed. Ctrl+M opens the upstream editor menu. Physical
  key release/held state and mouse drag are not captured: each key/cell click is
  followed by a synthetic release. Hold/repeat and shortcut interception remain
  client-unverified; custom inputs deliberately do not consume world controls.
- Advanced-editor changed rows echo in plain text first. Syntax colors refresh
  after a short typing pause; expensive highlighting can still delay later input.
  Hidden-widget focus, deletion, clipboard behavior and real latency need client testing.
- Single-byte input is a `char`; multi-byte updates are a `paste` (a heuristic,
  not clipboard detection). The byte-cell renderer shows printable ASCII and
  `?` for other bytes, without modifying stored source/file bytes. It uses a
  declared core monospaced font and an original solid background tile, not
  copied ComputerCraft glyph art. Actual client font metrics remain unverified.
- Foreground palette RGB changes are rendered. Background styles use the fixed
  default 16 colors in this alpha; custom background RGB mutations remain exact
  in the durable model but are not reflected by the GUI. Cursor blink and grid
  changes use bounded refresh sweeps, so large grids may repaint gradually.
- One physical computer has **one shared session**. All authorized viewers may
  send input, so simultaneous typing interleaves and may conflict. Personal
  computers remain owner-only. Real two-client focus/disconnect/join behavior
  remains a playtest gate, not a headless-test conclusion.
- Startup geometry defaults to **51×19**, shared by all viewers and fixed during
  play. The settings admit 1–160 columns and 1–60 rows as bounded model sizes;
  these are **not validated graphical support bounds**. Display/UI scaling must
  not silently change the guest grid.
- Rendering, color/cursor readability, actual keyboard/mouse capture and resize
  presentation are client-owned, unchecked acceptance tests. Assigning them to
  the playtester does not mean they have passed.

## Resource and upgrade caveats

- Updating from 0.2.0/0.2.1 does not replace already-compiled guest modules or discard
  suspended editor drafts. Save files and reboot each computer once to load the
  optimized OS code. Reboot discards unsaved buffers, not saved files.
- Per-computer instruction and collection quanta are now 4096 and 2048;
  their aggregate tick caps remain 4096. A few computers get faster service;
  many continuously busy computers still share those same aggregate caps.

- Timers use simulation time: power loss stops guest dispatch, but overdue timers
  become due after power returns; their remaining duration is not frozen.
- Blueprint/clone copies currently pass through legacy startup protection too:
  startup files remain preserved under inert recovery names rather than running
  automatically in a copied computer. Re-create startup deliberately if wanted.

- Object, instruction/work, event and file quotas are implemented in the guest
  runtime. They do **not** establish complete combined retained-memory bounds,
  emergency-memory accounting or acceptable production tick/input/boot latency.
  Compiler work can still be synchronous. Do not treat quota tests as a proof
  that all hostile or many-computer workloads are safe or responsive.
- Upgrade acceptance must verify file preservation, legacy draft recovery,
  read-only-ROM `/rc` collisions and inert recovery of old startup source.
  Consult the migration notice for actual recovery paths; do not assume the old
  callbacks resume or that migration converts programs. Existing documentation
  about no migration or the old workbench may predate this intended build.
- **Never downgrade a migrated save.** Restore an untouched backup with its old
  mod version instead. Upgraded-save preservation, save/reload continuation and
  client joining must be verified in the exact supplied archive.

Headless guest/shell/editor evidence is useful but does not certify the production
GUI, migration, multiplayer clients or stable-release acceptance. No graphical
pass is claimed here.
