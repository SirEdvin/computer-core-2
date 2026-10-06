# Proposal

## Why

Computer Core 2 currently owns a Factorio workbench, shell, and source editor instead of presenting a programmable character terminal. A terminal-only interface with an upstream-owned Lua shell/editor will make the computer feel like CC:Tweaked while keeping application UI behavior in Lua rather than adding more bespoke Factorio panels.

## What Changes

- Introduce a color character terminal with **startup-configurable columns and rows, defaulting to 51×19**, and CC-style cursor, blitting, scrolling, palette, and terminal-redirection behavior. Dimensions are shared by all viewers and remain fixed during play; presentation scaling does not change them.
- Provide the terminal-related guest environment: keyboard/mouse input, ordered events, virtual coroutines, timers, safe module loading, and the local filesystem/file handles required by the OS and editor. Reuse upstream terminal helpers rather than rewriting them.
- Bundle a pinned, terminal-only subset of **Recrafted** for its shell, editors, scheduler, and supporting libraries. Its `rc`/`require` conventions are retained; compatibility is specifically terminal-facing, not a claim to implement all CraftOS APIs.
- Own a persistent, pure-Lua guest VM using the MIT Phobos parser/compiler. Require a blocking feasibility gate covering upstream shell/editor execution, real client input/rendering, bounded execution, save/reload, and multiplayer joining **before** replacing the current interface.
- **BREAKING:** replace the custom workbench, built-in shell/editor, named-handler runtime, and associated legacy programming contracts. No legacy execution path or program conversion is required. Preserve stored user files; do not silently delete data.
- Physical computers have one shared OS/terminal and **all authorized viewers can send input**, admitted in synchronized event order without an exclusive input owner. Personal computers remain private.
- Target the **ComputerCraft: Greg Flavored Refreshed Advanced Computer** appearance using a cleared asset allowlist and attribution. Retain current world art if provenance/permission is unresolved; do not bundle the resource pack wholesale or copy CCPL assets.
- Do **not** implement peripheral, circuit, wireless, speaker, waypoint, HTTP, turtle, or other world-interaction compatibility. Existing physical entity infrastructure is not redesigned by this change.

## Capabilities

### New Capabilities

- `guest-lua-runtime`: sandboxed, budgeted Lua execution with guest coroutines and durable execution state.
- `computer-terminal`: the fixed character display and terminal-facing API contract.
- `terminal-os`: licensed upstream shell/editor delivery, local files, and terminal-related guest services.
- `computer-interface`: terminal-only Factorio presentation, shared input, authorization, and lifecycle behavior.
- `computer-artwork`: optional licensed world-sprite replacement with a safe existing-art fallback.

### Modified Capabilities

None. The project currently has no main OpenSpec capability specifications.

## Impact

- Runtime/lifecycle/event integration: `scripts/runtime.lua`, `scripts/lifecycle.lua`, `control.lua`.
- Files and user interface: `scripts/filesystem.lua`, `scripts/shell.lua`, `scripts/gui.lua`, `scripts/gui_layout.lua`, `scripts/gui_styles.lua`.
- New guest VM, terminal model, host bridge, and pinned ROM/compiler resources; no native executable, DLL, LuaJIT, external service, or game-side network dependency.
- Startup integer settings for terminal columns/rows, bounded by validated rendering/resource limits, with saved-display reconciliation when settings change between loads.
- Optional sprite/icon changes in `data.lua`/`graphics`; physical behavior remains outside the artwork scope.
- Packaging and attribution in `tools/package.py` and third-party notices; engine fixtures, GUI contracts, examples, API/migration docs, and the client acceptance checklist must reflect the intentional alpha breaking change.
