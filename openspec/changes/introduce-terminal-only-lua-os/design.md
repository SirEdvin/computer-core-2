# Design

## Context

See proposal.md for motivation and the intentional alpha compatibility break. The existing runtime reconstructs named callbacks for dispatch; `scripts/gui.lua` owns shell/editor/workbench views and authorization. `scripts/filesystem.lua` supplies quota-limited storage but also resolves `/mnt` to other computers, so it cannot be exposed wholesale as a local guest disk.

Research tested Factorio 2.0.77 in isolated engine processes. Phobos compiled all 88 inspected Recrafted Lua files and normalized compiler data survived save/reload. This proves neither guest execution nor suspended-state persistence. LuaLua_emu compiled 78/88 files, failed a nested coroutine return-value probe, and retained host functions in suspended state. No inspected upstream interpreter passed the required end-to-end gates.

## Goals / Non-Goals

**Goals:** Make execution, persistence, terminal mutation, and input observable and deterministic; keep the shell/editor upstream-owned; fail safely before replacing the working UI.

**Non-Goals:** A native runtime, runtime downloads, full CraftOS compatibility, peripheral/world API bridges, legacy program conversion, or a homegrown editor. Existing entity placement/power/ownership infrastructure is retained where applicable; obsolete callback dispatch is not retained as a second runtime.

## Decisions

### Experimental playtest delivery override

The user explicitly authorized an experimental playable build before the full
feasibility gate, with all graphical/client UI testing handed to the user.
Deliver terminal/runtime integration and a new alpha package now; document
remaining edge cases and provisional resource/performance limits rather than
extending interpreter hardening indefinitely. Existing authorization, disk
preservation, source sandbox and enforced quotas remain mandatory. Client,
multiplayer and full resource-envelope acceptance remain unverified, not waived
as completed. Section 5 may proceed for this explicitly labelled playtest build;
the original complete acceptance gate still applies to a validated release.

### 1. Data-backed guest VM with Phobos compilation

Pin Phobos at `2566dd85807b4f2bdff8e40ba4d79bcf8e96de3f`. Normalize compiler output into versioned instruction/constants/prototype records. Implement Lua 5.2 guest execution with explicit frames, closures/upvalues, guest tables/metatables, protected calls, and virtual coroutine state. Durable references use stable guest IDs; host services use symbolic bridge IDs resolved outside storage. Never save host closures, native coroutine objects, GUI objects, or raw compiler descriptors.

Guest `load`/`loadfile` compile source into this VM, never the Factorio host environment. Support nested yield/resume, nil-containing return tuples, yields through guest protected calls, closure aliasing, and the metatable/string facilities actually exercised by the pinned ROM. Guest iteration, random/time services, IDs, and scheduling must be deterministic. Only virtual file handles and approved host calls cross the boundary.

Alternative: adapting Recrafted to callback replay would require maintaining its control flow and editor internals. Native coroutines are unavailable in the target sandbox; existing Lua-in-Lua candidates have not demonstrated durable execution. Owning the VM is explicitly authorized, not presumed.

### 2. Feasibility gate before workbench cutover

Build the runtime/bridge and a diagnostic terminal surface without removing the current UI. Gate completion requires booting the actual vendored shell and advanced editor; editing, saving, reopening and running a file; color/window/paint tests; nested virtual coroutines; bounded hostile loops and large host operations; reload in a separate engine process while editing and waiting for events; and joining clients with matching state.

Real graphical-client checks must demonstrate character input/paste, navigation/function/modifier keys, repeat/release handling, cell-addressed mouse input, focus isolation from world controls, and readable color/cursor rendering at supported display scales. Factorio GUI does not automatically provide a raw terminal keyboard stream. Prototype event/custom-input capture first, inspect exact engine APIs, and document any missing path. A hidden text-entry widget may supply text/paste without becoming a second editor; it must not lose Unicode input or duplicate key/char events. Unsupported capture or unacceptable rendering is a failed gate, not permission to silently drop input support. Stop and consult the user if the gate fails.

