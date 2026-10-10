local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Collector = require("__computer_core_2__.scripts.guest.collector")
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
local names, declarations = {}, {}
for i=1,96 do
  names[i]='v'..i
  declarations[i]='local '..names[i]..'='..i
end
local locals=table.concat(declarations,'; ')
local capture='function() return '..table.concat(names,',')..' end'
local output=[[local all=table.pack(snapshot()); for i=1,96 do assert(all[i]==i) end
  return all.n,all[1],all[48],all[96],hole,73]]
local sources={
  ['return']="local function wide() "..locals.."; local snapshot="..capture..
    "; os.pullEventRaw('go'); return snapshot,nil,73 end; local snapshot,hole=wide(); "..output,
  tailcall="local function relay(...) return ... end; local function wide() "..locals..
    "; local snapshot="..capture.."; os.pullEventRaw('go'); return relay(snapshot,nil,73) end; local snapshot,hole=wide(); "..output,
  jmp="local snapshot; do "..locals.."; snapshot="..capture..
    "; os.pullEventRaw('go') end; local v1=999; "..output
}
local function prepare(mode,legacy)
  local vm=VM.new(assert(Compiler.compile(sources[mode],'=frame-cleanup-'..mode)),nil,nil,{columns=51,rows=19})
  VM.run(vm,10000); assert(vm.wait and VM.queue(vm,table.pack('go')))
  for _=1,100 do
    VM.run(vm,1)
    local co=vm.current and vm.objects[vm.current]
    local frame=co and co.frames[#co.frames]
    local inst=frame and frame.proto and frame.proto.instructions[frame.pc]
    if inst and inst.op==mode and frame.proto.max_stack_size>=96 and (mode~='jmp' or inst.a>0) then
      if legacy then
        frame.register_limit=nil
        for _,id in pairs(frame.registers) do vm.objects[id].captured=nil end
      end
      return vm
    end
  end
  error('frame cleanup fixture did not reach '..mode)
end
local function drain(vm,check,label)
  local bounded=true
  for _=1,2000 do
    local before,instructions=vm.cleanup_work or 0,vm.instructions
    local status,result,used=VM.run(vm,1)
    bounded=bounded and (vm.cleanup_work or 0)-before<=Limits.cleanup_work_per_step
      and used<=1 and vm.instructions-instructions==used
    if status=='dead' then
      check('frame cleanup preserves captured cells and nil tuple '..label,not vm.objects[vm.main.ref].failed
        and result.n==6 and result[1]==96 and result[2]==1 and result[3]==48 and result[4]==96
        and result[5]==nil and result[6]==73 and vm.pending_operation==nil)
      check('frame cleanup shares the paid-step ceiling '..label,bounded)
      return
    end
  end
  error('frame cleanup fixture deadline '..label)
end
function M.initial(check)
  storage.frame_cleanup={}
  for _,mode in ipairs({'return','tailcall','jmp'}) do
    local vm=prepare(mode)
    local before=vm.cleanup_work or 0
    VM.run(vm,1)
    local kind=mode=='jmp' and 'close_upvalues' or 'frame_cleanup'
    check('wide normal operation defers weighted cleanup '..mode,vm.pending_operation~=nil
      and vm.pending_operation.kind==kind and vm.pending_operation.recovery==false
      and (vm.cleanup_work or 0)-before>0 and (vm.cleanup_work or 0)-before<=Limits.cleanup_work_per_step)
    local record,instructions,work=vm.pending_operation,vm.instructions,vm.cleanup_work
    local _,_,used=VM.run(vm,0)
    check('zero credit preserves normal cleanup '..mode,used==0 and vm.pending_operation==record
      and vm.instructions==instructions and vm.cleanup_work==work)
    drain(vm,check,'initial-'..mode)
    vm=prepare(mode,true); VM.run(vm,1)
    assert(vm.pending_operation and vm.pending_operation.kind==kind)
    Collector.start(vm); Collector.step(vm,7)
    storage.frame_cleanup[mode]={vm=vm,instructions=vm.instructions,work=vm.cleanup_work,kind=kind}
  end
end
function M.resume(check)
  for _,mode in ipairs({'return','tailcall','jmp'}) do
    local saved=storage.frame_cleanup[mode]
    local vm=saved.vm
    check('normal cleanup survives reload without execution '..mode,vm.pending_operation.kind==saved.kind
      and vm.instructions==saved.instructions and vm.cleanup_work==saved.work)
    while vm.collection do Collector.step(vm,1024) end
    drain(vm,check,'legacy-reloaded-'..mode)
  end
end
return M
