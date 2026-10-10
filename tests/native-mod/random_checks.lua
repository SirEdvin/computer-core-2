local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Helpers = require('__computer_core_2__.scripts.native.helpers')
local Scheduler = require('__computer_core_2__.scripts.native.scheduler')
local Events = require('__computer_core_2__.scripts.native.events')
local Collector = require('__computer_core_2__.scripts.native.collector')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local function create(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-random')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 local s=Scheduler.new(); Scheduler.add(s,1,m)
 return s,m
end
local states={16807,282475249,1622650073,984943658,1144108930,470211272,101027544,1457850878}
return {
 run=function(check)
  local s,m=create('return 1'); Scheduler.begin_tick(s,100)
  local services=Helpers.services(function(domain,amount) return Scheduler.consume(s,1,domain,amount) end)
  local neighbor=select(2,create('return 1'))
  services['math.randomseed'](m,table.pack(1))
  for i,expected in ipairs(states) do
   local _,value=services['math.random'](m,{n=0})
   check('native private random vector '..i,m.random_state.version==1 and m.random_state.seed==expected
    and value.n==1 and value[1]==(expected-1)/2147483646 and value[1]>=0 and value[1]<1)
  end
  check('native random state is isolated from another machine',neighbor.random_state==nil)
  local _,default=services['math.random'](neighbor,{n=0})
  check('native legacy missing random state initializes only at admitted draw',neighbor.random_state.seed==states[1]
   and default[1]==(states[1]-1)/2147483646 and m.random_state.seed==states[8])
  local snapshot=m.random_state
  for _,args in ipairs({table.pack(0),table.pack(3,2),table.pack(-2147483646,2147483646),
   table.pack(math.huge),table.pack(0/0),table.pack(1,2,3)}) do
   check('native invalid random range retains generator',not pcall(services['math.random'],m,args) and m.random_state==snapshot)
  end
  check('native nil random interval is explicit and leaves stream unchanged',not pcall(services['math.random'],m,table.pack(nil))
   and m.random_state==snapshot)
  for _,args in ipairs({table.pack(math.huge),table.pack(0/0),table.pack(1.5),{n=0}}) do
   check('native invalid random seed retains generator',not pcall(services['math.randomseed'],m,args) and m.random_state==snapshot)
  end
  assert(Scheduler.consume(s,1,'continuation',Limits.continuation_work_per_computer-s.budget.used.continuation))
  check('native refused random draw cannot advance seed or budget',not pcall(services['math.random'],m,{n=0})
   and m.random_state==snapshot and s.budget.used.continuation==Limits.continuation_work_per_computer)
  check('native refused reseed cannot replace generator',not pcall(services['math.randomseed'],m,table.pack(42)) and m.random_state==snapshot)
  Scheduler.begin_tick(s,101)
  services['math.randomseed'](m,table.pack(0))
  check('native zero seed normalizes to valid deterministic state',m.random_state.seed==1)
  services['math.randomseed'](m,table.pack(-1))
  check('native negative seed normalizes within private state range',m.random_state.seed==2147483646)
  m.random_state={version=99,seed=1}; snapshot=m.random_state
  check('native incompatible generator is retained not silently reset',not pcall(services['math.random'],m,{n=0}) and m.random_state==snapshot)
  s,m=create([[math.randomseed(1); return math.random(),math.random(),math.random(33,126),math.random(-3,3),nil]])
  Scheduler.tick(s,200)
  check('native compiled random calls use private stream and nil arity',m.status=='return' and m.result.n==5
   and m.result[1]==(states[1]-1)/2147483646 and m.result[2]==(states[2]-1)/2147483646
   and m.result[3]==104 and m.result[4]==0 and m.result[5]==nil)
 end,
 suspend=function(check)
  local s,m=create([[
boot=(boot or 0)+1
math.randomseed(1)
local first=math.random()
coroutine.yield()
return first,math.random(),math.random(33,126),math.random(-3,3),boot,nil
]])
  Scheduler.tick(s,game.tick)
  assert(m.status=='yield' and m.random_state.seed==states[1])
  assert(Scheduler.consume(s,1,'continuation',Limits.continuation_work_per_computer-s.budget.used.continuation))
  Collector.start(m)
  check('native random snapshot retains admitted first draw and exhausted credits',m.random_state.seed==states[1]
   and s.budget.used.continuation==Limits.continuation_work_per_computer)
  return {scheduler=s,tick=game.tick,random_state=m.random_state}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native random load retains stream identity and spent credits',m.random_state==state.random_state
   and m.random_state.seed==states[1] and s.budget.used.continuation==Limits.continuation_work_per_computer)
  assert(Events.admit(m,table.pack('key',1)))
  Scheduler.tick(s,state.tick)
  check('native same-tick reload cannot deliver wait or draw through exhausted movement',m.random_state==state.random_state
   and m.random_state.seed==states[1] and m.status=='yield' and #m.events.queue==1)
  for i=1,200 do
   Scheduler.tick(s,state.tick+i)
   if m.status=='return' or m.status=='error' then break end
  end
  check('native random resumes exact later draws without reseeding or initialization replay',m.status=='return' and m.result.n==6
   and m.result[1]==(states[1]-1)/2147483646 and m.result[2]==(states[2]-1)/2147483646
   and m.result[3]==104 and m.result[4]==0 and m.result[5]==1 and m.result[6]==nil and m.random_state.seed==states[4])
 end,
}
