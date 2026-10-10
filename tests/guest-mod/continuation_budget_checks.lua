local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Scheduler = require("__computer_core_2__.scripts.guest.scheduler")
local Collector = require("__computer_core_2__.scripts.guest.collector")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
local function make(source,args)
  return VM.new(assert(Compiler.compile(source,'=continuation-budget')),args,nil,{columns=51,rows=19})
end
local function context(limit,aggregate)
  return {computer={used=0,limit=Limits.compiler_work_per_computer}, continuation_computer={used=0,limit=limit},
    continuation_aggregate=aggregate and {used=0,limit=aggregate} or nil}
end
local function finish(vm,credits)
  for _=1,200 do
    local status,result = VM.run(vm,256,credits)
    if status == 'dead' then assert(not vm.objects[vm.main.ref].failed); return result end
  end
  error('continuation budget fixture deadline')
end
local source = [[local args={}; for i=1,32 do args[i]=pcall end
  args[33]=function() os.pullEventRaw('go'); return 73 end
  return args[1](table.unpack(args,2,33))]]
local function pending()
  local vm = make(source)
  for _=1,100 do VM.run(vm,256); if vm.wait then break end end
  assert(vm.wait and VM.queue(vm,table.pack('go')))
  for _=1,100 do
    VM.run(vm,1)
    local record=vm.pending_operation
    if record and record.kind == 'deliver' and record.a.kind == 'return' then return vm end
  end
  error('no pending protected prefix')
