-- Host-only service implementations; installed guest values are plain identities.
local Execution = require('__computer_core_2__.scripts.native.execution')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local Format = require('__computer_core_2__.scripts.guest.format')
local Sort = require('__computer_core_2__.scripts.native.sort')
local Iteration = require('__computer_core_2__.scripts.native.iteration')
local Patterns = require('__computer_core_2__.scripts.native.patterns')
local M = {}
local globals = {'tonumber', 'tostring', 'select', 'ipairs', 'pairs', 'next'}
local tables = {'pack', 'unpack', 'concat', 'sort', 'insert', 'remove'}
local maths = {'abs', 'acos', 'asin', 'atan', 'atan2', 'ceil', 'cos', 'cosh', 'deg', 'exp', 'floor', 'fmod', 'frexp', 'ldexp', 'log', 'log10', 'max', 'min', 'modf', 'pow', 'rad', 'sin', 'sinh', 'sqrt', 'tan', 'tanh', 'random', 'randomseed'}
local strings = {'len', 'sub', 'byte', 'char', 'rep', 'lower', 'upper', 'reverse', 'find', 'match', 'gmatch', 'gsub', 'format', 'dump'}
local bits = {'arshift', 'band', 'bnot', 'bor', 'btest', 'bxor', 'extract', 'lrotate', 'lshift', 'replace', 'rrotate', 'rshift'}
local function text(value)
  assert(type(value) == 'string' or type(value) == 'number', 'string expected')
  local result = type(value) == 'string' and value or tostring(value)
  assert(#result <= Limits.string_bytes, 'native string quota exceeded')
  return result
end
local function index(value, default, spend)
  if value == nil then return default end
  if type(value) == 'string' then spend('string', #value) end
  assert(type(value) == 'string' or type(value) == 'number', 'number expected')
  value = tonumber(value)
  assert(value and value > -9007199254740992 and value < 9007199254740992
    and value == math.floor(value), 'integer expected')
  return value
end
local function range(size, first, last)
  if first < 0 then first = size + first + 1 end
  if last < 0 then last = size + last + 1 end
  first, last = math.min(size + 1, math.max(1, first)), math.max(0, math.min(size, last))
  return first, last, math.max(0, last - first + 1)
end
function M.install(machine)
  if machine.helpers_installed then return end
  for _, name in ipairs(globals) do Execution.service(machine, name) end
  machine.ipairs_iterator = Execution.service_value(machine, 'native.ipairs.step')
  machine.next_iterator = Execution.get(machine, machine.env, 'next')
  for _, group in ipairs({{'table', tables}, {'string', strings}, {'math', maths}, {'bit32', bits}, {'debug', {'traceback'}}}) do
    local library = Execution.table_value(machine)
    for _, name in ipairs(group[2]) do
      Execution.set(machine, library, name, Execution.service_value(machine, group[1] .. '.' .. name))
    end
    Execution.set(machine, machine.env, group[1], library)
    if group[1] == 'string' then machine.string_library = library end
    if group[1] == 'math' then
      Execution.set(machine, library, 'pi', math.pi)
      Execution.set(machine, library, 'huge', math.huge)
    end
  end
  machine.helpers_installed = true
end
function M.services(spend)
  assert(type(spend) == 'function', 'native helper admission required')
  local admission = spend
  spend = function(domain, amount)
    assert(admission(domain, amount) ~= false, 'native helper work quota exceeded (' .. domain .. ': ' .. amount .. ')')
  end
  local services = {}
  -- Host-only admission callback: no identity for this name enters guest globals.
  services['native.work'] = spend
  services['debug.traceback'] = function(_, args)
    -- Match the existing VM's sandbox stub, never host stack inspection.
    spend('continuation', 5)
    local value = args[1]
    if value == nil then value = 'guest traceback' end
    if type(value) == 'string' then
      assert(#value <= Limits.string_bytes, 'native string quota exceeded')
      spend('string', #value)
    end
    return 'return', {n = 1, value}
  end
  services['native.pattern.step'] = function(machine, operation) return Patterns.step(machine, operation, spend) end
  services.pairs = function(machine, args)
    assert(Execution.type(machine, args[1]) == 'table', 'table expected')
    spend('continuation', 16)
    return 'return', {n = 3, assert(machine.next_iterator, 'native next iterator not installed'), args[1]}
  end
  services.next = function(machine, args)
    return Iteration.start(machine, args, admission)
  end
  services['native.next.step'] = function(machine, operation)
    return Iteration.step(machine, operation, admission)
  end
  services.ipairs = function(machine, args)
    assert(Execution.type(machine, args[1]) == 'table', 'table expected')
    spend('continuation', 16)
    return 'return', {n = 3, assert(machine.ipairs_iterator, 'native ipairs iterator not installed'), args[1], 0}
  end
  services['native.ipairs.step'] = function(machine, args)
    assert(Execution.type(machine, args[1]) == 'table', 'table expected')
    local control = index(args[2], nil, spend)
    assert(control, 'iterator control expected')
    spend('table', 8)
    local next_index = control + 1
    local value = Execution.get(machine, args[1], next_index)
    if value == nil then return 'return', {n = 1} end
    return 'return', {n = 2, next_index, value}
  end
  services['table.sort'] = function(machine, args) return Sort.start(machine, args, spend) end
  services['table.sort.step'] = function(machine, state) return Sort.step(machine, state, spend) end
  local function sequence(machine, value)
    assert(Execution.type(machine, value) == 'table', 'table expected')
    local size = 0
    while size < Limits.table_keys do
      spend('table', 1)
      if Execution.get(machine, value, size + 1) == nil then break end
      size = size + 1
    end
    return size
  end
  services['table.insert'] = function(machine, args)
    assert(args.n == 2 or args.n == 3, 'expected item or position and item')
    local size = sequence(machine, args[1])
    assert(size < Limits.table_keys, 'table sequence limit exceeded')
    local position, item = size + 1, args[2]
    if args.n == 3 then position, item = index(args[2], nil, spend), args[3] end
    assert(position and position >= 1 and position <= size + 1, 'position out of bounds')
    Execution.validate_value(machine, item)
    local target = machine.heap[args[1].native_ref]
    assert(target.keys + (item == nil and 0 or 1) <= Limits.table_keys, 'native table key quota exceeded')
    spend('table', 16 + 8 * (size - position + 1))
    -- A nil insertion replaces a key with a hole. Free its slot first so
    -- temporary shifting cannot exceed a full table's final key count.
    local held
    if item == nil and position <= size then
      held = Execution.get(machine, args[1], position)
      Execution.set(machine, args[1], position, nil)
    end
    for i = size, position, -1 do
      local value
      if item == nil and i == position then value = held
      else value = Execution.get(machine, args[1], i) end
      Execution.set(machine, args[1], i + 1, value)
    end
    Execution.set(machine, args[1], position, item)
    return 'return', {n = 0}
  end
  services['table.remove'] = function(machine, args)
    local size = sequence(machine, args[1])
    local position = index(args[2], size, spend)
    assert(position == size or (position >= 1 and position <= size + 1), 'position out of bounds')
    spend('table', 16 + 8 * math.max(0, size - position))
    if size == 0 or position > size then return 'return', {n = 0} end
    local result = Execution.get(machine, args[1], position)
    for i = position, size - 1 do
      Execution.set(machine, args[1], i, Execution.get(machine, args[1], i + 1))
    end
    Execution.set(machine, args[1], math.max(size, position), nil)
    return 'return', {n = 1, result}
  end
  for _, method in ipairs(maths) do
    local name = method
    services['math.' .. name] = function(_, args)
      assert(name ~= 'random' and name ~= 'randomseed' and type(math[name]) == 'function',
        'unsupported native helper math.' .. name)
      local count = 1
      if name == 'min' or name == 'max' then count = args.n
      elseif name == 'atan2' or name == 'fmod' or name == 'pow' or name == 'ldexp'
        or (name == 'log' and args[2] ~= nil) then count = 2 end
      assert(count > 0, 'math argument expected')
      spend('continuation', 1 + 4 * count)
      local bytes = 0
      for i = 1, count do
        assert(type(args[i]) == 'number' or type(args[i]) == 'string', 'number expected')
        if type(args[i]) == 'string' then bytes = bytes + #args[i] end
      end
      -- Reserve paired/variadic conversions together before parsing either.
      spend('string', bytes)
      local values = {}
      for i = 1, count do values[i] = assert(tonumber(args[i]), 'number expected') end
      return 'return', table.pack(math[name](table.unpack(values, 1, count)))
    end
  end
  services['math.randomseed'] = function(machine, args)
    local seed = index(args[1], nil, spend)
    assert(seed, 'random seed expected')
    seed = seed % 2147483647
    if seed == 0 then seed = 1 end
    spend('continuation', 16)
    machine.random_state = {version = 1, seed = seed}
    return 'return', {n = 0}
  end
  services['math.random'] = function(machine, args)
    assert(args.n <= 2, 'invalid random argument count')
    local first, last = 0, 1
    if args.n == 1 then first, last = 1, index(args[1], nil, spend)
    elseif args.n == 2 then first, last = index(args[1], nil, spend), index(args[2], nil, spend) end
    assert(first and last, 'random interval expected')
    local width = last - first + 1
    assert(first >= -2147483646 and last <= 2147483646 and width >= 1 and width <= 2147483646,
      'native random interval out of range')
    local state = machine.random_state
    assert(not state or (state.version == 1 and type(state.seed) == 'number' and state.seed >= 1
      and state.seed < 2147483647 and state.seed == math.floor(state.seed)), 'unsupported native random state')
    local seed = state and state.seed or 1
    -- Split the product to keep every intermediate an exact small integer.
    local next_seed = 16807 * (seed % 127773) - 2836 * math.floor(seed / 127773)
    if next_seed <= 0 then next_seed = next_seed + 2147483647 end
    local unit = (next_seed - 1) / 2147483646
    local value = args.n == 0 and unit or first + math.floor(unit * width)
    spend('continuation', 16)
    machine.random_state = {version = 1, seed = next_seed}
    return 'return', {n = 1, value}
  end
  services.tonumber = function(_, args)
    local value, base = args[1], args[2]
    if base ~= nil then
      base = index(base, nil, spend)
      assert(base >= 2 and base <= 36 and type(value) == 'string', 'invalid tonumber base')
    elseif type(value) ~= 'number' and type(value) ~= 'string' then return 'return', {n = 1} end
    if type(value) == 'string' then spend('string', #value) end
    local result
    if base then result = tonumber(value, base) else result = tonumber(value) end
    return 'return', {n = 1, result}
  end
  services.tostring = function(machine, args)
    local value = args[1]
    local result
    if type(value) == 'table' then
      spend('table', 8)
      local object = machine.heap[value.native_ref]
      local method = object.metatable and Execution.get(machine, object.metatable, '__tostring')
      if method ~= nil then
        Execution.admit_helper(machine, spend)
        spend('continuation', 8)
        return 'continue', {kind = 'helper', service = 'native.tostring.step', phase = 'call',
          callee = method, args = {n = 1, value}}
      end
      -- Never stringify a host wrapper/address. Guest callbacks use transfers.
      result = Execution.type(machine, value) .. ': ' .. value.native_ref
    else result = tostring(value) end
    spend('string', #result)
    return 'return', {n = 1, result}
  end
  services['native.tostring.step'] = function(_, operation)
    if operation.phase == 'call' then
      operation.phase = 'result'
      return 'call', {callee = operation.callee, args = operation.args}
    end
    assert(operation.phase == 'result', 'invalid native tostring phase')
    local result = operation.values[1]
    assert(type(result) == 'string', '__tostring must return a string')
    assert(#result <= Limits.string_bytes, 'native string quota exceeded')
    spend('string', #result)
    return 'return', {n = 1, result}
  end
  services.select = function(_, args)
    if args[1] == '#' then return 'return', {n = 1, args.n - 1} end
    local first = index(args[1], nil, spend)
    if first < 0 then first = args.n + first end
    assert(first >= 1, 'select index out of range')
    first = math.min(first, args.n)
    local result = {n = args.n - first}
    spend('continuation', 1 + 4 * result.n)
    for i = 1, result.n do result[i] = args[first + i] end
    return 'return', result
  end
  services['table.pack'] = function(machine, args)
    spend('table', 1 + 4 * args.n)
    local result = Execution.table_value(machine)
    for i = 1, args.n do Execution.set(machine, result, i, args[i]) end
    Execution.set(machine, result, 'n', args.n)
    return 'return', {n = 1, result}
  end
  services['table.unpack'] = function(machine, args)
    assert(Execution.type(machine, args[1]) == 'table', 'table expected')
    local first = index(args[2], 1, spend)
    local last = index(args[3], nil, spend)
    if last == nil then
      last = 0
      repeat
        spend('table', 1)
        if Execution.get(machine, args[1], last + 1) == nil then break end
        last = last + 1
      until last == Limits.table_keys
    end
    local size = math.max(0, last - first + 1)
    assert(size <= Limits.tuple_values, 'native tuple limit exceeded')
    spend('table', 1 + 4 * size)
    local result = {n = size}
    for i = 1, size do result[i] = Execution.get(machine, args[1], first + i - 1) end
    return 'return', result
  end
  services['table.concat'] = function(machine, args)
    assert(Execution.type(machine, args[1]) == 'table', 'table expected')
    local separator = args[2] == nil and '' or text(args[2])
    local first, last = index(args[3], 1, spend), index(args[4], nil, spend)
    if last == nil then
      last = 0
      repeat
        spend('table', 1)
        if Execution.get(machine, args[1], last + 1) == nil then break end
        last = last + 1
      until last == Limits.table_keys
    end
    local count = math.max(0, last - first + 1)
    assert(count <= Limits.table_keys, 'native table range quota exceeded')
    spend('table', 1 + 4 * count)
    local parts, size = {}, #separator * math.max(0, count - 1)
    assert(size <= Limits.string_bytes, 'native string quota exceeded')
    for i = 1, count do
      local value = Execution.get(machine, args[1], first + i - 1)
      assert(type(value) == 'string' or type(value) == 'number', 'invalid native concat value')
      local bytes = type(value) == 'string' and #value or 32
      assert(bytes <= Limits.string_bytes - size, 'native string quota exceeded')
      spend('string', bytes)
      parts[i] = text(value)
      size = size + #parts[i]
    end
    spend('string', size)
    return 'return', {n = 1, table.concat(parts, separator)}
  end
  for _, method in ipairs({'len', 'sub', 'byte', 'lower', 'upper', 'reverse'}) do
    local name = method
    services['string.' .. name] = function(_, args)
      local value = text(args[1])
      if name == 'len' then return 'return', {n = 1, #value} end
      if name == 'sub' or name == 'byte' then
        local first = index(args[2], name == 'byte' and 1 or nil, spend)
        assert(first, 'substring index expected')
        local last = index(args[3], name == 'byte' and first or #value, spend)
        local size
        first, last, size = range(#value, first, last)
        if name == 'byte' then assert(size <= Limits.tuple_values, 'native tuple limit exceeded') end
        spend('string', size)
        if name == 'sub' then return 'return', {n = 1, string.sub(value, first, last)} end
        return 'return', table.pack(string.byte(value, first, last))
      end
      spend('string', 2 * #value)
      return 'return', {n = 1, string[name](value)}
    end
  end
  services['string.char'] = function(_, args)
    spend('string', args.n)
    local bytes = {}
    for i = 1, args.n do
      local byte = index(args[i], nil, spend)
      assert(byte and byte >= 0 and byte <= 255, 'byte out of range')
      bytes[i] = byte
    end
    return 'return', {n = 1, string.char(table.unpack(bytes, 1, args.n))}
  end
  services['string.rep'] = function(_, args)
    local value, separator = text(args[1]), args[3] == nil and '' or text(args[3])
    local count = math.max(0, index(args[2], nil, spend))
    local size = #value * count + #separator * math.max(0, count - 1)
    assert(size <= Limits.string_bytes, 'native string quota exceeded')
    spend('string', #value + #separator + size)
    -- Avoid huge native iteration counts even when the output is empty.
    return 'return', {n = 1, size == 0 and '' or string.rep(value, count, separator)}
  end
  services['string.find'] = function(machine, args)
    if not args[4] then return Patterns.start(machine, args, 'find', spend) end
    local value, needle = text(args[1]), text(args[2])
    local first = index(args[3], 1, spend)
    if first < 0 then first = #value + first + 1 end
    first = math.max(1, first)
    -- Conservative comparison bound, not a promise of linear opaque search.
    spend('string', math.max(0, #value - first + 1) * math.max(1, #needle) + #needle)
    if first > #value + 1 then return 'return', {n = 1} end
    return 'return', table.pack(string.find(value, needle, first, true))
  end
  services['string.format'] = function(_, args)
    return 'return', {n = 1, Format.format(args, function(amount) spend('string', amount) end)}
  end
  for _, method in ipairs({'match', 'gmatch', 'gsub'}) do
    local name = method
    services['string.' .. name] = function(machine, args) return Patterns.start(machine, args, name, spend) end
  end
  services['string.dump'] = function() error('unsupported native helper string.dump', 0) end
  for _, method in ipairs(bits) do
    local name = method
    services['bit32.' .. name] = function(_, args)
      -- Fixed-width host operations are bounded by the already validated tuple.
      -- Match the original VM's numeric-only surface, never coerce guest refs.
      assert(args.n <= Limits.tuple_values, 'native bit32 argument quota exceeded')
      spend('continuation', 1 + 4 * args.n)
      for i = 1, args.n do
        local value = args[i]
        assert(type(value) == 'number' and value > -9007199254740992 and value < 9007199254740992,
          'bit32 operands must be finite safe-range numbers')
      end
      return 'return', table.pack(bit32[name](table.unpack(args, 1, args.n)))
    end
  end
  return services
end
return M
