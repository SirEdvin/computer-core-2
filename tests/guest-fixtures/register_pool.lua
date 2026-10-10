local function hot(a, b) return a + b, nil, a - b end
local function counter(value)
  return function(delta) value = value + delta; return value end
end
local first, second = counter(7), counter(11)
local scoped = {}
for i = 1, 8 do
  local value = i
  scoped[i] = function() return value end
end
local survived_error
assert(not pcall(function()
  local value = 31
  survived_error = function() return value end
  error('retained closure')
end))
local key = {marker = 17}
local keyed = {[key] = {marker = 23}}
key = nil
local named = {kind = 'table', known = {marker = 29}, order = {marker = 37}}
for i = 1, 1000 do
  local sum, hole, difference = hot(i, 2)
  assert(sum == i + 2 and hole == nil and difference == i - 2)
  local discarded = {i}
end
for i = 1, 8 do assert(scoped[i]() == i) end
assert(first(1) == 8 and second(2) == 13 and first(1) == 9)
assert(survived_error() == 31)
for k, v in pairs(keyed) do assert(k.marker == 17 and v.marker == 23) end
assert(named.known.marker == 29 and named.order.marker == 37)
local function tail(count, ...)
  if count == 0 then return ... end
  return tail(count - 1, ...)
end
local a, b, c = tail(100, 'tail', nil, 7)
assert(a == 'tail' and b == nil and c == 7)
local co = coroutine.create(function()
  local value = 41
  coroutine.yield(function() return value end)
  value = 43
  return value
end)
local ok, retained = coroutine.resume(co)
assert(ok and retained() == 41)
local done, value = coroutine.resume(co)
assert(done and value == 43 and retained() == 43)
return 'register-pool-pass', first, second