end
local function pause_at_error(vm)
  VM.run(vm,1000); assert(vm.wait and VM.queue(vm,table.pack('go')))
  for _=1,100 do
    VM.run(vm,1)
    local co=vm.objects[vm.current]
    local frame=co and co.frames[#co.frames]
    local inst=frame and frame.proto and frame.proto.instructions[frame.pc]
    local cell=inst and frame.registers[inst.a] and vm.objects[frame.registers[inst.a]]
    local fn=cell and type(cell.value) == 'table' and vm.objects[cell.value.ref]
    if inst and (inst.op == 'call' or inst.op == 'tailcall') and fn and fn.name == 'error' then return vm end
  end
  error('copy recovery fixture did not reach error call')
end
local function native_handler()
  local vm=make([[local h=assert(io.open('/handler.txt','w')); h:write('new')
    return xpcall(function() os.pullEventRaw('go'); error(h) end,h.flush)]])
  vm.disk.fs['/handler.txt']={type='file',text='old'}
  return pause_at_error(vm)
end
local function concat_handler()
  local vm=make([[local h=assert(io.open('/concat.txt','w')); h:write('new')
    setmetatable(h,{__concat=h.flush})
    local middle=setmetatable({}, {__concat=pcall,
      __call=function() os.pullEventRaw('go'); error('boom') end})
    return pcall(function() return h .. middle .. {} end)]])
  vm.disk.fs['/concat.txt']={type='file',text='old'}
  return pause_at_error(vm)
end
function M.initial(check)
  for _,scope in ipairs({'computer','aggregate'}) do
    local vm=pending()
    local quote=2 + vm.pending_operation.b.n
    local credits=context(scope == 'computer' and quote-1 or quote,scope == 'aggregate' and quote-1 or quote)
    local result=finish(vm,credits)
    check('prefix copy refusal retains its protected boundary '..scope,result[result.n-1] == false
      and result[result.n] == (scope == 'computer' and 'per-computer' or 'aggregate')..' continuation work limit exceeded')
    check('paired continuation counters reject atomically '..scope,credits.continuation_computer.used == 0
      and credits.continuation_aggregate.used == 0)
  end
  local args={n=100}; for i=1,args.n do args[i]=73 end
  local vm=make([[local function f(...) os.pullEventRaw('go'); return ... end; return pcall(f,...)]],args)
  VM.run(vm,1000); assert(vm.wait and VM.queue(vm,table.pack('go')))
  local credits=context(1,1)
  local result=finish(vm,credits)
  check('vararg movement refuses with admitted prior work retained',result[1] == false
    and result[2] == 'per-computer continuation work limit exceeded' and credits.continuation_computer.used == 1
    and credits.continuation_aggregate.used == 1)

  vm=pending()
  credits=context(0,0)
  VM.run(vm,1,credits)
  check('exhausted copying stages mandatory recovery as data',vm.pending_operation ~= nil and vm.pending_operation.recovery == true)
  Collector.start(vm); Collector.step(vm,7)
  storage.continuation_budget_recovery={vm=vm,credits=credits}

  -- A native error handler can transfer ownership into guest bytecode while
  -- mandatory recovery is active. That bytecode must use ordinary credits.
  vm=make([[local child=coroutine.create(function() return 73 end)
    return xpcall(function() os.pullEventRaw('go'); error(child) end,coroutine.resume)]])
  VM.run(vm,1000); assert(vm.wait and VM.queue(vm,table.pack('go')))
  for _=1,100 do
    VM.run(vm,1)
    if vm.current ~= vm.main.ref then break end
  end
  assert(vm.current and vm.current ~= vm.main.ref)
  local child=vm.objects[vm.current]
  credits=context(0,0)
  result=finish(vm,credits)
  check('native recovery handler cannot grant its child free bytecode copies',
    child.status == 'dead' and child.failed == true and child.error == 'per-computer continuation work limit exceeded'
    and result.n == 2 and result[1] == false and result[2] == false)
  check('child refusal does not consume exhausted continuation credits',
    credits.continuation_computer.used == 0 and credits.continuation_aggregate.used == 0)

  -- The single error argument costs two units; the file receiver shift must
  -- not become free merely because the guest selected it as an error handler.
  storage.native_handler_admission={}
  storage.concat_handler_admission={}
  for _,scope in ipairs({'computer','aggregate'}) do
    local limit=scope == 'computer' and 2 or 3
    local aggregate=scope == 'aggregate' and 2 or 3
    vm=native_handler()
    credits=context(limit,aggregate)
    result=finish(vm,credits)
    check('native error handler cannot bypass receiver copy admission '..scope,result.n == 2
      and result[1] == false and result[2] == 'error in error handling'
      and credits.continuation_computer.used == 2 and credits.continuation_aggregate.used == 2)
    check('refused native handler leaves saved file unchanged '..scope,vm.disk.fs['/handler.txt'].text == 'old')

    vm=native_handler()
    credits=context(limit,aggregate)
    VM.run(vm,1,credits)
    check('guest handler is staged outside mandatory recovery '..scope,vm.pending_operation ~= nil
      and vm.pending_operation.kind == 'call' and vm.pending_operation.recovery == false)
    Collector.start(vm); Collector.step(vm,7)
    storage.native_handler_admission[scope]={vm=vm,credits=credits,instructions=vm.instructions}

    vm=concat_handler()
    credits=context(scope == 'computer' and 2 or 4,scope == 'aggregate' and 2 or 4)
    result=finish(vm,credits)
    check('recovery concat metamethod requires ordinary copy admission '..scope,result.n == 2
      and result[1] == false and result[2] == (scope == 'computer' and 'per-computer' or 'aggregate')..' continuation work limit exceeded'
      and vm.disk.fs['/concat.txt'].text == 'old')
    check('refused recovery metamethod preserves admitted counters '..scope,credits.continuation_computer.used == 2
      and credits.continuation_aggregate.used == 2)

    vm=concat_handler()
    credits=context(scope == 'computer' and 2 or 4,scope == 'aggregate' and 2 or 4)
    VM.run(vm,1,credits)
    check('recovery metamethod is staged as ordinary guest work '..scope,vm.pending_operation ~= nil
      and vm.pending_operation.kind == 'call' and vm.pending_operation.recovery == false)
    Collector.start(vm); Collector.step(vm,7)
    storage.concat_handler_admission[scope]={vm=vm,credits=credits,instructions=vm.instructions}
  end

  local state=Scheduler.new()
  vm=make('local t={n=0}; while true do t.n=t.n+1 end')
  VM.run(vm,1000)
  Scheduler.add(state,1,vm)
  local values=table.pack(Scheduler.tick(state,900))
  check('scheduler reports admitted continuation work',values.n == 11 and values[11] > 0
    and values[11] == state.continuation_budget.used)
  local counter=state.continuation_budget
  local used=counter.used
  Scheduler.tick(state,900)
  check('same-tick execution cannot renew copy credits',state.continuation_budget == counter and counter.used == used)
  storage.continuation_credit_scheduler=state
  storage.continuation_credit_used=used
end
function M.resume(check)
  for _,scope in ipairs({'computer','aggregate'}) do
    local concat=storage.concat_handler_admission[scope]
    check('ordinary metamethod remains pending without load-time execution '..scope,concat.vm.pending_operation.kind == 'call'
      and concat.vm.pending_operation.recovery == false and concat.vm.instructions == concat.instructions)
    while concat.vm.collection do Collector.step(concat.vm,1024) end
    local result=finish(concat.vm,concat.credits)
    check('reloaded recovery metamethod cannot bypass copy admission '..scope,result.n == 2 and result[1] == false
      and result[2] == (scope == 'computer' and 'per-computer' or 'aggregate')..' continuation work limit exceeded'
      and concat.vm.disk.fs['/concat.txt'].text == 'old' and concat.credits.continuation_computer.used == 2
      and concat.credits.continuation_aggregate.used == 2)
    local handler=storage.native_handler_admission[scope]
    check('ordinary handler mode survives reload without guest execution '..scope,handler.vm.pending_operation.kind == 'call'
      and handler.vm.pending_operation.recovery == false and handler.vm.instructions == handler.instructions)
    while handler.vm.collection do Collector.step(handler.vm,1024) end
    local refused=finish(handler.vm,handler.credits)
    check('collected reloaded native handler still needs ordinary copy credits '..scope,refused.n == 2
      and refused[1] == false and refused[2] == 'error in error handling'
      and handler.vm.disk.fs['/handler.txt'].text == 'old' and handler.credits.continuation_computer.used == 2
      and handler.credits.continuation_aggregate.used == 2)
  end
  local saved=storage.continuation_budget_recovery
  check('recovery mode and exhausted copy credits survive reload',saved.vm.pending_operation.recovery == true
    and saved.credits.continuation_computer.limit == 0 and saved.credits.continuation_aggregate.used == 0)
  while saved.vm.collection do Collector.step(saved.vm,1024) end
  local result=finish(saved.vm,saved.credits)
  check('mandatory recovery completes through collection with zero ordinary credits',result[result.n-1] == false
    and result[result.n] == 'per-computer continuation work limit exceeded' and saved.credits.continuation_computer.used == 0)
  local state=storage.continuation_credit_scheduler
  Scheduler.tick(state,900)
  check('same-tick reload preserves admitted copy credits',state.continuation_budget.tick == 900
    and state.continuation_budget.used == storage.continuation_credit_used)
  Scheduler.tick(state,901)
  check('later tick renews continuation ledger',state.continuation_budget.tick == 901)
end
return M
