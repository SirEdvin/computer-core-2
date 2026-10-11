# Design

## Context

See proposal.md for motivation. Release 0.3.0 routes blue computers to `scripts/shell/runtime.lua` (state version 2), explicit admitted jobs and the shared durable scheduler ledger. It rejects user programs and editors. The original/personal VM computers and the unsuccessful general-purpose native continuation experiment remain separate.

Observed reusable pieces:
- `scripts/native/compiler.lua:11` exposes bounded `analyze` returning an ephemeral Phobos AST; `compile` invokes the general continuation generator and is not the proposed execution path.
- `scripts/shell/file_job.lua` stages a complete validated filesystem before atomic publication, but currently supports only mkdir/copy/move/remove and refuses overwrite.
- `scripts/adapters.lua` implements signal normalization and owned constant-combinator sections. Its broad 1000-signal normalization ceiling is not an automation API quota.
- `scripts/lifecycle.lua:64` currently refuses all blue peripheral construction. Automation requires explicitly creating two owned circuit ports, not treating the existing ports as already available.
- Pinned Factorio 2.0.77 runtime API documents scalar `LuaCircuitNetwork.get_signal`, circuit networks by connector id and constant-combinator manual sections. No general entity access is needed.

The predecessor proposal/specs prohibit user source, editors and peripheral APIs. This follow-up supersedes those exclusions only for the defined restricted applications; it must not present old shell-only tests as scripting acceptance or rewrite historical failed speed results.

## Goals / Non-Goals

Goals: native editing and demonstrably real edited-file execution; finite native callbacks; deterministic persistent state; a useful circuit-controlled factory example; retained shell responsiveness under script load.

Non-goals: VM execution for blue programs, opcode/AST interpretation, continuation frames, arbitrary native source loading, general Lua compatibility, loops/recursion, user modules, direct game/entity/inventory access, wireless/HTTP, script-created entities, auto-start, or replacing original computers. No new dependencies or global budget increases.

## Decisions

### 1. Compile a finite Lua subset rather than resurrect the continuation runtime

Accept exactly one top-level return of a program descriptor: literal integer `interval` (1–3600 ticks, default 60), optional `on_start` and `on_tick` function literals taking `(event, state)`, with at least one handler. The descriptor contains no executable initializer expressions.

Handler grammar: local scalar declarations, scalar assignments, literal-name `state.FIELD` assignment/read, `event.tick`/`event.name` reads, if/elseif/else, do blocks, return, scalar literals, parentheses, arithmetic/comparison/boolean operators and bounded concatenation. Calls are only direct allowlisted `print`, `math.floor/abs/min/max`, `circuit.read/write/clear`. All names resolve to locals or these explicit API roots; locals cannot contain callable values. Missing state fields read nil; conditional defaulting (`state.runs or 0`) is supported.

Reject all loop forms, goto/labels, nested/user-defined functions, recursion, dynamic/computed indexing, general table construction, captured mutable upvalues, variadics, method calls, function aliases, arbitrary globals and every unlisted node. The only table/function syntax is the outer descriptor and its handler declarations. Strings/numbers remain checked scalars, so metatables and callable-table escapes cannot arise.

Reuse bounded AST analysis, then apply a new default-deny validator/emitter. Emit native expressions/conditional branches and checked host service calls; do not invoke `scripts/native/codegen.lua`, `Execution.run`, native continuation dispatch or any VM. Load only compiler-emitted wrapper code in a closed host-only environment. Player strings are emitted only with safe literal quoting. Never persist or execute unverified generated text; retain exact source and ABI, revalidate/re-emit on cold synchronized dispatch, with warm/cold equivalent admission. No code or migration runs during on_load.

Raw sandboxed `load(player_source)` was rejected: hiding game does not prevent infinite loops, recursive calls or oversized allocations. The old native continuation runtime was rejected because it recreates suspended-frame/boxed-value overhead and failed the earlier end-to-end speed gates.

### 2. Reserve complete callbacks and publish bounded transactions

Initial language ceilings: 16 KiB source, 1024 AST nodes, 256 statements, nesting 16, 64 KiB emitted wrapper, at most 64 state fields with 64-byte keys and 256-byte strings; total state string payload at most 16 KiB. Scalars are nil/boolean/finite numbers/bounded strings. Maximum 16 circuit calls and 8 print calls along any callback path, with each rendered print capped at 256 bytes; no host pattern/sort/iteration primitives are exposed.

Derive a conservative complete-handler cost envelope from the validated syntax, capped scalar sizes, state copy/validation and maximum effects. Reserve it against the existing per-machine AND aggregate ledger before executing any native callback. If the envelope does not fit a fresh existing quota, refuse activation; if current credits are insufficient, defer the whole event without mutation. Do not preempt partway, replay a partially executed callback or save native stacks.

