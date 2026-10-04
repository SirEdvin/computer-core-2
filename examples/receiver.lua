-- Start before sender.lua, on another computer in the same force/surface.
return {
  init = function()
    os.setComputerLabel("example_receiver")
    state.received = 0
    wlan.on("hello", "receive")
  end,
  receive = function(message)
    state.received = state.received + 1
    state.message = message
    term.write(message)
  end
}
