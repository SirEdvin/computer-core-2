local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Collector = require("__computer_core_2__.scripts.guest.collector")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
local source=[[local function dive(n)
  local a,b,c,d,e,f,g,h=n,n,n,n,n,n,n,n
  if n==0 then os.pullEventRaw('go'); error('unwind') end
  local result=dive(n-1)
  return a+b+c+d+e+f+g+h+result
end
return pcall(dive,80)]]
local proto=assert(Compiler.compile(source, '=weighted-unwind'))
local reference_source=source:gsub("error%('unwind'%)", "error({tag=73})")
local reference_proto=assert(Compiler.compile(reference_source, '=weighted-reference-unwind'))
local function prepare(reference)
  local vm=VM.new(reference and reference_proto or proto,nil,nil,{columns=51,rows=19})
  VM.run(vm,10000); assert(vm.wait and VM.queue(vm,table.pack('go')))
  for _=1,100 do
    VM.run(vm,1)
    local co=vm.objects[vm.current]
    local frame=co and co.frames[#co.frames]
    local inst=frame and frame.proto and frame.proto.instructions[frame.pc]
    local cell=inst and frame.registers[inst.a] and vm.objects[frame.registers[inst.a]]
    local fn=cell and type(cell.value)=='table' and vm.objects[cell.value.ref]
    if fn and fn.name=='error' and (inst.op=='call' or inst.op=='tailcall') then return vm end
  end
  error('unwind fixture did not reach error call')
end
local function drain(vm,check,phase,reference)
  local bounded=true
  for _=1,200 do
    local work,instructions=vm.cleanup_work or 0,vm.instructions
    local status,result,used=VM.run(vm,1)
    bounded=bounded and (vm.cleanup_work or 0)-work <= Limits.cleanup_work_per_step
      and used <= 1 and vm.instructions-instructions==used
    if status=='dead' then
      local error_ok=result[2]=='unwind'
      if reference then
        local value=type(result[2])=='table' and vm.objects[result[2].ref]
        error_ok=value and value.kind=='table' and value.entries['s:tag'].value==73
      end
      check('weighted unwind remains protected '..phase,result.n==2 and result[1]==false and error_ok
        and not vm.objects[vm.main.ref].failed and vm.pending_operation==nil)
      check('weighted unwind obeys one-credit work ceiling '..phase,bounded)
      return
    end
  end
  error('weighted unwind deadline')
end
function M.initial(check)
  local vm=prepare()
  VM.run(vm,1)
  check('deep exception cleanup is staged rather than bulk released',vm.pending_operation ~= nil
    and vm.pending_operation.kind=='failure_cleanup' and #vm.objects[vm.current].frames>1)
  check('first unwind slice respects weighted ceiling',(vm.cleanup_work or 0)>0
    and vm.cleanup_work<=Limits.cleanup_work_per_step)
  drain(vm,check,'initial')
  vm=prepare(); VM.run(vm,1)
  Collector.start(vm); Collector.step(vm,7)
  storage.weighted_unwind={vm=vm,instructions=vm.instructions,work=vm.cleanup_work}
  vm=prepare(true); VM.run(vm,1)
  Collector.start(vm); Collector.step(vm,7)
  storage.weighted_reference_unwind={vm=vm,instructions=vm.instructions,work=vm.cleanup_work}
  local instructions,work=vm.instructions,vm.cleanup_work
  while vm.collection do Collector.step(vm,1024) end
  local _,_,used=VM.run(vm,0)
  check('zero execution credit leaves partial unwind unchanged',used==0 and vm.instructions==instructions
    and vm.cleanup_work==work and vm.pending_operation.kind=='failure_cleanup')
end
function M.resume(check)
  local saved=storage.weighted_unwind
  local vm=saved.vm
  check('partial unwind survives reload without load-time work',vm.pending_operation.kind=='failure_cleanup'
    and vm.instructions==saved.instructions and vm.cleanup_work==saved.work)
  while vm.collection do Collector.step(vm,1024) end
  drain(vm,check,'reloaded')
  saved=storage.weighted_reference_unwind
  vm=saved.vm
  check('reference-valued partial unwind survives reload without work',vm.pending_operation.kind=='failure_cleanup'
    and vm.instructions==saved.instructions and vm.cleanup_work==saved.work)
  Collector.start(vm)
  while vm.collection do Collector.step(vm,1024) end
  drain(vm,check,'reference-reloaded',true)
end
return M
