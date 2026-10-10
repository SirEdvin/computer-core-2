local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Dispatch = require('__computer_core_2__.scripts.native.dispatch')
local Events = require('__computer_core_2__.scripts.native.events')
local Collector = require('__computer_core_2__.scripts.native.collector')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local function machine(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-event-fixture')))
 Execution.install_core(m); Events.install_services(m)
 return m
end
local function run(m,credits)
 return Dispatch.run(m,credits or 1000,function() return true end,Events.services())
end
local function collect(m)
 Collector.start(m)
 local turns=0
 while m.collector do Collector.step(m,17); turns=turns+1; assert(turns<10000) end
end
return {
 run=function(check)
  local m=machine('return nil')
  Events.advance(m,100)
  local a=Events.start_timer(m,0)
  local b=Events.start_timer(m,1/60)
  local c=Events.start_timer(m,0)
  check('native zero timers do not fire inline',#m.events.queue==0 and m.events.timers[a]==101)
  Events.cancel_timer(m,c)
  Events.advance(m,101)
  check('native timers use deadline then identity order',#m.events.queue==2 and m.events.queue[1].tuple[2]==a
   and m.events.queue[2].tuple[2]==b and m.events.timer_count==0)
  Events.cancel_timer(m,a)
  check('native cancellation removes queued undelivered timer',#m.events.queue==1 and m.events.queue[1].tuple[2]==b)
  local next_id=m.events.next_timer
  local ok=pcall(Events.start_timer,m,0,function() error('fixture credit refusal',0) end)
  check('native refused timer does not retain identity or deadline',not ok and m.events.next_timer==next_id and m.events.timer_count==0)
  local bytes,count=m.events.bytes,#m.events.queue
  ok=Events.admit(m,table.pack('unsafe',function() end))
  check('native event boundary rejects host functions without publication',not ok and m.events.bytes==bytes and #m.events.queue==count)
  ok=Events.admit(m,table.pack('unsafe',0/0))
  check('native event boundary rejects nonfinite numbers',not ok and #m.events.queue==count)
  for i=count+1,Limits.events do assert(Events.admit(m,table.pack('char','x'))) end
  ok=Events.admit(m,table.pack('extra'))
  check('native queue retains existing event cap',not ok and #m.events.queue==Limits.events)
  assert(Events.admit(m,table.pack('terminate'),true))
  check('native priority ingress survives full ordinary queue',#m.events.queue==Limits.events and m.events.queue[1].tuple[1]=='terminate')
  m=machine('local t={code=7}; local f=function() return t end; return f,t')
  assert(run(m)=='return')
  local f,t=m.result[1],m.result[2]
  assert(Events.admit(m,table.pack('objects',f,nil,t)))
  m.result=nil
  collect(m)
  check('native queued closure and aliased table survive collection',Execution.type(m,f)=='function'
   and Execution.get(m,t,'code')==7 and m.events.queue[1].tuple.n==4
   and m.events.queue[1].tuple[2].native_ref==f.native_ref and m.events.queue[1].tuple[4].native_ref==t.native_ref)
  m=machine('local co=coroutine.create(function() coroutine.yield("private",nil); return 7 end); local ok,v=coroutine.resume(co); return ok,v,coroutine.resume(co)')
  assert(Events.admit(m,table.pack('char','q')))
  check('native nested yield returns to parent instead of taking host input',run(m)=='return' and m.result.n==4
   and m.result[1]==true and m.result[2]=='private' and m.result[3]==true and m.result[4]==7 and #m.events.queue==1)
  m=machine('local id=os.startTimer(0); os.cancelTimer(id); os.queueEvent("custom",nil,7,nil); return id')
  check('native symbolic event services execute without VM objects',run(m)=='return' and m.result[1]==1 and m.events.timer_count==0
   and m.events.queue[1].tuple.n==4 and m.events.queue[1].tuple[1]=='custom' and m.events.queue[1].tuple[3]==7)
 end,
 suspend=function(check)
  local m=machine([[
effects=(effects or 0)+1
local tag,obj,hole,last=coroutine.yield()
local key,number,trailing=coroutine.yield()
local char,payload=coroutine.yield()
local timer,id=coroutine.yield()
return tag,obj,hole,last,key,number,trailing,char,payload,timer,id,effects
]])
  assert(run(m)=='yield')
  local obj=Execution.table_value(m)
  Execution.set(m,obj,'code',7)
  assert(Events.admit(m,table.pack('first',obj,nil,'tail')))
  assert(Events.admit(m,table.pack('key',9,nil)))
  Events.advance(m,100)
  local id=Events.start_timer(m,0)
  local bytes=m.events.bytes
  local delivered,spent=Events.deliver(m,0)
  check('native zero event credits preserve root wait and queue',not delivered and spent==0 and m.status=='yield'
   and m.events.bytes==bytes and #m.events.queue==2)
  Collector.start(m)
  local turns=0
  while true do
   Collector.step(m,1); turns=turns+1
   local found=false
   for _,job in ipairs(m.collector and m.collector.jobs or {}) do if job.value==m.events.queue then found=true end end
   if found then break end
   assert(m.collector and turns<10000,'collector failed to reach native queue snapshot')
  end
  Events.advance(m,101)
  delivered,spent=Events.deliver(m,1)
  check('native collection defers event delivery and due timer publication',not delivered and spent==0 and m.events.tick==101
   and m.events.timers[id]==101 and #m.events.queue==2)
  local old=m.events.queue
  local ok=Events.admit(m,table.pack('char','later'))
  check('native scalar input during collection preserves frozen queue snapshot',ok and #old==2 and #m.events.queue==3
   and old~=m.events.queue and old[1]==m.events.queue[1] and m.events.queue[3].tuple[1]=='char')
  ok=Events.admit(m,table.pack('objects',obj))
  check('native collection refuses new heap edges without dropping scalar input',not ok and #m.events.queue==3)
  return {machine=m,object=obj,timer=id,blocks=m.blocks,work=m.activation_work,bytes=m.events.bytes}
 end,
 reload=function(state,check)
  local m=state.machine
  check('native load preserves root wait timers queues and earlier work',m.status=='yield' and m.collector and m.blocks==state.blocks
   and m.activation_work==state.work and m.events.tick==101 and m.events.bytes==state.bytes and m.events.timer_count==1)
  while m.collector do Collector.step(m,13) end
  Events.advance(m,101)
  check('native overdue saved timer publishes once after collection',m.events.timer_count==0 and #m.events.queue==4
   and m.events.queue[4].tuple[1]=='timer' and m.events.queue[4].tuple[2]==state.timer)
  assert(Events.deliver(m,1))
  check('native root delivery resumes existing continuation with nil tuple',m.status=='running' and #m.events.queue==3)
  local delivered,spent=Events.deliver(m,1)
  check('native in-flight execution cannot consume another queued event',not delivered and spent==0 and #m.events.queue==3)
  assert(run(m)=='yield')
  assert(Events.deliver(m,1))
  assert(run(m)=='yield')
  -- Deliver collection-time input through the actual retained guest receiver.
  check('native collection-time scalar input remains ahead of later timer',m.events.queue[1].tuple[1]=='char')
  assert(Events.deliver(m,1))
  assert(run(m)=='yield')
  assert(Events.deliver(m,1))
  check('native ordered root waits preserve identities arity and single effects',run(m)=='return' and m.result.n==12
   and m.result[1]=='first' and m.result[2].native_ref==state.object.native_ref and m.result[3]==nil and m.result[4]=='tail'
   and m.result[5]=='key' and m.result[6]==9 and m.result[7]==nil and m.result[8]=='char' and m.result[9]=='later'
   and m.result[10]=='timer' and m.result[11]==state.timer and m.result[12]==1
   and m.delivered_events==4 and #m.events.queue==0 and m.events.bytes==0)
 end,
}
