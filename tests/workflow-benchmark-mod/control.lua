-- The same input trace on each backend, one dispatch per actual on_tick.
-- Module import time is separately logged; no GUI or wall-clock scheduling.
local config=require('benchmark_config')
local imports=helpers.create_profiler()
local Direct=config.backend=='shell'
assert(not Direct or config.case=='shell','direct shell has no editors')
local prefix='__computer_core_2__.scripts.'..(config.backend=='native' and 'native.' or 'guest.')
local Boot=not Direct and require(prefix..'boot') or nil
local Scheduler=require(Direct and '__computer_core_2__.scripts.shell.scheduler' or prefix..'scheduler')
local Native=config.backend=='native'
local Events=Native and require(prefix..'events') or nil
local VM=not Native and not Direct and require(prefix..'vm') or nil
local Limits=require('__computer_core_2__.scripts.guest.limits')
local Audit=config.diagnostics and require('allocation_audit') or nil
if Audit then assert(Native,'allocation diagnostics require native backend'); Audit.install() end
imports.stop()
local loaded=false
local domains={'compiler','string','terminal','filesystem','event','advance','table','continuation'}
local function check(name,value)
 assert(value,'workflow benchmark: '..name)
 storage.checks=storage.checks+1
 log('CC2 WORKFLOW PASS '..name)
end
local function count(m) return Native and m.blocks or m.instructions end
local function waiting(m,editor)
 if Direct then return m.status=='ready' and m.job==nil and #m.events.queue==0 end
 if m.collector or m.collection then return false end
 if not editor then
  return #m.events.queue==0 and (Native and m.status=='yield' or not Native and m.wait~=nil)
 end
 -- Shell polling may keep the root busy while the actual editor is suspended.
 -- Only pending non-timer ingress prevents editor readiness.
 for _,record in ipairs(m.events.queue) do if record.tuple[1]~='timer' then return false end end
 for _,object in pairs(Native and m.heap or m.objects) do
  if (object.kind=='thread' or object.kind=='coroutine') and object.status=='suspended' then
   for _,frame in ipairs(object.frames) do
    local source
    if Native then
     local b=frame.bundle_id and frame.bundle_id~=1 and m.bundles[frame.bundle_id] or m.bundle
     source=b.name
    else source=frame.proto and frame.proto.source end
    if source and source:find('/rc/editors/',1,true) then return true end
   end
  end
 end
 return false
