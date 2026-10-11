# Proposal

## Why

The released blue computer is responsive but cannot edit or execute user programs, so it cannot automate a factory. The user now explicitly requests `edit`, execution of edited Lua files and a practical Factorio example, with no VM and acceptable scripting restrictions.

## What Changes

- Add a native terminal `edit PATH` application with multiline editing, paste, navigation, atomic save, dirty-exit confirmation and durable drafts. Retain the fast shell and original/personal VM computers.
- Execute local `.lua` files through a new, restricted native event-script compiler/runtime, never the VM, opcode interpreter or experimental continuation dispatcher. Accept finite straight-line handlers, local scalar variables, conditional branches and bounded scalar persistent state; reject loops, recursion, arbitrary function calls, dynamic loading, modules, metatables and suspended stacks.
- Compile only an allowlisted AST into trusted generated native Lua. Reject unsupported source before activation; never directly load player-provided source or trust executable text from saves. Admit a complete conservative callback cost before any execution and stage effects/state for validated publication.
- Define an explicit program descriptor with optional `on_start` and `on_tick` handlers and a bounded tick interval. Allow one background controller per blue computer, keeping its terminal/editor usable. Add `run PATH`, direct `.lua` path invocation, `ps` and `stop`; no autorun on placement, import, clone or blueprint revival.
- Add narrow circuit access to owned left/right ports: scalar signal read and output set/clear. Do not expose Factorio objects, `game`, arbitrary entity lookup/control, inventories, wireless, HTTP or generic remote calls.
- Ship a stock-control Lua example as read-only sample data: copy it locally, edit/save it, then run it. Read a chest's stock through circuit wiring and emit a production-enable signal, demonstrated against real engine entities rather than mocked effects.
- Version durable editor/controller data and preserve active source snapshots, state, event ownership and shared work counters across cold reload and peer reconstruction. Stop/reboot/shutdown/error/removal clears owned automation outputs without deleting files; power loss pauses callbacks and clears outputs until power returns.
- Supersede the predecessor change's shell-only prohibition only for these explicitly added capabilities. Preserve its historical evidence and unchecked graphical/multiplayer gates; do not mark prior acceptance complete or claim general Lua/CC:Tweaked compatibility.

## Capabilities

### New Capabilities

- `blue-terminal-editor`: Native durable local text editing and atomic file publication.
- `restricted-native-scripting`: Statically bounded native Lua event scripts, controller lifecycle and deterministic persistence without any VM.
- `blue-circuit-automation`: Authorized owned circuit ports and a runnable factory-control example.

### Modified Capabilities

None: `openspec list --specs` reports no main specs. This follow-up explicitly changes the requirements of the still-open `add-blue-native-lua-computer` change; it does not silently rewrite or archive that change.

## Impact

Shell/runtime/backend/GUI integration, filesystem jobs, lifecycle-owned circuit children, localization, package resources, docs and exact-engine fixtures. Reuse the existing bounded Phobos AST analysis and circuit adapter contracts, not the retired unbounded callback runtime or continuation execution pipeline. No new dependencies, original prototype/vendor/VM ROM changes, automatic runtime conversions or publication are proposed. Native-client and multiplayer evidence remain required and separate from headless tests.
