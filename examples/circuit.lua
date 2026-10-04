-- Physical computers only: red-wire input on the left, output on the right.
return {
  init = function() os.wait("sample", 0) end,
  sample = function()
    local signals = lan.readLeftSignals("red")
    lan.writeRightSignals(signals)
    state.samples = (state.samples or 0) + 1
    os.wait("sample", 0.1)
  end
}
