# Computer Core 2 0.4.1 — ALPHA input controls and interactive Lua

Experimental playtest, not stable/full CraftOS acceptance. Back up saves and never
downgrade a migrated save. Original/personal VM/Recrafted behavior is retained.

## What changed

- Blue editors have native Save / Exit editor and dirty Save / Discard / Cancel.
  Focused Factorio text capture suppresses custom shortcuts; Ctrl+S/Q are not
  required for these actions and focused shortcut delivery is not claimed fixed.
- Every terminal has one key selector and Send key for Tab, Enter, Backspace,
  Delete, arrows, Home/End and Page Up/Down. Original/personal terminals additionally
  expose Editor menu: select/send it, then type s to save or e to exit.
- Blue `lua` enters a restricted native interactive session. Try `1+2`,
  `math.floor(4.9)`, `state.n=7`, `state.n`, `print("hello")`, then `exit` or
  Exit Lua. Stop a background controller before entering.
- Submissions are finite expressions/statements, not general Lua. Persistent
  scalar `state.FIELD`, math, print and the existing owned left/right circuit API
  are available. Locals last for one submission. No loops, user functions,
  recursion, modules, raw source execution, VM or continuation fallback.
- Each submission uses the existing shared work ledger and transactional
  state/print/signal publication. Refused submissions remain recoverable without
  publishing staged effects. Session/input/deferred work survive close/reopen
  and cold reload; copies contain only committed files. Explicit exit/lifecycle
  operations clear owned outputs.

## Exact archived verification

Factorio 2.0.77; the same deterministic 184-entry ZIP passed all 12 cases, with
40 clean engine processes, no forced kills and all completion markers. Base and
Space Age expansion configurations each exercised:

| Fixture | First / reload checks |
| --- | --- |
| Original/personal VM editors + table-backed native GUI consumers | 465 / 597 |
| Blue shell + real fixture configuration change | 245 / 309 |
| Native editor/compiler/REPL/circuit/factory + cold recovery | 199 / 248 |
| Real-tick shared shell/VM stress | 11 / 50 |
| Exact published 0.3.0 save upgrade | 1 / 6 / 10 cold |
| Exact published 0.4.0 save upgrade | 1 / 6 / 10 cold |

44 Python tests, strict OpenSpec validation and resource/package provenance pass.
Original vendor/VM ROM hashes remain unchanged. REPL fixtures cover false/nil,
8 KiB input, scalar/session/local semantics, syntax/runtime refusal, effect
rollback, real owned circuit reads/writes/power/ownership cleanup and exhausted
same-tick cold reconstruction without replay. Native key clicks feed actual
shell/blue-editor/VM-editor consumers; table-backed GUI tests are not client proof.

Archive: `computer_core_2_0.4.1.zip`

SHA-256: `9853b3fc932d4da3c0b8c0ffa7d1dfe525cda430cd3aac2c1a31331c7089c300`

Evidence: `blue-release-0.4.1-verified-matrix-v2.json` under the Albina scratch
workspace, with every case's result/logs. The earlier matrix is retained: an old
shell fixture incorrectly required `lua evil.lua` to be an unknown command.
Updated it to require the new no-arguments refusal and no REPL/controller creation;
no production quota or behavior was relaxed. The complete fresh matrix then passed.

## Still unverified

Licensed graphical rendering/focus/clipboard/physical shortcut behavior and a real
multiplayer joining peer remain separate blocking acceptance gates. Headless
engine and table-backed GUI checks do not satisfy them. No merge or OpenSpec
archive is authorized or implied. See BLUE_AUTOMATION.md and PLAYTEST.md for usage
and the unchecked client checklist.
