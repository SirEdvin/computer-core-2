local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Scheduler = require("__computer_core_2__.scripts.guest.scheduler")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local Files = require("__computer_core_2__.scripts.guest.files")
local M = {}
local function context(limit)
  return {computer = {used = 0, limit = Limits.compiler_work_per_computer}, filesystem_computer = {used = 0, limit = limit}}
end
local function populate(vm)
  vm.disk.fs['/tree'] = {type = 'dir'}
  for i = 1, 600 do vm.disk.fs['/tree/branch' .. i] = {type = 'file', text = 'saved'} end
end
local function snapshot(vm)
  local names, pieces = {}, {}
  for name in pairs(vm.disk.fs) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local node = vm.disk.fs[name]
    pieces[#pieces + 1] = name .. ':' .. node.type .. ':' .. (node.text or '')
  end
  return table.concat(pieces, '|')
end
local prototype = assert(Compiler.compile([[while true do
  local ok, err = pcall(fs.list, '/tree')
  if not ok then last_filesystem_error = err; os.pullEvent('retry') end
end]], '=filesystem-budget-loop'))
function M.initial(check)
  local state = Scheduler.new()
  for id = 1, 4 do
    local vm = VM.new(prototype)
    populate(vm)
    VM.run(vm, 1000, context(0))
    assert(vm.wait)
    assert(VM.queue(vm, table.pack('retry')))
    Scheduler.add(state, id, vm)
  end
  -- Several dispatches in one simulation tick must share all credits.
  for _ = 1, 500 do Scheduler.tick(state, 40) end
  local per_computer, aggregate = false, false
  for id, vm in pairs(state.machines) do
    assert(vm.wait and not vm.objects[vm.main.ref].failed)
    local err = vm.objects[vm.env.ref].entries['s:last_filesystem_error'].value
    per_computer = per_computer or err == 'per-computer filesystem work limit exceeded'
    aggregate = aggregate or err == 'aggregate filesystem work limit exceeded'
    assert(state.filesystem_budget.machines[id].used <= Limits.filesystem_work_per_computer)
  end
  local saved = state.filesystem_budget.used
  check('directory scans share filesystem work credits', per_computer and aggregate and saved > 0 and saved <= Limits.filesystem_work_per_tick)
  local counters = state.filesystem_budget
  for _, vm in pairs(state.machines) do assert(VM.queue(vm, table.pack('retry'))) end
  for _ = 1, 30 do Scheduler.tick(state, 40) end
  local remaining = state.filesystem_budget.used
  check('same-tick directory retries cannot refresh credits', state.filesystem_budget == counters
    and remaining >= saved and remaining <= Limits.filesystem_work_per_tick)
  storage.filesystem_budget_scheduler, storage.filesystem_budget_used = state, remaining

  local calls = {"fs.exists('/tree')", "fs.isDir('/tree')", "fs.isReadOnly('/rc')", "fs.getSize('/tree/branch1')", "fs.list('/tree')", "fs.makeDir('/new/branch')", "fs.delete('/tree')", "fs.copy('/tree','/copy')", "fs.move('/tree','/moved')", "fs.combine('tree','branch1')", "fs.getName('/tree/branch1')", "fs.getDir('/tree/branch1')", "fs.getFreeSpace()"}
  for _, code in ipairs(calls) do
    local vm = VM.new(assert(Compiler.compile('return pcall(function() '..code..' end)')))
    populate(vm)
    local before, disk = snapshot(vm), vm.disk.fs
    local credits, status, result = context(0)
    for _ = 1, 20 do
      status, result = VM.run(vm, 256, credits)
      if status == 'dead' then break end
    end
    check('filesystem refusal is atomic: '..code, status == 'dead' and not vm.objects[vm.main.ref].failed
      and result[1] == false and result[2] == 'per-computer filesystem work limit exceeded'
      and credits.filesystem_computer.used == 0 and vm.disk.fs == disk and snapshot(vm) == before)
  end
  -- Force refusal after scanning has begun, not only at operation entry.
  for _, method in ipairs({'delete', 'mkdir', 'transfer'}) do
    local vm = VM.new(assert(Compiler.compile('return true')))
    populate(vm)
    local before, disk, used = snapshot(vm), vm.disk.fs, 0
    local function spend(amount)
      if used + amount > 1000 then error('test filesystem work exhausted', 0) end
      used = used + amount
    end
    local ok, err
    if method == 'transfer' then ok, err = pcall(Files.transfer, vm, '/tree', '/moved', true, spend)
    elseif method == 'mkdir' then ok, err = pcall(Files.mkdir, vm, '/new/branch', spend)
    else ok, err = pcall(Files.delete, vm, '/tree', spend) end
    check('partial filesystem admission retains disk: '..method, not ok and err == 'test filesystem work exhausted'
      and used > 0 and vm.disk.fs == disk and snapshot(vm) == before)
  end
  local vm = VM.new(assert(Compiler.compile('return true')))
  populate(vm)
  local before, disk, scanned = snapshot(vm), vm.disk.fs, 0
  local ok, err = pcall(Files.list, vm, '/tree', function(amount)
    -- Candidate scanning charges exceed 25; short-name comparisons do not.
    if amount <= 25 then error('test directory comparison exhausted', 0) end
    scanned = scanned + amount
  end)
  check('directory sorting comparisons are metered', not ok and err == 'test directory comparison exhausted'
    and scanned > 0 and vm.disk.fs == disk and snapshot(vm) == before)
  for _, move in ipairs({false, true}) do
    ok, err = pcall(Files.transfer, vm, '/tree', '/' .. string.rep('d', 1019), move)
    check('overlong transferred descendants retain disk: '..tostring(move), not ok and err:find('normalized path exceeds length limit', 1, true)
      and vm.disk.fs == disk and snapshot(vm) == before)
  end
end
function M.resume(check)
  local state, saved = storage.filesystem_budget_scheduler, storage.filesystem_budget_used
  check('filesystem credits survive separate-process reload', state.filesystem_budget.tick == 40 and state.filesystem_budget.used == saved)
  local before = state.filesystem_budget
  Scheduler.tick(state, 40)
  check('reload retains same-tick filesystem counters', state.filesystem_budget == before and before.used == saved)
  for _, vm in pairs(state.machines) do assert(VM.queue(vm, table.pack('retry'))) end
  local _, _, _, _, _, _, work = Scheduler.tick(state, 41)
  check('later ticks restore bounded directory service', state.filesystem_budget.tick == 41 and work > 0 and work <= Limits.filesystem_work_per_tick)
end
return M
