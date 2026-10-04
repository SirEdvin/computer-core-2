local U = require("scripts.util")
local M = {max_bytes = 1048576, max_nodes = 2048}
function M.init(c)
  c.fs = {['/'] = {type = "dir", ctime = game.tick, mtime = game.tick, atime = game.tick}}
  c.cwd = "/"
end
function M.path(c, path)
  assert(type(path) == "string" and #path > 0 and #path <= 1024 and not path:find("%z"), "invalid path")
  local parts = {}
  local full = path:sub(1, 1) == "/" and path or c.cwd .. "/" .. path
  for part in full:gmatch("[^/]+") do
    if part == ".." then parts[#parts] = nil
    elseif part ~= "." then parts[#parts + 1] = part end
  end
  return "/" .. table.concat(parts, "/")
end
function M.peer(a, b)
  if a.id == b.id then return true end
  if a.personal and b.personal and a.player_index ~= b.player_index then return false end
  if b.personal and not a.personal then return false end
  return a.force_index == b.force_index and a.surface_index == b.surface_index
end
function M.mounts(c)
  local out = {}
  for _, id in ipairs(U.keys(storage.computers)) do
    local peer = storage.computers[id]
    if peer.label and M.peer(c, peer) then out[peer.label] = peer end
  end
  return out
end
function M.resolve(c, path)
  local normalized = M.path(c, path)
  if normalized == "/mnt" then return nil, normalized, {type = "dir", virtual = true} end
  local label, tail = normalized:match("^/mnt/([^/]+)(.*)$")
  if label then
    local peer = M.mounts(c)[label]
    assert(peer, "mount is unavailable: " .. label)
    return peer, tail == "" and "/" or tail
  end
  return c, normalized
end
function M.get(c, path)
  local owner, key, virtual = M.resolve(c, path)
  return virtual or owner.fs[key], owner, key
end
function M.read(c, path)
  local node = M.get(c, path)
  assert(node and node.type == "file", "not a file: " .. path)
  node.atime = game.tick
  return node.text
end
function M.exists(c, path)
  local ok, node = pcall(M.get, c, path)
  return ok and node ~= nil
end
function M.put(c, path, text, kind)
  local owner, key = M.resolve(c, path)
  assert(owner and key ~= "/" and key ~= "/mnt", "cannot replace a virtual/root directory")
  local parent = key:match("^(.*)/[^/]+$")
  if parent == "" then parent = "/" end
  assert(owner.fs[parent] and owner.fs[parent].type == "dir", "parent directory does not exist")
  assert(not owner.fs[key] or owner.fs[key].type == kind, "incompatible node type")
  if kind == "file" then assert(type(text) == "string", "file content must be text") end
  local count, bytes = 0, kind == "file" and #text or 0
  for p, node in pairs(owner.fs) do
    count = count + 1
    if p ~= key and node.type == "file" then bytes = bytes + #node.text end
  end
  assert(bytes <= M.max_bytes and (owner.fs[key] or count < M.max_nodes), "disk quota exceeded")
  local old = owner.fs[key]
  owner.fs[key] = {type = kind, text = text, ctime = old and old.ctime or game.tick, mtime = game.tick, atime = game.tick}
  return owner.fs[key]
end
function M.write(c, path, text) return M.put(c, path, text, "file") end
function M.mkdir(c, path) return M.put(c, path, nil, "dir") end
function M.remove(c, path)
  local owner, key = M.resolve(c, path)
  assert(owner and key ~= "/", "cannot remove virtual/root directory")
  assert(owner.fs[key], "no such file or directory")
  for _, p in ipairs(U.keys(owner.fs)) do
    if p == key or p:sub(1, #key + 1) == key .. "/" then owner.fs[p] = nil end
  end
  -- Resolve each cwd again: it may refer through a mount to the removed tree.
  for _, device in pairs(storage.computers) do
    local ok, node = pcall(M.get, device, device.cwd)
    if not ok or not node then device.cwd = "/" end
  end
end
function M.list(c, path)
  path = M.path(c, path or c.cwd)
  local node, owner, key = M.get(c, path)
  assert(node and node.type == "dir", "not a directory")
  local out = {}
  if path == "/mnt" then
    for label in pairs(M.mounts(c)) do out[label] = {type = "dir", virtual = true} end
  else
    local prefix = key == "/" and "/" or key .. "/"
    for p, child in pairs(owner.fs) do
      local name = p:sub(#prefix + 1)
      if p:sub(1, #prefix) == prefix and name ~= "" and not name:find("/", 1, true) then out[name] = child end
    end
    if path == "/" then out.mnt = {type = "dir", virtual = true} end
  end
  return out
end
function M.label(c, label)
  if label == nil or label == "" then c.label = nil; return end
  assert(type(label) == "string" and #label <= 64 and label:match("^[%w_%-%.]+$") and label ~= "." and label ~= "..", "label must be a path-safe name (max 64 characters)")
  for _, peer in pairs(storage.computers) do
    assert(peer.id == c.id or peer.force_index ~= c.force_index or peer.surface_index ~= c.surface_index or peer.label ~= label, "label already in use")
  end
  c.label = label
end
return M
