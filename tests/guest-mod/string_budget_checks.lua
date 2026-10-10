local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Scheduler = require("__computer_core_2__.scripts.guest.scheduler")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
local prototype = assert(Compiler.compile([[local text = ...
while true do
  local ok, err = pcall(string.reverse, text)
  if not ok then
    last_string_error = err
    os.pullEvent('retry')
  end
end]], '=string-budget-loop'))

function M.initial(check)
  local state = Scheduler.new()
  for id = 1, 4 do
    local vm = VM.new(prototype, table.pack(string.rep('x', Limits.string_bytes)))
    VM.run(vm, 1000, {computer = {used = 0, limit = Limits.compiler_work_per_computer}, string_computer = {used = 0, limit = 0}})
    assert(vm.wait, 'string probe must initialize and wait')
    assert(VM.queue(vm, table.pack('retry')))
    Scheduler.add(state, id, vm)
  end
  local _, _, _, _, work = Scheduler.tick(state, 20)
  local per_computer, aggregate = false, false
  for id, vm in pairs(state.machines) do
    assert(vm.wait and not vm.objects[vm.main.ref].failed)
    local err = vm.objects[vm.env.ref].entries['s:last_string_error'].value
    per_computer = per_computer or err == 'per-computer string work limit exceeded'
    aggregate = aggregate or err == 'aggregate string work limit exceeded'
    assert(state.string_budget.machines[id].used <= Limits.string_work_per_computer)
  end
  check('native string copies share per-computer and aggregate work budgets', per_computer and aggregate
    and work == state.string_budget.used and work > 0 and work <= Limits.string_work_per_tick)
  local saved = state.string_budget.used
  for _, vm in pairs(state.machines) do assert(VM.queue(vm, table.pack('retry'))) end
  Scheduler.tick(state, 20)
  check('same-tick weighted string refusals preserve both budget counters', state.string_budget.used == saved)
  storage.string_budget_scheduler, storage.string_budget_used = state, saved

  local sliced = VM.new(assert(Compiler.compile('local text=...; return text:sub(1,1),string.byte(text,1,1),string.char(65)')), table.pack(string.rep('a', Limits.string_bytes)))
  local slice_context = {computer = {used = 0, limit = Limits.compiler_work_per_computer}, string_computer = {used = 0, limit = 13}}
  local slice_status, slice_result
  for _ = 1, 20 do
    slice_status, slice_result = VM.run(sliced, 256, slice_context)
    if slice_status == 'dead' then break end
  end
  check('tiny substring and byte reads charge their clipped output rather than full input', slice_status == 'dead'
    and not sliced.objects[sliced.main.ref].failed and slice_result[1] == 'a' and slice_result[2] == 97 and slice_result[3] == 'A'
    and slice_context.string_computer.used == 13)

  local malformed = VM.new(assert(Compiler.compile([[pcall(string.byte,'abc',0/0); pcall(string.byte,'abc',math.huge); pcall(string.sub,'abc',0/0); return string.reverse('abc')]])))
  local malformed_context = {computer = {used = 0, limit = Limits.compiler_work_per_computer}, string_computer = {used = 0, limit = 1000}}
  local malformed_status, malformed_result
  for _ = 1, 20 do
    malformed_status, malformed_result = VM.run(malformed, 256, malformed_context)
    if malformed_status == 'dead' then break end
  end
  check('nonfinite string indices cannot poison shared work counters', malformed_status == 'dead'
    and not malformed.objects[malformed.main.ref].failed and malformed_result[1] == 'cba'
    and malformed_context.string_computer.used == math.floor(malformed_context.string_computer.used))

  local expressions = {"string.rep('x',3)", "string.sub('abc',1,2)", "string.lower('ABC')", "string.upper('abc')", "string.reverse('abc')", "string.byte('abc',1,2)", "string.char(65,66)", "string.format('%5s','x')", "table.concat({'a','b'},'-')", "'a'..tostring(7)"}
  for _, expression in ipairs(expressions) do
    local vm = VM.new(assert(Compiler.compile('return pcall(function() return '..expression..' end)')))
    local context = {computer = {used = 0, limit = Limits.compiler_work_per_computer}, string_computer = {used = 0, limit = 0}}
    local status, result
    for _ = 1, 20 do
      status, result = VM.run(vm, 256, context)
      if status == 'dead' then break end
    end
    assert(status == 'dead' and not vm.objects[vm.main.ref].failed)
    check('string entry point precharges host work: '..expression, result[1] == false and result[2] == 'per-computer string work limit exceeded' and context.string_computer.used == 0)
  end
end
function M.resume(check)
  local state, saved = storage.string_budget_scheduler, storage.string_budget_used
  check('string credits survive separate-process reload', state.string_budget.tick == 20 and state.string_budget.used == saved)
  for _, vm in pairs(state.machines) do assert(VM.queue(vm, table.pack('retry'))) end
  Scheduler.tick(state, 20)
  check('reload does not refresh same-tick string credits', state.string_budget.used == saved)
  for _, vm in pairs(state.machines) do assert(VM.queue(vm, table.pack('retry'))) end
  local _, _, _, _, work = Scheduler.tick(state, 21)
  check('later simulation ticks restore bounded string service', state.string_budget.tick == 21 and work > 0 and work <= Limits.string_work_per_tick)
end
return M