end
local function footer(m)
 local expected=config.case=='basic' and 'Press Control for menu' or 'Press Ctrl for menu'
 return m.display.lines[m.display.rows].text:sub(1,#expected)==expected
end
local function totals()
 local b=storage.benchmark
 local result={instructions=count(b.machine),collection_work=b.collection,collection_ticks=b.collection_ticks,
  display_revisions=b.machine.display.revision,dirty_rows=b.dirty_rows,
  activation_work=b.machine.activation_work or 0}
 for _,domain in ipairs(domains) do result[domain..'_work']=b.work[domain] or 0 end
 return result
end
local function phase(name)
 local b=storage.benchmark
 b.phase=name; b.first_tick=nil; b.start=game.tick; b.before=totals()
end
local function metric(label)
 local b=storage.benchmark
 local values={'phase='..label,'case='..config.case,'backend='..config.backend,'sample='..(b.character or 0),
  'ticks='..(game.tick-b.first_tick+1)}
 for key,value in pairs(totals()) do values[#values+1]=key..'='..(value-b.before[key]) end
 table.sort(values)
 log('CC2 WORKFLOW METRIC '..table.concat(values,' '))
 if Audit then Audit.snapshot(b.machine,label,b.character or 0) end
 check(label..' completed at a real simulation tick',game.tick>=b.first_tick)
end
local function send(...)
 local tuple=table.pack(...)
 local b=storage.benchmark; local m=b.machine
 local profiler=game.create_profiler()
 local before=Direct and b.scheduler.event_budget.used or 0
 if Direct then assert(Scheduler.push(m,b.scheduler,1,game.tick,tuple)); b.work.event=(b.work.event or 0)+b.scheduler.event_budget.used-before
 else assert(Native and Events.admit(m,tuple) or not Native and VM.queue(m,tuple)) end
 profiler.stop()
 log({'','CC2 WORKFLOW PROFILE kind=ingress backend='..config.backend..' case='..config.case..' ',profiler})
end
local function character()
 local b=storage.benchmark
 phase('character'); send('char','x')
end
local function boot()
 local profiler=game.create_profiler()
 local m,s
 if Direct then
  s={version=1}
  m=assert(Scheduler.new({fs={['/']={type='dir'}}},51,19,s,1,game.tick))
 else
  m=Boot.new({fs={['/']={type='dir'}}}, {columns=51,rows=19})
  s=Scheduler.new(); Scheduler.add(s,1,m)
 end
 profiler.stop()
 log({'','CC2 WORKFLOW PROFILE kind=creation backend='..config.backend..' case='..config.case..' ',profiler})
 storage.benchmark={machine=m,scheduler=s,collection=0,collection_ticks=0,dirty_rows=0,work={}}
 if Audit then Audit.watch(m) end
 phase('boot')
 if Direct then storage.benchmark.before.instructions=0; storage.benchmark.before.display_revisions=0 end
end
local function failure(m)
 if Direct then return m.status=='recovery' or m.status=='stopped' end
 if Native then return m.status=='error' or m.status=='recovery' or m.host_request end
 for _,o in pairs(m.objects) do if o.kind=='coroutine' and o.failed then return true end end
 return false
end
script.on_init(function()
 storage.checks=0; storage.finished=false
 log('CC2 WORKFLOW BOOTSTRAP PASS')
end)
script.on_load(function() loaded=true end)
script.on_event(defines.events.on_tick,function()
 if loaded then
  loaded=false
  log({'','CC2 WORKFLOW PROFILE kind=module-import backend='..config.backend..' case='..config.case..' ',imports})
  if storage.finished then
   local b=storage.benchmark
   check('cold load preserves final echoed character and execution count',count(b.machine)==storage.saved_count
    and b.machine.display.lines[b.row].text:sub(b.column,b.column)=='x')
   log('CC2 WORKFLOW COMPLETE RELOAD checks='..storage.checks)
   return
  end
 end
 if storage.finished then return end
 if not storage.benchmark then
  if Audit then Audit.verify() end -- Trusted observer probe only at first synchronized tick.
  boot()
 end
 local b=storage.benchmark; local m=b.machine
 assert(game.tick-b.start<6000,'workflow phase deadline: '..b.phase)
 if not b.first_tick then b.first_tick=game.tick end
 if Audit then Audit.phase(m,b.phase) end
 local profiler=game.create_profiler()
 local result
 if Direct then
  Scheduler.step(m,b.scheduler,1,game.tick,true)
  result={b.scheduler.execution_budget.instructions,1,b.scheduler.execution_budget.collection}
 else result=table.pack(Scheduler.tick(b.scheduler,game.tick)) end
 profiler.stop()
 log({'','CC2 WORKFLOW PROFILE kind=scheduler backend='..config.backend..' case='..config.case..' phase='..b.phase..' tick='..game.tick..' ',profiler})
 assert(result[1]<=Limits.instructions_per_tick and result[3]<=Limits.collection_work_per_tick and result[2]==1)
 b.collection=b.collection+result[3]
 if result[3]>0 then b.collection_ticks=b.collection_ticks+1 end
 for _,domain in ipairs(domains) do
  local amount=Native and (b.scheduler.budget.used[domain] or 0) or b.scheduler[domain=='compiler' and 'compile_budget' or domain..'_budget'].used
  assert(amount<=Limits[domain..'_work_per_tick'],'aggregate '..domain..' exceeded')
  b.work[domain]=(b.work[domain] or 0)+amount
 end
 for _ in pairs(m.display.dirty) do b.dirty_rows=b.dirty_rows+1 end
 -- No GUI is constructed: dirty rows model pending presentation, not rendering.
 m.display.dirty={}
 if failure(m) then
  log('CC2 WORKFLOW FAILURE '..serpent.line({phase=b.phase,error=m.error,recovery=m.recovery,events=m.events}))
  error('actual guest workflow failed: '..b.phase)
 end
 if b.phase=='launch' and game.tick==b.first_tick+200 then
  local threads={}
  for id,o in pairs(Native and m.heap or m.objects) do
   if o.kind=='thread' or o.kind=='coroutine' then
    local frames={}
    for _,f in ipairs(o.frames) do
     frames[#frames+1]=Native and (f.bundle_id and f.bundle_id~=1 and m.bundles[f.bundle_id] or m.bundle).name or f.proto.source
    end
    threads[#threads+1]={id=id,status=o.status,frames=frames}
   end
  end
  log('CC2 WORKFLOW LAUNCH DIAGNOSTIC '..serpent.line({status=m.status,wait=m.wait~=nil,queue=m.events.queue,
   footer=m.display.lines[m.display.rows].text,threads=threads,waiting=waiting(m,true),first=m.display.lines[1].text}))
 end
 if b.phase=='boot' and waiting(m,false) and m.display.lines[Direct and m.display.rows or 2].text:sub(1,2)=='/>' then
  metric('boot')
  if config.case=='shell' then
   b.row,b.column,b.character=m.display.y,m.display.x,1; character()
  else
   phase('launch')
   send('paste',config.case=='basic' and '/rc/editors/basic.lua /benchmark.txt' or 'edit /benchmark.lua')
   send('key',257,false)
  end
 elseif b.phase=='launch' and waiting(m,true) and footer(m) then
  metric('launch'); b.row,b.column,b.character=m.display.y,m.display.x,1; character()
 elseif b.phase=='character' and m.display.lines[b.row].text:sub(b.column,b.column)=='x' then
  -- First visible model echo, not later scheduler/wait drainage.
  metric('echo'); phase('settle')
 elseif b.phase=='settle' and waiting(m,config.case~='shell') then
  if b.character==config.characters then
   if Audit then Audit.finish(m) end
   if Native then
    log('CC2 WORKFLOW STATE allocations='..m.allocations..' steps='..m.blocks..' objects='..m.objects
     ..' next_id='..m.next_id..' revision='..m.display.revision..' tick='..game.tick)
   end
   storage.finished=true; storage.saved_count=count(m)
   game.server_save('cc2-resume')
   log('CC2 WORKFLOW SNAPSHOT tick='..game.tick)
   log('CC2 WORKFLOW COMPLETE FIRST checks='..storage.checks)
  else
   phase('erase'); send('key',259,false)
  end
 elseif b.phase=='erase' and m.display.lines[b.row].text:sub(b.column,b.column)==' ' and waiting(m,config.case~='shell') then
  -- Reset between individually measured characters to avoid width/scroll bias.
  b.character=b.character+1; character()
 end
end)
