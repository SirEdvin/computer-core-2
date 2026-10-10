local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Dispatch = require('__computer_core_2__.scripts.native.dispatch')
local Files = require('__computer_core_2__.scripts.guest.files')
local Collection = require('collection_checks')
local Collector = require('__computer_core_2__.scripts.native.collector')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local function admission(ledger)
 return function(amount)
  ledger.calls=ledger.calls+1
  if amount>ledger.left then return false end
  ledger.left,ledger.spent=ledger.left-amount,ledger.spent+amount
  return true
 end
end
local function allowance(limit)
 local ledger={left=limit,spent=0,calls=0}
 return ledger,admission(ledger)
end
local function services()
 return {pause=function(_,args) return 'yield',args end}
end
local source=[[
effects=(effects or 0)+1
local x=10
local a={}
a.self=a
local function f(n) x=x+n; return x,a end
local child=coroutine.create(function()
 local nested=coroutine.create(function()
  local ok,e=xpcall(function()
   pause(f,a,nil)
   error(a)
  end,function(e)
   pause(e,f,nil)
   return e
  end)
  coroutine.yield(ok,e,f,nil)
  return e,f,a,nil
 end)
 local first,ok,e,saved=coroutine.resume(nested)
 local second,e2,saved2,a2=coroutine.resume(nested)
 return first and second,ok,e==a and e2==a and a2==a,saved==f and saved2==f
end)
local resumed,valid,ok,aliased,shared=coroutine.resume(child)
return resumed and valid,ok,aliased,shared,f(2),effects,nil
]]
local function machine(bundle)
 local m=Execution.new(bundle)
 Execution.install_core(m)
 Execution.service(m,'pause')
 Collection.prepare_draft(m)
 Files.replace(m,'/active.lua',bundle.source,Collection.file_spend(m))
 return m
