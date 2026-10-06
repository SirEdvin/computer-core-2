local U = require("scripts.util")
local FS = require("scripts.filesystem")
local R = require("scripts.os_runtime")
local A = require("scripts.adapters")
local M = {}
local specs = {
  left_combinator = {name = "computer-combinator", x = -0.83, y = 0.51},
  right_combinator = {name = "computer-combinator", x = 0.76, y = 0.51},
  lamp = {name = "computer-lamp", x = 0, y = 0},
  speaker = {name = "computer-speaker", x = 0, y = 0},
  speaker_combinator = {name = "computer-speaker-combinator", x = 0, y = 0}
}
function M.init()
  storage.schema = storage.schema or 1
  storage.computers = storage.computers or {}
  storage.units = storage.units or {}
  storage.children = storage.children or {}
  storage.destroyed = storage.destroyed or {}
  storage.personal = storage.personal or {}
  storage.sessions = storage.sessions or {}
  storage.drafts = storage.drafts or {}
  storage.waypoints = storage.waypoints or {}
  storage.extensions = storage.extensions or {}
  storage.messages = storage.messages or {}
  storage.next_computer = storage.next_computer or 0
  storage.next_message = storage.next_message or 0
end
local function allocate()
  storage.next_computer = storage.next_computer + 1
  local c = {id = storage.next_computer, generation = 0, output = "", input = "", state = {}, vars = {}, extension_state = {}, outputs = {left = {}, right = {}}}
  FS.init(c)
  storage.computers[c.id] = c
  return c
end
function M.sync(c)
  local entity = c.entity
  if not entity or not entity.valid then return end
  c.position = {x = entity.position.x, y = entity.position.y}
  c.force_index, c.surface_index = entity.force.index, entity.surface.index
end
local function adopt(c, spec)
  local position = {x = c.entity.position.x + spec.x, y = c.entity.position.y + spec.y}
  local surface, force = c.entity.surface, c.entity.force
  local candidates = surface.find_entities_filtered{position = position, radius = 0.05, name = spec.name, force = force}
  for _, child in ipairs(candidates) do
    if not storage.children[child.unit_number] then return child end
  end
  for _, ghost in ipairs(surface.find_entities_filtered{position = position, radius = 0.05, name = "entity-ghost", ghost_name = spec.name, force = force}) do
    local _, revived = ghost.revive{raise_revive = false}
    if revived then return revived end
  end
  return surface.create_entity{name = spec.name, position = position, force = force, direction = defines.direction.south, create_build_effect_smoke = false}
end
function M.ensure(c)
  if not c.entity or not c.entity.valid then return end
  M.sync(c)
  if c.external then return end
  c.sub = c.sub or {}
  for _, key in ipairs(U.keys(specs)) do
    local spec, child = specs[key], c.sub[key]
    local created = not child or not child.valid
    if created then
      for unit, owner in pairs(storage.children) do if owner.id == c.id and owner.key == key then storage.children[unit] = nil end end
      child = adopt(c, spec); assert(child, "failed to create " .. spec.name); c.sub[key] = child
      if key == "speaker" or key == "speaker_combinator" then c._restore_sound = true end
    end
    child.destructible, child.minable, child.operable = false, false, false
    child.force = c.entity.force
    child.teleport{x = c.entity.position.x + spec.x, y = c.entity.position.y + spec.y}
    storage.children[child.unit_number] = {id = c.id, key = key}
    if created and (key == "left_combinator" or key == "right_combinator") then A.write(child, c.outputs[key == "left_combinator" and "left" or "right"]) end
  end
  if c.sound and c._restore_sound then
    c._restore_sound = nil
    local s = c.sound
    if s.kind == "note" then A.play(c, s.note, s.instrument, s.volume, s.polyphony) else A.alert(c, s.text, s.signal, s.sound) end
  end
