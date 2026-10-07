local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Collector = require("__computer_core_2__.scripts.guest.collector")
local Scheduler = require("__computer_core_2__.scripts.guest.scheduler")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
local source = [[local marker={value=73}; local args={}; for i=1,32 do args[i]=pcall end
  args[33]=function() os.pullEventRaw('resume'); return marker end
  return args[1](table.unpack(args,2,33))]]
local function make(text, args)
  return VM.new(assert(Compiler.compile(text, '=continuation-check')), args, nil, {columns=51, rows=19})
end
local function until_(vm, predicate)
  for _ = 1, 20000 do
    local before = vm.instructions
    local _, _, used = VM.run(vm, 1)
    assert(used <= 1 and vm.instructions - before == used)
    if predicate(vm) then return true end
    if vm.wait or vm.objects[vm.main.ref].status == 'dead' then return false end
  end
  error('continuation fixture deadline')
end
local function collect(vm)
  while vm.collection do Collector.step(vm,1024) end
end
local function complete(vm)
  assert(until_(vm,function(state) return state.objects[state.main.ref].status == 'dead' end))
  local co = vm.objects[vm.main.ref]
  assert(not co.failed)
  return co.result
end
local function check_result(check, vm, label)
  local result = complete(vm)
  local flags = result.n == 33
  for i = 1, 32 do flags = flags and result[i] == true end
  local marker = result[33] and vm.objects[result[33].ref]
  check(label, flags and marker and marker.entries['s:value'].value == 73 and vm.pending_operation == nil)
end
function M.initial(check)
  local vm = make(source)
  local pending = until_(vm,function(state) return state.pending_operation ~= nil end)
  check('native call propagation stages within one execution credit', pending and vm.pending_operation.kind == 'call')
  local before, record = vm.instructions, vm.pending_operation
  local _, _, used = VM.run(vm,0)
  check('zero execution credits cannot drain pending propagation', used == 0 and before == vm.instructions and vm.pending_operation == record)
  Collector.start(vm)
  Collector.step(vm,7)
  check('pending call can save during incremental collection', vm.collection ~= nil)
  storage.continuation_call = vm

  vm = make(source)
  assert(until_(vm,function(state) return state.wait ~= nil end))
  assert(VM.queue(vm,table.pack('resume')))
  assert(until_(vm,function(state) return state.pending_operation ~= nil and state.pending_operation.kind == 'deliver' end))
  record = vm.pending_operation
  local marker = record.b[record.b.n]
  check('return propagation retains the otherwise unrooted result tuple', marker and marker.ref and vm.objects[marker.ref].entries['s:value'].value == 73)
  Collector.start(vm)
  Collector.step(vm,7)
  storage.continuation_delivery = vm

  local nested = [[local n=...; local args={}
    for i=1,n-1 do args[i]=coroutine.create(coroutine.resume) end
    args[n]=coroutine.create(type); args[n+1]=7
    return coroutine.resume(args[1],table.unpack(args,2,n+1))]]
  local result = complete(make(nested,table.pack(Limits.coroutine_depth)))
  check('maximum resumer chain completes through staged propagation', result.n == Limits.coroutine_depth + 1 and result[result.n] == 'number')
  result = complete(make(nested,table.pack(Limits.coroutine_depth + 1)))
  check('resumer nesting refuses before activating the next child', result[result.n - 1] == false and result[result.n] == 'guest coroutine nesting limit exceeded')

  -- Start explicit-tick dispatch in the middle of native return propagation.
  local state = Scheduler.new()
  vm = make(source)
  assert(until_(vm,function(value) return value.wait ~= nil end))
  assert(VM.queue(vm,table.pack('resume')))
  assert(until_(vm,function(value) return value.pending_operation ~= nil and value.pending_operation.kind == 'deliver' end))
  Scheduler.add(state,1,vm)
  Scheduler.tick(state,700)
  -- Scheduler may first collect initialized guest objects; dispatch again later.
  for tick = 701, 750 do
    if vm.objects[vm.main.ref].status == 'dead' then break end
    Scheduler.tick(state,tick)
  end
  check('scheduler accounts native propagation under execution credits', vm.objects[vm.main.ref].status == 'dead'
    and state.execution_budget.instructions > 0 and state.execution_budget.instructions <= Limits.instructions_per_computer)

  vm = make('return os.pullEventRaw("resume")')
  assert(until_(vm,function(value) return value.wait ~= nil end))
  assert(VM.queue(vm,table.pack('resume',nil,9,nil)))
  local before = vm.instructions
  local status, event, count = VM.run(vm,1)
  check('wait delivery consumes a credit even without further bytecode', status == 'dead' and count == 1
    and vm.instructions == before + 1 and event.n == 4 and event[2] == nil and event[4] == nil)

  -- Missing depth metadata from compatible old graphs is reconstructed lazily.
  vm = make(nested,table.pack(Limits.coroutine_depth + 1))
  assert(until_(vm,function(value) return value.pending_operation ~= nil end))
  for _, object in pairs(vm.objects) do if object.kind == 'coroutine' then object.resume_depth = nil end end
  result = complete(vm)
  check('legacy active resumer chains cannot evade the nesting ceiling', result[result.n - 1] == false
    and result[result.n] == 'guest coroutine nesting limit exceeded')

  vm = make([[local marker={value=73}; local args={}; for i=1,32 do args[i]=pcall end
    args[33]=function() error(marker) end; return args[1](table.unpack(args,2,33))]])
  assert(until_(vm,function(value) return value.pending_operation ~= nil and value.pending_operation.kind == 'deliver' end))
  Collector.start(vm)
  Collector.step(vm,7)
  storage.continuation_failure = vm
end
function M.resume(check)
  local vm = storage.continuation_call
  check('pending call and partial collection survive separate-process reload', vm.pending_operation.kind == 'call' and vm.collection ~= nil)
  collect(vm)
  assert(until_(vm,function(state) return state.wait ~= nil end))
  assert(VM.queue(vm,table.pack('resume')))
  check_result(check,vm,'reloaded pending call preserves closure upvalues through collection')
  vm = storage.continuation_delivery
  check('pending return and partial collection survive separate-process reload', vm.pending_operation.kind == 'deliver' and vm.collection ~= nil)
  collect(vm)
  check_result(check,vm,'reloaded return keeps result identity through collection')
  vm = storage.continuation_failure
  check('staged protected error survives reload during collection', vm.pending_operation.kind == 'deliver' and vm.collection ~= nil)
  collect(vm)
  local result = complete(vm)
  local flags = result.n == 33 and result[32] == false
  for i=1,31 do flags = flags and result[i] == true end
  local marker = result[33] and vm.objects[result[33].ref]
  check('reloaded propagation preserves reference-valued protected errors', flags and marker and marker.entries['s:value'].value == 73)
end
return M
