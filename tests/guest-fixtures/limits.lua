local ok, err = pcall(function()
  local tab = {}
  for i = 1, 8193 do tab[i] = i end
end)
assert(not ok and type(err) == "string")
assert(not pcall(table.unpack, {}, 1, 1025))
assert(not pcall(table.unpack, {}, math.huge, math.huge))
assert(not pcall(table.unpack, {}, 0/0, 1))
assert(not pcall(table.concat, {[math.huge] = "x"}, "", math.huge, math.huge))
assert(not pcall(table.concat, {[-math.huge] = "x"}, "", -math.huge, -math.huge))
assert(not pcall(table.concat, {}, "", 0/0, 1))
assert(not pcall(function()
  local s = string.rep("x", 32769)
  return s .. s
end))
return "limits-pass"
