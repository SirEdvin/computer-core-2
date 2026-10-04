local U = require("scripts.util")
local FS = require("scripts.filesystem")
local A = require("scripts.adapters")
local M = {}
local runtimes = {}
local build
local function active(c, rt)
  assert(c.process and c.process.generation == rt.generation, "program is no longer running")
end
local function effect(c, rt)
  active(c, rt)
  assert(not rt.rebuilding, "persistent programs must put startup effects in init, not at module scope")
end
local function handler(name)
  assert(type(name) == "string" and #name > 0 and #name <= 128, "callback must be a named handler, not a function")
  return name
end
function M.output(c, text, replace)
  local value = replace and text or c.output .. text
  -- Preserve complete UTF-8 characters when trimming the bounded terminal.
  if #value > 65536 then
    local start = #value - 65535
    while start <= #value and value:byte(start) >= 128 and value:byte(start) < 192 do start = start + 1 end
    value = value:sub(start)
  end
  c.output = value
  if c.process then c.process.output_dirty = true end
end
function M.stop(c, reason)
  local rt
  if c.process then local ok, result = pcall(build, c, true); if ok then rt = result end end
  if rt then
    for _, name in ipairs(U.keys(rt.extensions)) do
      local entry = rt.extensions[name]
      local callback = (entry.definition.events or {}).on_script_kill
      if callback then
        local ok, err = pcall(callback, entry.instance)
        if not ok then M.output(c, "Extension stop error: " .. tostring(err) .. "\n") end
      end
      local ok, value = pcall(U.data, entry.instance.__state)
      if ok then c.extension_state[name] = value end
    end
  end
  if c.sub then
    A.mute(c)
    for _, key in ipairs({"left_combinator", "right_combinator"}) do
      local entity = c.sub[key]
      if entity and entity.valid then A.write(entity, {}) end
    end
  end
  c.outputs = {left = {}, right = {}}
  c.process = nil
  runtimes[c.id] = nil
  if reason then M.output(c, "Error: " .. tostring(reason) .. "\n") end
end
local function queue(c, kind, event, args, source)
  assert(#storage.messages < 4096, "message queue is full")
  storage.next_message = storage.next_message + 1
  storage.messages[#storage.messages + 1] = {id = storage.next_message, target = c.id, generation = c.process and c.process.generation, kind = kind, event = event, args = args, source = source, due = game.tick + 1}
end
local function environment(c, rt)
  local p = c.process
  local env = {state = U.data(c.state), args = U.data(p.args)}
  for _, name in ipairs({"assert", "error", "ipairs", "pairs", "next", "select", "tonumber", "tostring", "type", "pcall", "xpcall"}) do env[name] = _G[name] end
  -- Independent standard-library tables cannot mutate mod-global Lua libraries.
  env.math, env.table, env.string, env.utf8 = {}, {}, {}, {}
  for _, lib in ipairs({"math", "table", "string", "utf8"}) do
    for k, v in pairs(_G[lib] or {}) do
      if k ~= "dump" and k ~= "randomseed" and k ~= "random" then env[lib][k] = v end
    end
  end
  env.math.random = function(...) assert(not rt.rebuilding, "use randomness only in init/handlers"); return math.random(...) end
  env.unpack = table.unpack
  -- Library/disk paths are relative to the executing source, not the shell cwd.
  local function source_path(path)
    local base = rt.current_directory or p.directory
    return FS.path({cwd = base}, path)
  end
  local function write_file(path, text)
    path = source_path(path)
    local parent = path:match("^(.*)/[^/]+$")
    local parts, built = {}, ""
    for part in (parent or ""):gmatch("[^/]+") do parts[#parts + 1] = part end
    -- Plan the missing directories first; quotas/content are still checked by FS.
    for _, part in ipairs(parts) do
      built = built .. "/" .. part
      if not FS.exists(c, built) then FS.mkdir(c, built) end
    end
    FS.write(c, path, text)
  end
  env.os, env.term, env.disk, env.wlan = {}, {}, {}, {}
  local os, term, disk, wlan = env.os, env.term, env.disk, env.wlan
  local function resolve_handler(name)
    handler(name)
    assert(rt.constructing or rt.handlers[name], "unknown handler: " .. name)
    return name
  end
  os.getComputerID = function() return c.id end
  os.getComputerLabel = function() return c.label end
  os.getWaypoint = function(name)
    local points = storage.waypoints[c.force_index .. ":" .. c.surface_index] or {}
    return points[name] and U.data(points[name]) or nil
  end
  os.setComputerLabel = function(label) effect(c, rt); FS.label(c, label) end
  os.date = function() assert(not rt.rebuilding, "read the clock in a handler"); return game.tick end
  os.time = function() return (os.date() % 25000 / 25000 * 24 + 12) % 24 end
  os.pcall = pcall
  os.set = function(name, ...)
    effect(c, rt); assert(type(name) == "string" and #name <= 128, "name must be bounded text")
    local vars = U.data(c.vars)
    vars[name] = U.pack(...)
    c.vars = U.data(vars)
  end
  os.get = function(name) return U.unpack(c.vars[name] or {}) end
  os.clear = function(name) effect(c, rt); c.vars[name] = nil end
  os.register = function(name, fn)
    assert(rt.constructing and type(fn) == "function", "register handlers at module scope")
    rt.handlers[handler(name)] = fn
  end
  os.wait = function(name, seconds, ...)
    effect(c, rt); resolve_handler(name)
    U.finite(seconds, "seconds"); assert(seconds >= 0 and seconds <= 31536000, "delay out of range")
    assert(#p.timers < 256, "too many timers")
    local timers = U.data(p.timers)
    local id = p.next_timer + 1
    timers[#timers + 1] = {id = id, handler = name, due = game.tick + math.max(1, math.ceil(seconds * 60)), args = U.pack(...)}
    U.data({timers = timers, subscriptions = p.subscriptions, listeners = p.listeners})
    p.next_timer, p.timers = id, timers
    return p.next_timer
  end
  os.cancelTimer = function(id) effect(c, rt); for i, t in ipairs(p.timers) do if t.id == id then table.remove(p.timers, i); return true end end; return false end
  os.require = function(path)
    assert(type(path) == "string", "require expects a path")
    local key = source_path(path)
    if rt.library_results[key] ~= nil then return rt.library_results[key] end
    assert(not rt.loading[key], "cyclic require: " .. key)
    local source = p.libraries[key]
    if not source then
      assert(not rt.replay, "required library was not snapshotted")
      source = FS.read(c, key)
      assert(#source <= 262144, "library too large")
      local count, bytes = 1, #source
      for _, old in pairs(p.libraries) do count = count + 1; bytes = bytes + #old end
      assert(count <= 128 and bytes <= 1048576, "library snapshot quota exceeded")
      p.libraries[key] = source
    end
    rt.loading[key] = true
    local fn, err = load(source, "@" .. key, "t", env)
    assert(fn, err)
    local previous = rt.current_directory
    local rebuilding = rt.rebuilding
    local before = U.data(env.state)
    rt.rebuilding = true -- Required modules are declarations, never startup effects.
    rt.current_directory = key:match("^(.*)/[^/]+$")
    if rt.current_directory == "" then rt.current_directory = "/" end
    local ok, result = pcall(fn)
    rt.current_directory = previous
    rt.rebuilding = rebuilding
    rt.loading[key] = nil
    assert(ok, result)
    assert(U.equal(before, U.data(env.state)), "library module scope must not modify state")
    rt.library_results[key] = result == nil and true or result
    return rt.library_results[key]
  end
  term.write = function(...) effect(c, rt); M.output(c, U.text(...) .. "\n") end
  term.setOutput = term.write -- Historical API appends despite its name.
  term.getOutput = function() return c.output end
  term.setInput = function(text) effect(c, rt); local v = U.text(text); assert(#v <= 4096, "input too long"); c.input = v end
  term.getInput = function() return c.input end
  term.read = function() return c.output .. c.input end
  term.clear = function() effect(c, rt); M.output(c, "", true) end
  local function listen(kind, name)
    effect(c, rt); resolve_handler(name)
    local count = 0; for _ in pairs(p.listeners) do count = count + 1 end
    assert(count < 128, "too many listeners")
    p.next_listener = p.next_listener + 1
    p.listeners[p.next_listener] = {kind = kind, handler = name}
    return p.next_listener
  end
  term.addInputListener = function(name) return listen("input", name) end
  term.addOutputListener = function(name) return listen("output", name) end
  term.removeListener = function(id) effect(c, rt); p.listeners[id] = nil end
  disk.readFile = function(path) assert(not rt.rebuilding, "read files in init/handlers or use os.require"); return FS.read(c, source_path(path)) end
  disk.fileExist = function(path) assert(not rt.rebuilding, "inspect files in a handler"); return FS.exists(c, source_path(path)) end
  disk.writeFile = function(path, ...) effect(c, rt); write_file(path, U.text(...)) end
  disk.appendFile = function(path, ...) effect(c, rt); path = source_path(path); local old = FS.exists(c, path) and FS.read(c, path) or ""; write_file(path, old .. U.text(...)) end
  disk.removeFile = function(path) effect(c, rt); path = source_path(path); if FS.exists(c, path) then FS.remove(c, path) end end
  wlan.on = function(event, name, ...)
    effect(c, rt); resolve_handler(name); assert(type(event) == "string" and #event <= 128, "invalid event")
    assert(#p.subscriptions < 128, "too many subscriptions")
    local subscriptions = U.data(p.subscriptions)
    subscriptions[#subscriptions + 1] = {event = event, handler = name, args = U.pack(...), kind = "message"}
    U.data({timers = p.timers, subscriptions = subscriptions, listeners = p.listeners})
    p.subscriptions = subscriptions
  end
  wlan.onBuiltComputer = function(name, ...)
    effect(c, rt); resolve_handler(name); assert(#p.subscriptions < 128, "too many subscriptions")
    local subscriptions = U.data(p.subscriptions)
    subscriptions[#subscriptions + 1] = {event = "built", handler = name, args = U.pack(...), kind = "built"}
    U.data({timers = p.timers, subscriptions = subscriptions, listeners = p.listeners})
    p.subscriptions = subscriptions
  end
  local function send(label, event, ...)
    effect(c, rt); assert(type(event) == "string" and #event <= 128, "invalid event")
    local args, targets = U.data(U.pack(...), {nodes = 1024, bytes = 4096, depth = 8}), {}
    for _, id in ipairs(U.keys(storage.computers)) do
      local peer = storage.computers[id]
      if peer.process and FS.peer(c, peer) and (label == nil or peer.label == label) then targets[#targets + 1] = peer end
    end
    assert(#storage.messages + #targets <= 4096, "message queue is full")
    for _, peer in ipairs(targets) do queue(peer, "message", event, args, c.id) end
    return #targets
  end
  wlan.emit = function(label, event, ...) assert(type(label) == "string", "label must be text"); return send(label, event, ...) end
  wlan.broadcast = function(event, ...) return send(nil, event, ...) end
  if c.sub then
    env.lan = {}
    for _, side in ipairs({"left", "right"}) do
      local name = side == "left" and "Left" or "Right"
      env.lan["read" .. name .. "Signals"] = function(wire) assert(not rt.rebuilding, "read circuits in a handler"); return A.read(c.sub[side .. "_combinator"], wire, c.outputs[side]) end
      env.lan["write" .. name .. "Signals"] = function(signals) effect(c, rt); c.outputs[side] = A.write(c.sub[side .. "_combinator"], signals) end
      env.lan["get" .. name .. "Signals"] = env.lan["read" .. name .. "Signals"]
      env.lan["set" .. name .. "Signals"] = env.lan["write" .. name .. "Signals"]
    end
    env.speaker = {
      mute = function() effect(c, rt); A.mute(c) end,
      playNote = function(...) effect(c, rt); A.play(c, ...) end,
      setAlert = function(...) effect(c, rt); A.alert(c, ...) end,
      getInstruments = function() return U.data(A.instruments(c)) end,
      print = function(text, force)
        effect(c, rt)
        if force == false then
          local player = c.operator and game.get_player(c.operator)
          assert(player and player.valid and player.force.index == c.force_index, "no authorized operator")
          player.print(U.text(text))
        else game.forces[c.force_index].print(U.text(text)) end
      end
    }
  end
  env.print = term.write
  env.require = os.require
  env.load = function(source, name, mode)
    assert(type(source) == "string" and #source <= 262144 and (mode == nil or mode == "t"), "only bounded Lua source is supported")
    return load(source, name, "t", env)
  end
  M.extensions(c, rt, env)
  return env
end
-- Extension source is persistent; constructed functions and wrappers are not.
-- New extensions should use __state for their durable fields.
function M.extensions(c, rt, env)
  for _, name in ipairs(U.keys(c.process.extensions)) do
    local source = c.process.extensions[name]
    local construct, err = load(source, "@extension:" .. name, "t", {assert = assert, error = error, pairs = pairs, ipairs = ipairs, next = next, select = select, type = type, tostring = tostring, tonumber = tonumber, table = env.table, string = env.string, math = env.math, unpack = table.unpack, defines = defines})
    assert(construct, err)
    local definition = construct()
    local allowed = definition.entities == nil
    if type(definition.entities) == "function" then allowed = c.entity and c.entity.valid and definition.entities(c.entity)
    elseif type(definition.entities) == "table" then for _, v in ipairs(definition.entities) do if c.entity and c.entity.valid and c.entity.name == v then allowed = true end end end
    if allowed then
      assert(not env[name], "extension shadows built-in API")
      local instance = {__name = name, __state = U.data(c.extension_state[name] or {}), __entity = c.entity, __entityStructure = c.structure or {entity = c.entity, sub = c.sub},
        __env = env, __getID = function() return c.id end,
        __getLabel = function() return c.label end, __getGameTick = function() return game.tick end,
        __getAPI = function(api) return env[api] end,
        __getWaypoint = env.os.getWaypoint, __emit = env.wlan.emit, __broadcast = env.wlan.broadcast,
        __getOutput = env.term.getOutput, __setOutput = function(text) effect(c, rt); M.output(c, U.text(text), true) end,
        __getInput = env.term.getInput, __setInput = env.term.setInput,
        __setLabel = env.os.setComputerLabel, __require = env.os.require,
        __readFile = env.disk.readFile, __writeFile = env.disk.writeFile,
        __removeFile = env.disk.removeFile, __fileExist = env.disk.fileExist
      }
      setmetatable(instance, {__index = function(_, key)
        if key == "__player" then return c.operator and game.get_player(c.operator) end
      end})
      for key, value in pairs(definition.prototype or {}) do instance[key] = value[2] end
      local proxy = {}
      for key, value in pairs(definition.prototype or {}) do
        if key:sub(1, 1) ~= "_" then
          assert(type(value[2]) == "function", "extension method must be a function")
          proxy[key] = function(...) effect(c, rt); return instance[key](instance, ...) end
        end
      end
      rt.extensions[name] = {instance = instance, definition = definition}
      env[name] = proxy
    end
  end
end
build = function(c, rebuilding)
  local p = c.process
  local rt = {generation = p.generation, rebuilding = rebuilding, replay = rebuilding, constructing = true, handlers = {}, extensions = {}, library_results = {}, loading = {}}
  rt.env = environment(c, rt)
  local fn, err = load(p.source, "@" .. p.path, "t", rt.env)
  assert(fn, err)
  local result = fn()
  if type(result) == "table" then
    for name, callback in pairs(result) do
      assert(type(name) == "string" and type(callback) == "function", "program must return a table of named functions")
      rt.handlers[handler(name)] = callback
    end
  end
  if rebuilding then
    assert(U.equal(c.state, U.data(rt.env.state)), "persistent module scope must not modify state")
    for name, entry in pairs(rt.extensions) do
      assert(U.equal(c.extension_state[name] or {}, U.data(entry.instance.__state)), "extension module scope must not modify state")
    end
  end
  rt.constructing, rt.rebuilding, rt.replay = false, false, false
  return rt
end
local function persist(c, rt)
  local state = U.data(rt.env.state)
  assert(type(state) == "table", "state must be a plain table")
  local ext = U.data(c.extension_state)
  for name, entry in pairs(rt.extensions) do ext[name] = U.data(entry.instance.__state) end
  c.state, c.extension_state = state, ext
end
function M.invoke(c, name, args)
  -- Reconstruct for every dispatch, not merely after a disk load. Otherwise
  -- mutated captured locals differ on a joining client and cause desyncs.
  local ok, rt = pcall(build, c, true)
  if not ok then M.stop(c, rt); return false end
  runtimes[c.id] = rt
  local generation = rt.generation
  local fn = rt.handlers[name]
  if not fn then M.stop(c, "unknown handler: " .. tostring(name)); return false end
  local ok, err = pcall(function() fn(U.unpack(args or {})); if c.process and c.process.generation == generation then persist(c, rt) end end)
  if not ok then M.stop(c, err) end
  return ok
end
function M.extension_event(c, event, args)
  if not c.process then return end
  local generation = c.process.generation
  for _, name in ipairs(U.keys(c.process.extensions)) do
    if not c.process or c.process.generation ~= generation then break end
    -- Each callback gets a fresh declaration environment, exactly like handlers.
    local ok, rt = pcall(build, c, true)
    if not ok then M.stop(c, rt); return end
    local entry = rt.extensions[name]
    local callback = entry and (entry.definition.events or {})[event]
    if callback then
      local success, err = pcall(function()
        callback(entry.instance, U.unpack(args or {}))
        if c.process and c.process.generation == generation then persist(c, rt) end
      end)
      if not success then M.stop(c, err); return end
    end
  end
end
function M.start(c, source, path, args)
  assert(not c.process, "script already running; stop it first")
  assert(type(source) == "string" and #source <= 262144, "program exceeds source limit")
  args = U.data(args or {})
  assert(type(args) == "table", "arguments must be a plain table")
  path = FS.path(c, path or "program")
  local directory = path:match("^(.*)/[^/]+$")
  if directory == "" then directory = "/" end
  local extension_sources = U.data(storage.extensions, {nodes = 1024, bytes = 1064960, depth = 2})
  c.generation = c.generation + 1
  c.process = {generation = c.generation, source = source, path = path, directory = directory, args = args, extensions = extension_sources, timers = {}, next_timer = 0, listeners = {}, next_listener = 0, subscriptions = {}, libraries = {}}
  local ok, rt = pcall(function()
    local runtime = build(c, false)
    for _, timer in ipairs(c.process.timers) do assert(runtime.handlers[timer.handler], "unknown timer handler: " .. timer.handler) end
    for _, listener in pairs(c.process.listeners) do assert(runtime.handlers[listener.handler], "unknown terminal handler: " .. listener.handler) end
    for _, subscription in ipairs(c.process.subscriptions) do assert(runtime.handlers[subscription.handler], "unknown wireless handler: " .. subscription.handler) end
    persist(c, runtime)
    return runtime
  end)
  if not ok then M.stop(c, rt); return false, rt end
  runtimes[c.id] = rt
  for _, name in ipairs(U.keys(rt.extensions)) do
    local entry = rt.extensions[name]
    if entry.instance.__init then
      local success, err = pcall(function() entry.instance:__init(); persist(c, rt) end)
      if not success then M.stop(c, err); return false, err end
    end
  end
  if rt.handlers.init and not M.invoke(c, "init", c.process.args) then return false, "init failed" end
  -- One-shot programs need no reconstruction unless an extension has tick work.
  local extension_ticks, extension_events = false, false
  for _, entry in pairs(rt.extensions) do
    for event in pairs(entry.definition.events or {}) do
      if event == "on_tick" then extension_ticks = true end
      if event ~= "on_script_kill" then extension_events = true end
    end
  end
  c.process.extension_ticks = extension_ticks
  if next(rt.handlers) == nil and not extension_events then
    c.process = nil; runtimes[c.id] = nil
  else
    local success, checked = pcall(build, c, true)
    if not success then M.stop(c, checked); return false, checked end
    runtimes[c.id] = checked
  end
  return true
end
function M.on_load()
  -- No player/extension code runs in on_load: game is unavailable and
  -- storage is read-only. Dispatch reconstructs identically on all peers.
  runtimes = {}
end
function M.powered(c)
  if c.personal then
    local player = game.get_player(c.player_index)
    local tech = player and player.force.technologies["computer-gauntlet-technology"]
    return player and player.valid and player.character and player.character.valid and tech and tech.researched
  end
  return c.entity and c.entity.valid and (c.entity.electric_buffer_size == nil or c.entity.energy > 0)
end
function M.input(c, text, player_index)
  assert(type(text) == "string" and #text <= 4096, "input too long")
  c.input = text
  if not c.process or not M.powered(c) then return end
  M.extension_event(c, "on_gui_text_changed", {n = 1, {tick = game.tick, player_index = player_index, userInput = text}})
  if not c.process then return end
  local listeners = U.data(c.process.listeners)
  for _, id in ipairs(U.keys(listeners)) do
    local entry = listeners[id]
    if entry.kind == "input" and c.process then M.invoke(c, entry.handler, U.pack({listenerID = id, userInput = text, player_index = player_index})) end
  end
end
function M.built(c)
  c.autorun_available = true
  for _, id in ipairs(U.keys(storage.computers)) do
    local peer = storage.computers[id]
    if peer.process and FS.peer(c, peer) then queue(peer, "built", "built", U.pack({computerID = c.id, position = U.data(c.position), surface_index = c.surface_index}), c.id) end
  end
end
function M.tick()
  for _, id in ipairs(U.keys(storage.computers)) do
    local c = storage.computers[id]
    if c.process and M.powered(c) then
      local generation = c.process.generation
      if c.process.extension_ticks then M.extension_event(c, "on_tick", {n = 1, {tick = game.tick}}) end
      local due, remaining = {}, {}
      for _, t in ipairs(c.process and c.process.timers or {}) do
        if t.due <= game.tick then due[#due + 1] = t else remaining[#remaining + 1] = t end
      end
      if c.process then c.process.timers = remaining end -- Remove before callbacks: never execute twice.
      table.sort(due, function(a, b) return a.due == b.due and a.id < b.id or a.due < b.due end)
      for _, t in ipairs(due) do if c.process and c.process.generation == generation then M.invoke(c, t.handler, t.args) end end
      if c.process and c.process.output_dirty then
        c.process.output_dirty = nil
        M.extension_event(c, "after_text_print", {n = 1, {tick = game.tick, output = c.output}})
        local listeners = U.data(c.process and c.process.listeners or {})
        for _, listener_id in ipairs(U.keys(listeners)) do
          local entry = listeners[listener_id]
          if entry.kind == "output" and c.process then M.invoke(c, entry.handler, U.pack({listenerID = listener_id})) end
        end
      end
    end
  end
  local pending, ready = {}, {}
  for _, message in ipairs(storage.messages) do
    local c = storage.computers[message.target]
    local source = storage.computers[message.source]
    if c and c.process and c.process.generation == message.generation and source and FS.peer(source, c) then
      if message.due <= game.tick and M.powered(c) then ready[#ready + 1] = message else pending[#pending + 1] = message end
    end
  end
  storage.messages = pending
  for _, message in ipairs(ready) do
    local c = storage.computers[message.target]
    if c and c.process and c.process.generation == message.generation then
      local args = {n = message.args.n}
      for i = 1, message.args.n do args[i] = U.data(message.args[i]) end
      if message.kind == "built" and args[1] then
        local target_id = args[1].computerID
        args[1].autorun = function(source, name)
          local target = storage.computers[target_id]
          assert(target and FS.peer(c, target) and target.autorun_available and not target.process and M.powered(target), "autorun target unavailable/already claimed")
          assert(type(source) == "string", "autorun expects Lua source, not a function")
          target.autorun_available = nil
          return M.start(target, source, name or "autorun")
        end
        M.extension_event(c, "on_built_computer", args)
      elseif message.kind == "message" then
        M.extension_event(c, message.event, args)
        local envelope = {n = args.n + 1, message.event}
        for i = 1, args.n do envelope[i + 1] = args[i] end
        M.extension_event(c, "on_message", envelope)
      end
      local autorun = message.kind == "built" and args[1] and args[1].autorun
      local subscriptions = U.data(c.process and c.process.subscriptions or {})
      for _, sub in ipairs(subscriptions) do
        if sub.kind == message.kind and sub.event == message.event and c.process and c.process.generation == message.generation then
          local args = {n = message.args.n + sub.args.n}
          for i = 1, message.args.n do args[i] = U.data(message.args[i]) end
          for i = 1, sub.args.n do args[message.args.n + i] = sub.args[i] end
          if message.kind == "built" and args[1] then args[1].autorun = autorun end
          M.invoke(c, sub.handler, args)
        end
      end
    end
  end
end
function M.extension_help(c, name)
  local sources = c.process and c.process.extensions or storage.extensions
  local source = sources[name]
  if not source then return end
  local definition = assert(load(source, "@extension:" .. name, "t", {
    assert = assert, error = error, type = type, pairs = pairs, ipairs = ipairs,
    next = next, select = select, tonumber = tonumber, tostring = tostring,
    unpack = table.unpack, table = table, string = string, math = math, defines = defines
  }))()
  local lines = {type(definition.description) == "string" and definition.description or name}
  for _, method in ipairs(U.keys(definition.prototype or {})) do
    local entry = definition.prototype[method]
    if method:sub(1, 1) ~= "_" and type(entry) == "table" and type(entry[1]) == "string" then lines[#lines + 1] = entry[1] end
  end
  return table.concat(lines, "\n")
end
function M.supports(entity)
  if not entity or not entity.valid then return false end
  if entity.name == "computer-interface-entity" then return true end
  for _, name in ipairs(U.keys(storage.extensions)) do
    local ok, result = pcall(function()
      local fn = assert(load(storage.extensions[name], "@extension", "t", {assert = assert, type = type, pairs = pairs, ipairs = ipairs, table = table, string = string, math = math, defines = defines}))
      local definition = fn()
      if type(definition.entities) == "function" then return definition.entities(entity) end
      if type(definition.entities) == "table" then for _, candidate in ipairs(definition.entities) do if candidate == entity.name then return true end end end
      return false
    end)
    if ok and result then return true end
  end
  return false
end
function M.register(source)
  assert(type(source) == "string" and #source <= 262144, "API must be bounded source text")
  local fn, err = load(source, "@extension", "t", {assert = assert, type = type, pairs = pairs, ipairs = ipairs, table = table, string = string, math = math, defines = defines})
  assert(fn, err)
  local definition = fn()
  assert(type(definition) == "table" and type(definition.name) == "string" and definition.name:match("^[%a_][%w_]*$"), "API requires a name")
  assert(not ({os = true, term = true, disk = true, lan = true, wlan = true, speaker = true, state = true})[definition.name], "reserved API name")
  local count, bytes = 0, #source
  for name, old in pairs(storage.extensions) do
    count = count + 1
    if name ~= definition.name then bytes = bytes + #old end
  end
  assert(bytes <= 1048576 and (storage.extensions[definition.name] or count < 64), "extension registry quota exceeded")
  storage.extensions[definition.name] = source
  return definition.name
end
return M
