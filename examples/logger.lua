-- Poll the left green-wire network and retain the last 20 signal-count samples.
-- State is bounded; the log is replaced, not appended forever.
return {
  init = function()
    state.history = {}
    os.wait("sample", 0)
  end,
  sample = function()
    local signals = lan.readLeftSignals("green")
    state.history[#state.history + 1] = tostring(os.date()) .. ": " .. #signals .. " signal types"
    if #state.history > 20 then table.remove(state.history, 1) end
    disk.writeFile("/signal-log.txt", table.concat(state.history, "\n"))
    os.wait("sample", 1)
  end
}