end
function M.build(entity, tags)
  if not entity or not entity.valid or entity.name ~= "computer-interface-entity" then return end
  local existing = storage.units[entity.unit_number]
  if existing then M.ensure(storage.computers[existing]); return storage.computers[existing] end
  local c = allocate()
  c.entity = entity
  M.sync(c)
  storage.units[entity.unit_number] = c.id
  c.registration = script.register_on_object_destroyed(entity)
  storage.destroyed[c.registration] = c.id
  if tags and tags.computer_core_2 then
    local ok, snapshot = pcall(U.data, tags.computer_core_2, {nodes = 65536, bytes = 4194304, depth = 32})
    if ok and type(snapshot) == "table" and type(snapshot.fs) == "table" then
      -- Blueprint payloads are untrusted; validate the complete filesystem first.
      local valid = pcall(function()
        local probe = {id = c.id, cwd = "/", fs = {['/'] = {type = "dir"}}}
        local paths = U.keys(snapshot.fs)
        table.sort(paths, function(a, b) return #a == #b and a < b or #a < #b end)
        for _, path in ipairs(paths) do
          local node = snapshot.fs[path]
          assert(type(path) == "string" and FS.path(probe, path) == path and path ~= "/mnt" and not path:match("^/mnt/") and type(node) == "table", "invalid blueprint filesystem")
          if path ~= "/" then FS.put(probe, path, node.text, node.type); assert(node.type == "file" or node.type == "dir", "invalid node type") end
        end
        c.fs = probe.fs
      end)
      if not valid then R.output(c, "Blueprint files rejected: invalid filesystem\n") end
    end
  end
  M.ensure(c)
  c.new = true
  return c
end
function M.attach(entity, structure)
  assert(entity and entity.valid and entity.unit_number, "extension requires a valid entity with a unit number")
  local id = storage.units[entity.unit_number]
  if id then return storage.computers[id] end
  local c = allocate()
  c.entity, c.external = entity, true
  if structure then
    assert(type(structure.sub or {}) == "table", "structure.sub must be entity references")
    local sub = {}
    for key, child in pairs(structure.sub or {}) do
      assert(type(key) == "string" and child.valid and child.object_name == "LuaEntity", "invalid structure child")
      sub[key] = child
    end
    c.structure = {entity = entity, type = structure.type, sub = sub}
  end
  M.sync(c)
  storage.units[entity.unit_number] = c.id
  c.registration = script.register_on_object_destroyed(entity)
  storage.destroyed[c.registration] = c.id
  c.new = true
  return c
end
function M.personal(player)
  local id = storage.personal[player.index]
  local c = id and storage.computers[id]
  if not c then c = allocate(); c.personal = true; c.player_index = player.index; storage.personal[player.index] = c.id end
  c.position = {x = player.position.x, y = player.position.y}
  c.force_index, c.surface_index = player.force.index, player.surface.index
  return c
end
function M.remove(id)
  local c = storage.computers[id]
  if not c then return end
  R.stop(c)
  if c.sub then
    for _, child in pairs(c.sub) do
      if child.valid then storage.children[child.unit_number] = nil; child.destroy() end
    end
  end
  for unit, cid in pairs(storage.units) do if cid == id then storage.units[unit] = nil end end
  if c.registration then storage.destroyed[c.registration] = nil end
  if c.personal then storage.personal[c.player_index] = nil end
  storage.computers[id] = nil
end
function M.removed(entity)
  if entity and entity.valid then
    local id = storage.units[entity.unit_number]
    if id then M.remove(id) end
  end
end
function M.clone(source, destination)
  if not destination or not destination.valid then return end
  if destination.name == "computer-interface-entity" then
    local original = source and source.valid and storage.computers[storage.units[source.unit_number]]
    local c = M.build(destination)
    if original then
      c.fs, c.state, c.vars = U.data(R.files(original), {nodes = 65536, bytes = 4194304, depth = 32}), U.data(original.state), U.data(original.vars)
      c.extension_state = U.data(original.extension_state)
      -- Deliberately do not copy identity, label, running process or pending effects.
    end
  elseif specs.left_combinator.name == destination.name or destination.name:match("^computer%-speaker") or destination.name == "computer-lamp" then
    -- The parent creates/adopts its own children. Transfer external wires from
    -- cloned duplicates to the corresponding owned child before removing them.
    for _, c in pairs(storage.computers) do
      if c.sub and c.entity.valid and c.surface_index == destination.surface.index and c.force_index == destination.force.index then
        for _, key in ipairs(U.keys(specs)) do
          local child = c.sub[key]
          if child.valid and child.name == destination.name and math.abs(child.position.x - destination.position.x) < 0.05 and math.abs(child.position.y - destination.position.y) < 0.05 then
            for connector_id, connector in pairs(destination.get_wire_connectors(false)) do
              local target = child.get_wire_connector(connector_id, true)
              for _, connection in pairs(connector.connections) do target.connect_to(connection.target, false, connection.origin) end
            end
            destination.destroy()
            return
          end
        end
      end
    end
  end
end
function M.tick()
  for _, id in ipairs(U.keys(storage.computers)) do
    local c = storage.computers[id]
    if c.personal then
      local p = game.get_player(c.player_index)
      if not p then M.remove(id) else M.personal(p) end
    elseif not c.entity or not c.entity.valid then M.remove(id)
    else
      M.sync(c)
      if game.tick % 60 == 0 then M.ensure(c) end
      if c.new and R.powered(c) then c.new = nil; R.built(c) end
    end
  end
  -- Orphaned blueprint/clone children are never allowed to become immortal.
  if game.tick % 120 == 0 then
    for _, surface in pairs(game.surfaces) do
      for _, entity in ipairs(surface.find_entities_filtered{name = {"computer-combinator", "computer-lamp", "computer-speaker", "computer-speaker-combinator"}}) do
        if not storage.children[entity.unit_number] then entity.destroy() end
      end
    end
  end
end
function M.snapshot(c)
  return {computer_core_2 = {fs = U.data(R.files(c), {nodes = 65536, bytes = 4194304, depth = 32})}}
end
return M
