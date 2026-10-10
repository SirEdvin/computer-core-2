-- Real-tick production R.tick traversal with isolated host records. This is not
-- blue artwork, native entity interaction, graphical or joining-client proof.
local R=require('__computer_core_2__.scripts.os_runtime')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local VM=require('__computer_core_2__.scripts.guest.vm')
local Compiler=require('__computer_core_2__.scripts.guest.compiler')
local Boot=require('__computer_core_2__.scripts.guest.boot')
local Native=require('__computer_core_2__.scripts.native.dispatch')
local NativeCompiler=require('__computer_core_2__.scripts.native.compiler')
local VMScheduler=require('__computer_core_2__.scripts.guest.scheduler')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local Events=require('__computer_core_2__.scripts.guest.events')
local new=require('construct')
local M={}
local function packed(value) return serpent.line(value,{sortkeys=true}) end
local function body() return {valid=true,electric_buffer_size=100,energy=100} end
local function host(fn,state)
  local old=storage; storage=state
  local ok,result=pcall(fn)
  storage=old
  assert(ok,result)
  return result
end
local function caps(ledger)
  assert(ledger.execution_budget.instructions<=Limits.instructions_per_tick and ledger.execution_budget.collection<=Limits.collection_work_per_tick)
  for _,own in pairs(ledger.execution_budget.machines) do
    assert(own.instructions<=Limits.instructions_per_computer and own.collection<=Limits.collection_work_per_computer)
  end
  for _,domain in ipairs({'compiler','string','terminal','filesystem','event','advance','table','continuation'}) do
    local b=ledger[domain=='compiler' and 'compile_budget' or domain..'_budget']
    assert(b.used<=Limits[domain..'_work_per_tick'],'shared aggregate '..domain)
    for _,own in pairs(b.machines) do assert(own.used<=Limits[domain..'_work_per_computer'],'shared machine '..domain) end
  end
end
local function tick(m)
  local original={VM.run,Boot.new,Compiler.compile,Native.run,NativeCompiler.compile}
  VM.run=function(vm,...)
    assert(vm==m.host.computers[1].guest or vm==m.host.computers[8].guest,'shell entered VM execution')
    return original[1](vm,...)
  end
  local function forbidden() error('production shell entered VM boot/compiler/continuation',0) end
  Boot.new,Compiler.compile,Native.run,NativeCompiler.compile=forbidden,forbidden,forbidden,forbidden
  local ok,err=pcall(host,R.tick,m.host)
  VM.run,Boot.new,Compiler.compile,Native.run,NativeCompiler.compile=table.unpack(original)
  assert(ok,err)
  for _,c in pairs(m.host.computers) do assert(not c.os_error,c.os_error) end
  assert(m.host.computers[2].guest.instructions==0,'stale shell VM graph executed')
  caps(m.host.terminal_scheduler)
end
local function neighbor(m)
  local vm=m.host.computers[8].guest
  if not m.echo then
    local text=m.echoes%2==0 and 'W' or 'Q'
    assert(host(function() return R.event(m.host.computers[8],{n=2,'char',text}) end,m.host))
    m.echo={tick=game.tick,text=text,revision=vm.display.revision}
  end
end
local function echoed(m)
  local vm=m.host.computers[8].guest
  local e=m.echo
  if e and vm.display.revision>e.revision and vm.display.lines[1].text:sub(1,1)==e.text then
    m.max_echo=math.max(m.max_echo,game.tick-e.tick); m.echoes=m.echoes+1; m.echo=nil
  elseif e then assert(game.tick-e.tick<=2,'mixed production VM neighbor stalled') end