Instruction budgets cover each computer and the aggregate scheduler. Bound compiler work, allocations, event queues, file operations, pattern/string helpers and rendering updates separately: a cheap guest instruction can call an expensive host operation. Fail with recoverable terminal errors instead of freezing a tick. Calibrate and record concrete limits in engine benchmarks before cutover.

### 3. Recrafted terminal-only ROM

Pin Recrafted at `720773ec68239504cb134cd4f9b7e8bb66a1408e`. Keep BIOS, shell, editor and helpers upstream-derived with license notices and a small explicit integration patch set. Expose the required `rc`, `term`, `fs`, virtual `io`, `keys`, source loading, safe standard libraries and package facilities. Provide terminal-related `os.pullEvent[Raw]`, queue/timer/sleep conveniences as adapters to the same event service where needed; retain Recrafted's documented `require`/`rc` conventions rather than promising arbitrary CraftOS program compatibility.

Use an allowlist dependency closure: scheduler, shell, both editor implementations and syntax support, colors/colours, window, paintutils, settings, textutils, completion, expectations, and local-file commands needed for a usable shell. Never ship all ROM programs just because the compiler accepts them. Startup `30_peripheral.lua`, world completions and updater/network programs are excluded. `cc.completion` eagerly requires peripheral even for local filename completion: patch that dependency to load only when the peripheral-specific helper is called, and exclude peripheral completion registrations. Do not implement an empty fake peripheral API to make boot appear successful. Track every integration patch and prove that editor logic remains upstream-owned.

Mount `/rc` read-only from vendored resources. User files remain in writable local storage, with the existing content quotas enforced independently of ROM bytes. Reserve `/rc` without deleting colliding existing user files: detect collisions during migration and retain/recover their contents under a documented nonconflicting path. Reuse filesystem primitives only after separating local access from peer mount resolution. Guest handles are data-backed path/mode/offset records; no host filesystem, cross-computer mount or native IO access. Safe file replacement and quota failures must not truncate saved content.

### 4. Terminal model independent of presentation

Maintain a startup-configured grid of byte-character cells, defaulting to 51 columns and 19 rows, with independent foreground/background palette indices, a 16-entry RGB palette, cursor position/blink and current colors. Add mod-wide startup integer settings for columns and rows; physical and personal computers use the same configured dimensions, shared by all viewers. Dimensions remain fixed during play and are not guest-controlled or per-player preferences. Establish and document supported minimum/maximum dimensions through the shell/editor and rendering/resource feasibility checks before cutover; do not expose unbounded settings.

Implement documented CC terminal method semantics and American/British aliases, including off-screen cursors, clipping, signed scrolling, blit validation and palette overloads. Upstream Lua owns wrapping, windows and terminal redirection; the bridge supplies the native display. Cell graphics need an independently licensed glyph source; stock CC assets are not automatically permitted. Document text encoding and fallback explicitly and test supported editor text round-trips.

When startup dimensions differ from a saved terminal, reconcile at synchronized configuration-change/dispatch time, never by mutating storage or running the guest in on_load. Preserve overlapping cells, palette, colors, cursor state and suspended guest execution; initialize newly exposed cells with current colors and clip removed cells without touching files or editor buffers. Queue one term_resize notification after reconciliation and before new viewer input so upstream windows/editor can adapt. Unchanged startup settings preserve geometry without a resize event. Startup settings therefore avoid live resizing during play but still require safe saved-state reconciliation across loads.

A view converts this model to Factorio GUI elements with bounded dirty-cell/row updates; term.getSize() reports configured columns/rows and presentation scaling never changes them or emits term_resize. Rendering and blink follow synchronized game ticks, not wall time. Validate actual client fonts/glyph metrics and RGB/background representation at default and supported boundary dimensions. Factorio rich text cannot be assumed to provide arbitrary cell backgrounds or all terminal glyphs; the gate chooses a measured GUI/sprite composition strategy, not an untested rich-text-only design.

