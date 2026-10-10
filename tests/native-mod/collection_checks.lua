local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Collector = require('__computer_core_2__.scripts.native.collector')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local Files = require('__computer_core_2__.scripts.guest.files')
local Filesystem = require('__computer_core_2__.scripts.filesystem')
local committed, draft = 'previous file', 'unsaved user draft'
local function file_spend(m)
 return function(amount)
  assert(type(amount)=='number' and amount>=0 and amount==math.floor(amount))
  m.file_work=(m.file_work or 0)+amount
 end
end
local function prepare_draft(m)
 -- This local-only module consumes plain disk/counter records, not VM objects.
 -- Open an actual retained handle draft rather than fabricating metadata.
 m.disk={}; Filesystem.init(m.disk)
 m.open_handles,m.handle_bytes=0,0
 local spend=file_spend(m)
 Files.replace(m,'/draft.lua',committed,spend)
 m.file_handles={Files.open(m,'/draft.lua','w+',spend)}
 Files.write(m,m.file_handles[1],draft,spend)
 Files.seek(m.file_handles[1],'set',3,spend)
end
local function draft_intact(m)
 local h=m.file_handles[1]
 return not h.closed and not h.failed and h.text==draft and h.offset==3
  and m.open_handles==1 and m.handle_bytes==#draft
  and Files.read_source(m,'/draft.lua',file_spend(m))==committed
end
local function recover_draft(m,check,label)
 local h,left=m.file_handles[1],1
 local ok=pcall(Files.close,m,h,function(amount)
  if amount>left then error('fixture file work refused',0) end
  left=left-amount
 end)
 check(label..' credit-refused close preserves actual open draft',not ok and draft_intact(m))
 Files.close(m,h,file_spend(m))
 check(label..' explicit retry commits draft and releases handle quota',h.closed and m.open_handles==0 and m.handle_bytes==0
  and Files.read_source(m,'/draft.lua',file_spend(m))==draft)
end
local function collect(m, quantum)
 Collector.start(m)
 local turns=0
 while m.collector do
  local before=m.collection_work or 0
  local spent=Collector.step(m,quantum or 17)
  assert(spent<= (quantum or 17) and (m.collection_work or 0)-before==spent)
  turns=turns+1
  assert(turns<100000,'native collection failed to finish')
 end
 return turns