Execute against bounded scalar state and staged output/signal records. Validate all return state, arithmetic results, API arguments and owned port targets before publication; pre-admit publication and cleanup. A callback error discards its staged changes and stops that controller with an explicit diagnostic. Expected validation/admission failure cannot leave half-published state/signals. Entity destruction/reentrant engine errors after publication begins require bounded fail-safe output clearing and visible fault handling, not a claim of arbitrary engine rollback.

Conservative costs and source ceilings are initial restrictions to validate, not measured performance results. Build a small actual edited stock-controller slice before broad integration; reject or surface any impossible cost/performance envelope rather than increasing shared caps.

### 3. Separate the editor, controller and shell session

Add native editor/controller components under a distinct restricted-program area rather than extending the experimental VM-like runtime. Shell `edit PATH` opens a trusted terminal editor; `run PATH` and direct `.lua` paths compile the committed local file and start one background controller. `ps` reports running/paused/faulted status, path and next event. `stop` halts it and clears owned outputs. Replacing a running controller requires explicit stop first; compilation failure never silently replaces it.

The editor retains bounded multiline text, cursor/viewport, dirty status, base file content and save-job phase as plain versioned data. Limit editable bytes to the existing 32 KiB source ceiling (scripts themselves have the tighter 16 KiB ceiling); larger files remain readable but refuse edit without modification. Native newline insertion, deletion, arrows/Home/End/Page keys and CRLF-normalized paste preserve suffix/cursor and file bytes. Native Save/Exit editor and confirmation Save/Discard/Cancel controls are authoritative while text capture is focused; Ctrl+S/Ctrl+Q remain optional when the engine delivers them. A single native key selector/send control covers completion, deletion, navigation, history and original/personal editor menu without relying on custom-input delivery. Avoid introducing a second text capture widget or duplicate navigation controls.

Add a bounded atomic write/replace job using existing import/publication validation. It must preserve other committed files, refuse /rom and directories, detect a changed base file, keep a failed draft editable and mark clean only after successful publication. Foreground editor redraw/events and background controller share the same computer ledger. Background print records enter a plain bounded FIFO (64 records, 16 KiB total); show them only when the shell owns the screen, never over editor rows. When that FIFO is full, fail the callback before publication rather than overwrite or grow it. Closing/reopening the GUI does not stop either. Editor drafts survive save/reload; explicit reboot/shutdown require dirty-exit handling before discarding them and stop the controller.

### 4. Persist explicit controller data, not executable snapshots

Controller records contain format/compiler/API versions, canonical path, exact source snapshot, bounded scalar state, program generation, pending event and absolute next tick. Generated functions/caches are ephemeral and keyed by the active snapshot. Editing the source file does not change a running controller; stop/run selects the new committed version. Once on_start commits it is never replayed by reload/reconstruction. A descriptor without on_tick exits after on_start; periodic controllers run one due callback at a time with next deadline based on the successful tick, not catch-up storms.

Power loss clears owned outputs once and pauses dispatch; retained state/deadline survive. Restoration schedules one fresh on_tick evaluation before restoring control signals, without replaying on_start. With no on_tick handler a pending one-shot on_start can resume once; completed one-shots are stopped. Stop/error/reboot/shutdown/removal/force or surface invalidation clear owned outputs. Reserve bounded priority lifecycle cleanup from the existing shared cap before admitting ordinary workloads, so script exhaustion cannot consume its reservation; this is not a second allowance or a same-tick budget renewal. A callback reserves its own failure cleanup as part of its complete envelope. Retry lifecycle cleanup before allowing a new controller to run, and test simultaneous power/ownership loss at the active-computer cap.

Old shell-only sessions acquire optional editor/controller fields only during admitted dispatch, never automatic execution. Unsupported versions retain source/draft/state as recovery data. Clones and blueprints copy committed files only: no dirty draft, live controller, state, event, timer or active outputs. Multiplayer reconstruction consumes the same durable admission as warm dispatch and cannot replay effects.

### 5. Circuit-only capabilities with a real production example

Blue lifecycle creates only owned left/right `computer-combinator` children using the existing positioned circuit-port prototype. It does not instantiate the legacy speaker/lamp/peripheral bundle. Validate child registry ownership, body validity, power, researched force, same force/surface and program generation for every service and immediately before publication. Clear/destroy only owned resources; do not remove player combinator sections or reconnect player wiring.

