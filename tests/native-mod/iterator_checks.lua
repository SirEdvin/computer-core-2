local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Events=require('__computer_core_2__.scripts.native.events')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local function create(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-ipairs')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick)
 local m=s.machines[1]
 for i=0,200 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or m.status=='yield' then return m end
 end
 error('ipairs fixture failed to finish')
end
local source=[[
local input={false,'leaf',nil,'ignored'}
local count,last=0,0
for index,value in ipairs(input) do count=count+1; last=index end
local iterate,state,control=ipairs(input)
local first,a=iterate(state,control)
local second,b=iterate(state,first)
local ending=select('#',iterate(state,second))
local missing=iterate(state,second)
local empty=0
for index,value in ipairs({}) do empty=empty+1 end
return count,last,state==input,control,first,a,second,b,ending,missing,empty,nil
]]
return {
 run=function(check)
  local s,m=create(source); finish(s,10)
  local expected=table.pack(assert(load(source,'=ipairs-reference','t',{ipairs=ipairs,select=select}))())
  check('native ipairs generic-for and direct calls retain reference arity',m.status=='return' and m.result.n==expected.n)
  for i=1,expected.n do check('native ipairs reference value '..i,m.result[i]==expected[i]) end
  s,m=create([[
local input={false,7}
setmetatable(input,{__index=function() error('ipairs must be raw') end})
local count=0
for index,value in ipairs(input) do count=count+1 end
local f,t,k=ipairs(input)
local ok=pcall(function() f(t,0/0) end)
return count,ok,type(f),select('#',ipairs(input)),f==ipairs(input)
]])
  finish(s,50)
  check('native ipairs is raw preserves iterator identity and rejects invalid control',m.status=='return'
   and m.result[1]==2 and m.result[2]==false and m.result[3]=='function' and m.result[4]==3 and m.result[5]==true)
  s,m=create('return 1'); Scheduler.begin_tick(s,100)
  local services=Helpers.services(function(d,amount) return Scheduler.consume(s,1,d,amount) end)
  local input=Execution.table_value(m); Execution.set(m,input,1,false)
  local _,triple=services.ipairs(m,table.pack(input))
  check('native ipairs returns plain rooted service table and numeric control',triple.n==3 and triple[1]==m.ipairs_iterator
   and triple[2]==input and triple[3]==0 and Execution.type(m,triple[1])=='function'
   and s.budget.used.continuation==16)
  assert(Scheduler.consume(s,1,'table',Limits.table_work_per_computer))
  check('native iterator refuses read without changing input or shared table counter',not pcall(services['native.ipairs.step'],m,
   table.pack(input,0)) and Execution.get(m,input,1)==false and s.budget.used.table==Limits.table_work_per_computer)
  Scheduler.begin_tick(s,101)
  local _,value=services['native.ipairs.step'](m,table.pack(input,0))
  check('native iterator retained state can retry on a later tick',value.n==2 and value[1]==1 and value[2]==false
   and s.budget.used.table==8)
  Scheduler.begin_tick(s,102); assert(Scheduler.consume(s,1,'continuation',Limits.continuation_work_per_computer))
  local objects=m.objects
  check('native ipairs triple refusal allocates no new iterator or state',not pcall(services.ipairs,m,table.pack(input))
   and m.objects==objects and s.budget.used.continuation==Limits.continuation_work_per_computer)
  s,m=create([[
local iterate,state,control=ipairs({false})
local protect=pcall
coroutine.yield()
local ok=protect(iterate,state,control)
return ok
]])
  finish(s,199); assert(m.status=='yield')
  Scheduler.begin_tick(s,200); assert(Scheduler.consume(s,1,'table',Limits.table_work_per_computer))
  assert(Events.admit(m,table.pack('char','continue'))); Scheduler.tick(s,200)
  check('native iterator quota refusal reaches its protected guest receiver',m.status=='return' and m.result[1]==false)
  s,m=create('local count=0; for i,v in ipairs(input) do count=count+1 end; return count')
  input=Execution.table_value(m)
  for i=1,Limits.table_keys do Execution.set(m,input,i,false) end
  Execution.set(m,m.env,'input',input); finish(s,300)
  check('native maximum ipairs traversal is metered without widening table or execution limits',m.status=='return'
   and m.result[1]==Limits.table_keys and m.blocks>Limits.instructions_per_tick)
  s,m=create([[
local input={'first','old','tail'}
local f,t,k=ipairs(input)
local i,a=f(t,k)
input[2]='new'
local j,b=f(t,i)
input[3]=nil
return i,a,j,b,f(t,j)
]])
  finish(s,600)
  check('native ipairs reads current slots rather than replaying a snapshotted sequence',m.status=='return'
   and m.result.n==5 and m.result[1]==1 and m.result[2]=='first' and m.result[3]==2
   and m.result[4]=='new' and m.result[5]==nil)
 end,
 suspend=function(check)
  local s,m=create([[
boot=(boot or 0)+1
local source={false,{name='held'},7}
local saved=ipairs
local iterate,state,control=ipairs(source)
ipairs=nil
local count=0
for index,value in saved(source) do
 count=count+1
 if index==1 then coroutine.yield() end
end
local index,value=iterate(state,1)
local new_iterator,new_state,new_control=saved(source)
return count,index,value==source[2],value.name,new_iterator==iterate,new_state==source,new_control,boot,nil
]])
  finish(s,game.tick); assert(m.status=='yield')
  assert(Scheduler.consume(s,1,'table',Limits.table_work_per_computer-(s.budget.used.table or 0)))
  Collector.start(m)
  check('native ipairs snapshot retains generic-for control and exhausted table credits',m.collector~=nil)
  local factory,only=create('local saved=ipairs; ipairs=nil; coroutine.yield(); return saved({false})')
  finish(factory,game.tick); assert(only.status=='yield')
  Collector.start(only)
  check('native saved ipairs factory snapshot has no previously returned iterator',only.collector~=nil)
  return {scheduler=s,tick=game.tick,blocks=m.blocks,iterator=m.ipairs_iterator,factory=factory,factory_iterator=only.ipairs_iterator}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native ipairs load retains rooted iterator despite removed global',m.blocks==state.blocks
   and m.ipairs_iterator==state.iterator and Execution.get(m,m.env,'ipairs')==nil
   and s.budget.used.table==Limits.table_work_per_computer and m.collector~=nil)
  assert(Events.admit(m,table.pack('char','continue')))
  for i=1,200 do
   Scheduler.tick(s,state.tick+i)
   if m.status=='return' or m.status=='error' then break end
  end
  check('native suspended generic-for resumes once after collected separate-process reload',m.status=='return'
   and m.result.n==9 and m.result[1]==3 and m.result[2]==2 and m.result[3]==true and m.result[4]=='held'
   and m.result[5]==true and m.result[6]==true and m.result[7]==0 and m.result[8]==1 and m.result[9]==nil)
  s,m=state.factory,state.factory.machines[1]
  assert(Events.admit(m,table.pack('char','continue')))
  for i=1,200 do
   Scheduler.tick(s,state.tick+i)
   if m.status=='return' or m.status=='error' then break end
  end
  check('native implicit ipairs root survives collection before first iterator materialization',m.status=='return'
   and m.result.n==3 and m.result[1]==state.factory_iterator and m.result[1]==m.ipairs_iterator
   and Execution.get(m,m.result[2],1)==false and m.result[3]==0)
 end,
}