end
return {
 prepare_draft=prepare_draft,
 draft_intact=draft_intact,
 file_spend=file_spend,
 start_pressure=function()
  local b=assert(Compiler.compile('local t={}; for i=1,8192 do t[i]={a={}} end; return t','=native-tick-heap-quota'))
  local n=assert(Compiler.compile('local n=0; while true do n=n+1; visits=n end','=native-tick-neighbor'))
  local m=Execution.new(b)
  prepare_draft(m)
  return {machine=m,bundle=b,neighbor=Execution.new(n),neighbor_bundle=n,ticks=0}
 end,
 pressure_tick=function(state,check)
  state.ticks=state.ticks+1
  local m,n=state.machine,state.neighbor
  local work=m.collection_work or 0
  local before=n.blocks
  if state.recovering then Collector.step(m,Limits.collection_work_per_computer)
  else
   local collecting=m.collector or m.objects>=m.collect_at
   local credits=collecting and Limits.collection_work_per_computer or (Limits.instructions_per_tick-128)
   local _,spent=Execution.run(m,state.bundle,Execution.executable(state.bundle),credits)
   assert(spent<=credits)
  end
  assert((m.collection_work or 0)-work<=Limits.collection_work_per_computer)
  Execution.run(n,state.neighbor_bundle,Execution.executable(state.neighbor_bundle),128)
  assert(n.status=='running' and n.blocks>before,'neighbor lost service during native quota/collection work')
  if not state.recovering and m.status=='error' then
   check('native real-tick allocation pressure reaches actual object quota',m.error.message:find('heap quota',1,true) and m.objects<=Limits.heap_objects)
   state.recovering=true
   Collector.start(m)
  end
  assert(state.ticks<550,'native real-tick structural quota deadline exceeded')
  if state.recovering and not m.collector then
   check('native neighbor progresses on every real quota and recovery tick',Execution.get(n,n.env,'visits')>0 and state.ticks>1)
   check('native real-tick heap recovery preserves actual open draft and committed disk',m.objects<Limits.heap_objects and draft_intact(m))
   recover_draft(m,check,'native real-tick heap recovery')
   log('CC2 NATIVE REAL TICK HEAP ticks='..state.ticks..' allocations='..m.allocations..' blocks='..m.blocks..' collection_work='..m.collection_work..' neighbor_blocks='..n.blocks)
   return true
  end
  return false
 end,
 run=function(check)
  local b=assert(Compiler.compile('local t={}; for i=1,80 do local x={}; t[i]=function() return i,x end end; return t','=native-collection-roots'))
  local m=Execution.new(b)
  local status=Execution.run(m,b,Execution.executable(b),10000)
  assert(status=='return',m.error and m.error.message)
  local before=m.objects
  local root=m.result[1]
  collect(m)
  check('native collector removes unreachable cells and retains result closure graph',m.objects<before and Execution.type(m,Execution.get(m,root,1))=='function')
  check('native object quota matches dense live identity inventory',m.objects==#m.object_ids)
  for i,id in ipairs(m.object_ids) do assert(m.heap[id].object_slot==i) end
  check('native collector identity slots remain consistent after sweep',true)
  -- Fill the genuine object quota with rooted guest tables through constructors,
  -- not by replacing counters or injecting a synthetic heap graph.
  b=assert(Compiler.compile('local t={}; for i=1,8192 do t[i]={a={}} end; return t','=native-real-heap-quota'))
  m=Execution.new(b)
  prepare_draft(m)
  local blocks=Execution.executable(b)
  local turns=0
  -- Structural object-quota probe, not an OS/input latency gate. Include all
  -- collector work: the diagnostic 20001-turn run spent 522035 collection units
  -- before reaching the rooted cap, versus 97743 generated/transfer steps.
  repeat Execution.run(m,b,blocks,31); turns=turns+1 until m.status~='running' or turns>100000
  log('CC2 NATIVE HEAP PRESSURE status='..m.status..' objects='..m.objects..' blocks='..m.blocks..' collection_work='..tostring(m.collection_work)..' turns='..turns..' error='..tostring(m.error and m.error.message))
  check('native rooted allocation pressure refuses at genuine heap quota',m.status=='error' and m.error.message:find('heap quota',1,true) and m.objects<=Limits.heap_objects)
  collect(m,31)
  check('native exhausted-heap recovery retains actual draft offset and committed disk',draft_intact(m) and m.objects<Limits.heap_objects)
  recover_draft(m,check,'native exhausted-heap recovery')
  local neighbor=assert(Compiler.compile('return 42','=native-collection-neighbor'))
  local n=Execution.new(neighbor)
  check('native quota refusal does not stall separately serviced neighbor',Execution.run(n,neighbor,Execution.executable(neighbor),100)=='return' and n.result[1]==42)
 end,
 suspend=function(check)
  local b=assert(Compiler.compile([[
local e={code=7}
local a={}
a.self=a
local f=function(x) return x+a.self.code end
a.code=4
local n=0
for i=1,200 do local garbage={i} end
local ok,result=xpcall(function() error(e) end,function(err)
 n=n+1
 pause(err,a,f,nil)
 return err
end)
return ok,result==e,a.self==a,f(3),n,nil
]],'=native-collected-reload'))
  local m=Execution.new(b); Execution.install_core(m); Execution.service(m,'pause')
  prepare_draft(m)
  Execution.run(m,b,Execution.executable(b),10000,{pause=function(_,args) return 'yield',args end})
  assert(m.status=='yield',m.error and m.error.message)
  Collector.start(m)
  local before=m.blocks
  Collector.step(m,5)
  local work=m.collection_work
  Collector.step(m,0)
  check('native zero collection credits preserve live pending handler',m.collector and m.collection_work==work and m.blocks==before and m.status=='yield')
  return {machine=m,bundle=b,blocks=before,handle=m.file_handles[1],file_work=m.file_work}
 end,
 reload=function(state,check)
  local m=state.machine
  check('native incremental collection and protected handler survive reload',m.collector and m.blocks==state.blocks and m.status=='yield')
  check('native load preserves real handle identity draft offset and work',state.handle==m.file_handles[1] and m.file_work==state.file_work and draft_intact(m))
  local before=m.objects
  while m.collector do Collector.step(m,13) end
  check('native collected saved error closure and table identities remain live',m.objects<before and Execution.get(m,m.yielded[1],'code')==7
    and Execution.get(m,m.yielded[2],'self').native_ref==m.yielded[2].native_ref and Execution.type(m,m.yielded[3])=='function')
  Execution.resume(m,table.pack())
  local status=Execution.run(m,state.bundle,Execution.executable(state.bundle),1000)
  local r=m.result
  check('native collected protected recovery resumes captured values once',status=='return' and r.n==6 and r[1]==false and r[2] and r[3] and r[4]==7 and r[5]==1 and r[6]==nil)
  check('native collected protected recovery leaves real open draft intact',draft_intact(m))
  recover_draft(m,check,'native collected separate-process recovery')
 end,
}
