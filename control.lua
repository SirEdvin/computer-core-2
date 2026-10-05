local U = require("scripts.util")
local L = require("scripts.lifecycle")
local R = require("scripts.runtime")
local FS = require("scripts.filesystem")
local S = require("scripts.shell")
local GUI = require("scripts.gui")
local function initialize()
  L.init()
  for _, surface in pairs(game.surfaces) do
    for _, entity in ipairs(surface.find_entities_filtered{name = "computer-interface-entity"}) do L.build(entity) end
  end
end
script.on_init(initialize)
script.on_load(R.on_load)
script.on_configuration_changed(function()
  initialize()
  -- Existing source snapshots continue; each dispatch reconstructs its runtime.
  for _, c in pairs(storage.computers) do if c.sub then L.ensure(c) end end
end)
script.on_event(defines.events.on_tick, function()
  L.tick()
  R.tick()
  if game.tick % 6 == 0 then GUI.tick() end
end)
local function built(event)
  L.build(event.entity or event.created_entity or event.destination, event.tags)
end
script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity, defines.events.script_raised_built, defines.events.script_raised_revive}, built)
script.on_event(defines.events.on_entity_cloned, function(event) L.clone(event.source, event.destination) end)
script.on_event({defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined, defines.events.on_entity_died, defines.events.script_raised_destroy}, function(event) L.removed(event.entity) end)
script.on_event(defines.events.on_object_destroyed, function(event)
  local id = storage.destroyed[event.registration_number]
  if id then L.remove(id) end
end)
script.on_event(defines.events.on_pre_surface_deleted, function(event)
  for _, id in ipairs(U.keys(storage.computers)) do if not storage.computers[id].personal and storage.computers[id].surface_index == event.surface_index then L.remove(id) end end
  for key in pairs(storage.waypoints) do if key:match(":" .. event.surface_index .. "$") then storage.waypoints[key] = nil end end
end)
script.on_event(defines.events.on_forces_merged, function(event)
  -- Sync first; labels colliding after a force merge are cleared deterministically.
  local labels = {}
  for _, id in ipairs(U.keys(storage.computers)) do
    local c = storage.computers[id]
    if c.personal then local p = game.get_player(c.player_index); if p then L.personal(p) end else L.sync(c); L.ensure(c) end
    local key = c.force_index .. ":" .. c.surface_index .. ":" .. (c.label or "")
    if c.label then if labels[key] then c.label = nil else labels[key] = true end end
  end
  local source_prefix = event.source_index .. ":"
  for _, key in ipairs(U.keys(storage.waypoints)) do
    if key:sub(1, #source_prefix) == source_prefix then
      local target = event.destination.index .. ":" .. key:sub(#source_prefix + 1)
      storage.waypoints[target] = storage.waypoints[target] or {}
      for _, name in ipairs(U.keys(storage.waypoints[key])) do
        local unique = name; local n = 1
        while storage.waypoints[target][unique] do n = n + 1; unique = name .. "-" .. n end
        local point = storage.waypoints[key][name]; point.name = unique; storage.waypoints[target][unique] = point
      end
      storage.waypoints[key] = nil
    end
  end
end)
script.on_event(defines.events.on_player_removed, function(event)
  local id = storage.personal[event.player_index]
  if id then L.remove(id) end
  storage.sessions[event.player_index] = nil
  storage.drafts[event.player_index] = nil
end)
script.on_event(defines.events.on_player_left_game, function(event) local player = game.get_player(event.player_index); if player then GUI.close(player, true) end end)
script.on_event("open-computer", function(event)
  local player = game.get_player(event.player_index)
  local entity = player.selected
  local id = entity and entity.valid and (storage.units[entity.unit_number] or (storage.children[entity.unit_number] or {}).id)
  if not id and R.supports(entity) then id = L.attach(entity).id end
  if id then GUI.open(player, storage.computers[id]) end
end)
script.on_event("open-computer-gauntlet", function(event) GUI.gauntlet(game.get_player(event.player_index)) end)
script.on_event(defines.events.on_lua_shortcut, function(event) if event.prototype_name == "computer-gauntlet" then GUI.gauntlet(game.get_player(event.player_index)) end end)
script.on_event(defines.events.on_gui_opened, function(event)
  local entity = event.entity
  if entity and entity.valid then
    local id = storage.units[entity.unit_number] or (storage.children[entity.unit_number] or {}).id
    if not id and R.supports(entity) then id = L.attach(entity).id end
    if id then GUI.open(game.get_player(event.player_index), storage.computers[id]) end
  end
end)
script.on_event({defines.events.on_gui_click, defines.events.on_gui_text_changed, defines.events.on_gui_confirmed, defines.events.on_gui_selection_state_changed}, GUI.event)
script.on_event(defines.events.on_gui_closed, GUI.closed)
script.on_event(defines.events.on_player_setup_blueprint, function(event)
  local player = game.get_player(event.player_index)
  local blueprint = player.blueprint_to_setup
  if not blueprint or not blueprint.valid_for_read or not blueprint.is_blueprint then return end
  local mapping = event.mapping and event.mapping.get() or {}
  for index, entity in pairs(mapping) do
    local id = entity.valid and storage.units[entity.unit_number]
    if id then blueprint.set_blueprint_entity_tags(index, L.snapshot(storage.computers[id])) end
  end
end)
local function get(id)
  assert(type(id) == "number" and storage.computers[id], "unknown computer ID")
  return storage.computers[id]
end
local interface = {
  addComputerAPI = R.register,
  addEntityStructure = function(structure)
    assert(type(structure) == "table" and R.supports(structure.entity), "structure entity requires a registered API selector")
    return L.attach(structure.entity, structure).id
  end,
  registerEntity = function(entity) assert(R.supports(entity), "entity has no registered API selector"); return L.attach(entity).id end,
  removeComputerAPI = function(name) storage.extensions[name] = nil end,
  getComputerIDs = function() return U.keys(storage.computers) end,
  getComputer = function(id)
    local c = get(id)
    return {id = c.id, label = c.label, position = U.data(c.position), force_index = c.force_index, surface_index = c.surface_index, personal = c.personal, player_index = c.player_index, powered = not not R.powered(c), running = c.process ~= nil, state = U.data(c.state), output = c.output, input = c.input, outputs = U.data(c.outputs), fs = U.data(c.fs, {nodes = 65536, bytes = 4194304, depth = 32}), vars = U.data(c.vars), extension_state = U.data(c.extension_state), process = c.process and U.data(c.process, {nodes = 65536, bytes = 4194304, depth = 32})}
  end,
  getEntity = function(id) return get(id).entity end,
  getPorts = function(id) local c = get(id); return c.sub and {left = c.sub.left_combinator, right = c.sub.right_combinator, speaker = c.sub.speaker, music = c.sub.speaker_combinator, lamp = c.sub.lamp} end,
  run = function(id, source, name, args) return R.start(get(id), source, name, args) end,
  stop = function(id) R.stop(get(id)) end,
  exec = function(id, line) return S.execute(get(id), line) end,
  input = function(id, text) R.input(get(id), text) end,
  open = function(id, player_index) return GUI.open(game.get_player(player_index), get(id)) end,
  openGauntlet = function(player_index) return GUI.gauntlet(game.get_player(player_index)) end,
  snapshot = function(id) return L.snapshot(get(id)) end
}
-- Compatibility discovery name retained for companion mods, with a source-only
-- extension contract. All remote callers are trusted Factorio mods, not players.
remote.add_interface("computer_core", interface)
remote.add_interface("computer_core_2", interface)
