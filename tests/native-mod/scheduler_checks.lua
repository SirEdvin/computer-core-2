local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Events = require('__computer_core_2__.scripts.native.events')
local Collector = require('__computer_core_2__.scripts.native.collector')
local Scheduler = require('__computer_core_2__.scripts.native.scheduler')
local Dispatch = require('__computer_core_2__.scripts.native.dispatch')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local function machine(source)
 local m=Execution.new(assert(Compiler.compile(source,'=scheduled-native')))
 Execution.install_core(m); Events.install_services(m)
 return m
end
local function loops()
 local s=Scheduler.new()
 Scheduler.add(s,1,machine('local n=0; while true do n=n+1; visits=n end'))
 Scheduler.add(s,2,machine('local n=0; while true do n=n+1; visits=n end'))
 return s
end
return {
 run=function(check)
  local s=loops()
  local used,visited=Scheduler.tick(s,100)
  check('native scheduler uses unchanged aggregate execution cap',used==Limits.instructions_per_tick and visited==1
   and s.machines[1].status=='running' and s.machines[1].yielded==nil and s.machines[1].result==nil)
  local blocks=s.machines[1].blocks+s.machines[2].blocks
  local work=s.budget.used.compiler
  Dispatch.clear_cache()
  local loads=Dispatch.cache_stats().loads
  used,visited=Scheduler.tick(s,100)
  check('native repeated same tick does not renew execution or activation',used==0 and visited==0
   and s.machines[1].blocks+s.machines[2].blocks==blocks and s.budget.used.compiler==work and Dispatch.cache_stats().loads==loads)
  used=Scheduler.tick(s,101)
  check('native hostile loop cannot starve next round-robin neighbor',used==Limits.instructions_per_tick
   and Execution.get(s.machines[2],s.machines[2].env,'visits')>0 and s.machines[1].status=='running')
  check('native backwards tick fails without renewing spent budget',not pcall(Scheduler.tick,s,100) and s.budget.tick==101)
  local id,amount=1,Limits.event_work_per_computer
  check('native service ledger admits exact per-machine allowance',Scheduler.consume(s,id,'event',amount))
  local before=s.budget.used.event
  check('native per-machine refusal is atomic for both counters',not Scheduler.consume(s,id,'event',1)
   and s.budget.used.event==before and s.budget.machines[id].event==amount)
  assert(Scheduler.consume(s,2,'event',amount))
  Scheduler.add(s,3,machine('return 3'))
  check('native aggregate service refusal is atomic for a fresh neighbor',not Scheduler.consume(s,3,'event',1)
   and s.budget.used.event==Limits.event_work_per_tick and s.budget.machines[3]==nil)
  check('native malformed charges cannot poison ledger',not pcall(Scheduler.consume,s,1,'event',0/0)
   and not pcall(Scheduler.consume,s,1,'event',math.huge) and s.budget.used.event==Limits.event_work_per_tick)
  local old=s.budget.machines[1].event
  Scheduler.remove(s,1); Scheduler.add(s,1,machine('return 1'))
  check('native remove and readmit same identity cannot renew tick credits',s.budget.machines[1].event==old and not Scheduler.consume(s,1,'event',1))
  -- Host timer maintenance can defer independently of executable progress.
  s=Scheduler.new(); local m=machine('return 42'); Scheduler.add(s,1,m)
  Scheduler.begin_tick(s,200)
  assert(Scheduler.consume(s,1,'advance',Limits.advance_work_per_computer))
  used=Scheduler.tick(s,200)
  check('native deferred maintenance preserves clock and services selected guest',m.events.tick==200 and m.status=='return'
   and m.result[1]==42 and used>0 and s.budget.used.advance==Limits.advance_work_per_computer)
  s=Scheduler.new(); m=machine('return coroutine.yield()'); Scheduler.add(s,1,m)
  Scheduler.tick(s,300)
  assert(m.status=='yield' and Events.admit(m,table.pack('char','x',nil)))
  assert(Scheduler.consume(s,1,'event',Limits.event_work_per_computer))
  local queue,pc=m.events.queue,m.frames[1].pc
  Scheduler.tick(s,300)
  check('native wait admission refusal is invisible and preserves queued receiver',m.status=='yield' and m.events.queue==queue
   and #queue==1 and m.frames[1].pc==pc and m.error==nil and m.delivered_events==nil)
  Scheduler.tick(s,301)
  check('native later tick delivers original tail wait with nil arity',m.status=='return' and m.result.n==3
   and m.result[1]=='char' and m.result[2]=='x' and m.result[3]==nil and m.delivered_events==1)
  s=Scheduler.new(); m=machine('return coroutine.yield()'); Scheduler.add(s,1,m)
  Scheduler.tick(s,350)
  assert(Events.admit(m,table.pack('copy',nil,7,nil)))
  assert(Scheduler.consume(s,1,'continuation',Limits.continuation_work_per_computer))
  local event_before=s.budget.used.event
  Scheduler.tick(s,350)
  check('native weighted saved-wait copy refusal precedes queue mutation',m.status=='yield' and #m.events.queue==1
   and m.delivered_events==nil and m.error==nil and s.budget.used.event==event_before)
  Scheduler.tick(s,351)
  check('native saved-wait movement charges bounded arity on later tick',m.status=='return' and m.result.n==4
   and m.result[1]=='copy' and m.result[2]==nil and m.result[3]==7 and m.result[4]==nil
   and s.budget.used.continuation==17)
  s=Scheduler.new(); m=machine('return 1'); Scheduler.add(s,1,m)
  Scheduler.begin_tick(s,400)
  assert(Scheduler.consume(s,1,'execution',Limits.instructions_per_computer))
  local frames,blocks=m.frames,m.blocks
  Scheduler.tick(s,400)
  check('native zero execution budget leaves guest state and executable cache untouched',m.frames==frames and m.blocks==blocks
   and m.activation_work==nil and m.status=='running')
  s=Scheduler.new(); m=machine('return 1'); m.version=-1; Scheduler.add(s,1,m)
  local neighbor=machine('return 42'); Scheduler.add(s,2,neighbor)
  Scheduler.tick(s,500)
  check('native incompatible scheduled machine recovers without blocking neighbor',m.status=='recovery' and m.blocks==0
   and neighbor.status=='return' and neighbor.result[1]==42)
 end,
 start_pressure=function()
  local s=loops()
  return {scheduler=s,last={0,0},ticks=0,served={0,0}}
 end,
 pressure_tick=function(state,check)
  local s=state.scheduler
  local used=Scheduler.tick(s,game.tick)
  assert(used<=Limits.instructions_per_tick)
  assert(s.budget.used.execution<=Limits.instructions_per_tick and s.budget.used.collection<=Limits.collection_work_per_tick)
  state.ticks=state.ticks+1
  for id=1,2 do
   local m=s.machines[id]
   if m.blocks>state.last[id] then state.served[id]=state.served[id]+1 end
   state.last[id]=m.blocks
   assert(m.status=='running' and m.yielded==nil and m.result==nil)
  end
  local before=state.last[1]+state.last[2]
  assert(Scheduler.tick(s,game.tick)==0)
  assert(s.machines[1].blocks+s.machines[2].blocks==before)
  if state.ticks<8 then return false end
  check('native real-tick hostile neighbors receive bounded alternating service',state.served[1]>=3 and state.served[2]>=3)
  return true
 end,
 suspend=function(check)
  local s=Scheduler.new()
  local m=machine([[
boot=(boot or 0)+1
local name,value,hole=coroutine.yield()
first=(first or 0)+1
local n=0
for i=1,1000 do n=n+1 end
local next_name,next_value=coroutine.yield()
return name,value,hole,n,next_name,next_value,boot,first,nil
]])
  Scheduler.add(s,1,m)
  assert(Scheduler.tick(s,game.tick)>0 and m.status=='yield')
  assert(Events.admit(m,table.pack('first',7,nil)))
  assert(Events.admit(m,table.pack('second',9)))
  -- Use the remaining real-tick allowance; the long first event spans ticks.
  Scheduler.tick(s,game.tick)
  check('native mid-event preemption is invisible and keeps later event queued',m.status=='running' and m.yielded==nil and m.result==nil
   and #m.events.queue==1 and m.events.queue[1].tuple[1]=='second' and m.delivered_events==1)
  check('native mid-event exhausts actual retained tick execution credits',s.budget.used.execution==Limits.instructions_per_tick)
  local work=s.budget.used.compiler
  local blocks=m.blocks
  assert(Scheduler.tick(s,game.tick)==0)
  check('native same-tick reentry leaves in-flight receiver and work unchanged',m.blocks==blocks and s.budget.used.compiler==work)
  local frozen=Scheduler.new(); local paused=machine('while true do end'); Scheduler.add(frozen,1,paused)
  Collector.start(paused); Scheduler.begin_tick(frozen,game.tick)
  -- Direct reservations isolate collection/event exhaustion from execution
  -- preemption; these are not claims of real workload/latency measurement.
  assert(Scheduler.consume(frozen,1,'collection',Limits.collection_work_per_computer))
  local waiting=Scheduler.new(); local waiter=machine('return coroutine.yield()'); Scheduler.add(waiting,1,waiter)
  Scheduler.tick(waiting,game.tick)
  assert(waiter.status=='yield' and Events.admit(waiter,table.pack('retained',nil,9,nil)))
  assert(Scheduler.consume(waiting,1,'event',Limits.event_work_per_computer))
  assert(Scheduler.consume(waiting,1,'continuation',Limits.continuation_work_per_computer))
  return {scheduler=s,tick=game.tick,blocks=blocks,compiler=work,queue=m.events.queue,
   frozen=frozen,gc=paused.collector,phase=paused.collector.phase,cursor=paused.collector.cursor,
   waiting=waiting,wait_queue=waiter.events.queue}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  local loads=Dispatch.cache_stats().loads
  check('native on-load preserves real-tick exhausted ledger and queue alias',s.budget.tick==state.tick
   and s.budget.used.execution==Limits.instructions_per_tick and m.blocks==state.blocks and m.events.queue==state.queue)
  local used,visited=Scheduler.tick(s,state.tick)
  check('native same-tick cold reload cannot restore any execution credit',used==0 and visited==0 and m.blocks==state.blocks
   and s.budget.used.compiler==state.compiler and Dispatch.cache_stats().loads==loads)
  local turns=0
  repeat
   used=Scheduler.tick(s,state.tick+turns+1)
   assert(used<=Limits.instructions_per_tick)
   turns=turns+1
   assert(turns<100,'native scheduled event failed to complete')
  until m.status=='return' or m.status=='error'
  check('native later-tick continuation completes both ordered events exactly once',m.status=='return' and m.result.n==9
   and m.result[1]=='first' and m.result[2]==7 and m.result[3]==nil and m.result[4]==1000
   and m.result[5]=='second' and m.result[6]==9 and m.result[7]==1 and m.result[8]==1 and m.result[9]==nil
   and m.delivered_events==2 and #m.events.queue==0)
  -- Collection has its own retained quantum and does not activate guest code.
  s=state.frozen; m=s.machines[1]
  Scheduler.tick(s,state.tick)
  check('native saved exhausted collection quantum retains cursor without activation',m.collector==state.gc
   and state.gc.phase==state.phase and state.gc.cursor==state.cursor
   and m.activation_work==nil and s.budget.used.collection==Limits.collection_work_per_computer)
  s=state.waiting; m=s.machines[1]
  Scheduler.tick(s,state.tick)
  check('native saved exhausted event ledger preserves wait queue without error',m.status=='yield' and m.events.queue==state.wait_queue
   and #m.events.queue==1 and m.error==nil and m.delivered_events==nil and s.budget.used.event==Limits.event_work_per_computer)
  check('native reload retains exhausted saved-wait movement credits',s.budget.used.continuation==Limits.continuation_work_per_computer)
  Scheduler.tick(s,state.tick+1)
  check('native restored wait delivers retained tuple only with later-tick credits',m.status=='return' and m.result.n==4
   and m.result[1]=='retained' and m.result[2]==nil and m.result[3]==9 and m.result[4]==nil and m.delivered_events==1)
 end,
}
