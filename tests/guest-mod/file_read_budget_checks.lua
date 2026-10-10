local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Scheduler = require("__computer_core_2__.scripts.guest.scheduler")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local Files = require("__computer_core_2__.scripts.guest.files")
local M = {}
local function context(limit)
  return {computer = {used = 0, limit = Limits.compiler_work_per_computer}, filesystem_computer = {used = 0, limit = limit}}
end
local function input(vm, text)
  vm.disk.fs['/input'] = {type = 'file', text = text}
end
local function handle(vm)
  for _, value in pairs(vm.objects) do if value.kind == 'handle' then return value end end
end
local function finish(vm, credits)
  local status, result
  for _ = 1, 30 do
    status, result = VM.run(vm, 256, credits)
    if status == 'dead' then return result end
  end
  error('read-budget fixture did not complete')
end
local prototype = assert(Compiler.compile([[local f = assert(io.open('/input', 'r'))
os.pullEvent('retry')
while true do
  local ok, err = pcall(function() f:seek('set', 0); return f:readLine() end)
  if not ok then last_read_error = err; os.pullEvent('retry') end
end]], '=file-read-budget-loop'))
function M.initial(check)
  local calls = {"f:read(1)", "f:read('*a')", "f:readAll()", "f:readLine()", "f:seek('set',2)", "f:lines()()"}
  for _, call in ipairs(calls) do
    local vm = VM.new(assert(Compiler.compile("local f=assert(io.open('/input','r')); os.pullEvent('retry'); return pcall(function() return "..call.." end)")))
    input(vm, 'saved\nsecond')
    VM.run(vm, 1000)
    assert(vm.wait and VM.queue(vm, table.pack('retry')))
    local credits = context(0)
    local result = finish(vm, credits)
    local record = assert(handle(vm))
    check('zero-credit read/seek preserves handle: '..call, result[1] == false and result[2] == 'per-computer filesystem work limit exceeded'
      and record.offset == 0 and record.text == 'saved\nsecond' and not record.closed and not record.failed and credits.filesystem_computer.used == 0)
  end
  for _, call in ipairs({"loadfile('/input')", "dofile('/input')"}) do
    local vm = VM.new(assert(Compiler.compile('return pcall(function() return '..call..' end)')))
    input(vm, 'return 7')
    local credits = context(0)
    local result = finish(vm, credits)
    local refused = result[1] == false and result[2] == 'per-computer filesystem work limit exceeded'
      or result[1] == true and result[2] == nil and result[3] == 'per-computer filesystem work limit exceeded'
    check('source lookup shares filesystem credits: '..call, refused and credits.computer.used == 0 and vm.disk.fs['/input'].text == 'return 7')
  end
  local vm = VM.new(assert(Compiler.compile('return true')))
  input(vm, string.rep('a', 1048576))
  local record = Files.open(vm, '/input', 'r')
  local used = 0
  local function spend(amount) used = used + amount end
  check('tiny counted read charges clipped output', Files.read(record, 1, spend) == 'a' and record.offset == 1 and used == 2)
  local before, offset = used, record.offset
  local ok, err = pcall(Files.read, record, 'l', spend)
  check('oversized line search is bounded without advancing offset', not ok and err:find('line exceeds byte limit', 1, true)
    and record.offset == offset and used - before == 1 + 2 * (Limits.string_bytes + 1))
  record.text, record.offset, used = 'first\nsecond', 0, 0
  ok, err = pcall(Files.read, record, 'l', function(amount)
    if used + amount > 25 then error('test read work exhausted', 0) end
    used = used + amount
  end)
  check('post-scan refusal preserves read offset', not ok and err == 'test read work exhausted' and used == 25 and record.offset == 0)
  check('read recovers after later admission', Files.read(record, 'L', spend) == 'first\n' and record.offset == 6)
  record.text, record.offset = string.rep('a', Limits.string_bytes - 1) .. '\n' .. 'z', 0
  check('line at byte limit preserves following byte', #Files.read(record, 'L', spend) == Limits.string_bytes
    and Files.read(record, 1, spend) == 'z' and Files.read(record, 'l', spend) == nil)
  record.text, record.offset = string.rep('a', Limits.string_bytes) .. '\n', 0
  ok, err = pcall(Files.read, record, 'l', spend)
  check('newline just beyond byte limit is rejected without advancing', not ok and err:find('line exceeds byte limit', 1, true) and record.offset == 0)
  for _, call in ipairs({"f.read()", "f.readAll()", "f.readLine(true)"}) do
    local machine = VM.new(assert(Compiler.compile("local f=assert(fs.open('/input','rb')); os.pullEvent('retry'); return pcall(function() return "..call.." end)")))
    input(machine, 'saved\nsecond')
    VM.run(machine, 1000)
    assert(machine.wait and VM.queue(machine, table.pack('retry')))
    local result = finish(machine, context(0))
    check('binary fs read uses shared admission: '..call, result[1] == false and result[2] == 'per-computer filesystem work limit exceeded'
      and handle(machine).offset == 0)
  end
  local machine = VM.new(assert(Compiler.compile("local iterator=io.lines('/input'); os.pullEvent('retry'); return pcall(iterator)")))
  input(machine, 'saved\nsecond')
  VM.run(machine, 1000)
  assert(machine.wait and VM.queue(machine, table.pack('retry')))
  local result = finish(machine, context(0))
  check('io.lines refusal does not auto-close or advance handle', result[1] == false and result[2] == 'per-computer filesystem work limit exceeded'
    and handle(machine).offset == 0 and not handle(machine).closed)

  local state = Scheduler.new()
  for id = 1, 4 do
    local machine = VM.new(prototype)
    input(machine, string.rep('x', 60000))
    VM.run(machine, 1000)
    assert(machine.wait)
    assert(VM.queue(machine, table.pack('retry')))
    Scheduler.add(state, id, machine)
  end
  for _ = 1, 60 do Scheduler.tick(state, 50) end
  local per_computer, aggregate = false, false
  for id, machine in pairs(state.machines) do
    assert(machine.wait and not machine.objects[machine.main.ref].failed)
    local err = machine.objects[machine.env.ref].entries['s:last_read_error'].value
    per_computer = per_computer or err == 'per-computer filesystem work limit exceeded'
    aggregate = aggregate or err == 'aggregate filesystem work limit exceeded'
    assert(state.filesystem_budget.machines[id].used <= Limits.filesystem_work_per_computer)
  end
  check('repeated handle reads share filesystem scheduler credits', per_computer and aggregate and state.filesystem_budget.used > 0
    and state.filesystem_budget.used <= Limits.filesystem_work_per_tick)
  storage.file_read_budget_scheduler, storage.file_read_budget_used = state, state.filesystem_budget.used
end
function M.resume(check)
  local state, saved = storage.file_read_budget_scheduler, storage.file_read_budget_used
  check('read credits and handles survive separate-process reload', state.filesystem_budget.tick == 50 and state.filesystem_budget.used == saved
    and handle(state.machines[1]).text == string.rep('x',60000))
  local counters = state.filesystem_budget
  Scheduler.tick(state, 50)
  check('reload retains same-tick read counters', state.filesystem_budget == counters and counters.used == saved)
  for _, machine in pairs(state.machines) do assert(VM.queue(machine, table.pack('retry'))) end
  local _, _, _, _, _, _, work = Scheduler.tick(state, 51)
  check('later tick restores bounded handle reading', state.filesystem_budget.tick == 51 and work > 0 and work <= Limits.filesystem_work_per_tick)
end
return M
