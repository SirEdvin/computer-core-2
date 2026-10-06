-- Executed in the guest; assertions must not be evaluated by the host.
local sum = 0
for i = 1, 5 do sum = sum + i end
assert(sum == 15)
local function increment()
  local value = 0
  return function(step) value = value + step; return value end,
    function() return value end
end
local inc, read = increment()
assert(inc(3) == 3 and read() == 3)
local alias = {value = 7}
local shared = {alias, alias}
shared[1].value = 9
assert(shared[2].value == 9)
local function passthrough(...) return ... end
local tuple = table.pack(passthrough(1, nil, 3, nil))
assert(tuple.n == 4 and tuple[1] == 1 and tuple[2] == nil and tuple[3] == 3 and tuple[4] == nil)
local total = 0
for _, value in ipairs({2, 3, 4}) do total = total + value end
assert(total == 9)
local function a() return true, false, nil end
assert(table.pack(a()).n == 3)
return "diagnostic-pass", sum, nil, shared[2].value
