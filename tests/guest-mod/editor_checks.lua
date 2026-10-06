-- Real ROM programs driven with guest events; not graphical input acceptance.
local VM = require("__computer_core_2__.scripts.guest.vm")
local Scheduler = require("__computer_core_2__.scripts.guest.scheduler")
local M = {}
local enter, control = 257, 341 -- Pinned LWJGL3 Enter/leftCtrl identifiers.
local phase = 0
local function send(vm, ...)
  assert(VM.queue(vm, table.pack(...)))
end
local function editor_waiting(vm)
  for _, object in pairs(vm.objects) do
    if object.kind == 'coroutine' and object.status == 'suspended' then
      for _, frame in ipairs(object.frames) do
        if frame.proto and frame.proto.source:find('/rc/editors/', 1, true) then return true end
      end
    end
  end
  return false
end
local function pump(vm, predicate)
  phase = phase + 1
  local instructions, allocated = vm.instructions, vm.next_id
  local collection_ticks, collection_work, sources = 0, 0, {}
  local function report(turns)
    log('CC2 EDITOR PROFILE phase=' .. phase .. ' turns=' .. turns .. ' instructions=' .. (vm.instructions - instructions) .. ' allocated=' .. (vm.next_id - allocated) .. ' collection_ticks=' .. collection_ticks .. ' collection_work=' .. collection_work)
    local names = {}
    for source in pairs(sources) do names[#names + 1] = source end
    table.sort(names)
    for _, source in ipairs(names) do log('CC2 EDITOR SAMPLED SOURCE ' .. phase .. ' ' .. source .. ' quanta=' .. sources[source]) end
  end
  local scheduler = Scheduler.new()
  Scheduler.add(scheduler, 1, vm)
  for turns = 1, 40000 do
    local co = vm.current and vm.objects[vm.current]
    local frame = co and co.frames[#co.frames]
    local source = frame and frame.proto and frame.proto.source or '?'
    local _, _, work = Scheduler.tick(scheduler, vm.events.tick + 1)
    if work > 0 then collection_ticks = collection_ticks + 1; collection_work = collection_work + work
    else sources[source] = (sources[source] or 0) + 1 end
    for _, object in pairs(vm.objects) do
      if object.kind == 'coroutine' and object.failed then error('ROM editor coroutine: ' .. tostring(object.error)) end
    end
    -- The parent shell polls timers while its forked editor is alive, so the
    -- root need not wait. Verify the actual editor coroutine's suspension.
    if (vm.wait or editor_waiting(vm)) and predicate() then report(turns); return end
  end
  report(40000)
  for i, row in ipairs(vm.display.lines) do log('CC2 EDITOR FAILURE ROW ' .. i .. ' ' .. row.text) end
  log('CC2 EDITOR METRICS instructions=' .. vm.instructions .. ' objects=' .. vm.object_count .. ' queue=' .. #vm.events.queue .. ' collection=' .. (vm.collection and vm.collection.phase or 'none'))
  for id, object in pairs(vm.objects) do
    if object.kind == 'coroutine' then
      local frame = object.frames[#object.frames]
      log('CC2 EDITOR COROUTINE ' .. id .. ' ' .. object.status .. ' source=' .. (frame and frame.proto and frame.proto.source or '?'))
    end
  end
  error('ROM editor workflow exceeded dispatch ceiling')
end
local function footer(vm, prefix)
  return vm.display.lines[vm.display.rows].text:sub(1, #prefix) == prefix
end
local function command(vm, text)
  send(vm, 'paste', text)
  send(vm, 'key', enter, false)
end
local function type_text(vm, text)
  for i = 1, #text do send(vm, 'char', text:sub(i, i)) end
end
local function shell_ready(vm)
  if vm.events.timer_count ~= 0 then return false end
  for _, row in ipairs(vm.display.lines) do if row.text:sub(1, 2) == '/>' then return true end end
  return false
end
local function menu(vm, action)
  send(vm, 'key', control, false)
  pump(vm, function() return footer(vm, 'S:save') end)
  send(vm, 'char', action)
end
function M.initial(vm, check)
  command(vm, '/rc/editors/basic.lua /basic.txt')
  pump(vm, function() return footer(vm, 'Press Control for menu') end)
  check('actual basic editor starts through upstream shell', true)
  type_text(vm, 'b')
  pump(vm, function() return vm.display.lines[1].text:sub(1, 1) == 'b' end)
  menu(vm, 's')
  pump(vm, function() return vm.disk.fs['/basic.txt'] ~= nil end)
  check('actual basic editor saves typed content', vm.disk.fs['/basic.txt'].text == 'b\n')
  menu(vm, 'e')
  pump(vm, function() return shell_ready(vm) end)
  command(vm, 'edit /edited.lua')
  pump(vm, function() return footer(vm, 'Press Ctrl for menu') end)
  check('actual advanced editor starts through upstream edit command', true)
  type_text(vm, 'print(7)')
  pump(vm, function() return vm.display.lines[1].text:sub(1, 8) == 'print(7)' end)
  check('actual advanced editor highlights builtin and number cells', vm.display.lines[1].foreground:sub(1, 5) == '55555' and vm.display.lines[1].foreground:sub(7, 7) == '2')
  check('dirty advanced editor does not write its draft to disk', vm.disk.fs['/edited.lua'] == nil)
end
function M.reload(vm, check)
  check('dirty upstream editor buffer and event wait survive reload', editor_waiting(vm) and vm.display.lines[1].text:sub(1, 8) == 'print(7)' and vm.disk.fs['/edited.lua'] == nil)
  local resized = false
  for _, record in ipairs(vm.events.queue) do
    if record.tuple[1] == 'term_resize' then resized = true end
  end
  if resized then
    pump(vm, function() return footer(vm, 'Press Ctrl for menu') and vm.display.lines[1].text:sub(1, 8) == 'print(7)' end)
    check('actual dirty editor redraws to changed startup dimensions before new input', vm.disk.fs['/edited.lua'] == nil and editor_waiting(vm))
  end
  menu(vm, 's')
  pump(vm, function() return vm.disk.fs['/edited.lua'] ~= nil end)
  check('resumed advanced editor saves exact draft bytes', vm.disk.fs['/edited.lua'].text == 'print(7)\n')
  menu(vm, 'e')
  pump(vm, function() return shell_ready(vm) end)
  command(vm, 'edit /edited.lua')
  pump(vm, function() return footer(vm, 'Press Ctrl for menu') and vm.display.lines[1].text:sub(1, 8) == 'print(7)' end)
  check('actual advanced editor reopens saved source', true)
  menu(vm, 'e')
  pump(vm, function() return shell_ready(vm) end)
  command(vm, '/edited.lua')
  pump(vm, function()
    if not shell_ready(vm) then return false end
    for _, row in ipairs(vm.display.lines) do if row.text:match('^7%s*$') then return true end end
    return false
  end)
  check('upstream shell executes edited source and returns after its coroutine', true)
end
return M
