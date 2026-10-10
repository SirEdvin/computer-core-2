local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
local function make(source, arguments)
  return VM.new(assert(Compiler.compile(source, '=tuple-budget')), arguments, nil, {columns = 51, rows = 19})
end
local function complete(vm)
  for _ = 1, 200 do
    local status, result = VM.run(vm, 256)
    if status == 'dead' then assert(not vm.objects[vm.main.ref].failed); return result end
  end
  error('tuple budget fixture did not complete')
end
function M.initial(check)
  local source = 'local n=...; return pcall(function() return table.unpack({},1,n) end)'
  local result = complete(make(source, table.pack(Limits.tuple_values)))
  check('protected result prefix cannot exceed tuple quota', result.n == 2 and result[1] == false and result[2] == 'guest tuple limit exceeded')
  result = complete(make(source, table.pack(Limits.tuple_values - 1)))
  check('maximum protected nil tuple retains exact arity', result.n == Limits.tuple_values and result[1] == true and result[result.n] == nil)
  result = complete(make([[local n=...; return xpcall(function() return table.unpack({},1,n) end,
    function(err) return 'handled:'..err end)]], table.pack(Limits.tuple_values)))
  check('protected tuple refusal invokes the xpcall handler', result[1] == false and result[2] == 'handled:guest tuple limit exceeded')
  source = [[local n=...; local called=false; local target={}
    local fn=setmetatable(target,{__call=function(self,...) called=true; return select('#',...),self==target end})
    local ok,count,same=pcall(function() return fn(table.unpack({},1,n)) end)
    return ok,count,same,called]]
  result = complete(make(source, table.pack(Limits.tuple_values)))
  check('metamethod argument growth refuses before invocation', result[1] == false and result[2] == 'guest tuple limit exceeded' and result[4] == false)
  result = complete(make(source, table.pack(Limits.tuple_values - 1)))
  check('maximum metamethod argument tuple preserves receiver', result[1] == true and result[2] == Limits.tuple_values - 1 and result[3] == true and result[4] == true)
  source = [[local n=...; tuple_child=coroutine.create(function() return table.unpack({},1,n) end)
    local ok,err=coroutine.resume(tuple_child); return ok,err,coroutine.status(tuple_child)]]
  result = complete(make(source, table.pack(Limits.tuple_values)))
  check('coroutine return overflow fails the child recoverably', result[1] == false and result[2] == 'guest tuple limit exceeded' and result[3] == 'dead')
  source = [[local n=...; tuple_child=coroutine.create(function() coroutine.yield(table.unpack({},1,n)) end)
    local ok,err=coroutine.resume(tuple_child); return ok,err,coroutine.status(tuple_child)]]
  local vm = make(source, table.pack(Limits.tuple_values))
  result = complete(vm)
  local child = vm.objects[vm.objects[vm.env.ref].entries['s:tuple_child'].value.ref]
  check('yield overflow cannot strand a suspended child', result[1] == false and result[2] == 'guest tuple limit exceeded'
    and result[3] == 'dead' and child.awaiting_resume == nil and child.resumer == nil)
  source = [[local n=...; tuple_child=coroutine.create(function() return table.unpack({},1,n) end)
    local ok,err=pcall(coroutine.resume,tuple_child); return ok,err,coroutine.status(tuple_child)]]
  vm = make(source, table.pack(Limits.tuple_values - 1))
  result = complete(vm)
  child = vm.objects[vm.objects[vm.env.ref].entries['s:tuple_child'].value.ref]
  check('delivery overflow belongs to the protected parent', result[1] == false and result[2] == 'guest tuple limit exceeded'
    and result[3] == 'dead' and not child.failed and child.result.n == Limits.tuple_values - 1)
  source = [[local n=...; local calls={}; for i=1,n do calls[i]=pcall end
    calls[n+1]=type; calls[n+2]=7; return calls[1](table.unpack(calls,2,n+2))]]
  result = complete(make(source, table.pack(Limits.call_frames + 1)))
  check('native protected boundaries obey the existing frame ceiling', result[result.n - 1] == false and result[result.n] == 'guest call stack limit exceeded')
  result = complete(make(source, table.pack(Limits.call_frames)))
  check('maximum native protected boundary depth remains usable', result.n == Limits.call_frames + 1 and result[1] == true and result[result.n] == 'number')
  local ok, err = pcall(VM.new, assert(Compiler.compile('return true')), {n = Limits.tuple_values + 1})
  check('constructor rejects oversized argument tuples', not ok and err == 'guest argument tuple limit exceeded')
  source = [[local n=...; local calls={}; for i=1,n do calls[i]=pcall end
    calls[n+1]=os.pullEventRaw; calls[n+2]='go'; return calls[1](table.unpack(calls,2,n+2))]]
  vm = make(source, table.pack(100))
  for _ = 1, 100 do VM.run(vm,256); if vm.wait then break end end
  check('bounded native protected chain suspends as plain frames', vm.wait ~= nil and #vm.objects[vm.main.ref].frames == 100)
  storage.tuple_boundary_wait = vm
end
function M.resume(check)
  local vm = storage.tuple_boundary_wait
  check('protected chain remains suspended through reload', vm.wait ~= nil and #vm.objects[vm.main.ref].frames == 100)
  assert(VM.queue(vm, table.pack('go',nil,9,nil)))
  local result = complete(vm)
  local flags = true
  for i = 1, 100 do flags = flags and result[i] == true end
  check('reloaded protected chain preserves prefix and trailing nil arity', flags and result.n == 104 and result[101] == 'go'
    and result[102] == nil and result[103] == 9 and result[104] == nil and #vm.objects[vm.main.ref].frames == 0)
end
return M
