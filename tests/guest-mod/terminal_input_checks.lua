-- Table-backed keyboard routing checks, not native GUI/focus acceptance.
-- Exercise the actual GUI module and VM ingress while restoring host globals.
local GUI = require("__computer_core_2__.scripts.terminal_gui")
local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
return function(check)
  local real_game, real_storage = game, storage
  local vm = VM.new(assert(Compiler.compile("return 'key-route-pass'")))
  local frame = {valid = true, destroy = function() end}
  local tech = {researched = true}
  local player = {index = 1, valid = true, character = {valid = true},
    force = {technologies = {["computer-gauntlet-technology"] = tech}},
    opened = frame, gui = {screen = {cc2_root = frame}}}
  local computer = {id = 1, personal = true, player_index = 1, guest = vm}
  local count = 0
  local ok, err = pcall(function()
    game = {tick = 0, get_player = function(index) return index == 1 and player or nil end}
    storage = {sessions = {[1] = {id = 1}}, computers = {[1] = computer}}
    GUI.key({player_index = 1, in_gui = false}, 259)
    assert(#vm.events.queue == 2 and vm.events.queue[1].tuple[1] == 'key'
      and vm.events.queue[1].tuple[2] == 259 and vm.events.queue[2].tuple[1] == 'key_up')
    count = count + 1
    GUI.key({player_index = 1, in_gui = true, element = {valid = true}}, 263)
    assert(#vm.events.queue == 4 and vm.events.queue[3].tuple[2] == 263)
    count = count + 1
    player.opened = nil
    GUI.key({player_index = 1, in_gui = true}, 259)
    assert(#vm.events.queue == 4)
    count = count + 1
    player.opened = frame
    tech.researched = false
    GUI.key({player_index = 1, in_gui = true}, 259)
    assert(#vm.events.queue == 4 and storage.sessions[1] == nil)
    count = count + 1
  end)
  game, storage = real_game, real_storage
  assert(ok, err)
  check('mock keyboard Backspace routes with mouse outside GUI', count >= 1)
  check('mock keyboard navigation ignores foreign hovered elements', count >= 2)
  check('mock keyboard routing requires an opened terminal', count >= 3)
  check('mock keyboard routing rechecks terminal authorization', count == 4)
end
