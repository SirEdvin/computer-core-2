local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Scheduler = require("__computer_core_2__.scripts.guest.scheduler")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
local function context(limit)
  return {computer = {used = 0, limit = Limits.compiler_work_per_computer}, table_computer = {used = 0, limit = limit}}
end
local function complete(vm, credits)
  for _ = 1, 100 do
    local status, result = VM.run(vm, 256, credits)
    if status == 'dead' then return result end
  end
  error('table work fixture did not complete')
end
local function prepare(expression)
  local proto = assert(Compiler.compile([[local long = ...
    local target = {[long] = 7}
    for i = 1, 8 do target[i] = i end
    budget_target = target
    local raw_get, raw_set, next_key, raw_length, protected = rawget, rawset, next, rawlen, pcall
    os.pullEvent('retry')
    return protected(function() ]]..expression..[[ end)
  ]], '=table-work-operation'))
  local vm = VM.new(proto, table.pack(string.rep('k', Limits.string_bytes)))
  for _ = 1, 100 do VM.run(vm, 256); if vm.wait then break end end
  assert(vm.wait and not vm.objects[vm.main.ref].failed)
  local ref = vm.objects[vm.env.ref].entries['s:budget_target'].value
  assert(VM.queue(vm, table.pack('retry')))
  return vm, vm.objects[ref.ref]
end
function M.initial(check)
  local expressions = {'return target[long]', 'target[long] = 8', 'return raw_get(target, long)',
    'raw_set(target, long, 8)', 'return next_key(target, long)', 'return next_key(target)', 'return raw_length(target)', 'return #target'}
  for _, expression in ipairs(expressions) do
    local vm, data = prepare(expression)
    local credits = context(0)
    local result = complete(vm, credits)
    check('table primitive admits work before access: '..expression, result[1] == false
      and result[2] == 'per-computer table work limit exceeded' and credits.table_computer.used == 0
      and #data.order == 9 and data.entries[data.order[1]].value == 7 and data.known[data.order[1]] == 1)
  end
  local extending, extended = prepare('raw_set(target, 9, 9)')
  local partial = context(65)
  local failed = complete(extending, partial)
  check('sequence extension refuses before entry or metadata mutation', failed[1] == false
    and failed[2] == 'per-computer table work limit exceeded' and partial.table_computer.used == 65
    and #extended.order == 9 and extended.entries['n:9'] == nil and extended.known['n:9'] == nil and extended.sequence_length == 8)
  local vm, data = prepare('return next_key(target, long)')
  for encoded in pairs(data.known) do data.known[encoded] = true end
  local credits = context(1 + 2 * (Limits.string_bytes + 2) + 1)
  local result = complete(vm, credits)
  check('legacy index upgrade reserves all metadata writes', result[1] == false
    and result[2] == 'per-computer table work limit exceeded' and data.known[data.order[1]] == true
    and data.known['n:8'] == true and #data.order == 9 and data.entries[data.order[1]].value == 7)

  vm = prepare('return raw_get(target, long)')
  credits = context(Limits.table_work_per_computer)
  credits.table_aggregate = {used = 0, limit = 0}
  result = complete(vm, credits)
  check('table work refusal is atomic across computer and aggregate credits', result[1] == false
    and result[2] == 'aggregate table work limit exceeded' and credits.table_computer.used == 0 and credits.table_aggregate.used == 0)

  local prototype = assert(Compiler.compile([[local long = ...
    local target = {[long] = 7}
    local protected, read = pcall, rawget
    os.pullEvent('retry')
    while true do
      local ok, err = protected(read, target, long)
      if not ok then last_table_error = err; return end
    end
  ]], '=table-work-loop'))
  local state = Scheduler.new()
  for id = 1, 4 do
    local machine = VM.new(prototype, table.pack(string.rep('k', Limits.string_bytes)))
    for _ = 1, 100 do VM.run(machine, 256); if machine.wait then break end end
    assert(machine.wait and VM.queue(machine, table.pack('retry')))
    Scheduler.add(state, id, machine)
  end
  local _, _, _, _, _, _, _, _, _, work = Scheduler.tick(state, 90)
  local computer, aggregate = false, false
  for id, machine in pairs(state.machines) do
    assert(not machine.objects[machine.main.ref].failed and machine.objects[machine.main.ref].status == 'dead')
    local err = machine.objects[machine.env.ref].entries['s:last_table_error'].value
    computer = computer or err == 'per-computer table work limit exceeded'
    aggregate = aggregate or err == 'aggregate table work limit exceeded'
    assert(state.table_budget.machines[id].used <= Limits.table_work_per_computer)
  end
  check('long-key accesses share per-computer and aggregate table work', computer and aggregate and work > 0
    and work == state.table_budget.used and work <= Limits.table_work_per_tick)
  storage.table_budget_scheduler, storage.table_budget_used = state, state.table_budget.used
end
function M.resume(check)
  local state, saved = storage.table_budget_scheduler, storage.table_budget_used
  local credits = state.table_budget
  check('table credits survive separate-process reload', credits.tick == 90 and credits.used == saved)
  Scheduler.tick(state, 90)
  check('same-tick reload does not renew table work', state.table_budget == credits and credits.used == saved)
  Scheduler.add(state, 5, VM.new(assert(Compiler.compile('return rawget({[1]=7},1)'))))
  local _, _, _, _, _, _, _, _, _, work = Scheduler.tick(state, 91)
  local machine = state.machines[5]
  check('later tick restores bounded table service', state.table_budget.tick == 91 and work > 0
    and work <= Limits.table_work_per_tick and not machine.objects[machine.main.ref].failed
    and machine.objects[machine.main.ref].result[1] == 7)
end
return M
