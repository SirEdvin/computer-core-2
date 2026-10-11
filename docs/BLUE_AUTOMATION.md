# Blue native editing and restricted automation — 0.4.0 alpha

This guide describes the 0.4.0 alpha, which adds editing and restricted automation
to the 0.3.0 shell-only predecessor. Original physical and
personal computers still run the existing VM/Recrafted OS. Blue computers never
use that VM or the preserved experimental continuation runtime as a fallback.
Graphical and joining-peer acceptance remain separate, unverified gates.

## Edit, save and run

Supply power, research Computer, open the blue body with Ctrl+left-click within
ten tiles, and focus its terminal. Physical viewers share the same session.

    cp /rom/examples/stock-controller.lua /stock.lua
    edit /stock.lua

The native editor starts at the beginning of the document:

- Enter inserts LF; Tab inserts two spaces.
- Left/Right, Home/End, Up/Down and Page Up/Page Down move the cursor/viewport.
- Backspace deletes the preceding byte; Delete deletes the following byte.
- Paste inserts at the cursor, preserves the suffix and normalizes CRLF/CR to LF.
- Ctrl+S starts a save. The draft remains dirty while publication is pending.
- Ctrl+Q leaves a clean draft. For dirty text choose `s` save, `d` discard or
  `c` cancel. Escape cancels the confirmation. Reboot, Shutdown and Terminate
  also request explicit dirty disposition; cancel preserves editor/controller.
- Closing/reopening the GUI retains the draft and controller. This is not a save.

Targets must be local files or new files in existing local directories. `/`,
directories, `/rom` and its descendants, missing parents and files larger than
32 KiB are refused. The draft is capped at 32 KiB; program execution has a tighter
16 KiB ceiling. Navigation/rendering are byte-cell based, not a Unicode editor.
The terminal shows a viewport and save/error status, not a second input widget.
Native graphical shortcut interception, clipboard and focus still need testing.

Save is an admitted filesystem job: it stages and validates a complete candidate,
then replaces the committed disk atomically. Only the selected file is replaced;
ordinary `cp`/`mv` still refuse an existing destination. Disk/path/node quotas are
unchanged. The baseline is the exact old content (or absence for a new file).
A changed target or committed disk invalidates publication instead of overwriting
another writer. Errors retain the dirty draft and old committed files. A failed
conflict does not rebase silently: deliberately discard/reopen after recovering
any wanted text. Canceling an unpublished save discards its candidate, not its
draft. A cold reload before/after publication cannot publish twice.

After saving, Ctrl+Q returns to the shell:

    run /stock.lua
    ps
    stop

Direct `/stock.lua` invocation also works. Run requires committed local source;
ROM examples must first be copied locally. There is one controller per computer.
Explicitly stop before replacement, including replacement of a faulted controller.
A failed compile does not replace the old record. Editing/saving its path does not
change the active source snapshot; stop/run selects the newly committed bytes.
No REPL, auto-start, modules or general Lua environment is provided.

## Complete supported language

The top level contains exactly one literal descriptor return, with optional
semicolon no-ops before/after it. Named fields are only `interval`, `on_start`
and `on_tick`, without duplicates. At least one handler is required. `interval`
is a literal integer 1–3600 simulation ticks, default 60; computed initializers
are rejected. Handlers must be function literals with exactly `(event, state)`.

    return {
      interval = 60,
      on_start = function(event, state)
        state.starts = (state.starts or 0) + 1
        print("Started")
      end,
      on_tick = function(event, state)
        state.ticks = (state.ticks or 0) + 1
      end
    }

Handlers support:

- Scalar local declarations and assignments, including multiple assignments.
- Literal-identifier `state.FIELD` reads/writes and `event.tick`/`event.name` reads.
  Absent state fields read nil; assigning nil removes a field.
- `if`/`elseif`/`else`, lexical `do` blocks, semicolon no-ops and return of at most
  one scalar. Handler return values are ignored.
- Nil/boolean/finite numeric/string literals and parentheses.
- Arithmetic `+ - * / % ^`, comparisons `== ~= < > <= >=`, `and`, `or`, unary
  minus, `not`, string length `#`, and concatenation `..`.