end
function M.initial(check)
  local busy=assert(Compiler.compile('while true do local x=1 end','=mixed-production-busy'))
  local interactive=assert(Compiler.compile('while true do local e,c=os.pullEvent("char"); term.setCursorPos(1,1); term.write(c) end','=mixed-production-neighbor'))
  local busy_vm=VM.new(busy,nil,nil,{columns=51,rows=19},true)
  local vm=VM.new(interactive,nil,nil,{columns=51,rows=19},true)
  local sentinel=VM.new(assert(Compiler.compile('return 1','=mixed-production-sentinel')))
  local fs={['/']={type='dir'}}
  for i=1,128 do local suffix=tostring(i); fs['/'..string.rep('x',1023-#suffix)..suffix]={type='file',text=''} end
  local shell={id=2,backend='event-shell',fs=fs,guest=sentinel,entity=body()}
  local unsupported={id=3,backend='native',fs=fs,experiment={version=5,retained='original'},entity=body()}
  local invalid={id=4,backend='event-shell',fs=fs,shell=new(nil,51,19),entity=body()}; invalid.shell.version=99
  local personal={id=5,personal=true,player_index=1,os_stopped=true,terminal_schema=1,fs=sentinel.disk.fs}
  local input={id=6,backend='event-shell',fs={['/']={type='dir'}},entity=body()}
  local file={id=7,backend='event-shell',fs={['/']={type='dir'},['/data']={type='file',text='committed'}},entity=body()}
  local m={host={computers={
    [1]={id=1,terminal_schema=1,guest=busy_vm,fs=busy_vm.disk.fs,entity=body()},[2]=shell,[3]=unsupported,[4]=invalid,[5]=personal,
    [6]=input,[7]=file,[8]={id=8,terminal_schema=1,backend='vm',guest=vm,fs=vm.disk.fs,entity=body()}},sessions={},terminal_scheduler=VMScheduler.new()},
    setup_tick=game.tick,frames=0,echoes=0,max_echo=0,unsupported_before=packed(unsupported),invalid_before=packed(invalid),personal_before=packed(personal)}
  local ledger=m.host.terminal_scheduler
  Budget.begin(ledger,game.tick)
  assert(Budget.admit(ledger,2,{table=Limits.table_work_per_computer}))
  local source=packed(fs)
  tick(m)
  check('production construction admission refuses without retaining a session or converting stale VM data',shell.shell==nil and not shell.os_error
    and packed(fs)==source and R.status(shell)=='initializing' and sentinel.instructions==0 and ledger.table_budget.machines[2].used==Limits.table_work_per_computer)
  check('production traversal keeps unknown incompatible and personal VM records unchanged',packed(unsupported)==m.unsupported_before
    and packed(invalid)==m.invalid_before and packed(personal)==m.personal_before and R.backend(personal)=='vm')
  -- Trusted synthetic registration fixture, deliberately without dispatch:
  -- shared VM alias is never executed; the real workload above has distinct VMs.
  local capacity={computers={},terminal_scheduler=VMScheduler.new()}
  for id=1,Limits.active_computers do
    capacity.computers[id]={id=id,terminal_schema=1,guest=sentinel,fs=sentinel.disk.fs,entity=body()}
    VMScheduler.add(capacity.terminal_scheduler,id,sentinel)
  end
  local id=Limits.active_computers+1
  capacity.computers[id]={id=id,backend='event-shell',fs={['/']={type='dir'}},entity=body()}
  Budget.begin(capacity.terminal_scheduler,game.tick)
  assert(Budget.admit(capacity.terminal_scheduler,1,{execution=Limits.instructions_per_tick}))
  host(R.tick,capacity)
  check('production VM and shell share the unchanged active-computer admission cap',#capacity.terminal_scheduler.order==Limits.active_computers
    and capacity.computers[id].shell==nil and capacity.terminal_scheduler.execution_budget.instructions==Limits.instructions_per_tick)
  capacity.computers[Limits.active_computers].entity.energy=0
  host(R.tick,capacity)
  check('power removal releases an active slot but not spent same-tick construction credits',#capacity.terminal_scheduler.order==Limits.active_computers-1
    and capacity.computers[id].shell==nil and not capacity.computers[id].os_error and sentinel.instructions==0)
  local timer_vm=VM.new(interactive,nil,nil,{columns=51,rows=19},true)
  Events.start_timer(timer_vm.events,0) -- Trusted pressure setup; production advancement remains paid.
  local timer_host={computers={[8]={id=8,terminal_schema=1,guest=timer_vm,fs=timer_vm.disk.fs,entity=body()}},terminal_scheduler=VMScheduler.new()}
  Budget.begin(timer_host.terminal_scheduler,game.tick)
  assert(Budget.admit(timer_host.terminal_scheduler,8,{advance=Limits.advance_work_per_computer}))
  assert(timer_host.terminal_scheduler.advance_budget.deferred_per_computer==nil)
  host(R.tick,timer_host)
  check('VM timer refusal tolerates shared ledger optional diagnostics and still receives execution',not timer_host.computers[8].os_error
    and timer_vm.instructions>0 and timer_vm.events.timer_count==1 and timer_host.terminal_scheduler.advance_budget.deferred_per_computer==1)
  local retained=new(nil,51,19)
  local broken={computers={[2]={id=2,backend='event-shell',shell=retained,entity=body()}},terminal_scheduler=VMScheduler.new()}
  Budget.begin(broken.terminal_scheduler,game.tick+1)
  local original_ledger,original_shell=packed(broken.terminal_scheduler),packed(retained)
  host(R.tick,broken)
  check('production backwards clock halts visibly without mutating ledger or retained shell',broken.computers[2].os_error
    and broken.computers[2].os_error:find('backwards',1,true) and R.status(broken.computers[2])=='recovery'
    and packed(broken.terminal_scheduler)==original_ledger and packed(retained)==original_shell)
  return m
end
function M.prepare(m,check)
  -- The first server on_tick can still be the constructor's simulation tick.
  -- Do not pretend that loading the bootstrap map renewed its exhausted credits.
  if game.tick==m.setup_tick then return false end
  m.frames=m.frames+1
  local cs=m.host.computers
  if m.frames==3 then assert(host(function() return R.event(cs[6],{n=2,'char','p'}) end,m.host)) end
  if m.frames==4 then
    assert(host(function() return R.event(cs[6],{n=2,'char','w'}) end,m.host))
    assert(host(function() return R.event(cs[7],{n=2,'paste','cp /data /copy'}) end,m.host))
  end
  if m.frames==5 then assert(host(function() return R.event(cs[7],{n=2,'key',257}) end,m.host)) end
  neighbor(m); tick(m); echoed(m)
  if m.frames==1 then
    check('production construction and first import slice are charged before prompt',cs[2].shell and cs[2].shell.status=='initializing'
      and cs[2].shell.job.cursor>1 and R.files(cs[2])==nil and m.host.terminal_scheduler.backends[2]=='event-shell')
  end
  if m.frames<5 then return false end
  check('real production traversal rotates past a cap-consuming VM and services interactive neighbor',m.echoes>=4 and m.max_echo<=2
    and m.host.terminal_scheduler.execution_budget.instructions==Limits.instructions_per_tick and cs[2].shell.job.cursor>8)
  check('real production input and filesystem jobs belong to selected shell only',cs[6].shell.command=='pw' and cs[7].shell.job.kind=='filesystem'
    and not cs[7].shell.disk.fs['/copy'] and cs[2].shell.status=='initializing' and cs[2].guest.instructions==0)
  assert(host(function() return R.event(cs[6],{n=2,'char','d'}) end,m.host))
  local a,b,c=packed(cs[2].shell),packed(cs[6].shell),packed(cs[7].shell)
  tick(m)
  check('repeated production tick cannot refresh exhausted credits or consume retained input/jobs',packed(cs[2].shell)==a
    and packed(cs[6].shell)==b and packed(cs[7].shell)==c and m.host.terminal_scheduler.execution_budget.instructions==Limits.instructions_per_tick)
  m.import_job=cs[2].shell.job; m.import_source=m.import_job.source; m.import_nodes=m.import_job.nodes
  m.file_job=cs[7].shell.job; m.before=packed(m.host); m.resume_frames=0
  return true
end
function M.observe(m)
  if not m.before then return end
  assert(packed(m.host)==m.before,'mixed production state/counters changed on load')
  local cs=m.host.computers
  assert(cs[2].shell.job==m.import_job and m.import_job.source==m.import_source and m.import_job.nodes==m.import_nodes
    and cs[7].shell.job==m.file_job and m.host.terminal_scheduler.machines[2]==cs[2].shell
    and m.host.terminal_scheduler.machines[7]==cs[7].shell,'mixed scheduler/job aliases changed on load')
  local before=packed(m.host)
  host(R.on_load,m.host)
  assert(packed(m.host)==before,'production on_load mutated mixed state')
end
function M.resume(m,check)
  m.resume_frames=m.resume_frames+1
  local cs=m.host.computers
  if m.resume_frames==1 then
    M.observe(m)
    check('cold production scheduler retains shell/import/file aliases and spent shared budget',m.host.terminal_scheduler.execution_budget.instructions==Limits.instructions_per_tick
      and cs[6].shell.command=='pw' and #cs[6].shell.events.queue==1 and cs[2].shell.status=='initializing')
    cs[2].entity.energy=0
    m.paused=packed(cs[2].shell)
  elseif m.resume_frames==2 then
    check('unpowered production import is removed without advancing retained state',packed(cs[2].shell)==m.paused
      and m.host.terminal_scheduler.machines[2]==nil)
    cs[2].entity.energy=100
  end
  neighbor(m); tick(m); echoed(m)
  if m.resume_frames==1 then check('cold production registry applies queued character once',cs[6].shell.command=='pwd' and #cs[6].shell.events.queue==0) end
  if cs[2].shell.status~='ready' or cs[7].shell.job then
    assert(m.resume_frames<40,'mixed production jobs did not finish'); return false
  end
  check('cold production import and filesystem job publish once under original shared caps',cs[2].shell.disk.nodes==129
    and cs[7].shell.disk.fs['/copy'].text=='committed' and cs[7].shell.disk.fs['/data'].text=='committed'
    and cs[6].shell.command=='pwd' and m.max_echo<=2 and m.echoes>5)
  check('mixed execution preserves unknown incompatible and personal VM records after reload',packed(cs[3])==m.unsupported_before
    and packed(cs[4])==m.invalid_before and packed(cs[5])==m.personal_before and cs[2].guest.instructions==0)
  host(function() assert(R.shutdown(cs[6])); R.tick() end,m.host) -- Current tick is exhausted: control remains queued.
  m.finish='shutdown'; return true
end
function M.finish(m,check)
  local c=m.host.computers[6]
  tick(m)
  if m.finish=='shutdown' then
    assert(c.shell.status=='stopped' and m.host.terminal_scheduler.machines[6]==nil)
    host(function() assert(R.reboot(c)) end,m.host)
    m.finish='reboot'; return false
  end
  if c.shell.status~='ready' then return false end
  check('production shutdown removes only owned registration and explicit reboot resumes same disk',c.shell.status=='ready' and c.shell.command==''
    and m.host.computers[2].shell.status=='ready' and m.host.computers[7].shell.disk.fs['/copy'].text=='committed')
  log('CC2 SHELL MIXED EVIDENCE echoes='..m.echoes..' max_echo_ticks='..m.max_echo..' resume_ticks='..m.resume_frames)
  return true
end
return M
