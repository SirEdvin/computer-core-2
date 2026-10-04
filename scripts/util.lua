local M = {}
function M.keys(t)
  local r = {}
  for k in pairs(t) do r[#r + 1] = k end
  table.sort(r)
  return r
end
-- Copy only bounded, plain serializable data. Reject cycles, metatables,
-- userdata, functions, NaN and infinities at every player/remote boundary.
function M.data(value, limits)
  local count, bytes, seen = 0, 0, {}
  limits = limits or {nodes = 16384, bytes = 262144, depth = 32}
  local function copy(v, depth)
    count = count + 1
    assert(count <= limits.nodes and depth <= limits.depth, "data exceeds structural limit")
    local kind = type(v)
    if kind == "nil" or kind == "boolean" then return v end
    if kind == "number" then
      assert(v == v and math.abs(v) < math.huge, "non-finite number")
      return v
    end
    if kind == "string" then
      bytes = bytes + #v
      assert(bytes <= limits.bytes, "data exceeds byte limit")
      return v
    end
    assert(kind == "table" and not getmetatable(v), "only plain serializable data is allowed")
    assert(not seen[v], "cyclic data is not allowed")
    seen[v] = true
    local out = {}
    for k, x in pairs(v) do
      assert(type(k) == "string" or type(k) == "number", "invalid data key")
      out[copy(k, depth + 1)] = copy(x, depth + 1)
    end
    seen[v] = nil
    return out
  end
  return copy(value, 0)
end
function M.equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for key, value in pairs(a) do if not M.equal(value, b[key]) then return false end end
  for key in pairs(b) do if a[key] == nil then return false end end
  return true
end
function M.text(...)
  local out = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    out[#out + 1] = type(v) == "table" and helpers.table_to_json(M.data(v)) or tostring(v)
  end
  return table.concat(out)
end
function M.pack(...)
  return M.data({n = select("#", ...), ...})
end
function M.unpack(t)
  return table.unpack(t, 1, t.n or #t)
end
function M.finite(n, name)
  assert(type(n) == "number" and n == n and math.abs(n) < math.huge, (name or "value") .. " must be finite")
  return n
end
function M.words(text)
  local out, word, quote, escape = {}, "", nil, false
  local started = false
  for i = 1, #text do
    local c = text:sub(i, i)
    if escape then word = word .. c; escape = false; started = true
    elseif c == "\\" then escape = true; started = true
    elseif quote then
      if c == quote then quote = nil else word = word .. c end
    elseif c == '"' or c == "'" then quote = c; started = true
    elseif c:match("%s") then
      if started then out[#out + 1] = word; word = ""; started = false end
    else word = word .. c; started = true end
  end
  assert(not quote and not escape, "unterminated quote or escape")
  if started then out[#out + 1] = word end
  return out
end
return M
