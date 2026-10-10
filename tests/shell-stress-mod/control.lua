-- Maximum accepted workloads on real simulation ticks beside an interactive VM.
-- Source generation/compilation and observers are trusted fixture setup, not paid
-- production work or GUI evidence. Shell construction and every dispatch are paid.
local Shell=require('__computer_core_2__.scripts.shell.runtime')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local VM=require('__computer_core_2__.scripts.guest.vm')
local Compiler=require('__computer_core_2__.scripts.guest.compiler')
local VMScheduler=require('__computer_core_2__.scripts.guest.scheduler')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local FS=require('__computer_core_2__.scripts.filesystem')
local Adversarial=require('adversarial')
local loaded=false
local function packed(value) return serpent.line(value,{sortkeys=true}) end
local function check(name,value)
  assert(value,'shell stress: '..name); storage.checks=storage.checks+1
  log('CC2 SHELL STRESS PASS '..name)
end
local function send(event)
  assert(Scheduler.push(storage.shell,storage.ledger,2,game.tick,event))
end
local function idle() local s=storage.shell; return s.status=='ready' and not s.job and #s.events.queue==0 end
local function command(text) send({n=2,'paste',text}); send({n=2,'key',257}) end
local function phase(name)
  storage.phase=name; storage.phase_tick=game.tick
  log('CC2 SHELL STRESS PHASE '..name..' tick='..game.tick)
end
local function caps()
  local l=storage.ledger
  assert(l.execution_budget.instructions<=Limits.instructions_per_tick and l.execution_budget.collection<=Limits.collection_work_per_tick)
  for _,name in ipairs({'compiler','string','terminal','filesystem','event','advance','table','continuation'}) do
    local b=l[name=='compiler' and 'compile_budget' or name..'_budget']
    assert(b.used<=Limits[name..'_work_per_tick'],'aggregate '..name)
    for id,own in pairs(b.machines) do
      assert(own.used<=Limits[name..'_work_per_computer'],'machine '..id..' '..name)
    end
    storage.peaks[name]=math.max(storage.peaks[name] or 0,b.used)
  end
end
local function neighbor()
  local m=storage.vm
  if not storage.echo and game.tick%8==0 then
    local text=storage.echo_count%2==0 and 'W' or 'Q'
    assert(VM.queue(m,{n=2,'char',text})); storage.echo={tick=game.tick,text=text,revision=m.display.revision}
  end
  VMScheduler.tick(storage.ledger,game.tick)
  if storage.echo then
    local e=storage.echo
    if m.display.lines[1].text:sub(1,1)==e.text and m.display.revision>e.revision then
      storage.echo_count=storage.echo_count+1
      storage.echo_max=math.max(storage.echo_max,game.tick-e.tick)
      assert(game.tick-e.tick<=2,'VM interactive neighbor missed two-tick structural target')
      storage.echo=nil
    else assert(game.tick-e.tick<=2,'VM interactive neighbor stalled') end
  end
