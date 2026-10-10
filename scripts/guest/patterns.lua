-- Pattern parsing, backtracking and callbacks are guest bytecode, not host C.
return [=[
local sub, byte, char = string.sub, string.byte, string.char
local function text(value)
  if type(value) == 'number' then value = tostring(value) end
  assert(type(value) == 'string', 'expected string')
  return value
end
local function character(code, name)
  local lower = name:lower()
  local a = code >= 65 and code <= 90 or code >= 97 and code <= 122
  local d = code >= 48 and code <= 57
  local yes
  if lower == 'a' then yes = a
  elseif lower == 'c' then yes = code < 32 or code == 127
  elseif lower == 'd' then yes = d
  elseif lower == 'g' then yes = code > 32 and code < 127
  elseif lower == 'l' then yes = code >= 97 and code <= 122
  elseif lower == 'p' then yes = code > 32 and code < 127 and not a and not d
  elseif lower == 's' then yes = code == 32 or code >= 9 and code <= 13
  elseif lower == 'u' then yes = code >= 65 and code <= 90
  elseif lower == 'w' then yes = a or d
  elseif lower == 'x' then yes = d or code >= 65 and code <= 70 or code >= 97 and code <= 102
  elseif lower == 'z' then yes = code == 0
  else return code == byte(name) end
  if name ~= lower then return not yes end
  return yes
end
local function setmatch(set, code)
  local yes = false
  for _, item in ipairs(set.items) do
    if item.class then yes = character(code, item.class)
    elseif item.last then yes = code >= item.first and code <= item.last
    else yes = code == item.first end
    if yes then break end
  end
  if set.negate then return not yes end
  return yes
end
local function readset(pattern, at)
  local set = {items = {}, negate = sub(pattern, at + 1, at + 1) == '^'}
  local cursor = at + (set.negate and 2 or 1)
  local first = true
  while cursor <= #pattern do
    local value = sub(pattern, cursor, cursor)
    if value == ']' and not first then return set, cursor + 1 end
    first = false
    local item
    if value == '%' then
      assert(cursor < #pattern, 'malformed character set')
      item = {class = sub(pattern, cursor + 1, cursor + 1)}
      cursor = cursor + 2
    else item = {first = byte(value)}; cursor = cursor + 1 end
    if item.first and sub(pattern, cursor, cursor) == '-' and cursor + 1 <= #pattern and sub(pattern, cursor + 1, cursor + 1) ~= ']' then
      item.last = byte(pattern, cursor + 1)
      cursor = cursor + 2
    end
    set.items[#set.items + 1] = item
  end
  error('unfinished character set')
end
local function parse(pattern, anchors)
  pattern = text(pattern)
  assert(#pattern <= 4096, 'pattern byte limit exceeded')
  local nodes, stack, count, cursor = {}, {}, 0, 1
  local anchored = anchors and sub(pattern, 1, 1) == '^'
  if anchored then cursor = 2 end
  while cursor <= #pattern do
    local value = sub(pattern, cursor, cursor)
    local node
    if value == '(' then
      count = count + 1
      assert(count <= 32, 'capture limit exceeded')
      if sub(pattern, cursor + 1, cursor + 1) == ')' then node = {kind = 'position', capture = count}; cursor = cursor + 2
      else node = {kind = 'open', capture = count}; stack[#stack + 1] = count; cursor = cursor + 1 end
    elseif value == ')' then
      assert(#stack > 0, 'invalid pattern capture')
      node = {kind = 'close', capture = table.remove(stack)}
      cursor = cursor + 1
    elseif value == '$' and cursor == #pattern then node = {kind = 'finish'}; cursor = cursor + 1
    elseif value == '[' then
      local set; set, cursor = readset(pattern, cursor)
      node = {kind = 'atom', set = set}
    elseif value == '%' then
      assert(cursor < #pattern, 'unfinished pattern escape')
      local escaped = sub(pattern, cursor + 1, cursor + 1)
      if escaped == 'b' then
        assert(cursor + 3 <= #pattern, 'unbalanced pattern')
        node = {kind = 'balance', left = sub(pattern, cursor + 2, cursor + 2), right = sub(pattern, cursor + 3, cursor + 3)}
        cursor = cursor + 4
      elseif escaped == 'f' then
        assert(sub(pattern, cursor + 2, cursor + 2) == '[', 'frontier requires a character set')
        local set; set, cursor = readset(pattern, cursor + 2)
        node = {kind = 'frontier', set = set}
      elseif escaped >= '1' and escaped <= '9' then node = {kind = 'reference', capture = tonumber(escaped)}; cursor = cursor + 2
      else node = {kind = 'atom', class = escaped}; cursor = cursor + 2 end
    else node = {kind = 'atom', any = value == '.', literal = value ~= '.' and value or nil}; cursor = cursor + 1 end
    if node.kind == 'atom' then
      local repeat_ = sub(pattern, cursor, cursor)
      if repeat_ == '*' or repeat_ == '+' or repeat_ == '-' or repeat_ == '?' then node.repeat_ = repeat_; cursor = cursor + 1 end
    end
    nodes[#nodes + 1] = node
  end
  assert(#stack == 0, 'unfinished capture')
  return {nodes = nodes, captures = count, anchored = anchored}
end
local function atom(node, value, at)
  if at > #value then return false end
  local code = byte(value, at)
  if node.set then return setmatch(node.set, code)
  elseif node.class then return character(code, node.class)
  elseif node.any then return true
  else return sub(value, at, at) == node.literal end
end
local function capturecopy(captures, total)
  local copy = {}
  for i = 1, total do copy[i] = captures[i] end
  return copy
end
local matchfrom
matchfrom = function(value, at, compiled, index, captures)
  local node = compiled.nodes[index]
  if not node then return at, captures end
  local following = index + 1
  if node.kind == 'open' or node.kind == 'close' or node.kind == 'position' then
    local copy = capturecopy(captures, compiled.captures)
    if node.kind == 'open' then copy[node.capture] = {first = at}
    elseif node.kind == 'position' then copy[node.capture] = at
    else copy[node.capture] = {first = captures[node.capture].first, last = at - 1} end
    return matchfrom(value, at, compiled, following, copy)
  elseif node.kind == 'finish' then
    if at ~= #value + 1 then return nil end
  elseif node.kind == 'reference' then
    local captured = captures[node.capture]
    assert(type(captured) == 'table' and captured.last ~= nil, 'invalid capture index')
    local n = captured.last - captured.first + 1
    if sub(value, at, at + n - 1) ~= sub(value, captured.first, captured.last) then return nil end
    at = at + n
  elseif node.kind == 'frontier' then
    if setmatch(node.set, byte(value, at - 1) or 0) or not setmatch(node.set, byte(value, at) or 0) then return nil end
  elseif node.kind == 'balance' then
    if sub(value, at, at) ~= node.left then return nil end
    local depth, cursor = 1, at + 1
    while cursor <= #value and depth > 0 do
      local letter = sub(value, cursor, cursor)
      if letter == node.right then depth = depth - 1
      elseif letter == node.left then depth = depth + 1 end
      cursor = cursor + 1
    end
    if depth ~= 0 then return nil end
    at = cursor
  else
    local repeat_ = node.repeat_
    if not repeat_ then
      if not atom(node, value, at) then return nil end
      at = at + 1
    elseif repeat_ == '?' then
      if atom(node, value, at) then
        local finish, copy = matchfrom(value, at + 1, compiled, following, captures)
        if finish then return finish, copy end
      end
    else
      local last = at
      while atom(node, value, last) do last = last + 1 end
      local minimum = repeat_ == '+' and at + 1 or at
      if last < minimum then return nil end
      local first, final, step = last, minimum, -1
      if repeat_ == '-' then first, final, step = minimum, last, 1 end
      for position = first, final, step do
        local finish, copy = matchfrom(value, position, compiled, following, captures)
        if finish then return finish, copy end
      end
      return nil
    end
  end
  return matchfrom(value, at, compiled, following, captures)
end
local function initial(value, at)
  if at == nil then return 1 end
  at = tonumber(at)
  assert(at and at == math.floor(at) and math.abs(at) <= 2147483647, 'invalid match position')
  if at < 0 then at = #value + at + 1 end
  return math.max(at, 1)
end
local function locate(value, compiled, at)
  local last = compiled.anchored and at or #value + 1
  for position = at, last do
    local finish, captures = matchfrom(value, position, compiled, 1, {})
    if finish then return position, finish - 1, captures end
  end
end
local function captured(value, compiled, captures, first, last)
  local result = {n = compiled.captures}
  if result.n == 0 then result.n = 1; result[1] = sub(value, first, last)
  else
    for i = 1, result.n do
      local capture = captures[i]
      if type(capture) == 'number' then result[i] = capture
      else result[i] = sub(value, capture.first, capture.last) end
    end
  end
  return result
end
function string.find(value, pattern, at, plain)
  value, pattern = text(value), text(pattern)
  at = initial(value, at)
  if at > #value + 1 then return nil end
  if plain then
    for position = at, #value - #pattern + 1 do
      if sub(value, position, position + #pattern - 1) == pattern then return position, position + #pattern - 1 end
    end
    return nil
  end
  local compiled = parse(pattern, true)
  local first, last, captures = locate(value, compiled, at)
  if not first then return nil end
  if compiled.captures == 0 then return first, last end
  local values = captured(value, compiled, captures, first, last)
  return first, last, table.unpack(values, 1, values.n)
end
function string.match(value, pattern, at)
  value = text(value)
  at = initial(value, at)
  if at > #value + 1 then return nil end
  local compiled = parse(pattern, true)
  local first, last, captures = locate(value, compiled, at)
  if not first then return nil end
  local values = captured(value, compiled, captures, first, last)
  return table.unpack(values, 1, values.n)
end
function string.gmatch(value, pattern)
  value = text(value)
  local compiled, at = parse(pattern, false), 1
  return function()
    if at > #value + 1 then return nil end
    local first, last, captures = locate(value, compiled, at)
    if not first then at = #value + 2; return nil end
    at = math.max(last + 1, first + 1)
    local values = captured(value, compiled, captures, first, last)
    return table.unpack(values, 1, values.n)
  end
end
function string.gsub(value, pattern, replacement, limit)
  value = text(value)
  if type(replacement) == 'number' then replacement = tostring(replacement) end
  local kind = type(replacement)
  assert(kind == 'string' or kind == 'table' or kind == 'function', 'invalid replacement')
  limit = limit == nil and #value + 1 or tonumber(limit)
  assert(limit and limit == math.floor(limit) and math.abs(limit) <= 2147483647, 'invalid replacement limit')
  local compiled, pieces, bytes, at, count = parse(pattern, true), {}, 0, 1, 0
  local function append(piece)
    bytes = bytes + #piece
    assert(bytes <= 65536, 'pattern result byte limit exceeded')
    -- Coalesce through a bounded string, rather than exhausting table key history.
    if #pieces == 1024 then pieces = {table.concat(pieces)} end
    pieces[#pieces + 1] = piece
  end
  while at <= #value + 1 and count < limit do
    local finish, captures = matchfrom(value, at, compiled, 1, {})
    if finish then
      count = count + 1
      local values = captured(value, compiled, captures, at, finish - 1)
      local result
      if kind == 'function' then result = replacement(table.unpack(values, 1, values.n))
      elseif kind == 'table' then result = replacement[values[1]]
      else
        local expanded, expanded_bytes, cursor = {}, 0, 1
        while cursor <= #replacement do
          local letter = sub(replacement, cursor, cursor)
          if letter == '%' then
            cursor = cursor + 1
            letter = sub(replacement, cursor, cursor)
            if letter == '%' then letter = '%'
            elseif letter == '0' then letter = sub(value, at, finish - 1)
            elseif letter >= '1' and letter <= '9' then
              local index = tonumber(letter)
              assert(values[index] ~= nil, 'invalid replacement capture')
              letter = tostring(values[index])
            else error('invalid replacement escape') end
          end
          expanded_bytes = expanded_bytes + #letter
          assert(expanded_bytes <= 65536, 'replacement result byte limit exceeded')
          if #expanded == 1024 then expanded = {table.concat(expanded)} end
          expanded[#expanded + 1] = letter
          cursor = cursor + 1
        end
        result = table.concat(expanded)
      end
      if result == nil or result == false then result = sub(value, at, finish - 1) end
      if type(result) == 'number' then result = tostring(result) end
      assert(type(result) == 'string', 'invalid replacement value')
      append(result)
      if finish > at then at = finish
      elseif at <= #value then append(sub(value, at, at)); at = at + 1
      else at = at + 1; break end
    elseif at <= #value then append(sub(value, at, at)); at = at + 1
    else break end
    if compiled.anchored then break end
  end
  append(sub(value, at))
  return table.concat(pieces), count
end
]=]
