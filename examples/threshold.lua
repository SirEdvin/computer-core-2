-- Left red wire: iron-plate count. Right port: signal-A = 1 below target.
-- Both output wire colours receive the same right-port signal set.
local TARGET = 100
return {
  init = function() os.wait("sample", 0) end,
  sample = function()
    local count = 0
    for _, entry in ipairs(lan.readLeftSignals("red")) do
      if entry.signal.type == "item" and entry.signal.name == "iron-plate"
        and entry.signal.quality == "normal" then count = count + entry.count end
    end
    state.last_count = count
    lan.writeRightSignals({{signal = {type = "virtual", name = "signal-A"}, count = count < TARGET and 1 or 0}})
    os.wait("sample", 0.5)
  end
}
