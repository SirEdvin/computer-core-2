# Terminal and event feasibility contract

The live workbench is unchanged. These services belong to the isolated guest VM;
actual upstream shell/editor engine evidence is recorded separately in
GUEST_RUNTIME.md and EDITOR_FEASIBILITY.md. Neither these checks nor the saved-size
checks below establish client rendering, actual input capture or multiplayer joining.

## Native byte-cell terminal

`computer-core-terminal-columns` and `computer-core-terminal-rows` are mod-wide
startup integer settings, defaulting to 51 and 19. Current model/resource limits
are 1–160 columns and 1–60 rows. The engine exercises default, 80×24 and both
model boundaries. These bounds are provisional for graphical use: task 4.3 must
establish the final supported shell/editor/rendering range before cutover. Every
new VM uses the same startup settings; display scale is not an input to geometry.

Cells retain source bytes and independent hexadecimal foreground/background
palette indices. The default 16-entry palette matches the vendored colors
module's defaults. Changing a palette invalidates visible rows but does not
rewrite cell indices or file contents. No glyph substitution happens in this
model; the future renderer must document fallback without changing these bytes.

Supported native methods: write, blit, clear, clearLine, getSize, getCursorPos,
setCursorPos, scroll, get/setCursorBlink, isColor, get/setTextColor,
get/setBackgroundColor and get/setPaletteColor. Corresponding Color/Colour aliases
are provided. Color setters require one of the 16 single-bit masks. Palette
setters accept a packed 24-bit integer or three finite channels in [0,1]; getters
return three channels. Cursor/scroll inputs must be finite coordinates within
signed 32-bit magnitude and are floored. Off-screen cursors are retained.

Writing clips to visible intersections, advances by the full byte length, and
does not wrap. Blit requires three equally sized strings and lowercase 0–f color
indices. Validation occurs before mutation. Positive scrolling moves rows up;
negative scrolling moves them down. Exposed cells use current colors. Even a
very large scroll performs only one pass over the bounded display. The native
bridge does not implement a second application editor, wrapping or windows.

## Upstream terminal helper integration

The source-only guest harness runs the actual pinned `startup/15_term.lua`,
`rc.thread`, `cc.expect`, colors/colours, window, textutils and paintutils modules
from the read-only ROM. It creates a guest-owned startup object and a targeted
module registry, not host mocks or fake peripheral/world services. The separate
full BIOS/package/shell/editor probe now passes task 4.1; its acceptance is not
inferred from this targeted helper probe.

Native cells are the backing display for upstream windows. The fixture nests a
negatively positioned child in an invisible parent, checks retained byte/color
clipping, verifies the real outer surface stays unchanged while hidden, and then
reveals the parent and verifies redraw. It redirects the upstream term wrapper
through parent and child targets, writes via `term.at`, and restores the original
native target. The engine reads the resulting native byte/foreground/background
cells and verifies an actual paintutils filled box paints both color channels.

Two narrow upstream patches are reproduced in the vendor ledger. Keys select
the shipped LWJGL3 identifiers without spoofing a Minecraft `_HOST`. Thread
terminal get/set operations use the same boot/current-tab context so a redirect
before scheduler startup works and returns the previous native target. Active
scheduler/thread behavior is exercised during OS boot. The same tracked thread
patch updates tab geometry before propagating term_resize, so applications redraw
against the new size instead of seeing a stale tab window for one scheduler loop.

`string.format` is a scalar-only symbolic native helper needed by real upstream
expect/color/window code. Templates are limited to 4,096 bytes; parsed field
width/precision and string operands are bounded before host formatting, and the
complete result cannot exceed 65,536 bytes. Ordinary Lua numeric/string/quoted
conversions and `%%` are supported; host objects, pointers and unsupported
conversions are rejected. Formatting errors are recoverable through guest pcall.
This per-operation bound does not complete the aggregate host-work/compiler gate
in task 2.4.

## Ordered events, termination and timers

The VM supports os.queueEvent, os.pullEvent, os.pullEventRaw, os.startTimer,
os.cancelTimer, os.sleep, sleep and os.clock. These are virtual services only:
no native IO, processes, wall clock or world API is exposed.

Queued payloads have explicit tuple arity, preserving interior and trailing
nils. Guest objects keep their guest reference identity and are roots during
incremental collection. Host admission accepts scalar data only and copies the
admitted tuple; it cannot inject host functions, objects or arbitrary tables.
The engine verifies an object remains reachable solely through a queued event.

