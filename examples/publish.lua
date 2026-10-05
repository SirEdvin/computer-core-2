-- Publish a durable counter as signal-C on the right port once per second.
return {
  init = function()
    state.count = 0
    os.wait("publish", 0)
  end,
  publish = function()
    state.count = state.count + 1
    lan.writeRightSignals({{signal = {type = "virtual", name = "signal-C"}, count = state.count}})
    os.wait("publish", 1)
  end
}
