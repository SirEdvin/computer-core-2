# API reference

All programs have native safe Lua functions/libraries, `state` (durable plain table),
`args` (startup arguments), `print` (terminal write), `require` (alias of os.require),
and source-only `load`. No `game`, `script`, `remote`, filesystem IO, debug library,
bytecode dump or coroutine persistence is exposed to player programs.

## os

- `getComputerID()`, `getComputerLabel()`, `setComputerLabel(label)`.
- `date()` returns game ticks; `time()` returns hours on the legacy 25000-tick cycle.
- `set(name, ...)`, `get(name)`, `clear(name)` store durable tuples, including nil holes.
- `pcall(fn, ...)` is protected Lua execution.
- `register(name, fn)` declares a named handler at module scope. Alternatively return
  `{init=function(...) ... end, handler=function(...) ... end}`.
- `wait(name, seconds, ...)` schedules once and returns a timer ID; `cancelTimer(id)`
  removes it. Delay zero means next tick. Due timers order by due tick then timer ID.
  They remain pending while unpowered.
- `require(path)` loads a pure source library relative to the executing source.
  Returns its result; snapshots source for process lifetime. Avoid cyclic dependencies.
- `getWaypoint(name)` returns `{name,x,y}` or nil for the computer's force/surface.

## term and disk

`term.write(...)` / `term.setOutput(...)` append a line; tables print as bounded JSON.
`getOutput()`, `setInput(text)`, `getInput()`, `read()` (output+input), `clear()`.
`addInputListener(name)` and `addOutputListener(name)` return stable IDs;
`removeListener(id)`. Input handler receives `{listenerID,userInput,player_index}`;
output handler receives `{listenerID}`. Output notifications are deferred to ticks.
Do not endlessly print from an output listener.

`disk.readFile(path)`, `writeFile(path,...)`, `appendFile(path,...)`,
`removeFile(path)`, `fileExist(path)`. Paths are source-relative. Writes create missing
parent directories. Mounted paths use `/mnt/<label>/...`. Root/virtual directories
cannot be replaced or removed. Shell paths instead use terminal cwd.

## lan (physical computers)

`readLeftSignals([wire])`, `readRightSignals([wire])`,
`writeLeftSignals(signals)`, `writeRightSignals(signals)`.
Aliases: `getLeftSignals`, `getRightSignals`, `setLeftSignals`, `setRightSignals`.
Wire is `"red"` or `"green"`; omitted reads this computer's own outputs. Read/write shape:

```lua
{{signal={type="item",name="iron-plate",quality="normal"},count=42}}
```

Types: item/fluid/virtual; defaults item/normal. Counts are floored signed 32-bit
integers. Setting replaces the entire side's output. `stop` clears both sides.

## wlan

`on(event,name,...)` registers a handler and trailing saved arguments.
`emit(label,event,...)` sends to a label; `broadcast(event,...)` sends to eligible peers.
They return the number of queued target computers. Receiver arguments are message
arguments followed by subscription arguments. Only running receivers are queued;
stopping/restarting discards messages from the old generation.

`onBuiltComputer(name,...)` receives `{computerID,position,surface_index,autorun}`.
`event.autorun(source,[path])` starts source on that new powered computer once;
it does not accept functions. Do not store the transient autorun function in state.

## speaker (physical computers)

`print(text,[toForce])` prints to force by default; false selects the current authorized
operator. `getInstruments()` returns engine instrument/note definitions.
`playNote(note,[instrument,volume,polyphony])`: names or 1-based instrument/note IDs,
volume 0..1. `setAlert(text,signal,[sound])`: name or 1-based alarm note.
`mute()` disables sound/alerts. `stop` also mutes. Audible results require client tests.

## Companion mods

Use one remote identity, preferably `computer_core_2` (the `computer_core` alias has
identical methods). These are trusted-mod APIs, not a player authorization boundary.

- `addComputerAPI(source)` / `removeComputerAPI(name)` register/remove source definitions.
- `registerEntity(entity)` or `addEntityStructure({entity,type,sub={...}})` attach an
  entity matching a registered selector. `sub` contains string-keyed LuaEntity refs.
- `getComputerIDs()`, `getComputer(id)` (copied data), `getEntity(id)`, `getPorts(id)`.
- `run(id,source,[path,args])`, `stop(id)`, `exec(id,line)`, `input(id,text)`.
- `open(id,player_index)`, `openGauntlet(player_index)`, `snapshot(id)`.

Extension source returns `{name,entities,prototype,events}`. `entities` is an array of
prototype names, a pure predicate taking LuaEntity, or nil (all computers).
`prototype` entries are `{helpText,function(self,...) ... end}`; underscore-prefixed
methods are private. `__init` runs once on program start. `events.on_tick(self,event)`
and `events.on_script_kill(self)` are supported. Also supported:
`on_message(self,eventName,...)`, custom wireless event callbacks,
`on_built_computer(self,event)`, `on_gui_text_changed(self,event)` with `userInput`,
and `after_text_print(self,event)` with `output`. Events are transient data, not
persistent GUI references. Public calls use `api.method(...)`.
Instance helpers: `__entity`, `__entityStructure`, `__env`, `__state`, `__getID()`,
`__getLabel()`, `__getGameTick()`, `__getAPI(name)`, `__getWaypoint(name)`,
`__emit(label,event,...)`, `__broadcast(event,...)`, `__getOutput()`, `__setOutput(text)`, `__getInput()`, `__setInput(text)`,
`__setLabel(label)`, `__require(path)`, `__readFile(path)`, `__writeFile(path,...)`,
`__removeFile(path)`, `__fileExist(path)` and dynamic `__player`.
An extension can access engine objects; installing one is a trust decision.