- Direct `print`, `math.floor`, `math.abs`, `math.min`, `math.max`, and the three
  circuit calls below. Print accepts scalar arguments, including false/nil;
  floor/abs require one number; min/max require 1–64 numbers.

Every other AST form is refused: all loops, goto/labels, recursion, nested/local
functions, aliases of API functions, method calls, computed indexing, general
tables, variadics, modules, load/require, metatables, arbitrary globals and binary
chunks. There is no game/entity/inventory/network/HTTP access. No callable or
engine reference can be stored in state or returned by an exposed service.

Hard ceilings: source 16 KiB; 1024 validated AST nodes; 256 statements; nesting
16; emitted wrapper 64 KiB; cumulative emission-copy work 128 KiB; 64 state keys
of at most 64 bytes (`[A-Za-z_][A-Za-z0-9_]*`); scalar strings at most 256 bytes;
state string payload at most 16 KiB. Numbers/results must be finite. Concatenated
strings and rendered print records are capped at 256 bytes. Each handler path
has at most 8 print calls and 16 circuit calls. Fresh whole-work quotas can refuse
source below these ceilings: these are limits, not a promise of simultaneous
acceptance of every maximum. Source errors include bounded path/line/column
positions; runtime errors include the active path and a bounded diagnostic.

## Native execution and transactions

Bounded Phobos analysis builds an ephemeral AST. A default-deny validator emits
trusted native expressions/branches and closed checked service calls. Only that
fresh emitted wrapper enters text-only `load` in an empty environment. Player
source, saved generated text and ASTs are never executed. Closures/caches are
never saved. Cold synchronized dispatch revalidates/re-emits exact retained
source under the same reservation as warm dispatch; on_load does no work.

Compile reserves the existing compiler quantum, 196608 string work, 262144 table
work and one execution unit. Each whole callback reserves compiler quantum,
2048 execution, 262144 string, 524288 table, 8192 event and 65536 filesystem work
before any handler runs, including cold reconstruction. Syntax-derived costs
must also fit the unchanged fresh per-computer limits. All reservations use the
same per-machine AND aggregate ledger as shell input, saves and original VM
neighbors. Insufficient credits defer the complete event without state/output
mutation or same-tick renewal. These work units are not CPU-time guarantees.

Callbacks copy scalar state and output banks and stage print records. Successful
validation/publication commits them together. An arithmetic/API/state/FIFO error
publishes none of those staged changes, faults visibly and clears owned outputs.
Unexpected engine exceptions after a port write cannot promise arbitrary engine
rollback: the host clears only its private sections and retries failed cleanup.
Background prints use a 64-record/16 KiB FIFO. They are painted only when the
shell owns the screen, never over editor rows. A full FIFO faults rather than
silently overwriting queued text or growing memory.

After initial on_start (or an empty initial event), a periodic controller runs
at most one due on_tick per admission. Deadlines are absolute simulation ticks;
the next deadline is based on the successful tick, without a catch-up storm.
An on_start-only descriptor stops after its one successful event. Reload cannot
replay an already committed start. Power loss pauses and clears private outputs;
restoration evaluates a fresh due handler before republishing control signals.
Stop/reboot/shutdown/removal/ownership invalidation also clear private outputs.
Priority cleanup spends the original ledger before ordinary dispatch, not a
second quota pool. `cleanup_checks.lua` exercises simultaneous transitions on
512 real port pairs using explicitly synthetic admission clocks; this is a
resource/cleanup oracle, not a many-computer graphical latency measurement.

## Circuit API and factory layout

Blue bodies own left/right `computer-combinator` ports only, without the original
speaker/lamp bundle. The host validates body/child registry identities, research,
force, surface, power, generation and private manual-section ownership. Only
those private sections may be modified. Player sections and unrelated entities
are not output banks. Lifecycle repair does not reconnect player wires.

    circuit.read(side, wire, type, name)
    circuit.write(side, type, name, count)
    circuit.clear(side)

