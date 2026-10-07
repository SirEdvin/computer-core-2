local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Scheduler = require("__computer_core_2__.scripts.guest.scheduler")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}

local source = [[local source = ...
while true do
  local fn, err = load(source)
  if err == 'per-computer compiler work limit exceeded' or err == 'aggregate compiler work limit exceeded' then
    last_compile_error = err
    os.pullEvent('retry')
  end
end]]
local prototype = assert(Compiler.compile(source, '=compile-budget-loop'))
local expensive = string.rep('do local x=1 end;', 1200)

function M.initial(check)
  local metrics, charged = {}, 0
  local proto = Compiler.compile('return 7', '=charged-compile', metrics, function(amount) charged = charged + amount end)
  check('all compiler phases charge the shared host budget', proto ~= nil and charged > 0
    and charged == metrics.parse_work + metrics.link_work + metrics.generate_work + metrics.normalize_work)
  local refused, err = Compiler.compile('return 7', '=refused-compile', nil, function() error('test compiler budget exhausted', 0) end)
  check('shared compiler refusal is recoverable', refused == nil and err == 'test compiler budget exhausted' and Compiler.compile('return 9') ~= nil)

  local state = Scheduler.new()
  for id = 1, 4 do
    local vm = VM.new(prototype, table.pack(expensive))
    VM.run(vm, 1000, {computer = {used = 0, limit = 0}})
    assert(vm.wait, 'budget probe must finish initialization and wait')
    assert(VM.queue(vm, table.pack('retry')))
    Scheduler.add(state, id, vm)
  end
  local _, _, _, work = Scheduler.tick(state, 10)
  log('CC2 SHARED COMPILE WORK total=' .. state.compile_budget.used .. ' delta=' .. work)
  local per_computer, aggregate = false, false
  for id, vm in pairs(state.machines) do
    assert(vm.wait and not vm.objects[vm.main.ref].failed)
    local err = vm.objects[vm.env.ref].entries['s:last_compile_error'].value
    per_computer = per_computer or err == 'per-computer compiler work limit exceeded'
    aggregate = aggregate or err == 'aggregate compiler work limit exceeded'
    assert(state.compile_budget.machines[id].used <= Limits.compiler_work_per_computer)
  end
  check('repeated loads share per-computer and aggregate scheduler budgets', per_computer and aggregate
    and work == state.compile_budget.used and work <= Limits.compiler_work_per_tick and work > 0)
  local saved = state.compile_budget.used
  for _, vm in pairs(state.machines) do assert(VM.queue(vm, table.pack('retry'))) end
  Scheduler.tick(state, 10)
  check('dispatching again in the same tick does not refresh compiler credits', state.compile_budget.used == saved)
  check('backwards ticks cannot renew compiler credits', not pcall(Scheduler.tick, state, 9) and state.compile_budget.used == saved)
  storage.compile_budget_scheduler = state
  storage.compile_budget_used = saved

  -- Both file-loading entry points must use the same scoped compile admission.
  for _, code in ipairs({"local f,e=loadfile('/budget.lua'); return f,e", "return pcall(dofile,'/budget.lua')"}) do
    local vm = VM.new(assert(Compiler.compile(code)), nil, {fs = {['/budget.lua'] = {type = 'file', text = 'return 7'}}})
    local context = {computer = {used = 0, limit = 0}}
    local status, result
    for _ = 1, 20 do
      status, result = VM.run(vm, 256, context)
      if status == 'dead' then break end
    end
    assert(status == 'dead' and not vm.objects[vm.main.ref].failed)
    check('file-loading entry point cannot bypass compiler credits', not result[1] and result[2] == 'per-computer compiler work limit exceeded' and context.computer.used == 0)
  end
end

function M.resume(check)
  local state = storage.compile_budget_scheduler
  local saved = storage.compile_budget_used
  check('shared compiler credits survive separate-process reload', state.compile_budget.tick == 10 and state.compile_budget.used == saved)
  for _, vm in pairs(state.machines) do assert(VM.queue(vm, table.pack('retry'))) end
  Scheduler.tick(state, 10)
  check('reload cannot renew same-tick compiler credits', state.compile_budget.used == saved)
  for _, vm in pairs(state.machines) do assert(VM.queue(vm, table.pack('retry'))) end
  local _, _, _, work = Scheduler.tick(state, 11)
  check('a later simulation tick restores bounded compiler service', state.compile_budget.tick == 11 and work > 0 and work <= Limits.compiler_work_per_tick)
end
return M