end
return {
 run=function(check)
  local metrics={}
  local refused,err=Compiler.compile('return 1','=snapshot-refusal',metrics,function()
   if metrics.phase=='snapshot' then error('fixture snapshot refused',0) end
  end)
  check('native source snapshot admission refuses without a partial bundle',refused==nil and err:find('fixture snapshot refused',1,true)
   and metrics.snapshot_work==0)
  check('native compiler recovers after source snapshot refusal',Compiler.compile('return 1','=snapshot-refusal')~=nil)
  local b=assert(Compiler.compile('effects=(effects or 0)+1; return effects,nil','=activation'))
  local m=Execution.new(b)
  Dispatch.clear_cache()
  local count=Dispatch.cache_stats().loads
  local ledger,admit=allowance(0)
  local frames,pc=m.frames,m.frames[1].pc
  local status,spent,reason=Dispatch.run(m,100,admit)
  check('native activation refusal has no cache load or guest effect',status=='running' and spent==0 and reason=='activation-deferred'
   and m.frames==frames and m.frames[1].pc==pc and m.activation_work==nil and ledger.spent==0
   and Dispatch.cache_stats().loads==count and Execution.get(m,m.env,'effects')==nil)
  local cost=Dispatch.activation_cost(b)
  ledger,admit=allowance(cost)
  status,spent=Dispatch.run(m,100,admit)
  check('native cold activation pays exact deterministic reconstruction work',status=='return' and ledger.spent==cost
   and m.activation_work==cost and m.activation_dispatches==1 and Dispatch.cache_stats().loads==count+1)
  check('native cold activation executes initializer once and retains nil result',m.result.n==2 and m.result[1]==1 and m.result[2]==nil)
  local warm=Execution.new(b)
  ledger,admit=allowance(cost-1)
  status,spent,reason=Dispatch.run(warm,100,admit)
  check('native warm cache cannot bypass activation refusal',status=='running' and spent==0 and reason=='activation-deferred'
   and ledger.spent==0 and warm.activation_work==nil and Dispatch.cache_stats().loads==count+1)
  ledger,admit=allowance(cost)
  status,spent=Dispatch.run(warm,100,admit)
  check('native warm and cold activation have identical durable costs and outputs',status=='return' and warm.activation_work==m.activation_work
   and warm.activation_dispatches==m.activation_dispatches and warm.blocks==m.blocks and warm.result.n==m.result.n
   and warm.result[1]==m.result[1] and ledger.spent==cost and Dispatch.cache_stats().loads==count+1)
  local zero=Execution.new(b)
  ledger,admit=allowance(cost)
  Dispatch.run(zero,0,admit)
  check('native zero execution credits cannot charge activate or advance',ledger.calls==0 and zero.activation_work==nil and zero.blocks==0
   and zero.frames[1].pc==pc and Dispatch.cache_stats().loads==count+1)
  for _,kind in ipairs({'machine','bundle','compiler'}) do
   -- Each corrupted version gets a separate retained snapshot, not a mutation
   -- of a bundle shared by another running machine.
   local bad=machine(assert(Compiler.compile(source,'=incompatible-activation')))
   if kind=='machine' then bad.version=-1
   elseif kind=='bundle' then bad.bundle.version=-1
   else bad.bundle.source_version.compiler=-1 end
   local heap,frames,disk,draft=bad.heap,bad.frames,bad.disk,bad.file_handles[1]
   ledger,admit=allowance(cost*10)
   status,spent=Dispatch.run(bad,100,admit)
   check('native incompatible '..kind..' retains complete recovery graph',status=='recovery' and spent==0 and bad.recovery.previous_status=='running'
    and bad.heap==heap and bad.frames==frames and bad.disk==disk and bad.file_handles[1]==draft
    and Collection.draft_intact(bad) and ledger.calls==0 and bad.activation_work==nil)
  end
  local broken=machine(assert(Compiler.compile('return 1','=reconstruction-failure')))
  broken.bundle.generated='this is not valid Lua'
  ledger,admit=allowance(Dispatch.activation_cost(broken.bundle))
  status,spent=Dispatch.run(broken,100,admit)
  check('native host reconstruction failure is charged and retains recovery data',status=='recovery' and spent==0
   and broken.recovery.message:find('native reconstruction failed',1,true) and broken.blocks==0
   and ledger.spent==broken.activation_work and Collection.draft_intact(broken))
  local previous=broken.recovery
  Dispatch.run(broken,100,admit)
  check('native recovery dispatch does not overwrite original status or retry',broken.recovery==previous and previous.previous_status=='running'
   and ledger.calls==1 and broken.activation_dispatches==1)
  local primary=assert(Compiler.compile('local a,b=lib(); return a,b,nil','=bundle-caller'))
  local library=assert(Compiler.compile("effects=(effects or 0)+1; return 'leaf',effects,nil",'=bundle-library'))
  local function paired()
   local value=Execution.new(primary)
   Execution.install_core(value)
   local ref=Execution.register_bundle(value,library,function() end)
   Execution.set(value,value.env,'lib',ref)
   return value
  end
  local full=primary.activation_work+library.activation_work
  Dispatch.clear_cache(); count=Dispatch.cache_stats().loads
  local cold=paired(); ledger,admit=allowance(full)
  status,spent=Dispatch.run(cold,1000,admit)
  check('native cross-bundle cold dispatch admits each distinct source once',status=='return'
   and ledger.spent==full and cold.activation_dispatches==2 and Dispatch.cache_stats().loads==count+2
   and cold.result.n==3 and cold.result[1]=='leaf' and cold.result[2]==1 and cold.result[3]==nil)
  local hot=paired(); ledger,admit=allowance(full)
  status,spent=Dispatch.run(hot,1000,admit)
  check('native cross-bundle warm cache preserves exact activation and logical work',status=='return'
   and ledger.spent==full and hot.activation_work==cold.activation_work and hot.blocks==cold.blocks
   and Dispatch.cache_stats().loads==count+2 and hot.result[1]==cold.result[1] and hot.result[2]==1)
  local limited=paired(); ledger,admit=allowance(primary.activation_work)
  status,spent,reason=Dispatch.run(limited,1000,admit)
  check('native secondary activation refusal retains caller and unexecuted library frame',status=='running'
   and reason=='activation-deferred' and ledger.spent==primary.activation_work
   and limited.frames[#limited.frames].bundle_id==2 and Execution.get(limited,limited.env,'effects')==nil)
  local blocks=limited.blocks; ledger,admit=allowance(0)
  status,spent,reason=Dispatch.run(limited,1000,admit)
  check('native refused retained-library reentry cannot advance or use a warm executable',spent==0
   and limited.blocks==blocks and reason=='activation-deferred' and ledger.spent==0)
  ledger,admit=allowance(full); Dispatch.run(limited,1000,admit)
  check('native secondary activation retry resumes library initializer exactly once',limited.status=='return'
   and limited.result[2]==1 and limited.result.n==3 and ledger.spent==full)
  local refused_registry=Execution.new(primary)
  local before_objects,before_id=refused_registry.objects,refused_registry.next_id
  local accepted=pcall(Execution.register_bundle,refused_registry,library,function() error('registration refused',0) end)
  check('native bundle registration refuses before heap or source publication',not accepted
   and refused_registry.bundles==nil and refused_registry.objects==before_objects and refused_registry.next_id==before_id)
  local bad_library=assert(Compiler.compile('effects=99; return effects','=bad-bundle-library'))
  local incompatible=Execution.new(primary)
  local ref=Execution.register_bundle(incompatible,bad_library,function() end)
  Execution.set(incompatible,incompatible.env,'lib',ref)
  bad_library.source_version.compiler=-1
  ledger,admit=allowance(full)
  local original_heap=incompatible.heap
  Dispatch.run(incompatible,1000,admit)
  check('native incompatible secondary source retains recovery graph without initializer effects',incompatible.status=='recovery'
   and incompatible.heap==original_heap and incompatible.bundles[2]==bad_library
   and incompatible.frames[#incompatible.frames].bundle_id==2 and Execution.get(incompatible,incompatible.env,'effects')==nil)
  local missing=Execution.new(primary); missing.frames[1].bundle_id=2
  local original_frames=missing.frames
  ledger,admit=allowance(full); Dispatch.run(missing,1000,admit)
  check('native unknown retained frame bundle fails visibly without discarding recovery state',missing.status=='recovery'
   and missing.frames==original_frames and ledger.calls==0 and missing.blocks==0)
  local capped=Execution.new(primary)
  for i=2,Limits.call_frames do Execution.register_bundle(capped,library,function() end) end
  before_objects,before_id=capped.objects,capped.next_id
  accepted=pcall(Execution.register_bundle,capped,library,function() end)
  check('native retained-bundle count is bounded before overflow allocation',not accepted and #capped.bundles==Limits.call_frames
   and capped.objects==before_objects and capped.next_id==before_id)
 end,
 suspend=function(check)
  local b=assert(Compiler.compile(source,'=active-source-version'))
  local m=machine(b)
  local cost=Dispatch.activation_cost(b)
  local ledger,admit=allowance(2*cost)
  local status=Dispatch.run(m,1000,admit,services())
  check('native dispatcher snapshots active source and generated bundle',m.bundle==b and b.source==source and b.source_version.compiler==Compiler.VERSION
   and status=='yield' and m.yielded.n==3 and Execution.type(m,m.yielded[1])=='function')
  local closure,alias=m.yielded[1],m.yielded[2]
  Execution.resume(m,table.pack())
  status=Dispatch.run(m,1000,admit,services())
  local c=m.heap[m.active]
  check('native snapshot suspends nested owner chain in pending protected recovery',status=='yield' and c.depth==3
   and c.boundaries[#c.boundaries].phase=='handler' and m.heap[c.resumer.owner].resumer.owner==m.root
   and m.yielded[1].native_ref==alias.native_ref and m.yielded[2].native_ref==closure.native_ref)
  Files.replace(m,'/active.lua','return 99',Collection.file_spend(m))
  local work=m.activation_work
  -- No reconstruction/admission while waiting for a host event.
  Dispatch.run(m,1000,admit,services())
  check('native waiting dispatch does not activate or replay guest initializer',m.activation_work==work and m.activation_dispatches==2
   and Execution.get(m,m.env,'effects')==1)
  Collector.start(m)
  Dispatch.run(m,5,admit,services())
  check('native collector-only dispatch neither reconstructs nor charges activation',m.collector and m.activation_work==work
   and ledger.spent==work and ledger.left==0)
  local incompatible=machine(b)
  incompatible.version=-1
  Dispatch.run(incompatible,100,admit,services())
  return {machine=m,work=work,blocks=m.blocks,closure=closure,alias=alias,source=source,ledger=ledger,
   owner=m.active,parent=c.resumer.owner,frames=m.frames,active_handle=m.file_handles[1],
   incompatible=incompatible,handle=incompatible.file_handles[1]}
 end,
 reload=function(state,check)
  local m,b=state.machine,state.machine.bundle
  check('native on-load retains snapshotted source counters and effects',m.status=='yield' and m.blocks==state.blocks and m.activation_work==state.work
   and Execution.get(m,m.env,'effects')==1 and b.source==state.source)
  check('native separate-process cache starts cold',Dispatch.cache_stats().loads==0)
  local c=m.heap[m.active]
  check('native reload preserves nested resumers protected phase and frame alias',m.active==state.owner and m.frames==state.frames
   and m.frames==c.frames and c.resumer.owner==state.parent and m.heap[state.parent].resumer.owner==m.root
   and c.boundaries[#c.boundaries].phase=='handler')
  local ledger,admit=state.ledger,admission(state.ledger)
  local incompatible=state.incompatible
  Dispatch.run(incompatible,100,admit,services())
  check('native recovery state retains actual files handles and frames across reload',incompatible.status=='recovery'
   and incompatible.recovery.previous_status=='running' and incompatible.frames[1].pc==incompatible.bundle.prototypes[1].entry
   and incompatible.file_handles[1]==state.handle and Collection.draft_intact(incompatible) and incompatible.activation_work==nil)
  local turns=0
  while m.collector do
   Dispatch.run(m,13,admit,services())
   turns=turns+1; assert(turns<10000,'activation snapshot collection failed to finish')
  end
  check('native collected nested snapshot preserves closures aliases and spent ledger',m.status=='yield' and m.activation_work==state.work
   and ledger.left==0 and ledger.spent==state.work and Execution.get(m,state.alias,'self').native_ref==state.alias.native_ref
   and Execution.type(m,state.closure)=='function' and m.file_handles[1]==state.active_handle and Collection.draft_intact(m))
  Execution.resume(m,table.pack())
  local cost=Dispatch.activation_cost(b)
  local count=Dispatch.cache_stats().loads
  local status,spent,reason=Dispatch.run(m,1000,admit,services())
  check('native cold reload cannot renew exhausted activation credits',reason=='activation-deferred' and spent==0 and status=='running'
   and m.activation_work==state.work and m.blocks==state.blocks and ledger.spent==state.work and Dispatch.cache_stats().loads==count)
  -- Explicit fixture replenishment, not a production tick-budget policy.
  ledger.left=cost
  status=Dispatch.run(m,1000,admit,services())
  check('native reconstructed nested protected recovery completes exactly once',status=='return' and m.result.n==7
   and m.result[1]==true and m.result[2]==false and m.result[3]==true and m.result[4]==true and m.result[5]==12
   and m.result[6]==1 and m.result[7]==nil and m.activation_work==state.work+cost and ledger.spent==m.activation_work
   and Dispatch.cache_stats().loads==count+1)
  local warm=machine(b)
  ledger,admit=allowance(cost)
  status=Dispatch.run(warm,1000,admit,services())
  check('native warm nested activation pays same work without host reconstruction',status=='yield' and warm.yielded.n==3
   and Execution.get(warm,warm.env,'effects')==1 and warm.activation_work==cost and ledger.spent==cost
   and Dispatch.cache_stats().loads==count+1)
  local fresh=Execution.new(assert(Compiler.compile(Files.read_source(m,'/active.lua',Collection.file_spend(m)),'=active-source-version')))
  ledger,admit=allowance(Dispatch.activation_cost(fresh.bundle))
  status=Dispatch.run(fresh,100,admit)
  check('native disk edit affects fresh source load not suspended snapshot',status=='return' and fresh.result[1]==99
   and fresh.bundle.source~=b.source and b.source==state.source)
 end,
}