end
script.on_init(function()
  game.speed=8 -- Resource/neighbor oracle in simulation ticks, not wall/client latency.
  storage.checks=0; storage.peaks={}; storage.echo_count=0; storage.echo_max=0
  storage.adversarial=Adversarial.new()
  local source={fs={['/']={type='dir'}}}
  for i=1,FS.max_nodes-1 do
    local suffix=tostring(i)
    local path='/'..string.rep('x',1023-#suffix)..suffix
    source.fs[path]={type='file',text=i==1 and string.rep('L',FS.max_bytes) or ''}
    if i==1 then storage.payload_path=path elseif i==2 then storage.empty_path=path end
  end
  storage.ledger=VMScheduler.new()
  storage.shell=assert(Scheduler.new(source,160,60,storage.ledger,2,game.tick))
  local proto=assert(Compiler.compile('while true do local e,c=os.pullEvent("char"); term.setCursorPos(1,1); term.write(c) end','=interactive-stress-neighbor'))
  storage.vm=VM.new(proto,nil,nil,{columns=51,rows=19},true)
  VMScheduler.add(storage.ledger,1,storage.vm)
  check('accepted maximum content and path metadata are retained under admitted constructor',storage.shell.status=='initializing'
    and storage.shell.disk==nil and storage.shell.job.count==FS.max_nodes and storage.shell.job.bytes==FS.max_bytes)
  phase('snapshot')
  log('CC2 SHELL STRESS BOOTSTRAP PASS')
end)
script.on_load(function()
  loaded=true
  if storage.before then
    assert(packed(storage.shell)==storage.before and packed(storage.ledger)==storage.budget_before,'stress load changed state/counters')
    Adversarial.observe(storage.adversarial)
  end
end)
script.on_event(defines.events.on_tick,function()
  local s=storage.shell
  assert(game.tick<40000,'shell stress real-tick deadline')
  -- server_save queues persistence; a completion marker is not a save barrier.
  -- Freeze every fixture participant until the separate process actually loads.
  if storage.resume_pending and not loaded then return end
  if storage.phase=='snapshot' then
    loaded=false
    if not storage.before then
      assert(Scheduler.step(s,storage.ledger,2,game.tick,true))
      assert(s.status=='initializing' and s.job.cursor>1 and s.disk==nil)
      storage.before=packed(s)
    end
    local ready=Adversarial.prepare(storage.adversarial,storage.ledger,game.tick,check)
    neighbor(); caps()
    if not ready then return end
    storage.budget_before=packed(storage.ledger)
    phase('import')
    storage.resume_pending=true
    game.server_save('cc2-resume')
    log('CC2 SHELL STRESS SNAPSHOT')
    log('CC2 SHELL STRESS COMPLETE FIRST checks='..storage.checks)
    return
  end
  if loaded then
    loaded=false
    check('real-tick cold import retains source cursor disk absence and spent credits',packed(s)==storage.before and packed(storage.ledger)==storage.budget_before)
    storage.resume_pending=false
  end
  local adversarial=storage.adversarial
  if not adversarial.done then
    if adversarial.phase=='retry' then Adversarial.retry(adversarial,storage.ledger,game.tick,check)
    else adversarial.done=Adversarial.resume(adversarial,storage.ledger,game.tick,check) end
  end
  local powered=true
  if storage.phase=='import' and game.tick-storage.phase_tick<=3 then
    local before=packed(s); assert(not Scheduler.step(s,storage.ledger,2,game.tick,false))
    assert(packed(s)==before); powered=false
  elseif storage.phase=='byte-queue' then
    powered=false
    local left=Limits.event_bytes-s.events.bytes
    if left>=#'paste' then
      local size=math.min(Shell.command_bytes,left-#'paste')
      send({n=2,'paste',string.rep('Z',size)})
    else
      check('maximum event byte envelope refuses more data without growing input',s.events.bytes==Limits.event_bytes
        and not Scheduler.push(s,storage.ledger,2,game.tick,{n=2,'char','x'}) and s.command=='')
      phase('byte-drain'); powered=true
    end
  elseif storage.phase=='count-queue' then
    powered=false
    for _=1,Limits.events do send({n=2,'char','x'}) end
    check('maximum event inventory rejects overflow',#s.events.queue==Limits.events
      and not Scheduler.push(s,storage.ledger,2,game.tick,{n=2,'char','y'}))
    for i=1,Limits.timers do assert(Scheduler.start_timer(s,storage.ledger,2,game.tick,0)) end
    check('maximum timer ownership refuses excess',not pcall(Scheduler.start_timer,s,storage.ledger,2,game.tick,0))
    assert(Scheduler.cancel_timer(s,storage.ledger,2,game.tick,1))
    phase('count-drain')
  end
  if powered then Scheduler.step(s,storage.ledger,2,game.tick,true) end
  neighbor(); caps()
  assert(s.status~='recovery','unexpected shell recovery')
  if storage.phase=='import' and idle() then
    check('real-tick maximum import atomically installs full accepted inventory',s.disk.nodes==FS.max_nodes and s.disk.bytes==FS.max_bytes
      and s.disk.fs[storage.payload_path].text==string.rep('L',FS.max_bytes))
    send({n=2,'paste','cat '}); send({n=2,'key',258}); phase('completion')
  elseif storage.phase=='completion' and idle() then
    check('maximum path completion scans sorts and displays all candidates under shared credits',s.command=='cat ' and s.cursor==4)
    send({n=1,'terminate'}); phase('clear-completion')
  elseif storage.phase=='clear-completion' and idle() then
    command('cat '..storage.payload_path); phase('cat')
  elseif storage.phase=='cat' and idle() then
    check('real-tick maximum file output completes with exact disk preserved',s.disk.bytes==FS.max_bytes and s.disk.fs[storage.payload_path].text:sub(-1)=='L')
    command('mv '..storage.payload_path..' /payload'); phase('move')
  elseif storage.phase=='move' and idle() then
    check('maximum file and metadata staging commit exactly once',not s.disk.fs[storage.payload_path] and #s.disk.fs['/payload'].text==FS.max_bytes and s.disk.nodes==FS.max_nodes)
    command('rm '..storage.empty_path); phase('remove')
  elseif storage.phase=='remove' and idle() then
    check('maximum-inventory recursive removal preserves unrelated full file',not s.disk.fs[storage.empty_path] and #s.disk.fs['/payload'].text==FS.max_bytes and s.disk.nodes==FS.max_nodes-1)
    s.job={version=1,kind='output',text=string.rep('\n',Limits.string_bytes),cursor=1}
    send({n=2,'char','N'}); phase('newline')
  elseif storage.phase=='newline' and idle() then
    check('maximum newline output allows interactive VM and ordered shell input',s.command=='N' and storage.echo_count>100)
    send({n=1,'terminate'}); phase('clear-newline')
  elseif storage.phase=='clear-newline' and idle() then phase('byte-queue')
  elseif storage.phase=='byte-drain' and idle() then
    check('queued maximum pastes reject overflow atomically',#s.command==Shell.command_bytes and s.error=='command byte limit exceeded')
    send({n=1,'terminate'}); phase('clear-byte')
  elseif storage.phase=='clear-byte' and idle() then phase('count-queue')
  elseif storage.phase=='count-drain' and idle() and s.events.timer_count==0 then
    check('full queue drains without lost or duplicated chars and cancelled timer stays gone',#s.command==Limits.events and not s.events.timers[1])
    send({n=1,'terminate'}); phase('clear-count')
  elseif storage.phase=='clear-count' and idle() then
    storage.history_trial=1; command(string.rep('z',Shell.command_bytes)); phase('history-bytes')
  elseif storage.phase=='history-bytes' and idle() then
    storage.history_trial=storage.history_trial+1
    if storage.history_trial<=6 then command(string.rep('z',Shell.command_bytes))
    else
      local bytes=0; for _,line in ipairs(s.history) do bytes=bytes+#line end
      check('maximum line history evicts at total-byte ceiling under unchanged budgets',bytes==Shell.history_bytes and #s.history==4)
      storage.history_trial=1; command('pwd'); phase('history-count')
    end
  elseif storage.phase=='history-count' and idle() then
    storage.history_trial=storage.history_trial+1
    if storage.history_trial<=33 then command('pwd')
    else
      check('history entry ceiling remains independently enforced',#s.history==Shell.history_count and s.history[1]=='pwd')
      check('shared real-tick VM echo remains responsive through every maximum job',storage.echo_count>=100 and storage.echo_max<=2)
      log('CC2 SHELL STRESS EVIDENCE echoes='..storage.echo_count..' max_echo_ticks='..storage.echo_max..' peaks='..packed(storage.peaks))
      phase('done'); log('CC2 SHELL STRESS COMPLETE RELOAD checks='..storage.checks)
    end
  end
end)
