-- Actual released archive creates the first save; the candidate resumes it.
-- Isolated production host consumers, not graphical or multiplayer acceptance.
local L=require('__computer_core_2__.scripts.lifecycle')
local R=require('__computer_core_2__.scripts.os_runtime')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local loaded=false
local text='return {interval=1,on_start=function(event,state) state.starts=1; print("upgraded start") end,on_tick=function(event,state) state.runs=(state.runs or 0)+1 end}'
local function packed(value) return serpent.line(value,{sortkeys=true}) end
local function host(fn)
  local outer=storage; storage=outer.host
  local ok,a,b=pcall(fn); storage=outer; assert(ok,a); return a,b
end
local function check(name,value)
  assert(value,'blue upgrade: '..name); storage.checks=storage.checks+1; log('CC2 BLUE UPGRADE PASS '..name)
end
local function send(event) host(function() assert(R.event(storage.computers[1],event)) end) end
local function command(value) send({n=2,'paste',value}); send({n=2,'key',257}) end
local function capture()
  local s=storage.c.shell
  storage.before=packed(s); storage.credits=packed(storage.host.terminal_scheduler)
  storage.shell=s; storage.disk=s.disk; storage.job=s.job; storage.editor=s.editor; storage.controller=s.controller
  storage.saved_tick=game.tick
end
local function observe()
  assert(storage.c.shell==storage.shell and storage.shell.disk==storage.disk and storage.shell.job==storage.job
    and storage.shell.editor==storage.editor and storage.shell.controller==storage.controller
    and packed(storage.shell)==storage.before and packed(storage.host.terminal_scheduler)==storage.credits,'upgrade changed data/work on load')
end
script.on_init(function()
  storage.host={}; storage.checks=0; storage.phase='boot'
  game.forces.player.technologies['computer-technology'].researched=true
  local entity=assert(game.surfaces[1].create_entity{name='blue-computer-interface-entity',position={240,80},force=game.forces.player,raise_built=true})
  host(function()
    L.init(); R.init()
    storage.computers={} -- Only this fixture's isolated registry, not mod storage.
    local disk={fs={['/']={type='dir'},['/keep']={type='file',text='released committed bytes'},['/script.lua']={type='file',text=text},
      ['/wide']={type='file',text=string.rep('old output ',1024)}}}
    assert(L.build(entity,{computer_core_2=disk}))
  end)
  storage.c=storage.host.computers[1]
  local old=script.active_mods.computer_core_2=='0.3.0'
  check('released baseline retains version-appropriate circuit hardware without applications',storage.c.backend=='event-shell'
    and (old and not storage.c.native_ports or not old and storage.c.native_ports.left and storage.c.native_ports.right))
  log('CC2 BLUE UPGRADE BOOTSTRAP PASS')
end)
script.on_load(function()
  loaded=true
  if storage.phase=='old-snapshot' or storage.phase=='candidate-snapshot' then observe() end
end)
script.on_configuration_changed(function()
  observe()
  storage.configuration_changes=(storage.configuration_changes or 0)+1
  log('CC2 BLUE UPGRADE CONFIGURATION CHANGED')
end)
script.on_event(defines.events.on_tick,function()
  local phase=storage.phase; local s=storage.c.shell
  if phase=='done' or (phase=='old-snapshot' or phase=='candidate-snapshot') and not loaded then return end
  if loaded and (phase=='old-snapshot' or phase=='candidate-snapshot') then
    observe(); loaded=false
    local saved_tick=storage.saved_tick
    local ok=host(function() return Scheduler.step(s,storage.terminal_scheduler,1,saved_tick,true) end)
    check('cold same-tick exhausted work remains unchanged',not ok and packed(s)==storage.before and packed(storage.host.terminal_scheduler)==storage.credits)
    if phase=='old-snapshot' then
      check('real old archive session upgrades without replacement or autorun',not s.editor and not s.controller and not s.program_output
        and s.version==2 and s.disk.fs['/keep'].text=='released committed bytes' and storage.configuration_changes==1)
      storage.phase='old-output'; return
    end
    check('candidate cold draft controller save and queued print identities survive',s.editor.dirty and s.editor.saving
      and s.job.phase=='publish' and s.controller.started and s.controller.state.starts==1
      and s.program_output.queue[1]=='upgraded start')
    storage.phase='cold-save'; return
  end
  loaded=false; storage.c.entity.energy=5000000
  host(function() L.tick(); R.tick() end)
  s=storage.c.shell; phase=storage.phase
  if phase=='boot' and s.status=='ready' then
    command('cat /wide'); storage.phase='old-job'
  elseif phase=='old-job' and s.job and s.job.kind=='cat' then
    send({n=2,'char','Z'})
    host(function() local ledger=storage.terminal_scheduler; assert(Budget.admit(ledger,1,{execution=Budget.remaining(ledger,1,'execution')})) end)
    capture(); storage.phase='old-snapshot'; game.server_save('cc2-resume')
    log('CC2 BLUE UPGRADE SNAPSHOT'); log('CC2 BLUE UPGRADE COMPLETE FIRST checks='..storage.checks)
  elseif phase=='old-output' and not s.job and s.command=='Z' then
    check('old output and queued command finish once with committed files intact',s.disk==storage.disk and s.disk.fs['/keep'].text=='released committed bytes')
    send({n=2,'key',259}); command('edit /script.lua'); storage.phase='editor'
  elseif phase=='editor' and s.editor then
    check('upgraded session opens native editor without discarding old disk',s.editor.text==text and s.editor.base==text)
    send({n=2,'key',502}); command('run /script.lua'); command('edit /script.lua'); storage.phase='controller'
  elseif phase=='controller' and s.editor and s.controller and s.controller.started then
    send({n=2,'paste','-- saved upgrade\n'}); send({n=2,'key',501}); storage.phase='pending-save'
  elseif phase=='pending-save' and s.job and s.job.phase=='publish' then
    check('upgraded controller executes actual retained committed source and owns new ports',s.controller.source==text
      and s.controller.state.starts==1 and storage.c.native_ports.left and storage.c.native_ports.right)
    send({n=2,'char','C'})
    host(function() local ledger=storage.terminal_scheduler; assert(Budget.admit(ledger,1,{execution=Budget.remaining(ledger,1,'execution')})) end)
    capture(); storage.phase='candidate-snapshot'; game.server_save('cc2-upgraded')
    log('CC2 BLUE UPGRADE CANDIDATE SNAPSHOT'); log('CC2 BLUE UPGRADE COMPLETE RELOAD checks='..storage.checks)
  elseif phase=='cold-save' and not s.job and s.editor.text:find('-- saved upgrade\nC',1,true)==1 and s.controller.state.runs then
    check('cold save publishes once before retained queued character edits the draft',s.disk.fs['/script.lua'].text=='-- saved upgrade\n'..text
      and s.editor.dirty and s.editor.base==s.disk.fs['/script.lua'].text and s.disk.fs['/keep'].text=='released committed bytes')
    check('cold controller keeps active source and does not replay start',s.controller==storage.controller and s.controller.source==text
      and s.controller.state.starts==1 and s.controller.state.runs>=1)
    storage.phase='done'; log('CC2 BLUE UPGRADE COMPLETE COLD checks='..storage.checks)
  end
end)
