# Computer Core 2

Programmable Lua computers for Factorio 2.0: a terminal, filesystem, circuit ports,
wireless messaging, programmable speaker, personal gauntlet and waypoint manager.
A source-based modernization of [Computer Core](https://github.com/Relik77/factorio_computer_core),
retaining its artwork and MIT license. Upstream reference:
`92e4ab616d385dfb0247ce2fc195c0e189b01efd`.

## Install and play

Requires Factorio **2.0.77 or newer**. Automated verification is pinned to 2.0.77,
with both base-only and Quality / Elevated Rails / Space Age configurations.
Use a fresh 2.0 world; old Computer Core saves are not supported. The two mods
cannot be enabled together.

1. Build the archive with `python3 tools/package.py`.
2. Copy `dist/computer_core_2_0.1.0.zip` to your Factorio `mods` directory.
3. Research Personal Computer and Computer. Craft a computer and connect power.
4. Select a computer and press **Ctrl + left mouse button** to open its terminal.
   Stay within 10 tiles. Use **Ctrl + G** or the gauntlet shortcut for your personal computer.
5. Enter `help`, `help apis` or `help os`. Create a script with `edit /counter.lua`,
   paste [examples/counter.lua](examples/counter.lua), then choose Save & run.

The gauntlet requires a character and research; it has no physical circuit ports
or speaker. Computer labels expose same-force/same-surface files under
`/mnt/<label>`. Programs pause without power; overdue timers fire after power returns.

## Durable programs, not serialized closures

```lua
return {
  init = function()
    state.count = state.count or 0
    os.wait("step", 1)
  end,
  step = function()
    state.count = state.count + 1
    term.write(state.count)
    os.wait("step", 1)
  end
}
```

Keep lasting values in `state` or `os.set`. Callbacks use **handler names**, not
function values. `init` runs once at program start, not at load. Program declarations
are reconstructed before every dispatch; captured locals do not carry between
callbacks. Keep module scope free of side effects and state mutations. Pure libraries
loaded with `os.require` are snapshotted with the running program.

See [API reference](docs/API.md), [migration contract](docs/MIGRATION.md),
[client verification checklist](docs/CLIENT_CHECKLIST.md) and [examples](examples/).

## Development and verification

Install the official Factorio 2.0.77 Linux headless distribution separately. No engine
binary is redistributed by this project. Python scripts need only the standard library.

```sh
python3 tests/run_engine.py --factorio /path/to/factorio/bin/x64/factorio
python3 tests/run_engine.py --factorio /path/to/factorio/bin/x64/factorio --expansion
python3 tools/package.py
```

Tests create isolated mod/config/save directories, run the actual engine, save at tick
30 and resume that save. Logs and a machine-readable `result.json` remain in the printed
output directory. `--output <directory>` chooses its location. GUI tests require a
client-created player and are explicitly skipped in playerless headless worlds.
Client appearance, controls, audible playback and multiplayer joining need the checklist;
headless success is not proof of those checks.

Code layout: `data.lua` (modern prototypes), `control.lua` (events/remote interface),
`scripts/` (runtime, filesystem, adapters, lifecycle, shell, GUI), `tests/` (engine harness).
