local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Scheduler = require("__computer_core_2__.scripts.guest.scheduler")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
local function snapshot(display)
  local pieces = {tostring(display.revision), tostring(display.x), tostring(display.y), display.foreground, display.background, tostring(display.blink)}
  for row, line in ipairs(display.lines) do
    pieces[#pieces + 1] = line.text .. line.foreground .. line.background .. tostring(display.dirty[row])
  end
  for _, entry in ipairs(display.palette) do
    pieces[#pieces + 1] = tostring(entry.r) .. '/' .. tostring(entry.g) .. '/' .. tostring(entry.b)
  end
  return table.concat(pieces, '|')
end
local prototype = assert(Compiler.compile([[while true do
  local ok, err = pcall(term.clear)
  if not ok then last_terminal_error = err; os.pullEvent('retry') end
end]], '=terminal-budget-loop'))
local function context(limit)
  return {computer = {used = 0, limit = Limits.compiler_work_per_computer}, terminal_computer = {used = 0, limit = limit}}
end
function M.initial(check)
  local state = Scheduler.new()
  for id = 1, 4 do
    local vm = VM.new(prototype, nil, nil, {columns = 160, rows = 60})
    VM.run(vm, 1000, context(0))
    assert(vm.wait)
    assert(VM.queue(vm, table.pack('retry')))
    Scheduler.add(state, id, vm)
  end
  local _, _, _, _, _, work = Scheduler.tick(state, 30)
  local per_computer, aggregate = false, false
  for id, vm in pairs(state.machines) do
    assert(vm.wait and not vm.objects[vm.main.ref].failed)
    local err = vm.objects[vm.env.ref].entries['s:last_terminal_error'].value
    per_computer = per_computer or err == 'per-computer terminal work limit exceeded'
    aggregate = aggregate or err == 'aggregate terminal work limit exceeded'
    assert(state.terminal_budget.machines[id].used <= Limits.terminal_work_per_computer)
  end
  check('repeated full-grid operations share terminal work credits', per_computer and aggregate and work > 0
    and work == state.terminal_budget.used and work <= Limits.terminal_work_per_tick)
  local saved = state.terminal_budget.used
  for _, vm in pairs(state.machines) do assert(VM.queue(vm, table.pack('retry'))) end
  Scheduler.tick(state, 30)
  check('same-tick terminal refusals preserve credits', state.terminal_budget.used == saved)
  storage.terminal_budget_scheduler, storage.terminal_budget_used = state, saved

  local calls = {"term.write('tree')", "term.blit('x','0','f')", "term.clear()", "term.clearLine()", "term.scroll(1)", "term.setCursorPos(3,4)", "term.setCursorBlink(true)", "term.setTextColour(2)", "term.setBackgroundColor(2)", "term.setPaletteColour(1,0)"}
  for _, code in ipairs(calls) do
    local vm = VM.new(assert(Compiler.compile('return pcall(function() '..code..' end)')))
    local display = vm.display
    local before = snapshot(display)
    local line, palette, dirty = display.lines[1], display.palette[1], display.dirty
    local revision, x, y, foreground, background, blink = display.revision, display.x, display.y, display.foreground, display.background, display.blink
    local credits = context(0)
    local status, result
    for _ = 1, 20 do
      status, result = VM.run(vm, 256, credits)
      if status == 'dead' then break end
    end
    check('terminal refusal is atomic: '..code, status == 'dead' and not vm.objects[vm.main.ref].failed
      and result[1] == false and result[2] == 'per-computer terminal work limit exceeded' and credits.terminal_computer.used == 0
      and display.lines[1] == line and display.palette[1] == palette and display.dirty == dirty and display.revision == revision
      and display.x == x and display.y == y and display.foreground == foreground and display.background == background and display.blink == blink
      and snapshot(display) == before)
  end
end
function M.resume(check)
  local state, saved = storage.terminal_budget_scheduler, storage.terminal_budget_used
  check('terminal credits survive separate-process reload', state.terminal_budget.tick == 30 and state.terminal_budget.used == saved)
  for _, vm in pairs(state.machines) do assert(VM.queue(vm, table.pack('retry'))) end
  Scheduler.tick(state, 30)
  check('reload does not refresh same-tick terminal credits', state.terminal_budget.used == saved)
  for _, vm in pairs(state.machines) do assert(VM.queue(vm, table.pack('retry'))) end
  local _, _, _, _, _, work = Scheduler.tick(state, 31)
  check('later ticks restore bounded terminal service', state.terminal_budget.tick == 31 and work > 0 and work <= Limits.terminal_work_per_tick)
end
return M
