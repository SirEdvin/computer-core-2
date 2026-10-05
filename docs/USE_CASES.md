# Practical Computer Core 2 programs

These guides and the `examples/` directory are **repository-only**. They are not
included in the mod ZIP and are not preinstalled in the computer filesystem.
Copy a complete example into the in-game editor (Files → New file), save it, and
choose Save & run. Terminal users can enter `edit /circuit.lua` and then
`run /circuit.lua`. Stop the running program before starting another.

## Circuit wiring and signal format

A physical computer has independent **left and right feet**. Attach a red or green
circuit wire to the foot, not the screen/body. A port's output is visible on both
wire colours connected to that port. Read a particular wire colour explicitly.
These are circuit networks, not the roboport logistic network. To observe logistic
contents, wire a roboport configured to read its network contents to a computer foot.

`lan.readLeftSignals("red")` reads the total connected red network. Use `"green"`
to read green, or `readRightSignals` for the right foot. Omitting the wire argument
reads only the computer's own output set; it does not select a connected network.
A disconnected wire read currently falls back to that port's own outputs.

Entries have the following shape:

```lua
{signal = {type = "item", name = "iron-plate", quality = "normal"}, count = 42}
```

Types are `item`, `fluid`, or `virtual`; item/normal are defaults when writing.
Quality is part of signal identity: do not silently combine normal and uncommon
items. Missing signals are absent, not entries with count zero. Counts are signed
32-bit integers. Publishing replaces **all** signals on that side; it does not
append. Stop clears both ports and stops the speaker.

Keep the input and output on separate networks to avoid reading your own output
and creating feedback. Do not connect the left and right feet together unless you
intentionally want a shared network. Poll at a suitable interval instead of every
simulation tick.

## 1. Read and republish a circuit network

Source: [`examples/circuit.lua`](../examples/circuit.lua).

Connect an input constant combinator or a chest to the **left red wire**. Connect
the **right foot** to an output network, using either colour. This program reads
and copies every signal, including type, count and quality, ten times per second.

```lua
return {
  init = function() os.wait("sample", 0) end,
  sample = function()
    lan.writeRightSignals(lan.readLeftSignals("red"))
    os.wait("sample", 0.1)
  end
}
```

Try a constant combinator emitting virtual signal B = 42: the right network should
show B = 42. If no input is connected, the result is an empty output set (provided
you have not published on the left port).

## 2. Publish a value computed by Lua

Source: [`examples/publish.lua`](../examples/publish.lua).

The program increments `state.count` once per second and publishes virtual signal C
on the right foot. Attach a lamp or combinator to that foot. The timer and count
survive save/reload without replaying `init`. Starting it afresh resets the count.

## 3. Request more items below a threshold

Source: [`examples/threshold.lua`](../examples/threshold.lua).

Wire a chest with “Read contents” enabled to the left red foot. The program totals
**normal-quality iron plates** and sets right-port A = 1 below 100 plates, otherwise
publishes nothing. Connect an inserter's enable condition to A > 0. Adjust `TARGET`,
item name and quality in the source for your use case. The example polls twice per
second; it is a simple threshold, not a hysteresis controller.

## 4. Bounded persistent logging

Source: [`examples/logger.lua`](../examples/logger.lua).

Read the left **green** network once per second and retain the latest 20 summaries
in `state.history`. `/signal-log.txt` is replaced with the current ring of samples.
Use `cat /signal-log.txt` in the Terminal to inspect it. This illustrates durable
state and disk access without an ever-growing log exhausting storage.

## 5. Interactive program input

Source: [`examples/input.lua`](../examples/input.lua).

Start it, type a message into the Terminal's **Program input** field, then press
Enter there or choose Send. Typing does not send partial messages. The listener
prints a numbered response and writes `/last-input.txt`. This also works on the
personal computer, which has no physical circuit/speaker APIs.

## 6. Wireless communication between computers

Sources: [`receiver.lua`](../examples/receiver.lua) and
[`sender.lua`](../examples/sender.lua).

Start the receiver first on one computer; it claims the label `example_receiver`.
Start the sender on a second computer in the same force and surface. It sends a
message received on a later tick. Labels must be unique in that force/surface.
No red/green wire is needed. Messages and timers pause without power; restarting a
receiver invalidates queued messages for its previous run.

## Durable programming rules

- Return a table with named handlers, or register named handlers with `os.register`.
- Put startup effects in `init`; declarations and captured locals are reconstructed.
- Put lasting values in `state`, `os.set`, or extension `__state`, never captured locals.
- `os.wait("name", seconds)` schedules once; reschedule in the handler to repeat.
- `init` runs at program start, not after loading a save. Restarting starts a new run.
- Only plain bounded data is persistent. Functions, engine objects and cycles are rejected.
- Only run trusted Lua. An infinite loop can stall the simulation.

Full signatures: [API reference](API.md). Compatibility contract: [migration notes](MIGRATION.md).
