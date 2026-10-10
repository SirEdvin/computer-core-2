-- Real-engine saved-grid/settings checks, independent of presentation.
local Compiler = require('__computer_core_2__.scripts.guest.compiler')
local VM = require('__computer_core_2__.scripts.guest.vm')
local Terminal = require('__computer_core_2__.scripts.guest.terminal')
local Scheduler = require('__computer_core_2__.scripts.guest.scheduler')
local Collector = require('__computer_core_2__.scripts.guest.collector')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local M = {}
local source = [[
local old_w, old_h = term.getSize()
local identity = {value = 17}
local retained = function() return identity.value end
term.blit('KEEP', '0123', 'fedc')
term.setTextColor(8)
term.setBackgroundColor(16)
term.setPaletteColor(4, 0.1, 0.2, 0.3)
term.setCursorPos(-10, 999)
term.setCursorBlink(true)
local resized, before = 0, false
while true do
  local event = os.pullEventRaw()
  if event == 'term_resize' then
    assert(not before, 'resize arrived after saved input')
    resized = resized + 1
  elseif event == 'geometry_before' then before = true
  elseif event == 'geometry_after' then assert(before); break
  else error('unexpected geometry event: ' .. tostring(event)) end
end
local w, h = term.getSize()
assert(retained() == 17)
local file = assert(io.open('/keep.txt', 'r'))
local text = file:read('*a'); file:close()
return 'geometry-reload-pass', resized, old_w, old_h, w, h, text
]]
function M.initial(check)
  local paused = VM.new(assert(Compiler.compile("return 'dispatch-pass'")), nil, nil, {columns = 1, rows = 1})
  paused.configured_geometry = nil -- Compatible older graph with no binding metadata.
  Collector.start(paused)
  local scheduler = Scheduler.new()
  Scheduler.add(scheduler, 1, paused)
  local instructions, _, work = Scheduler.tick(scheduler)
  local w, h = Terminal.dimensions()
  check('scheduler reconciles before a collection-only dispatch', instructions == 0 and paused.instructions == 0 and work <= Limits.collection_work_per_computer and paused.display.columns == w and paused.display.rows == h and paused.events.queue[1].tuple[1] == 'term_resize')
  local vm = VM.new(assert(Compiler.compile(source, '=geometry-reload')), nil, {fs = {['/keep.txt'] = {type = 'file', text = 'unchanged'}}})
  assert(VM.run(vm, 10000) == 'waiting')
  assert(VM.queue(vm, table.pack('geometry_before')))
  check('startup-configured geometry probe waits without consuming saved input', #vm.events.queue == 1)
  Collector.start(vm)
  Collector.step(vm, 1)
  return vm
end
function M.configuration(vm, check)
  local instructions = vm.instructions
  local wait, objects, disk, collection = vm.wait, vm.objects, vm.disk, vm.collection
  VM.reconcile_configured(vm)
  check('configuration reconciliation preserves execution and disk identities', vm.instructions == instructions and vm.wait == wait and vm.objects == objects and vm.disk == disk and vm.collection == collection)
end
function M.reload(vm, dimensions, check)
  local old_w, old_h = dimensions.columns, dimensions.rows
  local w, h = dimensions.reload_columns, dimensions.reload_rows
  local changed = old_w ~= w or old_h ~= h
  local instructions = vm.instructions
  -- Ingress must reconcile first even without a configuration callback.
  assert(VM.queue(vm, table.pack('geometry_after')))
  check('real engine startup settings changed as requested', settings.startup['computer-core-terminal-columns'].value == w and settings.startup['computer-core-terminal-rows'].value == h)
  check('reconciliation and new input do not execute the suspended guest', vm.instructions == instructions)
  local d = vm.display
  local overlap = math.min(old_w, w)
  check('saved grid overlap retains independent cells and colors', d.columns == w and d.rows == h and d.lines[1].text:sub(1, 4) == 'KEEP' and d.lines[1].foreground:sub(1, 4) == '0123' and d.lines[1].background:sub(1, 4) == 'fedc')
  for y = 1, h do
    assert(#d.lines[y].text == w and #d.lines[y].foreground == w and #d.lines[y].background == w)
    if y > old_h then
      assert(d.lines[y].text == string.rep(' ', w) and d.lines[y].foreground == string.rep('3', w) and d.lines[y].background == string.rep('4', w))
    elseif w > old_w then
      assert(d.lines[y].text:sub(overlap + 1) == string.rep(' ', w - overlap) and d.lines[y].foreground:sub(overlap + 1) == string.rep('3', w - overlap) and d.lines[y].background:sub(overlap + 1) == string.rep('4', w - overlap))
    end
  end
  check('new cells use current colors and removed rows are clipped', #d.lines == h)
  check('resize preserves palette and off-screen blinking cursor', d.palette[3].r == 0.1 and d.palette[3].g == 0.2 and d.palette[3].b == 0.3 and d.x == -10 and d.y == 999 and d.blink and d.foreground == '3' and d.background == '4')
  local count = 0
  for _, record in ipairs(vm.events.queue) do if record.tuple[1] == 'term_resize' then count = count + 1 end end
  check('changed settings queue exactly one resize; unchanged settings queue none', count == (changed and 1 or 0) and vm.events.queue[1].tuple[1] == (changed and 'term_resize' or 'geometry_before'))
  local revision = d.revision
  check('repeated startup reconciliation is idempotent', not VM.reconcile_configured(vm) and d.revision == revision)
  local main = vm.main.ref
  local scheduler = Scheduler.new()
  Scheduler.add(scheduler, 1, vm)
  for _ = 1, 2000 do
    local used, _, work = Scheduler.tick(scheduler)
    assert(used <= Limits.instructions_per_computer and work <= Limits.collection_work_per_computer)
    if vm.objects[main].status == 'dead' then break end
  end
  local status, result = vm.objects[main].status, vm.objects[main].result
  check('reloaded guest observes resize before saved and new input without reboot', status == 'dead' and vm.main.ref == main and result.n == 7 and result[1] == 'geometry-reload-pass' and result[2] == (changed and 1 or 0) and result[3] == old_w and result[4] == old_h and result[5] == w and result[6] == h and result[7] == 'unchanged')
end
return M
