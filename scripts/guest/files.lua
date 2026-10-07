-- Local/ROM filesystem only. Never resolve a peer mount or open native IO.
local F = require("__computer_core_2__.scripts.filesystem")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local sources = require("__computer_core_2__.scripts.guest.rom")
local M = {}
local rom = {['/rc'] = {type = "dir"}}
for path, text in pairs(sources) do
  if path:sub(1, 4) == "/rc/" then
    rom[path] = {type = "file", text = text}
    local parent = path:match("^(.*)/[^/]+$")
    while parent and parent ~= "" do
      rom[parent] = rom[parent] or {type = "dir"}
      parent = parent:match("^(.*)/[^/]+$")
    end
  end
end
local function charge(spend, amount) if spend then spend(amount) end end
local function path(vm, name, spend)
  assert(type(name) == "string" and #name <= 1024, "invalid path")
  charge(spend, 1 + 16 * (#name + #vm.disk.cwd + 1))
  return F.path(vm.disk, name == "" and "/" or name)
end
local function protected(name) return name == "/rc" or name:sub(1, 4) == "/rc/" end
local function within(name, directory)
  if directory == "/" then return name:sub(1, 1) == "/" end
  return name == directory or name:sub(1, #directory + 1) == directory .. "/"
end
local function usage(nodes, spend)
  local count, bytes = 0, 0
  for _, node in pairs(nodes) do charge(spend, 1); count = count + 1; if node.type == "file" then bytes = bytes + #node.text end end
  return count, bytes
end
local function quota(nodes, spend)
  local count, bytes = usage(nodes, spend)
  assert(count <= F.max_nodes and bytes <= F.max_bytes, "local disk quota exceeded")
end
local function writable(name)
  assert(name ~= "/" and not protected(name), "read-only path")
end
function M.get(vm, name, spend)
  name = path(vm, name, spend)
  if protected(name) then return rom[name], name end
  return F.get_local(vm.disk, name)
end
function M.read_source(vm, name, spend)
  local node = M.get(vm, name, spend)
  assert(node and node.type == "file", "not a local/ROM file")
  return node.text
end
function M.exists(vm, name, spend) return M.get(vm, name, spend) ~= nil end
function M.is_dir(vm, name, spend) local node = M.get(vm, name, spend); return node ~= nil and node.type == "dir" end
function M.is_readonly(vm, name, spend) return protected(path(vm, name, spend)) end
function M.size(vm, name, spend)
  local node = assert(M.get(vm, name, spend), "path does not exist")
  return node.type == "file" and #node.text or 0
end
function M.list(vm, name, spend)
  local node, normalized = M.get(vm, name, spend)
  assert(node and node.type == "dir", "not a directory")
  local names, found = {}, {}
  local prefix = normalized == "/" and "/" or normalized .. "/"
  for _, nodes in ipairs({vm.disk.fs, rom}) do
    for candidate in pairs(nodes) do
      charge(spend, 1 + 4 * (#candidate + #prefix))
      local tail = candidate:sub(#prefix + 1)
      if candidate:sub(1, #prefix) == prefix and tail ~= "" and not tail:find("/", 1, true) and not found[tail] then
        found[tail] = true; names[#names + 1] = tail
      end
    end
  end
  table.sort(names, function(a, b)
    charge(spend, 1 + #a + #b)
    return a < b
  end)
  return names
end
function M.replace(vm, name, text, spend)
  name = path(vm, name, spend)
  writable(name)
  assert(type(text) == "string" and #text <= F.max_bytes, "local disk quota exceeded")
  local parent = name:match("^(.*)/[^/]+$"); if parent == "" then parent = "/" end
  assert(M.is_dir(vm, parent, spend), "parent directory does not exist")
  local old = vm.disk.fs[name]
  assert(not old or old.type == "file", "path is a directory")
  local count, bytes = usage(vm.disk.fs, spend)
  assert((old or count < F.max_nodes) and bytes - (old and #old.text or 0) + #text <= F.max_bytes, "local disk quota exceeded")
  charge(spend, 1)
  vm.disk.fs[name] = {type = "file", text = text}
end
function M.mkdir(vm, name, spend)
  name = path(vm, name, spend)
  if name == "/" then return end
  writable(name)
  local proposed = {}; for k, v in pairs(vm.disk.fs) do charge(spend, 1); proposed[k] = v end
  local prefix = ""
  for part in name:gmatch("[^/]+") do
    charge(spend, 1 + #prefix + #part)
    prefix = prefix .. "/" .. part
    assert(not proposed[prefix] or proposed[prefix].type == "dir", "path component is a file")
    proposed[prefix] = proposed[prefix] or {type = "dir"}
  end
  quota(proposed, spend)
  vm.disk.fs = proposed
end
function M.delete(vm, name, spend)
  name = path(vm, name, spend); writable(name)
  local removals = {}
  for candidate in pairs(vm.disk.fs) do
    charge(spend, 2 + #candidate + 2 * #name)
    if within(candidate, name) then removals[#removals + 1] = candidate end
  end
  charge(spend, #removals)
  for _, candidate in ipairs(removals) do vm.disk.fs[candidate] = nil end
end
function M.transfer(vm, from, to, move, spend)
  local node, source = M.get(vm, from, spend)
  assert(node, "source does not exist")
  local target = path(vm, to, spend); writable(target)
  if move then writable(source) end
  assert(not within(target, source) and not M.exists(vm, target, spend), "invalid destination")
  local parent = target:match("^(.*)/[^/]+$"); if parent == "" then parent = "/" end
  assert(M.is_dir(vm, parent, spend), "parent directory does not exist")
  local proposed = {}; for k, v in pairs(vm.disk.fs) do charge(spend, 1); proposed[k] = v end
  local originals = protected(source) and rom or vm.disk.fs
  for name, value in pairs(originals) do
    charge(spend, 2 + 4 * (#name + #source + #target))
    if within(name, source) then
      local destination = target .. name:sub(#source + 1)
      assert(#destination <= 1024, "normalized path exceeds length limit")
      proposed[destination] = {type = value.type, text = value.text}
      if move then proposed[name] = nil end
    end
  end
  quota(proposed, spend)
  vm.disk.fs = proposed
end
function M.open(vm, name, mode, spend)
  name, mode = path(vm, name, spend), mode or "r"
  local modes = {r = true, w = true, a = true, rb = true, wb = true, ab = true,
    ['r+'] = true, ['w+'] = true, ['a+'] = true, ['r+b'] = true, ['w+b'] = true, ['a+b'] = true,
    ['rb+'] = true, ['wb+'] = true, ['ab+'] = true}
  assert(type(mode) == "string" and modes[mode], "invalid open mode")
  local access = mode:gsub("b", "")
  assert(access == "r" or access == "w" or access == "a" or access == "r+" or access == "w+" or access == "a+", "unsupported open mode")
  local node = M.get(vm, name, spend)
  assert(not node or node.type == "file", "cannot open a directory")
  local readable, write = access:find("r", 1, true) ~= nil or access:find("+", 1, true) ~= nil, access ~= "r"
  if write then
    writable(name)
    local parent = name:match("^(.*)/[^/]+$"); if parent == "" then parent = "/" end
    assert(M.is_dir(vm, parent, spend), "parent directory does not exist")
  end
  if access:sub(1, 1) == "r" then assert(node, "file does not exist") end
  local text = access:sub(1, 1) == "w" and "" or (node and node.text or "")
  assert(vm.open_handles < Limits.open_handles and vm.handle_bytes + #text <= Limits.handle_bytes, "file handle quota exceeded")
  -- The content is an immutable string reference, not a native byte copy.
  -- Include the bounded symbolic handle/method construction in admission.
  charge(spend, 32)
  vm.open_handles = vm.open_handles + 1
  vm.handle_bytes = vm.handle_bytes + #text
  return {kind = "handle", version = 1, path = name, mode = access, binary = mode:find("b", 1, true) ~= nil, readable = readable, writable = write,
    append = access:sub(1, 1) == "a", text = text, offset = access:sub(1, 1) == "a" and #text or 0, closed = false, failed = false}
end
local function available(handle) assert(not handle.closed, "file handle is closed") end
function M.read(handle, format, spend)
  available(handle); assert(handle.readable, "file is not readable")
  format = format == nil and "l" or format
  local remaining = #handle.text - handle.offset
  if format == "a" or format == "*a" then
    assert(remaining <= Limits.string_bytes, "read result exceeds byte limit")
    charge(spend, 1 + math.max(0, remaining))
    local result = handle.text:sub(handle.offset + 1)
    handle.offset = #handle.text
    return result
  end
  if type(format) == "number" then
    assert(format == math.floor(format) and format >= 0 and format <= Limits.string_bytes, "invalid read length")
    charge(spend, 1 + math.min(math.max(0, remaining), format))
    if remaining <= 0 then return nil end
    local result = handle.text:sub(handle.offset + 1, handle.offset + format)
    handle.offset = handle.offset + #result
    return result
  end
  assert(format == "l" or format == "*l" or format == "L" or format == "*L", "unsupported read format")
  if remaining <= 0 then charge(spend, 1); return nil end
  -- Bound the opaque native scan even when a disk-sized file has no newline.
  local scan = math.min(remaining, Limits.string_bytes + 1)
  charge(spend, 1 + 2 * scan)
  local probe = handle.text:sub(handle.offset + 1, handle.offset + scan)
  local relative = probe:find("\n", 1, true)
  local newline = relative and handle.offset + relative
  local finish = newline or #handle.text
  assert(finish - handle.offset <= Limits.string_bytes, "line exceeds byte limit")
  local last = (format == "L" or format == "*L") and finish or (newline and finish - 1 or finish)
  charge(spend, last - handle.offset)
  local result = handle.text:sub(handle.offset + 1, last)
  handle.offset = finish
  return result
end
function M.write(vm, handle, text, spend)
  available(handle); assert(handle.writable and not handle.failed, "file is not writable")
  assert(type(text) == "string" and #text <= Limits.string_bytes, "write operand exceeds byte limit")
  local offset = handle.append and #handle.text or handle.offset
  local new_size = math.max(#handle.text, offset + #text)
  local old = vm.disk.fs[handle.path]
  local count, bytes = usage(vm.disk.fs, spend)
  if new_size > F.max_bytes or bytes - (old and old.type == "file" and #old.text or 0) + new_size > F.max_bytes or (not old and count >= F.max_nodes) or vm.handle_bytes - #handle.text + new_size > Limits.handle_bytes then
    handle.failed = true
    error("local disk quota exceeded; previous file retained", 0)
  end
  -- Reserve six byte passes in eight-byte work blocks for the fixed
  -- substring/padding/concatenation pipeline, before changing retained state.
  charge(spend, 1 + math.floor((6 * new_size + 7) / 8))
  local padding = offset > #handle.text and string.rep("\0", offset - #handle.text) or ""
  vm.handle_bytes = vm.handle_bytes - #handle.text + new_size
  handle.text = handle.text:sub(1, offset) .. padding .. text .. handle.text:sub(offset + #text + 1)
  handle.offset = offset + #text
end
function M.seek(handle, whence, offset, spend)
  available(handle)
  whence, offset = whence or "cur", offset or 0
  assert(type(offset) == "number" and offset == math.floor(offset) and math.abs(offset) <= F.max_bytes, "invalid seek offset")
  local base = whence == "set" and 0 or (whence == "cur" and handle.offset or (whence == "end" and #handle.text or nil))
  assert(base, "invalid seek origin")
  local next_offset = base + offset
  assert(next_offset >= 0 and next_offset <= F.max_bytes, "seek out of bounds")
  charge(spend, 1)
  handle.offset = next_offset
  return next_offset
end
function M.flush(vm, handle, spend)
  available(handle)
  assert(not handle.failed, "failed write; previous file retained")
  charge(spend, 1)
  if handle.writable then M.replace(vm, handle.path, handle.text, spend) end
end
function M.close(vm, handle, spend)
  available(handle)
  charge(spend, 1) -- Reserve cleanup before a successful flush can publish.
  local refused = false
  local function admit(amount)
    local ok, err = pcall(spend, amount)
    if not ok then refused = true; error(err, 0) end
  end
  local ok, err = pcall(M.flush, vm, handle, spend and admit or nil)
  -- Admission errors preserve the open draft for a later retry. Content-quota
  -- errors retain the existing close-and-release contract without publishing.
  if refused then error(err, 0) end
  handle.closed = true
  vm.open_handles = vm.open_handles - 1
  vm.handle_bytes = vm.handle_bytes - #handle.text
  handle.text = ""
  if not ok then error(err, 0) end
end
return M
