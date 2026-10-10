-- Trusted definitions execute as ordinary guest frames, never host table.sort.
return [=[
local maximum = ...
local function size(value)
  assert(type(value) == 'table', 'expected table')
  local n = #value
  assert(type(n) == 'number' and n == math.floor(n) and n >= 0 and n <= maximum, 'table sequence limit exceeded')
  return n
end
local function position(value, first, last)
  assert(type(value) == 'number' and value == math.floor(value) and value >= first and value <= last, 'position out of bounds')
  return value
end
function table.insert(value, ...)
  local n, count = size(value), select('#', ...)
  assert(n < maximum, 'table sequence limit exceeded')
  local index, item
  if count == 1 then index, item = n + 1, ...
  else assert(count == 2, 'expected item or position and item'); index, item = ... end
  position(index, 1, n + 1)
  for i = n, index, -1 do rawset(value, i + 1, rawget(value, i)) end
  rawset(value, index, item)
end
function table.remove(value, index)
  local n = size(value)
  index = index == nil and n or index
  if index ~= n then position(index, 1, n + 1) end
  local result = rawget(value, index)
  for i = index, n - 1 do rawset(value, i, rawget(value, i + 1)) end
  rawset(value, math.max(n, index), nil)
  return result
end
function table.sort(value, compare)
  local n = size(value)
  assert(compare == nil or type(compare) == 'function', 'comparison must be a function')
  compare = compare or function(a, b) return a < b end
  -- Bottom-up merge sort bounds work and uses data-only, resumable guest state.
  -- Keep input untouched until comparisons succeed; comparator errors are safe.
  local source, target = {}, {}
  for i = 1, n do source[i] = rawget(value, i) end
  local width = 1
  while width < n do
    for first = 1, n, width * 2 do
      local middle, last = math.min(first + width - 1, n), math.min(first + width * 2 - 1, n)
      local left, right = first, middle + 1
      for output = first, last do
        if left > middle then target[output] = source[right]; right = right + 1
        elseif right > last then target[output] = source[left]; left = left + 1
        elseif compare(source[right], source[left]) then target[output] = source[right]; right = right + 1
        else target[output] = source[left]; left = left + 1 end
      end
    end
    source, target, width = target, source, width * 2
  end
  for i = 2, n do assert(not compare(source[i], source[i - 1]), 'invalid order function for sorting') end
  for i = 1, n do rawset(value, i, source[i]) end
end
]=] .. require("__computer_core_2__.scripts.guest.patterns")
