-- Exact-engine compiled continuation fixtures plus an independent hand probe.
local frontend_checks = require('compiler_checks')
local lowering_checks = require('lowering_checks')
local emission_checks = require('emission_checks')
local value_checks = require('value_checks')
local coroutine_checks = require('coroutine_checks')
local protected_checks = require('protected_checks')
local collection_checks = require('collection_checks')
local rom_inventory = require('rom_inventory')
local layout_checks = require('layout_checks')
local activation_checks = require('activation_checks')
local event_checks = require('event_checks')
local scheduler_checks = require('scheduler_checks')
local helper_checks = require('helper_checks')
local random_checks = require('random_checks')
local terminal_checks = require('terminal_checks')
local filesystem_checks = require('filesystem_checks')
local file_handle_checks = require('file_handle_checks')
local loader_checks = require('loader_checks')
local bit32_checks = require('bit32_checks')
local tostring_checks = require('tostring_checks')
local key_checks = require('key_checks')
local escape_checks = require('escape_checks')
local boot_checks = require('boot_checks')
local glob_checks = require('glob_checks')
local editor_checks = require('editor_checks')
local length_checks = require('length_checks')
local sandbox_checks = require('sandbox_checks')
local stress_checks = require('stress_checks')
local cell_pool_checks = require('cell_pool_checks')
local temporary_checks = require('temporary_checks')
local loaded = false
local source = [=[
return {
  function(frame, event)
    frame.effects = frame.effects + 1
    frame.local_value = 42
    frame.pc = 2
    return 'yield', pack('key', nil, 7)
  end,
  function(frame, event)
    if event[1] ~= 'key' then return 'yield', pack('key', nil, 7) end
    frame.result = pack(frame.local_value, event[2], nil, event[4])
    frame.effects = frame.effects + 1
    frame.pc = 3
    return 'return', frame.result
  end,
}
]=]
local function check(name, value)
  assert(value, 'native probe: ' .. name)
  storage.checks = storage.checks + 1
  log('CC2 NATIVE PASS ' .. name)
end
local function plain(value, seen)
  local kind = type(value)
  assert(kind == 'nil' or kind == 'boolean' or kind == 'number' or kind == 'string' or kind == 'table', 'non-data native probe state')
  if kind ~= 'table' then return end
  assert(getmetatable(value) == nil)
  if seen[value] then return end
  seen[value] = true
  for key, child in pairs(value) do plain(key, seen); plain(child, seen) end
end
local function executable()
  return assert(load(storage.bundle, '=native-generated-probe', 't', {pack = table.pack}))()
