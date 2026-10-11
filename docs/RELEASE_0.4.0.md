# Computer Core 2 0.4.0 — ALPHA native automation playtest

This is a user-authorized experimental release, not stable or completed graphical/multiplayer acceptance. Back up saves, test a separate copy and never downgrade an upgraded save.

## New on blue computers

- Native multiline `edit PATH`, recoverable drafts, Ctrl+S save and Ctrl+Q save/discard/cancel.
- Atomic conflict-safe saves and dirty reboot/shutdown/termination handling.
- Committed `.lua` files execute as restricted event-driven controllers: `run PATH`, direct `.lua` invocation, `ps`, `stop`.
- Default-deny AST validation emits trusted native Lua. No arbitrary Lua, user modules, VM fallback or experimental continuation fallback.
- Owned left/right circuit ports, bounded scalar read/write/clear and fail-safe output cleanup.
- An editable stock-controller example controls a real circuit-wired inserter from chest contents.
- Original and personal VM computers retain their Recrafted shell/editors and saved execution.

## Try the stock controller

Research Computer, place and power the blue computer, then Ctrl+left-click within ten tiles. Wire a read-enabled iron-plate chest to the left red network and a circuit-controlled inserter to a separate right red network. Enable the inserter when signal-A > 0.

    cp /rom/examples/stock-controller.lua /stock.lua
    edit /stock.lua

Edit the threshold; Ctrl+S saves, Ctrl+Q exits. Then:

    run /stock.lua
    ps
    stop

See `docs/BLUE_AUTOMATION.md` for the exact layout, supported descriptor/handler grammar and resource limits. This is restricted Lua automation, not a general Lua OS or CC:Tweaked compatibility.

## Exact release verification — October 11, 2026

Factorio 2.0.77 headless, base and expansion. Two independent deterministic ZIP builds were byte-identical, with 184 entries:

    computer_core_2_0.4.0.zip
    SHA-256 71fa51e8bdb2a77fc4537a5f1a27d3ff4c7910fe2c26095135c87e9edc8fe7fa

All ten scenario/configuration combinations passed. All 32 engine processes exited zero without forced kills and with required markers present. Counts after reload are cumulative, not additional assertions:

| Suite, each configuration | Initial | Cumulative reload | Third cold process |
| --- | ---: | ---: | ---: |
| Native programs | 156 | 194 | — |
| Shell/configuration change | 245 | 309 | — |
| Original VM/GUI mocks | 423 | 555 | — |
| Shell stress | 11 | 50 | — |
| Released blue-save upgrade | 1 | 6 | 10 |

41 Python tests, resource/provenance verification and strict OpenSpec validation passed. Original VM ROM and pinned vendor resources remain unchanged.

The upgrade test starts with the actual published 0.3.0 archive, SHA-256 `0fc551cdf4c4e563cbfcc45a05b842fe00e34eefc77dd8734505610bd36130d9`, switches to the 0.4.0 release ZIP, then cold-reloads pending save/editor/controller work. The first release matrix exposed a runner-only baseline-folder assumption; its failed attempts were retained, the runner was fixed, and both upgrade cases passed in fresh directories. No production ZIP bytes changed for that runner fix.

## Still unverified

- Licensed graphical-client focus, clipboard, shortcuts, rendering, visible factory wiring and rendered latency.
- Real multiplayer peer joining during dirty editing and pending credit-exhausted save/controller work.

Headless persistence and GUI mocks do not substitute for these checks. OpenSpec tasks 5.2 and 5.3 remain unchecked; publication does not authorize merging or archiving the change. The preceding 0.3.0 and pre-publication candidate evidence remains historical and has different archive checksums.
