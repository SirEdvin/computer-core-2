-- rc.keys

local expect = require("cc.expect").expect

-- Host-independent guest key IDs; graphical capture must use this shipped map.
-- Do not spoof a Minecraft _HOST or probe unavailable host environments.
local kmap = "lwjgl3"

local base = dofile("/rc/keymaps/"..kmap..".lua")
local lib = {}

-- reverse-index it!
for k, v in pairs(base) do lib[k] = v; lib[v] = k end
lib["return"] = lib.enter

function lib.getName(code)
  expect(1, code, "number")
  return lib[code]
end

return lib