end
script.on_init(function()
  storage.checks = 0
  temporary_checks.run(check)
  cell_pool_checks.run(check)
  frontend_checks(check)
  lowering_checks.run(check)
  emission_checks(check)
  value_checks.run(check)
  coroutine_checks.run(check)
  protected_checks.run(check)
  collection_checks.run(check)
  rom_inventory(check)
  layout_checks.run(check)
  activation_checks.run(check)
  event_checks.run(check)
  scheduler_checks.run(check)
  helper_checks.run(check)
  random_checks.run(check)
  terminal_checks.run(check)
  filesystem_checks.run(check)
  glob_checks.run(check)
  length_checks.run(check)
  sandbox_checks.run(check)
  file_handle_checks.run(check)
  loader_checks.run(check)
  bit32_checks.run(check)
  tostring_checks.run(check)
  key_checks.run(check)
  escape_checks.run(check)
  storage.os_boot = boot_checks.run(check)
  storage.editor_sessions = editor_checks.suspend(editor_checks.run(check),check)
  storage.bundle = source
  storage.frame = {pc = 1, effects = 0}
  check('host coroutine absent in control stage', coroutine == nil)
  local sandbox = assert(load('return game, script, remote, storage, _G, debug, require, load, io, os', '=native-boundary-probe', 't', {}))
  local values = table.pack(sandbox())
  check('restricted native load hides host globals', values.n == 10)
  for i = 1, values.n do check('host global unavailable ' .. i, values[i] == nil) end
  check('binary source rejected in text-only mode', load('\27Lua', '=native-binary', 't', {}) == nil)
  check('required scalar and tuple facilities available', table.pack(1, nil, 3).n == 3
    and table.unpack and math.floor(3.5) == 3 and string.sub('tree', 2) == 'ree')
  plain(storage, {})
  log('CC2 NATIVE BOOTSTRAP PASS')
end)
script.on_load(function() loaded = true end)
script.on_event(defines.events.on_tick, function()
  if loaded then
    loaded = false
    if storage.saved then
      check('load callback preserved suspended plain frame', storage.frame.pc == 2
        and storage.frame.effects == 1 and storage.frame.local_value == 42)
      lowering_checks.reload(storage.compiled_suspension, check)
      value_checks.reload(storage.value_suspension, check)
      coroutine_checks.reload(storage.coroutine_suspension, check)
      protected_checks.reload(storage.protected_suspension, check)
      cell_pool_checks.reload(storage.cell_pool_suspension, check)

      collection_checks.reload(storage.collection_suspension, check)
      layout_checks.reload(storage.layout_suspension, check)
      activation_checks.reload(storage.activation_suspension, check)
      temporary_checks.reload(storage.temporary_suspension, check)
      event_checks.reload(storage.event_suspension, check)
      scheduler_checks.reload(storage.scheduler_suspension, check)
      stress_checks.reload(storage.stress_suspension, check)
      helper_checks.reload(storage.helper_suspension, check)
      random_checks.reload(storage.random_suspension, check)
      terminal_checks.reload(storage.terminal_suspension, check)
      filesystem_checks.reload(storage.filesystem_suspension, check)
      glob_checks.reload(storage.glob_suspension, check)
      length_checks.reload(storage.length_suspension, check)
      editor_checks.reload(storage.editor_sessions, check)
      file_handle_checks.reload(storage.file_handle_suspension, check)
      loader_checks.reload(storage.loader_suspension, check)
      bit32_checks.reload(storage.bit32_suspension, check)
      tostring_checks.reload(storage.tostring_suspension, check)
      key_checks.reload(storage.key_suspension, check)
      escape_checks.reload(storage.escape_suspension, check)
      boot_checks.reload(storage.os_boot, check)
      local blocks = executable()
      local status, tuple = blocks[storage.frame.pc](storage.frame, table.pack('key', 9, nil, 11))
      check('native continuation reconstructed without replay', status == 'return' and storage.frame.effects == 2)
      check('native resumption retains locals and nil arity', tuple.n == 4 and tuple[1] == 42
        and tuple[2] == 9 and tuple[3] == nil and tuple[4] == 11)
      plain(storage, {})
      storage.finished = true
      log('CC2 NATIVE COMPLETE RELOAD checks=' .. storage.checks)
      return
    end
  end
  if storage.finished or storage.saved then return end
  if not storage.native_stress_complete then
    storage.native_stress = storage.native_stress or stress_checks.start()
    if not stress_checks.tick(storage.native_stress, check) then return end
    storage.native_stress_complete = true
  end
  if not storage.pressure_complete then
    storage.pressure = storage.pressure or collection_checks.start_pressure()
    if not collection_checks.pressure_tick(storage.pressure, check) then return end
    storage.pressure_complete = true
  end
  if not storage.scheduler_pressure_complete then
    storage.scheduler_pressure = storage.scheduler_pressure or scheduler_checks.start_pressure()
    if not scheduler_checks.pressure_tick(storage.scheduler_pressure, check) then return end
    storage.scheduler_pressure_complete = true
  end
  storage.compiled_suspension = lowering_checks.suspend(check)
  storage.value_suspension = value_checks.suspend(check)
  storage.coroutine_suspension = coroutine_checks.suspend(check)
  storage.protected_suspension = protected_checks.suspend(check)
  storage.cell_pool_suspension = cell_pool_checks.suspend(check)
  storage.temporary_suspension = temporary_checks.suspend(check)
  storage.collection_suspension = collection_checks.suspend(check)
  storage.layout_suspension = layout_checks.suspend(check)
  storage.activation_suspension = activation_checks.suspend(check)
  storage.event_suspension = event_checks.suspend(check)
  storage.scheduler_suspension = scheduler_checks.suspend(check)
  storage.stress_suspension = stress_checks.suspend(check)
  storage.helper_suspension = helper_checks.suspend(check)
  storage.random_suspension = random_checks.suspend(check)
  storage.terminal_suspension = terminal_checks.suspend(check)
  storage.filesystem_suspension = filesystem_checks.suspend(check)
  storage.glob_suspension = glob_checks.suspend(check)
  storage.length_suspension = length_checks.suspend(check)
  storage.file_handle_suspension = file_handle_checks.suspend(check)
  storage.loader_suspension = loader_checks.suspend(check)
  storage.bit32_suspension = bit32_checks.suspend(check)
  storage.tostring_suspension = tostring_checks.suspend(check)
  storage.key_suspension = key_checks.suspend(check)
  storage.escape_suspension = escape_checks.suspend(check)
  storage.os_boot = boot_checks.suspend(storage.os_boot, check)
  local status, tuple = executable()[storage.frame.pc](storage.frame, table.pack())
  check('generated block executes natively and suspends explicitly', status == 'yield'
    and tuple.n == 3 and tuple[1] == 'key' and tuple[2] == nil and tuple[3] == 7)
  plain(storage, {})
  storage.saved = true
  game.server_save('cc2-resume')
  log('CC2 NATIVE SNAPSHOT tick=' .. game.tick)
  log('CC2 NATIVE COMPLETE FIRST checks=' .. storage.checks)
end)
