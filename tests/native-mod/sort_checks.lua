local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Events=require('__computer_core_2__.scripts.native.events')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local function create(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-sort')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick)
 local m=s.machines[1]
 for i=0,200 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or m.status=='yield' then return m end
 end
 error('sort fixture failed to finish')
end
local function direct_suspend(source)
 local s,m=create(source)
 local input,ids=Execution.table_value(m),{}
 for i,value in ipairs({3,1,2}) do
  local member=Execution.table_value(m)
  Execution.set(m,member,'key',value); Execution.set(m,input,i,member)
  ids[i]=member.native_ref
 end
 Execution.set(m,m.env,'input',input)
 finish(s,game.tick); assert(m.status=='yield')
 -- Drop public edges before collection. The un-compared third member must
 -- survive solely through the helper's private saved-wait receiver.
 for i=1,3 do Execution.set(m,input,i,nil) end
 Collector.start(m)
 return {scheduler=s,tick=game.tick,ids=ids}
end
return {
 run=function(check)
  local s,m=create([[
local a={7,1,3,1,-5}; table.sort(a)
local b={'leaf','root','branch'}; table.sort(b)
local empty={}; local one={7}; table.sort(empty); table.sort(one)
local tagged={{n=2,id='a'},{n=1,id='b'},{n=1,id='c'}}
table.sort(tagged,function(a,b) return a.n<b.n end)
return table.concat(a,','),table.concat(b,','),#empty,one[1],tagged[1].id,tagged[2].id,tagged[3].id
]])
  finish(s,10)
  check('native staged sort supports numbers strings empty singleton and stable guest comparison',m.status=='return'
   and m.result[1]=='-5,1,1,3,7' and m.result[2]=='branch,leaf,root' and m.result[3]==0 and m.result[4]==7
   and m.result[5]=='b' and m.result[6]=='c' and m.result[7]=='a')
  s,m=create([[
local marker={}; local a={3,1,2}; local calls=0
local ok,err=pcall(function() table.sort(a,function(x,y) calls=calls+1; error(marker) end) end)
local bad=pcall(function() table.sort(a,function() return true end) end)
local unsupported=pcall(function() table.sort({{}, {}}) end)
return ok,err==marker,table.concat(a,','),calls,bad,unsupported
]])
  finish(s,300)
  check('native sort callback errors preserve identity and staged input',m.status=='return' and m.result[1]==false
   and m.result[2]==true and m.result[3]=='3,1,2' and m.result[4]==1)
  check('native sort rejects inconsistent order and unsupported default reference comparison',m.status=='return'
   and m.result[5]==false and m.result[6]==false)
  s,m=create('return 1')
  local input=Execution.table_value(m)
  for i=1,Limits.table_keys do Execution.set(m,input,i,Limits.table_keys-i+1) end
  local work=0
  local services=Helpers.services(function(domain,amount) if domain=='table' then work=work+amount end end)
  local status,p=services['table.sort'](m,{n=1,input})
  local steps=0
  while status=='continue' do status,p=services['table.sort.step'](m,p); steps=steps+1; assert(steps<200000) end
  check('native maximum dense sort has bounded stages and ascending output',status=='return' and p.n==0
   and Execution.get(m,input,1)==1 and Execution.get(m,input,Limits.table_keys)==Limits.table_keys
   and steps<200000 and work>Limits.table_keys)
  local _,pending=services['table.sort'](m,{n=1,input})
  pending.phase,pending.size,pending.source='commit',2,{2,1}
  Scheduler.begin_tick(s,600)
  assert(Scheduler.consume(s,1,'table',Limits.table_work_per_computer-8))
  local metered=Helpers.services(function(domain,amount) return Scheduler.consume(s,1,domain,amount) end)
  check('native sort publication refuses atomically under exhausted table credit',not pcall(metered['table.sort.step'],m,pending)
   and Execution.get(m,input,1)==1 and Execution.get(m,input,2)==2
   and s.budget.used.table==Limits.table_work_per_computer)
  local full=Execution.table_value(m)
  for i=2,Limits.table_keys+1 do Execution.set(m,full,i,1) end
  pending.object,pending.source=full,{2,3}
  check('native sort preflights callback-mutated key capacity before any publication',not pcall(services['table.sort.step'],m,pending)
   and Execution.get(m,full,1)==nil and Execution.get(m,full,2)==1)
  s,m=create([[
local a={2,1}; local calls=0
local function cmp(x,y) calls=calls+1; table.sort({2,1},cmp); return x<y end
local ok=pcall(function() table.sort(a,cmp) end)
return ok,a[1],a[2],calls
]])
  finish(s,700)
  check('native nested sorting refuses at bounded helper depth without publishing input',m.status=='return'
   and m.result[1]==false and m.result[2]==2 and m.result[3]==1 and m.result[4]<=Limits.continuation_depth)
  s,m=create([[
local depth,maximum=0,0
local function leaf()
 depth=depth+1; maximum=math.max(maximum,depth)
 local ok,err=pcall(function() table.sort({leaf,leaf},pcall) end)
 depth=depth-1
 if not ok then error(err) end
 return false
end
local ok=pcall(function() table.sort({leaf,leaf},pcall) end)
return ok,maximum,depth
]])
  finish(s,750)
  check('native sort nesting remains bounded through direct protected-service comparators',m.status=='return'
   and m.result[1]==false and m.result[2]==Limits.continuation_depth and m.result[3]==0)
  s,m=create('local ok,value,gap=pcall(coroutine.yield); return ok,value,gap')
  finish(s,800); assert(m.status=='yield')
  Execution.resume(m,{n=2,'restored'})
  finish(s,801)
  check('native root wait publishes direct service results through protected receiver',m.status=='return'
   and m.result.n==3 and m.result[1]==true and m.result[2]=='restored' and m.result[3]==nil)
 end,
 suspend=function(check)
  local s,m=create([[
boot=(boot or 0)+1
local input={{key=3,id='a'},{key=1,id='b'},{key=2,id='c'},{key=1,id='d'}}
local calls=0
local child=coroutine.create(function()
 table.sort(input,function(a,b)
  calls=calls+1
  if calls==1 then coroutine.yield('comparison',nil,a.key,b.key,nil) end
  return a.key<b.key
 end)
 return input[1].id,input[2].id,input[3].id,input[4].id,calls
end)
local ok,tag,gap=coroutine.resume(child)
assert(ok and tag=='comparison' and gap==nil and input[1].id=='a')
coroutine.yield()
local success,a,b,c,d,count=coroutine.resume(child)
return success,a,b,c,d,count,boot,nil
]])
  finish(s,game.tick)
  assert(m.status=='yield')
  Collector.start(m)
  check('native comparator snapshot retains private helper control while callback is suspended',m.collector~=nil)
  local large,lm=create('table.sort(input); return input[1],input[8192]')
  local input=Execution.table_value(lm)
  for i=1,Limits.table_keys do Execution.set(lm,input,i,Limits.table_keys-i+1) end
  Execution.set(lm,lm.env,'input',input)
  local _,neighbor=create('while true do end')
  Scheduler.add(large,2,neighbor)
  Scheduler.tick(large,game.tick)
  check('native maximum sort suspends internally without a guest yield or result',lm.status=='running'
   and lm.heap[lm.active].pending.kind=='helper' and lm.heap[lm.active].pending.phase=='copy'
   and lm.yielded==nil and lm.result==nil)
  Collector.start(lm)
  local root=direct_suspend('table.sort(input,coroutine.yield); return input[1].key,input[2].key,input[3].key')
  local child=direct_suspend([[
local child=coroutine.create(function()
 table.sort(input,coroutine.yield)
 return input[1].key,input[2].key,input[3].key
end)
local ok,a,b=coroutine.resume(child)
coroutine.yield()
while coroutine.status(child)~='dead' do
 assert(ok)
 ok,a,b=coroutine.resume(child,a.key<b.key)
end
return ok,a,b
]])
  return {scheduler=s,tick=game.tick,blocks=m.blocks,large=large,large_blocks=lm.blocks,root=root,child=child}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native sort load executes no callback or initializer',m.blocks==state.blocks and m.collector~=nil)
  assert(Events.admit(m,table.pack('char','continue')))
  for i=1,200 do
   Scheduler.tick(s,state.tick+i)
   if m.status=='return' or m.status=='error' then break end
  end
  check('native collected callback sort resumes once across a separate engine process',m.status=='return'
   and m.result.n==8 and m.result[1]==true and m.result[2]=='b' and m.result[3]=='d'
   and m.result[4]=='c' and m.result[5]=='a' and m.result[6]>1 and m.result[7]==1 and m.result[8]==nil)
  s,m=state.large,state.large.machines[1]
  check('native mid-copy sort retains exhausted same-tick execution through load',m.blocks==state.large_blocks
   and m.status=='running' and s.budget.used.execution==Limits.instructions_per_tick)
  local neighbor,last,neighbor_ticks=s.machines[2],0,0
  local bounded=true
  for i=1,300 do
   local before=neighbor.blocks
   Scheduler.tick(s,state.tick+i)
   if neighbor.blocks>before then last=i; neighbor_ticks=neighbor_ticks+1 end
   bounded=bounded and i-last<=1 and s.budget.used.execution<=Limits.instructions_per_tick
    and (s.budget.used.table or 0)<=Limits.table_work_per_tick
    and s.budget.used.collection<=Limits.collection_work_per_tick
   if m.status=='return' or m.status=='error' then break end
  end
  check('native maximum staged sort finishes after collected mid-copy reload',m.status=='return'
   and m.result[1]==1 and m.result[2]==Limits.table_keys)
  check('native maximum sorting preserves shared caps and bounded neighbor service',bounded and neighbor_ticks>1)
  for _,kind in ipairs({'root','child'}) do
   local saved=state[kind]
   s,m=saved.scheduler,saved.scheduler.machines[1]
   local tick=saved.tick
   for i=1,200 do
    if not m.collector then break end
    tick=tick+1; Scheduler.tick(s,tick)
   end
   check('native direct '..kind..' callback receiver roots un-compared staged identities',not m.collector
    and m.heap[saved.ids[3]]~=nil and m.status=='yield')
   for i=1,10 do
    if m.status~='yield' then break end
    local values={n=0}
    if kind=='root' then
     values={n=1,Execution.get(m,m.yielded[1],'key')<Execution.get(m,m.yielded[2],'key')}
    end
    Execution.resume(m,values); tick=tick+1; finish(s,tick)
   end
   check('native direct '..kind..' yielding service comparator completes after collected reload',m.status=='return'
    and ((kind=='root' and m.result[1]==1 and m.result[2]==2 and m.result[3]==3)
     or (kind=='child' and m.result[1]==true and m.result[2]==1 and m.result[3]==2)))
  end
 end,
}
