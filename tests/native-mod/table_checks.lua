local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Events=require('__computer_core_2__.scripts.native.events')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local function create(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-table')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick)
 local m=s.machines[1]
 for i=0,200 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or m.status=='yield' then return m end
 end
 error('table fixture failed to finish')
end
local source=[[
local a={'root','leaf'}
local arity=select('#',table.insert(a,'twig'))
table.insert(a,2,'branch')
local first=table.remove(a,1)
local last=table.remove(a)
local outside=table.remove(a,#a+1)
local empty=table.remove({})
local b={false,'tail'}; table.insert(b,1,nil)
local c={}; table.insert(c,nil)
return arity,first,last,outside,empty,table.concat(a,','),b[1],b[2],b[3],c[1],
 select('#',table.remove(a,#a+1)),select('#',table.remove({}))
]]
return {
 run=function(check)
  local s,m=create(source); finish(s,10)
  local expected=table.pack(assert(load(source,'=table-reference','t',{table=table,select=select}))())
  check('native insertion and removal retain fixed-reference result arity',m.status=='return' and m.result.n==expected.n)
  for i=1,expected.n do check('native insertion removal reference value '..i,m.result[i]==expected[i]) end
  s,m=create([[
local a={3,2,1}; local called=0
setmetatable(a,{__newindex=function() called=called+1; error('not raw') end})
table.insert(a,1,4); local removed=table.remove(a,2)
local bad1=pcall(function() table.insert(a,0,7) end)
local bad2=pcall(function() table.remove(a,0) end)
local bad3=pcall(function() table.insert(a,1.5,7) end)
return called,removed,bad1,bad2,bad3,table.concat(a,',')
]])
  finish(s,50)
  check('native table mutation stays raw and refuses invalid indices',m.status=='return' and m.result[1]==0
   and m.result[2]==3 and m.result[3]==false and m.result[4]==false and m.result[5]==false and m.result[6]=='4,2,1')
  s,m=create('return 1')
  local input=Execution.table_value(m)
  for i=1,Limits.table_keys-1 do Execution.set(m,input,i,i) end
  local work=0
  local services=Helpers.services(function(domain,amount) if domain=='table' then work=work+amount end end)
  services['table.insert'](m,table.pack(input,1,'first'))
  check('native maximum insertion preserves both endpoints and bounded key inventory',Execution.get(m,input,1)=='first'
   and Execution.get(m,input,Limits.table_keys)==Limits.table_keys-1 and m.heap[input.native_ref].keys==Limits.table_keys)
  check('native excessive sequence insertion refuses without mutation',not pcall(services['table.insert'],m,table.pack(input,'extra'))
   and Execution.get(m,input,1)=='first' and m.heap[input.native_ref].keys==Limits.table_keys)
  local _,removed=services['table.remove'](m,table.pack(input,1))
  check('native maximum removal returns item and shifts all slots under existing limit',removed.n==1 and removed[1]=='first'
   and Execution.get(m,input,1)==1 and Execution.get(m,input,Limits.table_keys)==nil
   and m.heap[input.native_ref].keys==Limits.table_keys-1 and work>Limits.table_keys)
  local full=Execution.table_value(m)
  Execution.set(m,full,1,false); Execution.set(m,full,2,'tail')
  for i=1,Limits.table_keys-2 do Execution.set(m,full,'field'..i,i) end
  check('native full-key insertion rejects extra value atomically',not pcall(services['table.insert'],m,table.pack(full,1,'new'))
   and Execution.get(m,full,1)==false and Execution.get(m,full,2)=='tail' and Execution.get(m,full,3)==nil)
  services['table.insert'](m,table.pack(full,1,nil))
  check('native nil insertion into full-key table avoids temporary quota failure and preserves false',Execution.get(m,full,1)==nil
   and Execution.get(m,full,2)==false and Execution.get(m,full,3)=='tail' and m.heap[full.native_ref].keys==Limits.table_keys)
  local small=Execution.table_value(m)
  Execution.set(m,small,1,'a'); Execution.set(m,small,2,'b')
  Scheduler.begin_tick(s,100)
  assert(Scheduler.consume(s,1,'table',Limits.table_work_per_computer-3))
  local metered=Helpers.services(function(domain,amount) return Scheduler.consume(s,1,domain,amount) end)
  check('native insertion credit refusal happens after scan but before any writes',not pcall(metered['table.insert'],m,table.pack(small,1,'new'))
   and Execution.get(m,small,1)=='a' and Execution.get(m,small,2)=='b' and Execution.get(m,small,3)==nil
   and s.budget.used.table==Limits.table_work_per_computer)
  Scheduler.begin_tick(s,101)
  assert(Scheduler.consume(s,1,'table',Limits.table_work_per_computer-3))
  check('native removal credit refusal cannot shift or delete input',not pcall(metered['table.remove'],m,table.pack(small,1))
   and Execution.get(m,small,1)=='a' and Execution.get(m,small,2)=='b' and m.heap[small.native_ref].keys==2
   and s.budget.used.table==Limits.table_work_per_computer)
  s,m=create('local t={2,1}; local protect,insert=pcall,table.insert; coroutine.yield(t); return protect(function() insert(t,1,3) end)')
  finish(s,149); assert(m.status=='yield')
  local preserved=m.yielded[1]
  Scheduler.begin_tick(s,150); assert(Scheduler.consume(s,1,'table',Limits.table_work_per_computer-3))
  assert(Events.admit(m,table.pack('char','continue')))
  Scheduler.tick(s,150)
  check('native insertion refusal uses guest protected continuation',m.status=='return' and m.result[1]==false
   and Execution.get(m,preserved,1)==2 and Execution.get(m,preserved,2)==1 and Execution.get(m,preserved,3)==nil)
 end,
 suspend=function(check)
  local s,m=create([[
boot=(boot or 0)+1
local marker={name='held'}
local a={marker,false}
table.insert(a,2,'middle')
local removed=table.remove(a,1)
coroutine.yield()
table.insert(a,1,removed)
local middle=table.remove(a,2)
return a[1]==marker,middle,a[2],removed.name,boot,nil
]])
  finish(s,game.tick); assert(m.status=='yield')
  Scheduler.begin_tick(s,game.tick)
  assert(Scheduler.consume(s,1,'table',Limits.table_work_per_computer-(s.budget.used.table or 0)))
  Collector.start(m)
  check('native table edits snapshot retained reference and exhausted table credit',m.collector~=nil)
  return {scheduler=s,tick=game.tick,blocks=m.blocks}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native table edit load retains spent credits and executes no initializer',m.blocks==state.blocks and m.collector~=nil
   and s.budget.used.table==Limits.table_work_per_computer)
  assert(Events.admit(m,table.pack('char','continue')))
  for i=1,200 do
   Scheduler.tick(s,state.tick+i)
   if m.status=='return' or m.status=='error' then break end
  end
  check('native insertion removal preserve reference alias false and nil after collected reload',m.status=='return'
   and m.result.n==6 and m.result[1]==true and m.result[2]=='middle' and m.result[3]==false
   and m.result[4]=='held' and m.result[5]==1 and m.result[6]==nil)
 end,
}