`side` is `left` or `right`; read `wire` is `red` or `green`; type is `item`,
`fluid` or `virtual`; name must identify a known prototype. Read returns one
normal-quality scalar count, zero for a disconnected valid port. A missing,
stolen or unauthorized port faults instead of returning zero. Non-normal quality
is not exposed. Write stages an int32 count (-2147483648 through 2147483647),
replacing that identity; zero removes it. Clear stages an empty bank for one side.
Each side retains at most 32 identities, including accumulation across events.
Publication validates both targets before its first write. A read can see the
computer's own output if it shares that network: red/green networks and the two
ports are distinct; keep input/output wiring separate to avoid feedback.

Reproducible stock-controller layout:

1. Connect a read-enabled chest to LEFT using red wire. Enable the chest's
   circuit read-contents behavior. This is the destination stock, not the feeder.
2. Put an electrically powered inserter between a feeder chest and that stock
   chest, with pickup at the feeder and drop at the stock chest.
3. Connect RIGHT to that inserter using a separate red network. Enable circuit
   control with virtual `signal-A > 0`. Do not connect LEFT to RIGHT.
4. Copy/edit the example as above. Change `stock < 100` to `stock < 5`, Ctrl+S,
   Ctrl+Q and run it. The file actually saved is what runs.
5. Below five normal iron plates, signal-A is 1 and the inserter transfers stock.
   At 25 plates (above 5 but below the original 100), signal-A is absent/zero and
   transfer stops. Allow an already-held item to finish dropping before measuring
   stable inventory; polling every 60 ticks is not a zero-overshoot limiter.
6. Check `ps`, then `stop`. Test power loss/restoration and save/reload: no start
   replay or stale enabling before a fresh evaluation. The example keeps a scalar
   `starts` count and last observed `stock` for inspection.

## Persistence, copies and evidence

Old 0.3.0 blue sessions acquire optional application fields only in admitted
work; no program automatically starts. Editor/controller records are separately
versioned plain data. Unsupported records remain inert recovery data instead of
being converted/executed. Clones/blueprints copy committed files only, never a
dirty draft, active controller, state/deadline, FIFO or active output. Keep an
untouched backup; rollback means restoring that backup with its matching build,
never downgrading an upgraded save.

Tests: `tests/shell-mod/write_checks.lua` covers conflict/quota/maximum metadata,
zero-credit writes and cold publication; `editor_checks.lua` covers native
controls, failed-save drafts, lifecycle cancellation and cold input/save identity.
`tests/program-mod/control.lua` exercises genuine editor/save/source execution,
separate-process reconstruction and actual simulation-tick neighbors.
`transaction_checks.lua` uses explicitly synthetic clocks for functional
exact/one-short admission, scalar semantics, staged-fault and FIFO/state bounds.
`circuit_checks.lua` exercises real owned ports, registry refusal and bank bounds;
its second-target exception is injected, not a claim of actual engine reentrancy.
`factory_checks.lua` uses actual chest/inserter entities and production runtime
consumers, including the deliberately edited threshold and cold stop sequence.
It also samples an actual original VM input neighbor on the same host ledger;
the poison guard permits that exact VM identity only, never native fallback.
`recovery_checks.lua` persists incompatible drafts/controllers/jobs/FIFOs and
checks zero-credit inactivity plus admitted recovery without losing their graphs.
Its exhaustive small FIFO-index oracle rejects sparse queues independently of
Lua's ambiguous array-length behavior.

The released-save upgrade scenario creates a snapshot using the actual 0.3.0
shell-only ZIP, switches to the candidate, then cold-reloads a second snapshot
with a dirty editor, unpublished save, controller, queued print/input and spent
work. A test-fixture version change forces configuration reconciliation without
changing the candidate's release metadata. Run it in base and expansion:

    python tests/run_engine.py --blue-upgrade --baseline-archive RELEASED.zip --archive CANDIDATE.zip --output FRESH_DIRECTORY

Use a fresh output directory for each run. Preserve failed attempts separately.

The factory fixture also registers the body with the actual mod so its orphan
sweep recognizes ports used by isolated host consumers. It supplies a real power
grid and tests body-buffer loss through the production powered check. These are
headless component/integration oracles, not graphical or two-peer acceptance.
Run `--programs` in base and `--expansion`; use `--archive` for exact ZIP evidence.
Terminal-model echo is distinct from keyboard/GUI/render/network latency. Keep
client checklist items unchecked until a licensed graphical client and real
joining peer have actually exercised them. No complete acceptance is claimed.
