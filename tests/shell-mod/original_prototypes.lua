-- Derive engine-owned schemas from the pinned base prototypes; retain upstream art.
-- Styles are checked independently; return frozen original prototype definitions.
local prefix = "__computer_core_2__/graphics/"
local blank = {filename = prefix .. "blank.png", width = 1, height = 1}
local computer = table.deepcopy(data.raw["electric-energy-interface"]["electric-energy-interface"])
computer.name = "computer-interface-entity"
computer.icon = prefix .. "icons/computer-icon.png"
computer.icon_size = 32
computer.flags = {"placeable-neutral", "placeable-player", "player-creation"}
computer.minable = {mining_time = 2, result = "computer-item"}
computer.max_health = 250
computer.collision_box = {{-1.2, -0.65}, {1.2, 0.65}}
computer.selection_box = {{-1.5, -1}, {1.5, 1}}
computer.selection_priority = 50
computer.energy_source = {type = "electric", usage_priority = "primary-input", buffer_capacity = "5MJ", input_flow_limit = "300kW", output_flow_limit = "0kW"}
computer.energy_production = "0kW"
computer.energy_usage = "50kW"
computer.gui_mode = "none"
computer.picture = {filename = prefix .. "entities/computer_hr.png", width = 1000, height = 800, shift = {2.1, -1.1}, scale = 0.25}
local port = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
port.name = "computer-combinator"
port.minable = {mining_time = 0.1, result = "computer-combinator-item"}
port.flags = {"placeable-player", "player-creation", "placeable-off-grid", "not-deconstructable"}
port.collision_box = {{0, 0}, {0, 0}}
port.collision_mask = {layers = {}}
port.selection_box = {{-0.4, -0.4}, {0.4, 0.4}}
port.selection_priority = 100
-- These entities sit directly on the artwork's legs, not on a vanilla
-- combinator. Inherited directional wire points displaced both wire ends.
port.circuit_wire_connection_points = {}
for i = 1, 4 do
  port.circuit_wire_connection_points[i] = {wire = {red = {0, 0}, green = {0, 0}}, shadow = {red = {0, 0}, green = {0, 0}}}
end
port.sprites = {north = blank, east = blank, south = blank, west = blank}
port.activity_led_sprites = table.deepcopy(port.sprites)
port.activity_led_light = {intensity = 0, size = 1}
local music = table.deepcopy(port)
music.name = "computer-speaker-combinator"
music.flags = {"placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable", "not-selectable-in-game"}
music.selection_box = {{0, 0}, {0, 0}}
local lamp = table.deepcopy(data.raw.lamp["small-lamp"])
lamp.name = "computer-lamp"
lamp.minable = nil
lamp.flags = table.deepcopy(music.flags)
lamp.collision_box = {{0, 0}, {0, 0}}
lamp.collision_mask = {layers = {}}
lamp.selection_box = {{0, 0}, {0, 0}}
lamp.picture_off = blank
lamp.picture_on = blank
local speaker = table.deepcopy(data.raw["programmable-speaker"]["programmable-speaker"])
speaker.name = "computer-speaker"
speaker.minable = nil
speaker.flags = table.deepcopy(music.flags)
speaker.collision_box = {{0, 0}, {0, 0}}
speaker.collision_mask = {layers = {}}
speaker.selection_box = {{0, 0}, {0, 0}}
speaker.sprite = blank
local science = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1}, {"utility-science-pack", 1}}
return {computer, port, music, lamp, speaker,
  {type = "item", name = "computer-combinator-item", icon = "__base__/graphics/icons/constant-combinator.png", icon_size = 64, hidden = true, place_result = port.name, stack_size = 50},
  {type = "item", name = "computer-item", icon = computer.icon, icon_size = 32, subgroup = "circuit-network", order = "z[computer]", place_result = computer.name, stack_size = 10},
  {type = "item", name = "computer-gauntlet-equipment", icon = prefix .. "icons/computer-gauntlet-icon.png", icon_size = 32, subgroup = "equipment", order = "z[computer]", stack_size = 1},
  {type = "recipe", name = "computer-recipe", enabled = false, energy_required = 20, ingredients = {{type = "item", name = "iron-plate", amount = 9}, {type = "item", name = "steel-plate", amount = 5}, {type = "item", name = "copper-cable", amount = 28}, {type = "item", name = "processing-unit", amount = 4}}, results = {{type = "item", name = "computer-item", amount = 1}}},
  {type = "technology", name = "computer-gauntlet-technology", icon = prefix .. "icons/computer-gauntlet-technology.png", icon_size = 128, prerequisites = {"modular-armor", "processing-unit", "battery", "utility-science-pack"}, effects = {}, unit = {count = 150, ingredients = science, time = 30}},
  {type = "technology", name = "computer-technology", icon = prefix .. "icons/computer-technology.png", icon_size = 128, prerequisites = {"computer-gauntlet-technology", "circuit-network", "logistics-3"}, effects = {{type = "unlock-recipe", recipe = "computer-recipe"}}, unit = {count = 300, ingredients = science, time = 30}},
  {type = "virtual-signal", name = "signal-music-note", icon = prefix .. "icons/note-icon.png", icon_size = 32, subgroup = "virtual-signal-special", order = "z[music]"},
  {type = "custom-input", name = "open-computer", key_sequence = "CONTROL + mouse-button-1", consuming = "game-only"},
  {type = "custom-input", name = "open-computer-gauntlet", key_sequence = "CONTROL + G", consuming = "game-only"},
  {type = "shortcut", name = "computer-gauntlet", action = "lua", associated_control_input = "open-computer-gauntlet", technology_to_unlock = "computer-gauntlet-technology", icon = prefix .. "icons/computer-gauntlet-icon.png", icon_size = 32, small_icon = prefix .. "icons/computer-gauntlet-icon.png", small_icon_size = 32}
}
