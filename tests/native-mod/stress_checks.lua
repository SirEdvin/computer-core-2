-- Real on_tick stress with one shared scheduler and an interactive neighbor.
local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Events=require('__computer_core_2__.scripts.native.events')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Filesystem=require('__computer_core_2__.scripts.native.filesystem')
local Terminal=require('__computer_core_2__.scripts.native.terminal')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local M={}
local source=[[
local chunk=assert(loadfile('/maximum-source.lua'))
assert(chunk()==17)
local refused,why=load(string.rep(' ',32769))
assert(refused==nil and type(why)=='string')
return 'source'
]]
local service=[[
local bytes=string.rep('x',65536)
coroutine.yield('maximum-ready')
local h=assert(io.open('/maximum.bin','w+'))
h:write(bytes); h:seek('set',0)
local got=h:read(65536); h:close()
coroutine.yield('maximum-written')
assert(got==bytes)
term.write(bytes); term.clear()
return 'service'
]]
local cleanup=[[
local e={marker='retained-error'}
local function f(n)
 if n==0 then coroutine.yield('cleanup-ready',e); error(e,0) end
 local value=f(n-1)
 return value
end
local ok,value=pcall(f,254)
assert(not ok and value==e)
return 'cleanup',value
]]
local neighbor=[[
local n=0
while true do
 local event,value=coroutine.yield()
 if event=='char' then n=n+1; echo=value; receipts=n end
end
]]
local phases={{name='source',source=source},{name='service',source=service},{name='cleanup',source=cleanup}}
local function machine(text,name)
 local m=Execution.new(assert(Compiler.compile(text,name)))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 Filesystem.install(m,{fs={['/']={type='dir'},['/maximum-source.lua']={type='file',
  text=string.rep(' ',Limits.source_bytes-9)..'return 17'}}})
 Terminal.install(m,160,60)
 return m
end
local function begin(state)
 local p=phases[state.phase]
 local s=Scheduler.new(); Scheduler.add(s,1,machine("coroutine.yield('stress-start')\n"..p.source,'=stress-'..p.name))
 Scheduler.add(s,2,machine(neighbor,'=stress-interactive-neighbor'))
 state.scheduler=s; state.started=game.tick; state.pending=nil; state.sent=0; state.acks=0; state.max_echo=0; state.depth=0
