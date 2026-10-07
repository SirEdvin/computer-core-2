# Pinned guest resources

This directory is an explicit source-only allowlist, not a running OS or a full
CraftOS distribution. The existing workbench remains active during feasibility.

- Phobos: JanSharp/phobos at `2566dd85807b4f2bdff8e40ba4d79bcf8e96de3f`,
  MIT. Only the parser, jump linker, compiler and their twelve-module dependency
  closure are included. No native executables, native bytecode loader or CLI IO
  tools are included. See `phobos/LICENSE.txt`.
- Recrafted: Ocawesome101/recrafted at
  `720773ec68239504cb134cd4f9b7e8bb66a1408e`, MIT. See
  `recrafted/LICENSE`. `rc/json.lua` retains its complete rxi MIT notice.
  `rc/copy.lua` retains its upstream lua-users CopyTable attribution.

`manifest.json` gives each file's original path, revision, original SHA-256,
installed SHA-256, copyright, license, and license-document path. Guest resources
have explicit virtual paths; the BIOS is separate from the read-only `/rc` ROM.
The manifest's patch ledger records exact unified diffs in `patches/`:

1. Phobos literal requires are namespaced to this mod's compiler modules.
   Compiler options are also propagated into nested prototypes: upstream omits
   the options argument on the recursive call, disabling nested tail calls.
   The guest recursive-tail-call fixture verifies this narrowly scoped fix.
   Jump linking accepts an optional work-charge callback, invoked before body,
   label/goto comparison and nested-function traversal work. The guest compiler
   supplies a per-invocation quota; exhaustion clears temporary linker error
   state and returns a recoverable compile failure. No callback enters stored
   prototypes. Parser work uses a scoped utility callback for source/token bytes,
   scanner and grammar iterations, AST construction, name/upvalue searches and
   array shifts. Variable-width long-string delimiter comparisons are charged
   before matching. A shared block/expression nesting guard bounds recursive
   parser entry. Success and quota exceptions both release temporary parser
   roots and restore the previous callback. Raw bytecode generation shares a
   per-compilation quota across nested functions, charging instruction emission,
   register/constant construction and generator loop iterations, including
   historical-register scans at scope exit. Shared recursive generation guards
   restore temporary depth counters on success and exceptions. Callback and depth
   state do not enter normalized prototypes. Compilation remains synchronous;
   this is not aggregate host-work or production tick-latency acceptance.
2. Recrafted `cc.completion` resolves `peripheral` only when its peripheral
   completion helper is explicitly invoked. Local shell/editor completion does
   not require a fake peripheral module. World completion registrations are
   absent; requests for excluded modules must fail normally.
3. Recrafted `keys` selects the shipped LWJGL3 numeric keymap explicitly rather
   than detecting Minecraft/CraftOS through `_HOST` patterns. The guest does not
   spoof another platform. Actual Factorio input translation remains a client
   gate; this patch only establishes the source-level guest key identifiers.
4. Recrafted `rc.thread` resolves get/set terminal targets through the same
   current-thread or boot-tab context. A redirect before scheduler startup now
   returns the native target for restoration and remains observable through
   `term.current()`. Active-thread setters target their own tab, not the focused
   tab. The actual upstream terminal/window fixture verifies boot-context nested
   redirection and restoration; the BIOS/shell probe also exercises scheduler tabs.
   On `term_resize`, tab geometry is updated before resuming applications, rather
   than one scheduler loop afterwards. The unmodified advanced editor otherwise
   redraws against stale dimensions. Dirty-editor grow/shrink reload probes verify
   the event-only redraw before new input, then save/reopen/run the preserved draft.
5. Recrafted textutils serializes booleans and numbers as Lua literals instead
   of relying on newer `%q` scalar behavior. Finite numbers retain 17-digit
   precision; infinities/NaN use source expressions and strings remain quoted.
   Actual shell-driven settings save/load and scalar round-trip tests verify it.

The ROM includes the BIOS, scheduler, shell, both editors and syntax definitions,
terminal/color/window/paint helpers, settings, filesystem/IO startup modules,
local-file commands and their completions. Keymaps are upstream source data,
not an assertion that Factorio client input has passed acceptance.

Peripheral, network, command/world startup modules, updater/installer programs,
world completions, native resources, and Minecraft artwork are excluded.
The optional Lua REPL/`cc.pretty` is not part of this terminal dependency closure.
No upstream editor logic has been rewritten.

Verify installed hashes and exact inventory:

    python3 tools/verify_guest_resources.py

Also verify original hashes and reproduce every integration patch from pinned
Git objects (not possibly edited working-tree sources):

    python3 tools/verify_guest_resources.py --upstream /path/to/research

The upstream directory must contain `phobos/` and `recrafted/` Git checkouts.
A compiler-only success is not evidence of resumable execution, OS boot,
interactive editing, graphical rendering, or multiplayer joining.