Limits: 256 queued events, 65,536 payload bytes, 1,024 tuple values and 256 active
timers per VM. New guest queueing beyond quota raises an ordinary recoverable
error without changing existing tuples. Host ingress rejects newest input and
returns false plus an error, rather than throwing into the engine event handler.
A dropped-event counter records overflow. Host lifecycle controls can use priority
admission, evicting newest queued events as needed and entering before input;
guest queueEvent cannot request this privilege. Resize uses that path so it stays
admissible under pressure. No exclusive input owner is introduced.

Normal waits discard nonmatching events and raise `terminated` on termination,
including while filtered or sleeping. Raw waits receive termination even with a
filter. Waiting stores the coroutine reference, continuation and filter as plain
data; guest execution stops until an admitted matching event is available.
Nested/protected call frames remain attached. The scheduler keeps serving other
machines. A selected-OS root event loop can explicitly enable main-coroutine
yield as a raw event wait, supporting Recrafted's scheduler convention without
changing ordinary virtual child-coroutine yield/resume behavior.

Timers derive from supplied synchronized simulation ticks at 60 ticks/second.
Durations must be finite, nonnegative and at most one simulation day. Zero waits
fire at the next tick, never inline. Due timers are admitted in deadline order,
then ascending ID. IDs are stable and never reused. Cancel removes an active
timer and any queued but undelivered tuple. Queue pressure leaves a due timer
pending for retry, rather than losing a sleep wakeup. Sleep waits for its own
timer ID, not another timer. The engine saves a live wait and timer, reloads in a
separate process, resumes with a nil-containing event tuple and completes sleep.

## Saved display reconciliation

VM.reconcile_configured binds saved computer displays to actual startup settings
at synchronized configuration-change, scheduler dispatch, VM run/advance and host
input admission boundaries, never in on_load. Booted OS instances are bound even
when initialized with explicit test dimensions. Standalone VM.new test grids with
explicit dimensions are detached; a missing binding field in an older compatible
graph defaults to startup binding. VM.reconcile is the validated model/event
primitive beneath that policy. It preserves overlapping cell bytes/colors, palette, current colors,
cursor/blink and guest execution. New cells use current colors; removed cells
are clipped without touching disk data. A changed geometry admits one
term_resize before existing/new input; identical geometry does not queue one.

The scheduler reconciles even when the current dispatch performs collection only.
The queue bridge performs reconciliation before admitting new input, without
executing the suspended guest. Repeated reconciliation is idempotent. Priority
resize admission remains bounded and can evict newest events under queue pressure.
Collection, frame/coroutine identities and local disk state are not reset.

tests/run_engine.py accepts --reload-columns/--reload-rows with --guest. Between
the initial-save and reload processes, the isolated test mod changes data-stage
setting defaults/allowed values. The guest probe asserts actual settings.startup
values; these are not substituted runtime dimensions. Equal integer setting
minimum/maximum values are rejected by the pinned engine, so this harness uses
allowed_values to enforce the new size. This is only test-mod scaffolding; the
shipped settings retain their provisional model bounds.

Packaged Factorio 2.0.77 acceptance passes:

- Base 51x19 -> 51x19 and expansion 80x24 -> 80x24: 82 initial / 122 cumulative
  reload checks, including no synthetic resize with unchanged settings.
- Base 51x19 -> 80x24 and expansion 80x24 -> 51x19: 82 initial / 124 cumulative
  reload checks. Both changes preserve the actual dirty advanced-editor draft,
  redraw its status at the new bottom row using term_resize alone, and then save,
  reopen and execute the unchanged program via the real shell.
- Existing workbench base/expansion: 154 initial / 155 cumulative reload checks.

A separate waiting probe retains independent byte/color cells, palette, current
colors, off-screen blinking cursor, captured data and disk contents. It saves with
collection in progress and queued old input; reload observes exactly one resize
before old/new input, with no reboot. Saved instruction/display-revision checks
run before configuration reconciliation or tick work, verifying that on_load did
neither. The on_load handler still only sets an ephemeral flag.

Reproductions:

    python3 tests/run_engine.py --guest --reload-columns 80 --reload-rows 24
    python3 tests/run_engine.py --guest --expansion --columns 80 --rows 24 --reload-columns 51 --reload-rows 19

The initially stricter event-only redraw probe failed: the upstream scheduler
resized its outer wrapper, resumed the editor against old tab dimensions, then
resized the tab on its next loop. The two-line vendor scheduler correction and
its source/hash ledger reproduce exactly; editor logic remains unchanged. Task
3.5 is complete at guest-service scope. Opening or closing the existing workbench
still does not use this experimental VM, and section-4 graphical/client gates
remain blocking before cutover.
