local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Files = require("__computer_core_2__.scripts.guest.files")
local Scheduler = require("__computer_core_2__.scripts.guest.scheduler")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
local function context(limit)
  return {computer = {used = 0, limit = Limits.compiler_work_per_computer}, filesystem_computer = {used = 0, limit = limit}}
end
local function finish(vm, credits)
  for _ = 1, 30 do
    local status, result = VM.run(vm, 256, credits)
    if status == 'dead' then return result end
  end
  error('write-budget fixture did not complete')
end
function M.initial(check)
  for _, api in ipairs({'io', 'fs'}) do
    for _, mode in ipairs({'r', 'w', 'a', 'r+'}) do
      local vm = VM.new(assert(Compiler.compile("return " .. api .. ".open('/input','" .. mode .. "')")))
      vm.disk.fs['/input'] = {type = 'file', text = 'saved'}
      local result = finish(vm, context(0))
      check('zero-credit open retains disk/quotas: ' .. api .. ' ' .. mode, result[1] == nil
        and result[2] == 'per-computer filesystem work limit exceeded' and vm.open_handles == 0
        and vm.handle_bytes == 0 and vm.disk.fs['/input'].text == 'saved')
    end
  end
  for _, call in ipairs({"f:write('new')", "f:writeLine('new')", "f:flush()", "f:close()"}) do
    local vm = VM.new(assert(Compiler.compile("local f=assert(io.open('/input','r+')); f:write('draft'); os.pullEvent('admit'); return pcall(function() " .. call .. " end)")))
    vm.disk.fs['/input'] = {type = 'file', text = 'saved'}
    VM.run(vm, 1000)
    assert(vm.wait)
    local record
    for _, value in pairs(vm.objects) do if value.kind == 'handle' then record = value end end
    assert(record)
    local text, offset, bytes = record.text, record.offset, vm.handle_bytes
    assert(VM.queue(vm, table.pack('admit')))
    local result = finish(vm, context(0))
    check('zero-credit mutation retains staged handle: ' .. call, result[1] == false
      and result[2] == 'per-computer filesystem work limit exceeded' and record.text == text
      and record.offset == offset and not record.closed and not record.failed and vm.handle_bytes == bytes
      and vm.open_handles == 1 and vm.disk.fs['/input'].text == 'saved')
  end
  local vm = VM.new(assert(Compiler.compile('return true')))
  vm.disk.fs['/input'] = {type = 'file', text = 'saved'}
  local record = Files.open(vm, '/input', 'r+')
  Files.write(vm, record, 'draft')
  for _, operation in ipairs({'write', 'flush', 'close'}) do
    local used = 0
    local function spend(amount)
      if used + amount > 150 then error('test write work exhausted', 0) end
      used = used + amount
    end
    local ok, err
    if operation == 'write' then
      ok, err = pcall(Files.write, vm, record, string.rep('x', 60000), function(amount)
        if amount > 2 then error('test write work exhausted', 0) end
        used = used + amount
      end)
    else ok, err = pcall(Files[operation], vm, record, spend) end
    check('partial admission preserves draft: ' .. operation, not ok and err == 'test write work exhausted'
      and used > 0 and record.text == 'draft' and record.offset == 5 and not record.closed
      and not record.failed and vm.handle_bytes == 5 and vm.open_handles == 1 and vm.disk.fs['/input'].text == 'saved')
  end
  storage.write_budget_vm, storage.write_budget_handle = vm, record
  vm = VM.new(assert(Compiler.compile('return true')))
  vm.disk.fs['/input'] = {type = 'file', text = string.rep('z', 1048576)}
  record = Files.open(vm, '/input', 'r+')
  local used = 0
  Files.write(vm, record, 'x', function(amount)
    assert(amount <= Limits.filesystem_work_per_computer - used)
    used = used + amount
  end)
  check('disk-sized reconstruction fits fresh configured credits', used > 0 and #record.text == 1048576 and record.text:sub(1, 2) == 'xz')
  Files.seek(record, 'set', 1048576)
  local ok = pcall(Files.write, vm, record, 'x', function(amount) used = used + amount end)
  local closed = pcall(Files.close, vm, record, function(amount) used = used + amount end)
  check('content-quota failure still releases failed handle without commit', not ok and not closed and record.closed
    and vm.open_handles == 0 and vm.handle_bytes == 0 and vm.disk.fs['/input'].text:sub(1, 1) == 'z')
  local prototype = assert(Compiler.compile([[local f=assert(io.open('/input','r+'))
local text=string.rep('x',60000)
os.pullEvent('admit')
while true do
  local ok,err=pcall(function() f:seek('set',0); f:write(text) end)
  if not ok then last_write_error=err; os.pullEvent('retry') end
end]], '=write-budget-loop'))
  local state = Scheduler.new()
  for id = 1, 4 do
    local machine = VM.new(prototype)
    machine.disk.fs['/input'] = {type = 'file', text = string.rep('s', 400000)}
    VM.run(machine, 1000)
    assert(machine.wait and VM.queue(machine, table.pack('admit')))
    Scheduler.add(state, id, machine)
  end
  for _ = 1, 60 do Scheduler.tick(state, 60) end
  local per_computer, aggregate = false, false
  for id, machine in pairs(state.machines) do
    assert(machine.wait and not machine.objects[machine.main.ref].failed)
    local err = machine.objects[machine.env.ref].entries['s:last_write_error'].value
    per_computer = per_computer or err == 'per-computer filesystem work limit exceeded'
    aggregate = aggregate or err == 'aggregate filesystem work limit exceeded'
    assert(state.filesystem_budget.machines[id].used <= Limits.filesystem_work_per_computer)
    assert(machine.disk.fs['/input'].text:sub(1, 1) == 's')
  end
  check('repeated staged writes share scheduler credits', per_computer and aggregate and state.filesystem_budget.used > 0
    and state.filesystem_budget.used <= Limits.filesystem_work_per_tick)
  storage.write_budget_scheduler, storage.write_budget_used = state, state.filesystem_budget.used
end
function M.resume(check)
  local vm, record = storage.write_budget_vm, storage.write_budget_handle
  check('budget-refused draft survives reload without commit', not record.closed and record.text == 'draft'
    and record.offset == 5 and vm.open_handles == 1 and vm.disk.fs['/input'].text == 'saved')
  local used = 0
  Files.close(vm, record, function(amount) used = used + amount end)
  check('close retry commits exact draft and releases quotas', used > 0 and record.closed and record.text == ''
    and vm.open_handles == 0 and vm.handle_bytes == 0 and vm.disk.fs['/input'].text == 'draft')
  local state, saved = storage.write_budget_scheduler, storage.write_budget_used
  check('write admission counters survive reload', state.filesystem_budget.tick == 60 and state.filesystem_budget.used == saved)
  local counters = state.filesystem_budget
  Scheduler.tick(state, 60)
  check('same-tick reload retains write counters', state.filesystem_budget == counters and counters.used == saved)
  for _, machine in pairs(state.machines) do assert(VM.queue(machine, table.pack('retry'))) end
  local _, _, _, _, _, _, work = Scheduler.tick(state, 61)
  check('later tick restores bounded staged writes', state.filesystem_budget.tick == 61 and work > 0 and work <= Limits.filesystem_work_per_tick)
end
return M
