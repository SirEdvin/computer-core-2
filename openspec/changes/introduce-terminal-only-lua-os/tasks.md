# Tasks

Playtest override: deliver an experimental alpha now, with client UI validation
owned by the user and remaining resource-envelope/edge cases documented. Client
acceptance tasks remain unchecked until verified. The user explicitly permits
section 5 integration for this playtest without claiming section 4 passed.

## 1. Pinned dependencies and diagnostic harness

- [x] 1.1 Vendor the pinned Phobos and terminal-only Recrafted dependency closure with a source/hash/license manifest and minimal integration patch ledger; verify every included file is attributed and no excluded peripheral/network startup or completion program is included.
- [x] 1.2 Extend the isolated Factorio engine harness in `tests/run_engine.py` with guest-runtime fixtures and separate-process reload phases; verify a diagnostic fixture runs in the pinned engine and logs independently identify initial and resumed execution.
- [ ] 1.3 Add a diagnostic terminal view without removing the existing workbench, and prototype actual focused text/paste, navigation/modifier/repeat/release and cell-addressed mouse capture; verify in a graphical client and record failures as gate blockers rather than substituting mock acceptance.

## 2. Persistent bounded guest execution

- [x] 2.1 Normalize Phobos output into versioned data-only prototypes and implement guest scalar/table, closure/upvalue and frame operations; verify arithmetic, control flow, varargs, nil tuples, aliasing and metatable fixtures against expected Lua semantics in the engine.
- [x] 2.2 Implement guest calls, protected error handling and virtual coroutine create/resume/yield/status including nested suspension and protected calls; verify exact return tuples and errors with regression fixtures covering the failed upstream nested-resume case.
- [x] 2.3 Implement source-only guest load/loadfile, safe language helpers and symbolic host-service resolution; verify sandbox escape attempts cannot access host globals, Factorio objects, native IO or host functions and document the supported language/service boundary.
- [ ] 2.4 Implement per-computer and aggregate scheduling, allocation reclamation/quotas, bounded compiler/host operations and recoverable exhaustion; verify infinite loops, oversized compile/string workloads, event flooding and many computers remain within measured bounds and record configured limits.
- [ ] 2.5 Persist the versioned execution graph with guest object identity, coroutines, queued tuples, timers and handle offsets; verify separate-process reload and multiplayer joining without guest execution in on_load, and document compatible execution-state recovery rules.

## 3. Terminal model and local guest services

- [x] 3.1 Implement startup integer settings for terminal columns/rows (defaults 51/19), a configured character/color model and write/blit/clear/cursor/signed-scroll semantics with Color/Colour aliases and 16-entry palette operations; verify default/nondefault geometry, clipping, invalid-call atomicity, palette recoloring and off-screen cursor fixtures and document the settings and terminal contract.
- [x] 3.2 Add bounded event admission, filtered/raw waits, termination, cancellable simulation-tick timers and sleep with selected OS adapters; verify event ordering, nil payloads, timer cancellation/reload and termination behavior and document queue overflow policy.
- [x] 3.3 Separate local filesystem primitives from peer mount resolution and expose a read-only `/rc` plus quota-limited local disk with durable guest fs/io handles; verify path confinement, ROM protection, seek/iteration/close, reload and nontruncating quota failures and document disk/handle behavior.
- [x] 3.4 Wire upstream terminal redirection, colors/colours, window and paintutils helpers to the guest display; verify nested clipping, invisible-window redraw, redirect restoration and painted color cells using real upstream modules.
- [x] 3.5 Reconcile saved display dimensions after startup-setting changes at synchronized configuration-change/dispatch time, preserving guest/editor state and overlapping cells and delivering one term_resize before new input; verify grow/shrink reload fixtures, unchanged-settings reload without resize and no guest execution/storage mutation in on_load.

## 4. Upstream OS boot and feasibility acceptance

- [x] 4.1 Integrate the pinned BIOS, scheduler, shell, settings/completion modules and both editors with narrowly tracked dependency patches; verify shell filename completion and editor startup without peripheral stubs or world/network APIs and document upstream integration differences.
- [x] 4.2 Run an engine-driven shell/editor workflow that creates, edits, saves, reopens and executes a local program, including syntax highlighting and a suspended dirty editor save/reload; verify contents, terminal cells and coroutine results from the actual upstream programs.
- [ ] 4.3 Complete graphical terminal rendering with independently licensed glyph resources, per-cell foreground/background, palette updates and cursor blink; establish documented supported startup dimension bounds from shell/editor and rendering/resource checks, enforce them in settings, and verify default/nondefault/boundary dimensions and coordinate accuracy at supported display scales without scale-driven resize; document encoding/fallback without file-byte loss.
- [ ] 4.4 Exercise two real clients typing into one computer, focus loss/disconnect, save/reload and another client joining; verify synchronized shared display, input ordering and isolated per-viewer pressed state without exclusive input ownership.
- [ ] 4.5 Record the complete feasibility verdict across guest execution, upstream editor/shell, host-operation bounds, actual input/rendering, reload and joining; verify every gate has real evidence before authorizing section 5, and stop for user review if any gate fails.

## 5. Terminal cutover and safe migration — experimental playtest override applies

- [ ] 5.1 Replace workbench views in `scripts/gui.lua`, layout/styles and control event wiring with the terminal-only view; verify there is no native editor/file-browser/custom-shell panel and all authorized viewers may input while existing per-event research/force/surface/distance and personal-owner checks remain effective.
- [ ] 5.2 Replace named-handler dispatch in runtime/lifecycle integration with the guest scheduler, retaining existing physical power/ownership constraints; verify opening/closing viewers does not reboot execution and remove obsolete callback extension dispatch without adding world API bridges.
- [ ] 5.3 Add an explicit storage migration that preserves user files, recovers legacy editor drafts and `/rc` collisions, retires callback processes and retains legacy startup content inertly with a visible notice; verify upgraded-save fixtures lose no recoverable content and never automatically execute legacy startup code.
- [ ] 5.4 Replace obsolete examples, GUI/runtime tests and API/workbench docs with terminal/OS workflows and breaking-upgrade guidance; verify documented shell/editor commands run and no remaining documentation claims legacy or full CraftOS compatibility.

## 6. Optional cleared world artwork

- [ ] 6.1 Produce a per-file provenance/license/hash allowlist for the selected Refreshed Advanced Computer model, inherited geometry, casing, screen overlays and animation metadata; verify each dependency's original terms independently and obtain explicit permission where needed, or record the existing-art fallback without bundling unresolved assets.
- [ ] 6.2 If the complete selected appearance is cleared, render/package Factorio sprites and icons and update only artwork references in `data.lua`; verify actual client appearance and packaged resources for required directions/states with unchanged footprint/behavior, or verify existing artwork remains intact when clearance fails.

## 7. Packaged integration acceptance

- [x] 7.1 Update `tools/package.py` to include pinned ROM/compiler resources, glyph/art resources, notices and manifests; verify the built ZIP contains only allowlisted resources and passes engine creation and separate-process reload in base and supported expansion configurations.
- [ ] 7.2 Run the final packaged-mod client/multiplayer workflow and upgraded-save acceptance checklist; verify shell boot, editor save/reopen/run, colors/windows, shared all-viewer input, authorization, power/viewer lifecycle, save/reload and join behavior with no untested acceptance claim.