end
function M.start() return {phase=1,total_ticks=0} end
local domains={'execution','collection','compiler','event','advance','continuation','string','table','terminal','filesystem'}
function M.tick(state,check)
 if not state.scheduler then begin(state) end
 local s=state.scheduler; local m,n=s.machines[1],s.machines[2]
 state.total_ticks=state.total_ticks+1
 assert(state.total_ticks<150,'native stress structural deadline exceeded')
 if not state.pending and n.status=='yield' and not n.collector then
  state.sent=state.sent+1
  state.pending={value='echo-'..state.sent,tick=game.tick}
  assert(Events.admit(n,{n=2,'char',state.pending.value}))
 end
 if m.status=='yield' and not m.collector and #m.events.queue==0 then
  if m.yielded[1]=='cleanup-ready' then
   state.depth=math.max(state.depth,#m.frames)
   assert(m.yielded[1]=='cleanup-ready')
  end
  assert(Events.admit(m,{n=1,'resume-stress'}))
 end
 local profiler=game.create_profiler()
 local before=m.cleanup_work or 0
 local used,visited,collected=Scheduler.tick(s,game.tick)
 profiler.stop()
 -- Timings are diagnostic LocalisedStrings only, never storage or scheduling input.
 log({'','CC2 NATIVE STRESS PROFILE phase='..phases[state.phase].name..' tick='..game.tick..' ',profiler})
 assert(used<=Limits.instructions_per_tick and collected<=Limits.collection_work_per_tick and visited<=2)
 assert((m.cleanup_work or 0)-before<=Limits.cleanup_work_per_step*Limits.instructions_per_tick)
 for _,domain in ipairs(domains) do
  local cap=domain=='execution' and Limits.instructions_per_tick or domain=='collection' and Limits.collection_work_per_tick
   or Limits[domain..'_work_per_tick']
  assert((s.budget.used[domain] or 0)<=cap,'stress aggregate '..domain..' exceeded')
  local machine_cap=domain=='execution' and Limits.instructions_per_computer or domain=='collection' and Limits.collection_work_per_computer
   or Limits[domain..'_work_per_computer']
  for _,ledger in pairs(s.budget.machines) do
   assert((ledger[domain] or 0)<=machine_cap,'stress machine '..domain..' exceeded')
  end
 end
 if state.pending and Execution.get(n,n.env,'echo')==state.pending.value then
  state.acks=state.acks+1
  state.max_echo=math.max(state.max_echo,game.tick-state.pending.tick+1)
  state.pending=nil
 end
 if state.pending then assert(game.tick-state.pending.tick<4,'interactive stress neighbor starved') end
 assert(m.status~='error' and m.status~='recovery' and n.status~='error' and n.status~='recovery',
  'native stress failed: '..serpent.line(m.error or m.recovery))
 if m.status~='return' then return false end
 if state.pending then return false end
 local phase=phases[state.phase].name
 check('native real-tick '..phase..' maximum workload completes beside interactive neighbor under unchanged shared caps',
  m.result[1]==phase and state.acks>0 and state.max_echo<=2)
 if phase=='source' then
  local found=false
  for _,bundle in pairs(m.bundles) do if #bundle.source==Limits.source_bytes then found=true end end
  check('native real-tick stress compiles exact maximum source and refuses oversized source before effects',found)
 elseif phase=='service' then
  check('native real-tick stress preserves exact maximum IO bytes and bounded largest terminal grid',
   #m.disk.fs['/maximum.bin'].text==Limits.string_bytes and m.open_handles==0 and m.handle_bytes==0
   and m.display.columns==160 and m.display.rows==60 and m.display.lines[60].text==string.rep(' ',160))
 else
  check('native real-tick stress reaches maximum call frames and returns same protected error after bounded cleanup',
   state.depth==Limits.call_frames and Execution.get(m,m.result[2],'marker')=='retained-error' and (m.cleanup_work or 0)>0)
 end
 log('CC2 NATIVE STRESS RESULT '..serpent.line({phase=phase,ticks=game.tick-state.started+1,
  neighbor_acks=state.acks,max_echo_ticks=state.max_echo,blocks=m.blocks,cleanup=m.cleanup_work,
  collection=m.collection_work,activation=m.activation_work,depth=state.depth,budget=s.budget.used}))
 state.phase=state.phase+1; state.scheduler=nil
 return state.phase>#phases
end
function M.suspend(check)
 local m=machine(cleanup,'=stress-cleanup-cold'); local s=Scheduler.new(); Scheduler.add(s,1,m)
 Scheduler.add(s,2,machine(neighbor,'=stress-cold-neighbor'))
 local tick=game.tick
 for _=1,200 do
  Scheduler.tick(s,tick); tick=tick+1
  if m.status=='yield' then break end
 end
 assert(m.status=='yield' and #m.frames==Limits.call_frames)
 local error_value=m.yielded[2]
 assert(Events.admit(m,{n=1,'resume-stress'}))
 -- A labelled one-credit dispatch reaches an actual pending unwind, never a fabricated frame.
 for _=1,100 do
  Scheduler.begin_tick(s,tick)
  assert(Scheduler.consume(s,1,'execution',Limits.instructions_per_computer-1))
  Scheduler.tick(s,tick); tick=tick+1
  local p=m.heap[m.active].pending
  if p and p.kind=='unwind' then break end
 end
 local pending=m.heap[m.active].pending
 assert(pending and pending.kind=='unwind')
 Collector.start(m)
 check('native maximum cleanup suspends actual unwind with retained reference error and collection',pending.value.native_ref==error_value.native_ref)
 return {scheduler=s,tick=s.budget.tick,blocks=m.blocks,error=error_value,pending=pending,cleanup=m.cleanup_work or 0}
end
function M.reload(state,check)
 local s,m=state.scheduler,state.scheduler.machines[1]
 check('native cold maximum cleanup preserves pending unwind cursor ownership error and spent credits',m.blocks==state.blocks
  and m.heap[m.active].pending==state.pending and state.pending.value.native_ref==state.error.native_ref
  and m.collector~=nil and Scheduler.remaining(s,1,'execution')==0)
 for tick=state.tick+1,state.tick+200 do
  Scheduler.tick(s,tick)
  if m.status=='return' then break end
 end
 check('native cold maximum cleanup completes protected reference recovery without replay or neighbor corruption',
  m.status=='return' and m.result[1]=='cleanup' and m.result[2].native_ref==state.error.native_ref
  and Execution.get(m,state.error,'marker')=='retained-error' and (m.cleanup_work or 0)>=state.cleanup
  and s.machines[2].status=='yield')
end
return M
