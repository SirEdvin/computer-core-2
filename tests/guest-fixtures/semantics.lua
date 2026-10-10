local function make(n)
  return setmetatable({n = n}, {
    __index = function(tab, k) if k == "double" then return tab.n * 2 end end,
    __newindex = function(tab, k, value) rawset(tab, "written_" .. k, value) end,
    __add = function(a, b) return a.n + b.n end,
    __len = function(tab) return tab.n end,
    __unm = function(tab) return -tab.n end,
    __concat = function(a, b) return a.n .. ":" .. b.n end,
    __call = function(tab, v) return tab.n + v end,
    __tostring = function(tab) return "value=" .. tab.n end
  })
end
local a, b = make(4), make(6)
assert(a.double == 8)
a.test = 11
assert(a.written_test == 11 and a.test == nil)
assert(a + b == 10 and #a == 4 and -a == -4 and a(7) == 11)
assert(a .. b == "4:6" and tostring(a) == "value=4")
local mt = {__eq = function(a,b) return a.n == b.n end,
  __lt = function(a,b) return a.n < b.n end}
local x, y = setmetatable({n = 2}, mt), setmetatable({n = 3}, mt)
assert(x < y and x <= y and y >= x and not (y < x))
assert(x == setmetatable({n = 2}, mt) and x ~= y)
local redirect = setmetatable({}, {__index = {hello = false}})
assert(redirect.hello == false)
local closures = {}
for i = 1, 3 do closures[i] = function() return i end end
assert(closures[1]() == 1 and closures[2]() == 2 and closures[3]() == 3)
local function multi(...) return select("#", ...), ... end
local count, first, second, third = multi(false, nil, 8)
assert(count == 3 and first == false and second == nil and third == 8)
local n = 3
repeat n = n - 1 until n == 0
while n < 4 do n = n + 1 end
assert(n == 4)
local sum = 0
for i = 3, 1, -1 do sum = sum + i end
assert(sum == 6)
local q = {[a] = 1}
assert(q[a] == 1 and q[b] == nil)
local join
join = {__concat = function(left, right)
  return setmetatable({value = "(" .. left.value .. right.value .. ")"}, join)
end}
local j1, j2, j3 = setmetatable({value = "a"}, join), setmetatable({value = "b"}, join), setmetatable({value = "c"}, join)
assert((j1 .. j2 .. j3).value == "(a(bc))")
local function tail(n, total)
  if n == 0 then return total end
  return tail(n - 1, total + n)
end
assert(tail(1000, 0) == 500500)
local locked = setmetatable({}, {__metatable = false})
assert(getmetatable(locked) == false and not pcall(setmetatable, locked, {}))
local ordered = {a = 1, b = 2}
ordered.a = nil
ordered.a = 3
local visited = 0
for k in pairs(ordered) do visited = visited + 1 end
assert(visited == 2)
local nan = 0/0
local missing = {}
assert(missing[nil] == nil and missing[nan] == nil)
assert(rawget(missing, nil) == nil and rawget(missing, nan) == nil)
local lookup = setmetatable({}, {__index = function(_, key) return key == nil and 'nil-key' or 'nan-key' end})
assert(lookup[nil] == 'nil-key' and lookup[nan] == 'nan-key')
assert(not pcall(rawset, missing, nil, nil) and not pcall(rawset, missing, nan, nil))
return "semantics-pass"
