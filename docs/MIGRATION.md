# Migration contract

## Scope and baseline

Ported from Relik77/factorio_computer_core commit
`92e4ab616d385dfb0247ce2fc195c0e189b01efd` to fresh Factorio 2.0 worlds.
Mod identity: `computer_core_2`; remote identities: `computer_core_2` and compatibility
alias `computer_core`. No Factorio 0.16 save conversion or old bytecode import.

## Feature mapping

| Original feature | Computer Core 2 implementation |
| --- | --- |
| Computer artwork, item, recipe, research | Original graphics with modern base-derived schemas |
| Composite left/right ports, lamp, speaker/music port | Owned child entities, repair/adoption, removal cleanup |
| Shell commands | cat/cd/cp/edit/help/label/ls/mkdir/rm/run/tree/position/waypoint; clear/date/exit/id/mv/pwd/stop/time/touch |
| Files/directories and labelled mounts | Bounded persistent filesystem; `/mnt/<label>` within force/surface |
| OS state, waits, libraries | Plain data tuples, named timers, source library snapshots |
| Terminal input/output/listeners | Persistent text and named listeners with stable IDs |
| Circuit reads/writes | Left/right APIs and aliases, red/green connectors, manual sections and quality-aware identities |
| Wireless messages/built callbacks | Deterministic queued next-tick delivery; named handlers; source-only built-event autorun |
| Speaker notes, alerts, instruments, printing | Modern speaker behavior and wire connectors |
| Personal gauntlet | Research-gated character computer, Ctrl+G/shortcut; no physical ports |
| Waypoints and camera | Shared per-force/per-surface create/edit/delete and camera preview |
| Companion APIs/entity structures | Source definitions, entity selectors, __state, start/tick/stop callbacks |
| Copy/clone/blueprint | Fresh identity and no process replay; clone copies data, blueprint tags copy files |

## Intentional compatibility changes

- `os.wait`, terminal listeners and WLAN subscriptions take a string handler name
  instead of a function. Register via returned handler table or `os.register` at
  declaration time. Bytecode, dumped functions and persisted closures are unsupported.
- Module declarations execute again before **each** handler/extension tick/stop.
  Put effects in `init` or handlers. Captured locals are ephemeral; no heap serializer
  or coroutine persistence. A local alias of `state` remains valid within a dispatch.
- `state`, `os.set` tuples, callback arguments and extension `__state` must contain
  finite numbers, strings, booleans, nil and plain acyclic tables only.
- `os.require` uses the executing source directory, not the terminal cwd. Library
  module scope must be pure. Source snapshots protect existing processes from later
  file/extension registry changes; restart to adopt new definitions.
- Network delivery is queued, not synchronous. Force/surface isolation applies to
  mounts, messages and built-computer callbacks. Personal computers cannot be read by
  physical computers or another player's personal computer.
- Signal quality is part of identity. Duplicate signal entries aggregate and are
  range-checked; outputs use one private constant-combinator section.
- No legacy global table/string helper monkey patches. Use native Lua functions.
- Extension definitions are source strings, not tables of live functions. Durable
  extension fields belong in `self.__state`, not other instance fields. Supported
  callbacks include `on_tick`, `on_script_kill`, `on_message`, `on_built_computer`,
  `on_gui_text_changed` and `after_text_print`, plus custom wireless event names.
  GUI callbacks receive data (`userInput` / `output`, tick, optional player index),
  not persisted GUI objects. Extension code is reconstructed for each callback.
- UI access requires gauntlet research, same force/surface and 10-tile range
  (or ownership of the personal computer). The 0.2 workbench remains available without
  power for file/draft inspection; running programs and sending input require power.
  Program input is explicitly submitted with Send/Enter, not per-keystroke.
  Remote callers are trusted installed mods.
- A conflicting editor save is rejected without overwriting someone else's changes.
  Forced closure retains bounded drafts recoverable from the personal gauntlet.
  Review the current file and choose Keep draft & rebase to accept that version as
  the new base; a later Save still rejects any further concurrent change.
- Blueprint files are untrusted and validated before import. No process, identity,
  label, callback or pending message is copied from blueprint tags. Clones copy
  filesystem/state/variables but start with a fresh identity and stopped process.

## Validation and limits

These intentionally add bounds beyond the old mod: 1 MiB file content and 2048 nodes
per filesystem; 256 KiB program/library source; 256 KiB plain state/variable payloads;
32-level data depth; 256 KiB aggregate extension state; extension names <=128 bytes; 256 timers; 128 terminal listeners and wireless subscriptions;
4096 queued messages, with 4 KiB message payloads; 128 libraries / 1 MiB total library
source; 64 registered extensions / 1 MiB registry source; 1000 signal entries;
64 KiB terminal output; 4 KiB command/input; 16 retained editor drafts per player.
These are validation bounds, **not** CPU/memory isolation. A deliberately infinite
Lua loop can still stall the simulation; only run programs/extensions you trust.

## Verification boundaries

Automated tests use the real pinned headless engine, both base and expansion modes,
including source snapshots, named callbacks, state/tuple persistence, timers and
power restoration, quality circuits, networking, blueprint capture and lifecycle
cleanup. They do not establish GUI appearance, audible sound or multiplayer client
join behavior. Those are required manual acceptance checks in CLIENT_CHECKLIST.md.
