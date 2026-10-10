-- One production scheduler dispatch per actual simulation tick. No GUI claim.
local Boot = require('__computer_core_2__.scripts.guest.boot')
local VM = require('__computer_core_2__.scripts.guest.vm')
local Scheduler = require('__computer_core_2__.scripts.guest.scheduler')
local loaded = false
local cases = {'shell', 'basic', 'advanced'}
local function check(name, value)
  assert(value, 'VM benchmark: ' .. name)
  storage.checks = storage.checks + 1
  log('CC2 VM BENCH PASS ' .. name)
end
local function waiting(vm, editor)
  if #vm.events.queue ~= 0 then return false end
  if not editor then return vm.wait ~= nil and vm.events.timer_count == 0 end
  for _, object in pairs(vm.objects) do
    if object.kind == 'coroutine' and object.status == 'suspended' then
      for _, frame in ipairs(object.frames) do
        if frame.proto and frame.proto.source:find('/rc/editors/', 1, true) then return true end
      end
    end
  end
  return false
end
local function footer(vm, expected)
  return vm.display.lines[vm.display.rows].text:sub(1, #expected) == expected
end
local function metric(label)
  local b = storage.benchmark
  local ticks = game.tick - b.first_tick + 1
  log('CC2 VM BENCH METRIC phase=' .. label .. ' ticks=' .. ticks
    .. ' instructions=' .. (b.vm.instructions - b.instructions)
    .. ' collection_work=' .. (b.collection - b.collection_start))
  check(label .. ' completed at a real simulation tick', ticks > 0)
end
local function start_phase(phase)
  local b = storage.benchmark
  b.phase, b.start = phase, game.tick
  b.first_tick = nil
  b.instructions, b.collection_start = b.vm.instructions, b.collection
end
local function boot(index)
  local b = {case = index, collection = 0, collection_start = 0,
    start = game.tick, phase = 'boot', instructions = 0}
  storage.benchmark = b
  b.vm = Boot.new({fs = {}}, {columns = 51, rows = 19})
  b.scheduler = Scheduler.new()
  Scheduler.add(b.scheduler, 1, b.vm)
end
local function send(...)
  assert(VM.queue(storage.benchmark.vm, table.pack(...)))
end
local function character()
  local b = storage.benchmark
  start_phase('character')
  send('char', 'x')
end
script.on_init(function()
  storage.checks, storage.finished = 0, false
  log('CC2 VM BENCH BOOTSTRAP PASS')
end)
script.on_load(function() loaded = true end)
script.on_event(defines.events.on_tick, function()
  if loaded then
    loaded = false
    if storage.finished then
      check('benchmark snapshot survives a separate process', storage.benchmark.case == 3
        and storage.benchmark.vm.display.lines[1].text:sub(1, 4) == 'xxxx')
      log('CC2 VM BENCH COMPLETE RELOAD checks=' .. storage.checks)
      return
    end
  end
  if storage.finished then return end
  if not storage.benchmark then boot(1) end
  local b = storage.benchmark
  local vm = b.vm
  assert(game.tick - b.start < 6000, 'VM benchmark phase exceeded 6000 actual ticks: ' .. b.phase)
  if not b.first_tick then b.first_tick = game.tick end
  local _, visited, collection = Scheduler.tick(b.scheduler, game.tick)
  assert(visited == 1, 'benchmark requires exactly one scheduler visit per game tick')
  b.collection = b.collection + collection
  for _, object in pairs(vm.objects) do
    if object.kind == 'coroutine' and object.failed then error('VM benchmark guest failure: ' .. tostring(object.error)) end
  end
  local name = cases[b.case]
  if b.phase == 'boot' and waiting(vm, false) and vm.display.lines[2].text:sub(1, 2) == '/>' then
    metric('boot-' .. name)
    if name == 'shell' then
      b.row, b.column, b.characters = vm.display.y, vm.display.x, 1
      character()
    else
      start_phase('launch')
      local command = name == 'basic' and '/rc/editors/basic.lua /benchmark.txt' or 'edit /benchmark.lua'
      send('paste', command)
      send('key', 257, false)
    end
  elseif b.phase == 'launch' and waiting(vm, true)
    and footer(vm, name == 'basic' and 'Press Control for menu' or 'Press Ctrl for menu') then
    metric('launch-' .. name)
    b.row, b.column, b.characters = vm.display.y, vm.display.x, 1
    character()
  elseif b.phase == 'character' then
    local text = vm.display.lines[b.row].text:sub(b.column, b.column + b.characters - 1)
    if text == string.rep('x', b.characters) and waiting(vm, name ~= 'shell') then
      metric(name .. '-char-' .. b.characters)
      if b.characters < 4 then
        b.characters = b.characters + 1
        character()
      elseif b.case < #cases then
        boot(b.case + 1)
      else
        storage.finished = true
        game.server_save('cc2-resume')
        log('CC2 VM BENCH SNAPSHOT tick=' .. game.tick)
        log('CC2 VM BENCH COMPLETE FIRST checks=' .. storage.checks)
      end
    end
  end
end)
