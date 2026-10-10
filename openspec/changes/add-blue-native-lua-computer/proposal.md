# Proposal

## Why

The current VM computer is reported to be too slow. The experimental native continuation backend also failed the measured performance gates, so the blue computer will instead provide a small, directly executed event-driven shell, without a general-purpose Lua application runtime.

## What Changes

- Add a distinct blue physical computer entity, item, localized identity and recipe unlocked by the existing `computer-technology`; retain the current footprint, power requirements, recipe costs and authorized terminal interaction as initial defaults.
- Rewrite the blue shell as trusted bundled native Lua handlers. Each handler returns normally; longer operations advance through explicit, bounded plain-data jobs between events. No coroutine support, continuation compiler, guest opcode interpreter or hidden VM fallback on this model.
- Provide a prompt, command-line editing, bounded history, command/path completion, paste and resize handling, plus built-in commands for help, local directory navigation/listing, reading/managing files, clearing the display, reboot and shutdown.
- Bound command lines at 8,192 bytes to represent the existing maximum paths with literal escaping and two-path commands; retain history at at most 32 entries and 32,768 total bytes. Keep shared work, queue, output and filesystem ceilings unchanged.
- **BREAKING relative to the unshipped blue-computer proposal:** exclude both editors, arbitrary user Lua execution, external scripts/modules, general-purpose application loading and transparent Recrafted/CC:Tweaked compatibility. The blue shell is a rewritten shell, not the unchanged pinned OS running through another backend. Existing VM computers keep their current behavior.
- Persist shell session data, terminal state, ordered events/timers and explicit job progress, not suspended Lua stacks, closures or generated executable bundles. Loading and multiplayer reconstruction must not replay effects.
- Include construction and snapshot import in bounded shared work: a fixed versioned boot/import job validates and stages disk data in admitted chunks, then installs the complete disk atomically before exposing a prompt. Report initialization explicitly; never export unfinished staging as committed files or hide import costs from cold boot.
- Route lifecycle, GUI, authoritative disk/display/status and trusted metadata through a narrow backend facade. Records without backend metadata and personal computers remain VM; unknown or incompatible states halt with recoverable data intact.
- Retain exact-engine, bounded-work, separate-process persistence, measured performance, graphical and multiplayer gates. Keep the 2x lower median cold boot-to-prompt and p95 two-tick character-echo targets; remove editor-launch/editor-state acceptance because editors are explicitly out of scope.
- Preserve the experimental continuation implementation, tests and failed measurements as historical evidence. Its completed tasks are not proof that the new shell is implemented. No code deletion, release or publication is authorized by this specification revision.

## Capabilities

### New Capabilities

- `blue-computer`: Distinct blue physical model with the existing research unlock, safe VM coexistence, lifecycle, authorization and backend-aware metadata.
- `native-lua-runtime`: Bounded direct execution of trusted event handlers, deterministic plain-data jobs and persistence; the capability identifier is retained, but no user-source compiler or coroutine contract remains.
- `native-terminal-os`: A built-in-command-only event-driven shell with durable interaction, confined local file operations and measured responsiveness.

### Modified Capabilities

None. The main capability inventory is empty. The in-progress `introduce-terminal-only-lua-os` change and existing VM behavior remain unchanged; the shell-only revision affects only this additive blue-computer change.

## Impact

- Data/art/localization: `data.lua`, `graphics/`, `locale/en/locale.cfg`; preserve original prototype identities and artwork.
- Integration: `control.lua`, `scripts/lifecycle.lua`, `scripts/os_runtime.lua`, `scripts/terminal_gui.lua` and terminal/filesystem consumers need model-aware routing without replacing the VM implementation.
- New implementation: a small bundled shell and event/job dispatcher, isolated from the experimental `scripts/native/` compiler/continuation pipeline. Reuse safe existing presentation, filesystem validation and event facilities after checking their contracts; do not add a generic plugin framework.
- User execution boundary: local files are data only on blue computers. No `load`, `loadfile`, user module loading, Lua REPL or arbitrary script execution; unsupported requests return explicit errors.
- Provenance: preserve pinned Recrafted/vendor sources, licenses, resource manifests and original VM ROM. Any borrowed/adapted shell material must retain attribution and resource verification without claiming unchanged upstream OS execution.
- Tests/tooling: exact Factorio 2.0.77 base/expansion fixtures, matched shell-only benchmarks, deterministic packaging, graphical interaction and multiplayer joins.
- Saves: introduce an explicit shell backend/state version; no live VM-to-shell or experimental-continuation-to-shell conversion. Unsupported experimental state retains disk and recovery data rather than being reinterpreted as a shell session.