### 5. Shared input without ownership arbitration

The user's latest decision supersedes exclusive input ownership: every authorized viewer may send input to the same physical computer. Admit input in synchronized engine event order, assign an ordered sequence, and append one bounded shared queue. Keep pressed-key/button bookkeeping per viewer to prevent one player's release/focus loss from clearing another's state. The guest receives ordinary key/char/mouse event tuples, not separate per-player shells. Document that simultaneous typing interleaves; do not introduce locks or silently serialize entire user sessions.

Recheck existing research, force, surface and distance authorization on each input. Personal machines remain owner-only. GUI focus is local; authoritative terminal/VM state is shared. Closing a view or disconnecting one player releases that viewer's input state but does not stop the OS or reset other viewers. Joining reconstructs presentation from durable state without rebooting. Runtime does not execute during on_load.

### 6. Asset allowlist, not a blanket MIT assumption

ComputerCraft-Greg-Flavored revision `ac6cafc3993c902e2ca95d85b501d3c7e172570c` declares MIT, but README.md:34–38 identifies borrowed/modified assets from multiple projects, including CC:Tweaked. The selected Refreshed advanced model resolves through the pack's normal model and combines casing with screen overlays. Research traced the Refreshed casing textures to the MIT GregTechRefreshed revision `370725c47763dae247068580f9026cc17b3466c5`; absence of an exact CC texture match does not prove independent authorship of an overlay or model.

Before distribution, record each selected texture/model/animation dependency, original author/source/revision, hash, applicable license, and required notices. Clear screen overlays and inherited geometry independently or obtain explicit permission. Do not ship CCPL-derived material on the strength of the pack's top-level MIT license. If the complete selected appearance cannot be cleared, use existing art, as the user approved; terminal rollout does not depend on art clearance.

Render cleared geometry/textures offline into Factorio sprite/icon assets; runtime has no Minecraft model loader. Preserve selected animation semantics where converted; avoid importing KubeJS, Minecraft shader/runtime dependencies, recipes, or unrelated peripherals. Keep existing entity behavior/footprint unchanged and test packaged sprites in the client.

## Risks / Trade-offs

- [Maintaining a guest VM is substantial] → Gate an end-to-end ROM workload before committing to UI replacement; keep unsupported syntax/runtime behavior explicit.
- [Host operations bypass instruction limits] → Bound payloads, compilation and host-helper costs; test quotas and malicious programs, not just opcode loops.
- [Save-state graph grows or changes] → Version execution data, measure saves, preserve user disk and reset only incompatible execution state with a visible notice.
- [Factorio input/rendering limitations] → Require actual client acceptance early; stop rather than promise unsupported keyboard/mouse or glyph behavior.
- [Multiple users interleave edits] → One shared OS is intentional; deterministic event ordering and per-viewer key bookkeeping prevent desynchronization, not collaborative editing conflicts.
- [License provenance remains incomplete] → Keep the existing world artwork; ship only allowlisted cleared resources with notices.

## Migration Plan

1. Keep current UI usable while the feasibility prototype runs; retain reproducible engine/client gate evidence outside the repository.
2. After all gates pass, migrate storage version, preserve user files and recover unsaved legacy drafts, retire callback processes without executing them, and boot the new OS. Do not auto-run an old `/startup.lua` as a converted named-handler program; detect legacy startup metadata/content and preserve it as an inert recoverable file with a visible migration notice.
3. Replace workbench entry points with terminal views, update examples/docs and remove obsolete callback dispatch/UI contracts. No broad physical/world feature redesign accompanies removal.
4. Test upgraded saves and packaged archives. Advise a save backup before the breaking alpha upgrade. Rollback uses the previous mod version and pre-upgrade save, not an unsupported downgrade of migrated VM state.

## Open Questions

Concrete budget values, GUI glyph composition, and final asset clearance are measured gate outcomes, not alternate product semantics. A failed gate requires user review before scope or architecture changes.
