-- Scalar-only formatting: validate expansion bounds before calling the host.
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
M.template_bytes = 4096
local flags = {['-'] = true, ['+'] = true, [' '] = true, ['#'] = true, ['0'] = true}
local conversions = {}
for char in ("cdiouxXeEfgGqs"):gmatch(".") do conversions[char] = true end
local function conversion(template, first)
  local cursor = first + 1
  while flags[template:sub(cursor, cursor)] do cursor = cursor + 1 end
  local function digits()
    local value = 0
    while cursor <= #template do
      local char = template:sub(cursor, cursor)
      if char < "0" or char > "9" then break end
      value = value * 10 + tonumber(char)
      assert(value <= Limits.string_bytes, "format expansion exceeds byte limit")
      cursor = cursor + 1
    end
    return value
  end
  local width, precision = digits(), nil
  if template:sub(cursor, cursor) == "." then cursor = cursor + 1; precision = digits() end
  assert(conversions[template:sub(cursor, cursor)], "invalid format conversion")
  return template:sub(first, cursor), cursor + 1, width, precision
end
function M.format(args, spend)
  local template = args[1]
  assert(type(template) == "string" and #template <= M.template_bytes, "format template exceeds byte limit")
  if spend then spend(1 + 2 * #template) end
  local pieces, bytes, cursor, argument = {}, 0, 1, 2
  local function append(text)
    bytes = bytes + #text
    assert(bytes <= Limits.string_bytes, "format result exceeds byte limit")
    pieces[#pieces + 1] = text
  end
  while cursor <= #template do
    local percent = template:find("%", cursor, true)
    if not percent then append(template:sub(cursor)); break end
    append(template:sub(cursor, percent - 1))
    if template:sub(percent + 1, percent + 1) == "%" then
      append("%")
      cursor = percent + 2
    else
      local token, following, width, precision = conversion(template, percent)
      assert(argument <= args.n, "missing format argument")
      local value = args[argument]
      assert(type(value) ~= "table" and type(value) ~= "function" and type(value) ~= "userdata" and type(value) ~= "thread", "format operands must be scalar")
      -- Lua 5.2 %s stringifies scalar nil/booleans; Factorio's formatter does not.
      if token:sub(-1) == "s" and (value == nil or type(value) == "boolean") then value = tostring(value) end
      if type(value) == "string" then assert(#value <= Limits.string_bytes, "format operand exceeds byte limit") end
      if spend then
        local input = type(value) == "string" and #value or 0
        local output = 512 + (precision or 6)
        local kind = token:sub(-1)
        if kind == "s" then
          output = #tostring(value)
          if precision then output = math.min(output, precision) end
        elseif kind == "q" then output = 4 * input + 64
        elseif kind == "c" then output = 1 end
        spend(#token + input + math.max(width, output))
      end
      append(string.format(token, value))
      argument, cursor = argument + 1, following
    end
  end
  if spend then spend(1 + bytes) end
  return table.concat(pieces)
end
return M
