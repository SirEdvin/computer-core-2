local values = {3, 1, 2}
assert(table.insert(values, 2, 9) == nil)
assert(#values == 4 and values[2] == 9 and values[3] == 1)
assert(table.remove(values, 2) == 9 and #values == 3)
table.insert(values, 4)
assert(table.remove(values) == 4)
assert(not pcall(table.insert, values, 0, 1))
assert(not pcall(table.remove, values, 99))
assert(not pcall(table.insert, values, math.huge, 1))
assert(table.remove({}) == nil)
assert(table.remove({[0] = 'zero'}) == 'zero')
local tail = {1, 2}
assert(table.remove(tail, 3) == nil and #tail == 2 and tail[2] == 2)
table.sort(values)
assert(table.concat(values, ',') == '1,2,3')
table.sort(values, function(a, b) return a > b end)
assert(table.concat(values, ',') == '3,2,1')
local names = {'20_io.lua', '00_fs.lua', '15_term.lua', '10_package.lua'}
table.sort(names)
assert(table.concat(names, ',') == '00_fs.lua,10_package.lua,15_term.lua,20_io.lua')
local meta = {__lt = function(a, b) return a.rank < b.rank end}
local objects = {setmetatable({rank=2}, meta), setmetatable({rank=1}, meta)}
table.sort(objects)
assert(objects[1].rank == 1 and objects[2].rank == 2)
assert(not pcall(table.sort, values, false))
local prior = table.concat(values, ',')
assert(not pcall(table.sort, values, function() error('comparison failed') end))
assert(table.concat(values, ',') == prior)
assert(not pcall(table.sort, values, function() return true end))
local sorting = coroutine.create(function()
  local values = {4, 2, 3, 1}
  table.sort(values, function(a, b) coroutine.yield('comparison'); return a < b end)
  return table.concat(values, ',')
end)
local comparisons = 0
local sparse = {1, 2, 3}
sparse[2] = nil
assert(rawlen(sparse) == 1)
sparse[2] = 2
assert(rawlen(sparse) == 3)
sparse[5] = 5
assert(rawlen(sparse) == 3)
sparse[4] = 4
assert(rawlen(sparse) == 5)
repeat
  local ok, value = coroutine.resume(sorting)
  assert(ok)
  if coroutine.status(sorting) == 'dead' then assert(value == '1,2,3,4')
  else assert(value == 'comparison'); comparisons = comparisons + 1 end
until coroutine.status(sorting) == 'dead'
assert(comparisons > 0)
return 'table-helpers-pass'
