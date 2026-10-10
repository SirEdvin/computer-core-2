local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Events=require('__computer_core_2__.scripts.native.events')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local function create(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-key-test')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick,terminal)
 local m=s.machines[1]
 for i=0,200 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or (m.status=='yield' and not terminal) then return m end
 end
 error('native key fixture deadline exceeded')
end
local refused=[[
local value={saved=9}
local calls=0
local delegated=setmetatable({},{__index=function() calls=calls+1; return 7 end,
 __newindex=function() calls=calls+1 end})
local protect=pcall
local key='saved'
coroutine.yield('key-ready',value,delegated)
local a=protect(function() value[key]=99 end)
local b=protect(function() return value[key] end)
local c=protect(function() return delegated[key] end)
local d=protect(function() delegated[key]=1 end)
return a,b,c,d,calls
]]
return {
 run=function(check)
  local s,m=create([[
local key=string.rep('k',65536)
local value={}
coroutine.yield('maximum-key',value,key)
value[key]=false
return value[key]
]])
  finish(s,10); assert(m.status=='yield')
  local value,key=m.yielded[2],m.yielded[3]
  assert(Events.admit(m,table.pack('char','continue')))
  finish(s,30,true)
  check('native maximum ordinary string-key write read pays all encoded copies',m.status=='return' and m.result[1]==false
   and Execution.get(m,value,key)==false and m.heap[value.native_ref].keys==1
   and s.budget.used.string==3*(1+Limits.string_bytes) and s.budget.used.table==24)
  s,m=create([[
local key=string.rep('k',65536)
coroutine.yield('constructor-ready')
local value={[key]=17}
return value[key]
]])
  finish(s,100); assert(m.status=='yield')
  assert(Events.admit(m,table.pack('char','continue'))); finish(s,110,true)
  check('native maximum keyed constructor pays initializer and subsequent read bytes',m.status=='return'
   and m.result[1]==17 and s.budget.used.string==2*(1+Limits.string_bytes) and s.budget.used.table==16)
  for i,domain in ipairs({'string','table'}) do
   s,m=create(refused); finish(s,200+i*10); assert(m.status=='yield')
   value=m.yielded[2]
   assert(Scheduler.consume(s,1,domain,Scheduler.remaining(s,1,domain)))
   assert(Events.admit(m,table.pack('char','continue'))); finish(s,s.budget.tick,true)
   check('native zero-credit '..domain..' ordinary access refuses before mutation or guest metamethod',m.status=='return'
    and m.result[1]==false and m.result[2]==false and m.result[3]==false and m.result[4]==false
    and m.result[5]==0 and Execution.get(m,value,'saved')==9
    and s.budget.used[domain]==Limits[domain..'_work_per_computer'])
  end
  s,m=create([[
local key=string.rep('k',65536)
local target={}
local front=setmetatable({},{__newindex=target})
local protect=pcall
coroutine.yield('delegated-ready',front,target,key)
return protect(function() front[key]=17 end)
]])
  finish(s,300); assert(m.status=='yield')
  local front,target=m.yielded[2],m.yielded[3]; key=m.yielded[4]
  assert(Events.admit(m,table.pack('char','continue'))); finish(s,310,true)
  check('native maximum delegated write bills each hop and refuses without partial publication',m.status=='return'
   and m.result[1]==false and Execution.get(m,front,key)==nil and Execution.get(m,target,key)==nil
   and m.heap[target.native_ref].keys==0 and s.budget.used.string==2*(1+Limits.string_bytes)+11)
  s,m=create([[
local counter={effects=0}
local callable=setmetatable({},{__call=function(self,a,b) counter.effects=counter.effects+1; return a,b,self end})
local protect=pcall
local invoke=function() return callable(4,nil) end
coroutine.yield('call-ready',callable,counter)
return protect(invoke)
]])
  finish(s,400); assert(m.status=='yield')
  local callable,counter=m.yielded[2],m.yielded[3]
  local pending,args
  assert(Events.admit(m,table.pack('char','continue')))
  Scheduler.tick(s,410,{['native.work']=function(domain,amount)
   local p=m.heap[m.active].pending
   if domain=='continuation' and amount==13 and p and p.kind=='call' and p.callee.native_ref==callable.native_ref then
    pending,args=p,p.args
    assert(Scheduler.consume(s,1,domain,Scheduler.remaining(s,1,domain)))
   end
   return Scheduler.consume(s,1,domain,amount)
  end})
  check('native callable prefix refusal preserves pending callee nil arguments and callback effects',m.status=='return'
   and m.result[1]==false and pending and pending.callee.native_ref==callable.native_ref and pending.args==args
   and args.n==2 and args[1]==4 and args[2]==nil and pending.depth==nil
   and Execution.get(m,counter,'effects')==0 and Scheduler.remaining(s,1,'continuation')==0)
 end,
 suspend=function(check)
  local s,m=create([[
boot=(boot or 0)+1
local key=string.rep('s',65536)
local target={}
local alias=target
local calls=0
setmetatable(target,{__newindex=function(self,k,v)
 calls=calls+1
 coroutine.yield('write-wait',self,k,v)
 rawset(self,k,v)
end})
target[key]=17
return alias[key],calls,boot,nil
]])
  finish(s,game.tick); assert(m.status=='yield')
  local value,key=m.yielded[2],m.yielded[3]
  assert(Scheduler.consume(s,1,'string',Scheduler.remaining(s,1,'string')))
  assert(Scheduler.consume(s,1,'table',Scheduler.remaining(s,1,'table')))
  Collector.start(m)
  check('native maximum-key setter snapshot retains aliased target input and refused-publication boundary',m.yielded.n==4
   and #key==Limits.string_bytes and m.yielded[4]==17 and Execution.get(m,value,key)==nil and m.collector~=nil)
  return {scheduler=s,tick=s.budget.tick,blocks=m.blocks,value=value,key=key}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native cold maximum-key setter load preserves aliases cursor and exhausted ledgers',m.blocks==state.blocks
   and m.yielded[2].native_ref==state.value.native_ref and m.yielded[3]==state.key
   and Scheduler.remaining(s,1,'table')==0 and Scheduler.remaining(s,1,'string')==0)
  assert(Events.admit(m,table.pack('char','continue')))
  finish(s,state.tick+1,true)
  check('native collected maximum-key metamethod resumes without replay and commits once',m.status=='return'
   and m.result.n==4 and m.result[1]==17 and m.result[2]==1 and m.result[3]==1 and m.result[4]==nil
   and Execution.get(m,state.value,state.key)==17 and m.heap[state.value.native_ref].keys==1)
 end,
}
