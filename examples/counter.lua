-- Durable counter: paste into edit /counter.lua, then run /counter.lua.
return {
  init = function()
    state.count = state.count or 0
    os.wait("step", 0.1)
  end,
  step = function()
    state.count = state.count + 1
    term.write("Count: ", state.count)
    os.wait("step", 0.1)
  end
}
