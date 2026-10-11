-- Read-only example text, not a loaded program or automatic startup hook.
return [=[return {
  interval = 60,
  on_start = function(event, state)
    circuit.clear("right")
    state.starts = (state.starts or 0) + 1
    print("Stock controller started")
  end,
  on_tick = function(event, state)
    local stock = circuit.read("left", "red", "item", "iron-plate")
    local enabled = 0
    if stock < 100 then
      enabled = 1
    end
    circuit.write("right", "virtual", "signal-A", enabled)
    state.stock = stock
  end
}
]=]
