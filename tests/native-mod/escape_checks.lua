local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Events=require('__computer_core_2__.scripts.native.events')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local function create(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-escape')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick,terminal)
 local m=s.machines[1]
 for i=0,500 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or (m.status=='yield' and not terminal) then return m end
 end
 error('native escaped fixture deadline exceeded')
end
return {
 run=function(check)
  local cases={
   {'(ab)',"string.rep('%1',32768)",string.rep('%1',32768),'ab'},
   {'a',"string.rep('%0',32768)",string.rep('%0',32768),'a'},
   {'a',"string.rep('%%',32767)..'x%'",string.rep('%%',32767)..'x%','a'},
   {'a',"string.rep('%q',32768)",string.rep('%q',32768),'a'},
   {'(abc)',"string.rep('%1',32768)",string.rep('%1',32768),'abc'},
  }
  for i,c in ipairs(cases) do
   local s,m=create("local replacement="..c[2].."; local protect,substitute=pcall,string.gsub; coroutine.yield(); local target='saved'; local ok,why=protect(function() target=substitute('"..c[4].."','"..c[1].."',replacement) end); return ok,target,why")
   finish(s,100); assert(m.status=='yield')
   assert(Events.admit(m,table.pack('char','continue'))); finish(s,110,true)
   local ok,expected=pcall(string.gsub,c[4],c[1],c[3])
   -- The engine accepts the last oversized output, but our documented byte cap
   -- deliberately refuses it before publication.
   if i==5 then ok=false end
   check('native grouped escape matches engine or documented output refusal '..i,m.status=='return' and m.result[1]==ok
    and m.result[2]==(ok and expected or 'saved'))
   if i==5 then check('native grouped escape overflow reports expansion limit before native repetition',
    m.result[3]:find('replacement result byte limit exceeded',1,true)~=nil) end
  end
 end,
 suspend=function(check)
  local s,m=create([[
boot=(boot or 0)+1
string.match('warm','%a+')
local replacement='%%'..string.rep('x',65534)
local substitute=string.gsub
string=nil
coroutine.yield('escape-ready')
return substitute('a','a',replacement),boot,nil
]])
  finish(s,game.tick); assert(m.status=='yield')
  Scheduler.begin_tick(s,s.budget.tick+1)
  -- This is a labelled single-step persistence fixture, not production timing:
  -- bundles already passed scheduler activation during warm-up, and only their
  -- trusted executable registrations are reused to stop at an exact API probe.
  Execution.resume(m,table.pack('char','continue'))
  local executables={}
  executables[m.bundle]=Execution.executable(m.bundle)
  for _,bundle in pairs(m.bundles) do executables[bundle]=Execution.executable(bundle) end
  local services=Helpers.services(function(d,n) return Scheduler.consume(s,1,d,n) end)
  local find=services['string.find']
  local stopped=false
  services['string.find']=function(machine,args)
   local status,result=find(machine,args)
   if args[4] and args[2]=='%' and #args[1]==256 then stopped=true end
   return status,result
  end
  for i=1,Limits.instructions_per_computer do
   local _,spent=Execution.run(m,m.bundle,executables[m.bundle],1,services,function(b) return executables[b] end)
   assert(Scheduler.consume(s,1,'execution',spent))
   if stopped then break end
  end
  assert(stopped and m.status=='running')
  assert(Scheduler.consume(s,1,'string',Scheduler.remaining(s,1,'string')))
  assert(Scheduler.consume(s,1,'execution',Scheduler.remaining(s,1,'execution')))
  Collector.start(m)
  check('native escaped save retains bounded probe expanded cursor and captured primitives after global removal',
   m.collector~=nil and Execution.get(m,m.env,'string')==nil)
  return {scheduler=s,tick=s.budget.tick,blocks=m.blocks}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native cold escaped load retains spent byte execution credits without initializer replay',m.blocks==state.blocks
   and Scheduler.remaining(s,1,'string')==0 and Scheduler.remaining(s,1,'execution')==0)
  finish(s,state.tick+1,true)
  check('native collected escaped expansion resumes original source cursor and exact trailing nil output',m.status=='return'
   and m.result.n==3 and m.result[1]=='%'..string.rep('x',65534) and m.result[2]==1 and m.result[3]==nil)
 end,
}