Public scalar API (normal quality only initially):
- `circuit.read(side, wire, type, name)` reads one exact signal, zero for an unconnected valid port. Side is left/right, wire red/green, type item/fluid/virtual; validate prototype identity. Missing/unauthorized ports are faults, not zero.
- `circuit.write(side, type, name, count)` stages replacement of that output identity, finite int32 only; zero removes it. Retain at most 32 output identities per side. Validate all entries before atomically replacing that owned port's private manual section.
- `circuit.clear(side)` stages clearing that owned output bank.
No service returns an engine object, signal-array alias, registry or callable value. Reading one's own output network is possible; docs recommend left=input/right=output and separate networks to avoid feedback.

Proposed bundled `/rom/examples/stock-controller.lua` (documentation/example data, not execution during planning):

    return {
      interval = 60,
      on_start = function(event, state)
        print("Stock controller started")
      end,
      on_tick = function(event, state)
        local count = circuit.read("left", "red", "item", "iron-plate")
        local enabled = 0
        if count < 100 then
          enabled = 1
        end
        circuit.write("right", "virtual", "signal-A", enabled)
        state.stock = count
      end
    }

User flow: wire a read-enabled chest to the left port using red wire; wire the right port to an inserter configured `signal-A > 0`, keeping the two networks separate. `cp /rom/examples/stock-controller.lua /stock.lua`, `edit /stock.lua`, change the threshold, click Save then Exit editor, and `run /stock.lua`. Real-engine tests assert chest signal reads, controller output and inserter enable/transfer behavior across threshold changes, cold reload, stop and power failure. A packaged default example is not enough: acceptance must run the version actually edited/saved through the native editor.

### 6. Restricted native interactive shell and input audit

`lua` enters an explicit foreground session after stopping any background controller; entry refuses replacement rather than stopping it implicitly. Each submitted line (8 KiB maximum) is parsed as finite statements or a scalar expression and compiled through the same default-deny validator/emitter. Expressions and explicit scalar returns are displayed, including false/nil. Locals last only for that submission; `state.FIELD` persists until session exit. The existing bounded terminal history is shared. No descriptor is required, no raw player-source load occurs and no new APIs or quotas are introduced.

Retain a versioned session marker, scalar state owner, immutable pending submission, terminal input/history and spent work as plain data. Compile/evaluate a whole submission only after complete admission; reject syntax/runtime errors visibly and retain the usable session and previous state/output banks. Publish staged state/prints/signals only after validation. Original/personal VM execution remains unchanged. No on_load evaluation, implicit replay of committed submissions, suspended frames or persistent executable caches are permitted.

The REPL exclusively owns the existing circuit controller lease and banks: no concurrent background controller. A native Exit Lua control, `exit` command or Terminate exits and clears owned outputs; reboot/shutdown also stop it. Close/reopen and cold reload retain unfinished input, pending submission and state; copies exclude all of them. Power/ownership failure retains plain recovery data but clears unsafe outputs through existing priority cleanup. A new `lua` session starts with fresh scalar state.

Audit every registered key against its actual shell/editor/VM consumer. Native selector delivery must use the same authorization, power, event admission and selected-backend protocol, restore typing focus, reject foreign/stale controls and avoid duplicate Backspace/Enter. Verify native click paths without injected custom-key events; keep actual graphical key/focus behavior and multiplayer joining as separate incomplete gates. Publication of 0.4.1 is authorized only after the requested audit and REPL verification, with honest alpha limitations; merge/archive remain unauthorized.

## Risks / Trade-offs

- Static subset is intentionally small → precise line/column diagnostics, complete syntax/API matrix and runnable examples; no claim of arbitrary Lua or ComputerCraft compatibility.
- Native handlers cannot be interrupted safely → prohibit unbounded constructs and native opaque-work APIs; reserve worst-case complete work before effects; adversarial exact-engine tests.
- Conservative reservation can reject useful programs → calibrate finite limits with the vertical slice and document refusals; obtain approval before broadening syntax or quotas.
- Engine services have opaque costs → scalar lookups, small port banks and measured contention; work-unit bounds are not hard CPU-time guarantees.
- Background updates and editing can contend → one controller per body and shared scheduler, with p95 two-tick terminal-model echo tested under maximum allowed scripts; separately verify actual client latency.
- Lifecycle/engine errors can leave unsafe signals → owned-output fail-safe clearing with priority bounded cleanup and actual powered entity tests.

## Migration Plan

Implement on the follow-up feature branch based on the 0.3.0 commit; keep predecessor PR/history and unfinished client gates intact. Version the new optional application records, retain 0.3.0 shell sessions without auto-start, verify source-only resources and original VM/vendor bytes. Run strict planning validation, then the actual archived Factorio 2.0.77 base/expansion matrix, old-save upgrade, cold no-work-on-load, graphics and two-client join checks. Do not publish, merge or archive this change until separately authorized. Roll back code for fresh test worlds; restore an untouched save backup rather than downgrade an upgraded save.
