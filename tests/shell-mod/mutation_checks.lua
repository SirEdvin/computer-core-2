local Shell=require('__computer_core_2__.scripts.shell.runtime')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local FS=require('__computer_core_2__.scripts.filesystem')
local new=require('construct')
local M={}
local function packed(s) return serpent.line(s,{sortkeys=true}) end
local function driver(s,ledger,tick)
  local d={tick=tick or 0}
  function d.step() d.tick=d.tick+1; assert(Scheduler.step(s,ledger,1,d.tick,true)); assert(s.status~='recovery',s.recovery and s.recovery.message) end
  function d.send(event) d.tick=d.tick+1; assert(Scheduler.push(s,ledger,1,d.tick,event)); assert(Scheduler.step(s,ledger,1,d.tick,true)) end
  function d.command(text) d.send({n=2,'paste',text}); d.send({n=2,'key',257}) end
  function d.drain() local turns=0; while s.job do d.step(); turns=turns+1; assert(turns<20000) end end
  return d
end
function M.initial(check)
  local disk={fs={['/']={type='dir'},['/source']={type='dir'},['/source/a']={type='file',text='A'},
    ['/source/sub']={type='dir'},['/source/sub/b']={type='file',text='B'}}}
  for i=1,20 do disk.fs['/source/f'..i]={type='file',text=tostring(i)} end
  local s,ledger=new(disk,51,19),{version=1}; local tick=0
  while s.status=='initializing' do assert(Scheduler.step(s,ledger,1,tick,true)); tick=tick+1 end
  local d=driver(s,ledger,tick)
  local committed=s.disk
  d.command('mkdir target'); check('mkdir stages without exposing partial tree',s.job.kind=='filesystem' and s.disk==committed and not s.disk.fs['/target'])
  d.drain(); check('mkdir publishes authoritative new disk',s.disk~=committed and Shell.committed_disk(s)==s.disk and s.disk.fs['/target'].type=='dir')
  d.command('cp source target/copy'); d.drain()
  check('recursive copy keeps original and all nested data',s.disk.fs['/source/sub/b'].text=='B' and s.disk.fs['/target/copy/sub/b'].text=='B')
  local before=packed(s.disk)
  d.command('cp source target/copy'); check('existing destinations refuse without overwrite',s.job.kind=='output' and packed(s.disk)==before); d.drain()
  d.command('mv target/copy moved'); d.drain()
  check('move publishes destination and removes source together',s.disk.fs['/moved/sub/b'].text=='B' and not s.disk.fs['/target/copy'])
  d.command('cd moved'); d.command('rm /moved'); check('current directory ancestors are protected',s.job.kind=='output' and s.disk.fs['/moved']); d.drain()
  d.command('cd /'); d.command('rm moved'); d.drain(); check('recursive remove preserves unrelated tree',not s.disk.fs['/moved'] and s.disk.fs['/source/sub/b'].text=='B')
  for _,line in ipairs({'rm /','rm /rom','mkdir /rom/private','mv /rom/help.txt /help'}) do
    before=packed(s.disk); d.command(line); check('protected mutation refuses '..line,s.job.kind=='output' and packed(s.disk)==before); d.drain()
  end
  d.command('cp /rom/help.txt /help'); d.drain(); check('copy can read resource without mutating it',s.disk.fs['/help'].text:find('trusted built-in',1,true) and not s.disk.fs['/rom'])
  committed=s.disk; d.command('cp source canceled'); d.step()
  assert(s.job.phase=='prepare' and next(s.job.nodes))
  d.send({n=1,'terminate'}); check('interrupt discards unpublished file changes and restores prompt',s.job==nil and s.disk==committed and not s.disk.fs['/canceled'] and s.display.blink)
  d.command('cp source paused'); d.step(); before=packed(s)
  Budget.begin(ledger,d.tick); assert(Budget.admit(ledger,1,{filesystem=Budget.remaining(ledger,1,'filesystem')}))
  check('credit-refused file preparation retains progress and committed aliases',not Scheduler.step(s,ledger,1,d.tick,true) and packed(s)==before and s.disk==committed)
  d.drain(); check('retry publishes once after new credits',s.disk~=committed and s.disk.fs['/paused/sub/b'].text=='B')
  d.command('rm paused'); d.drain()
  -- Full-content copying must fail without deleting or truncating the source.
  local full=new({fs={['/']={type='dir'},['/full']={type='file',text=string.rep('x',FS.max_bytes)}}},51,19)
  local l2={version=1}; assert(Scheduler.step(full,l2,1,0,true)); local f=driver(full,l2)
  local original=full.disk; f.command('cp full overflow'); f.drain()
  check('content quota failure leaves full source exact and prompt usable',full.disk==original and #full.disk.fs['/full'].text==FS.max_bytes and not full.disk.fs['/overflow'] and full.display.blink)
  local path='/source/'..string.rep('x',1024-#'/source/')
  local wide=new({fs={['/']={type='dir'},['/source']={type='dir'},[path]={type='file',text='preserved'}}},51,19)
  local lwide={version=1}; assert(Scheduler.step(wide,lwide,1,0,true)); local w=driver(wide,lwide)
  original=wide.disk; w.command('cp source '..string.rep('d',1023)); w.drain()
  check('every descendant path is checked before publication',wide.disk==original and wide.disk.fs[path].text=='preserved' and wide.display.blink)
  local inventory={fs={['/']={type='dir'}}}
  for i=1,FS.max_nodes-1 do inventory.fs['/n'..i]={type='file',text=''} end
  local counted=new(inventory,51,19); local ln={version=1}; local nt=0
  while counted.status=='initializing' do assert(Scheduler.step(counted,ln,1,nt,true)); nt=nt+1 end
  local n=driver(counted,ln,nt); original=counted.disk; n.command('cp n1 added'); n.drain()
  check('node quota refuses oversized staging without reduced accepted inventory',counted.disk==original and counted.disk.nodes==FS.max_nodes and not counted.disk.fs['/added'] and counted.display.blink)
  local malformed_sources={}
  local variants={
    {'unknown source field',function(job) job.source[#job.source].handler='scripts.guest.vm' end},
    {'unknown node field',function(job) job.source[#job.source].node.module='scripts.guest.vm' end},
    {'sparse source inventory',function(job) job.source[0]=job.source[1] end},
    {'forged resource ownership',function(job) job.source[#job.source].resource=true end},
    {'forged resource content',function(job)
      job.src='/rom'; job.source[#job.source]={path='/rom/help.txt',resource=true,node={type='file',text='substituted'}}
    end},
  }
  for _,variant in ipairs(variants) do
    local probe=new(disk,51,19); local pl={version=1}; local pt=0
    while probe.status=='initializing' do assert(Scheduler.step(probe,pl,1,pt,true)); pt=pt+1 end
    local pd=driver(probe,pl,pt); pd.command('cp source candidate')
    local retained_job,retained_disk=probe.job,probe.disk
    variant[2](retained_job); local before_audit=packed(probe)
    check('zero-credit malformed source audit is inactive '..variant[1],not Shell.handle(probe,{n=1,'advance'},function() return false end)
      and packed(probe)==before_audit)
    pd.tick=pd.tick+1
    check('admitted malformed source enters preserved recovery '..variant[1],not Scheduler.step(probe,pl,1,pd.tick,true)
      and probe.status=='recovery' and probe.job==retained_job and probe.disk==retained_disk and not probe.disk.fs['/candidate'])
    malformed_sources[#malformed_sources+1]={shell=probe,job=retained_job,disk=retained_disk,before=packed(probe)}
  end
  local malformed=new({fs={['/']={type='dir'},['/a']={type='file',text='kept'}}},51,19)
  local lm={version=1}; assert(Scheduler.step(malformed,lm,1,0,true)); local m=driver(malformed,lm)
  m.command('mkdir b'); while malformed.job.phase~='publish' do m.step() end
  local retained=malformed.disk; local forged=malformed.job
  forged.paths[2]=forged.paths[1]
  local before_index=packed(malformed)
  check('zero-credit duplicate index audit leaves original job untouched',not Shell.handle(malformed,{n=1,'advance'},function() return false end)
    and packed(malformed)==before_index)
  m.tick=m.tick+1
  check('duplicate staged index preserves job and files in recovery',not Scheduler.step(malformed,lm,1,m.tick,true)
    and malformed.status=='recovery' and malformed.job==forged and malformed.disk==retained
    and malformed.disk.fs['/a'].text=='kept' and not malformed.disk.fs['/b'])
  malformed_sources[#malformed_sources+1]={shell=malformed,job=forged,disk=retained,before=packed(malformed)}
  -- Reboot replaces the event ownership object: scheduler must not decrement
  -- bytes or remove entries from the replacement queue after command return.
  local preserved=s.disk
  assert(Scheduler.start_timer(s,ledger,1,d.tick,10))
  d.send({n=2,'paste','reboot'})
  d.tick=d.tick+1; assert(Scheduler.push(s,ledger,1,d.tick,{n=2,'key',257})); assert(Scheduler.push(s,ledger,1,d.tick,{n=2,'char','DROP'}))
  assert(Scheduler.step(s,ledger,1,d.tick,true))
  check('reboot cleans owned session queue timers without losing disk',s.status=='boot' and s.disk==preserved and s.events.bytes==0
    and #s.events.queue==0 and s.events.timer_count==0 and #s.history==0)
  d.step(); check('explicit reboot boots once without import replacement',s.status=='ready' and s.disk==preserved and s.display.blink)
  d.command('shutdown'); local before_stop=packed(s)
  check('shutdown remains stopped with empty owned input and same disk',s.status=='stopped' and s.disk==preserved and s.events.bytes==0 and not s.display.blink)
  d.tick=d.tick+1; check('stopped scheduler does not silently reboot',not Scheduler.step(s,ledger,1,d.tick,true) and packed(s)==before_stop)
  -- Trusted explicit reboot event is added separately; no implicit start on input.
  assert(Shell.handle(s,{n=1,'boot'},function() return true end)); check('ordinary boot event cannot restart stopped computer',s.status=='stopped')
  local restarted=new(nil,51,19); local restart_ledger={version=1}
  assert(Scheduler.step(restarted,restart_ledger,1,0,true))
  local r=driver(restarted,restart_ledger); r.command('shutdown')
  local stopped=packed(restarted)
  check('stopped ordinary input is rejected without retention',not Scheduler.push(restarted,restart_ledger,1,r.tick,{n=2,'char','x'}) and packed(restarted)==stopped)
  r.send({n=1,'reboot'}); r.step()
  check('authorized explicit reboot event can restart stopped session',restarted.status=='ready' and restarted.display.blink and restarted.events.bytes==0)
  local saved=new(disk,51,19); local l3={version=1}; tick=0
  while saved.status=='initializing' do assert(Scheduler.step(saved,l3,1,tick,true)); tick=tick+1 end
  local cold=driver(saved,l3,tick); cold.command('mv source finished')
  while saved.job.phase~='publish' do cold.step() end
  local job=saved.job; local old=saved.disk
  assert(Budget.admit(l3,1,{execution=Budget.remaining(l3,1,'execution')}))
  return {shell=saved,ledger=l3,tick=cold.tick,before=packed(saved),budget=packed(l3),job=job,staging=job.nodes,disk=old,
    completed=s,completed_disk=s.disk,stopped=packed(s),malformed_sources=malformed_sources}
end
function M.reload(saved,check)
  for i,retained in ipairs(saved.malformed_sources) do
    local probe=retained.shell
    check('cold malformed source recovery is retained '..i,packed(probe)==retained.before and probe.job==retained.job
      and probe.disk==retained.disk and probe.status=='recovery' and not probe.disk.fs['/candidate'])
  end
  local s=saved.shell
  check('cold unpublished filesystem job retains exact aliases counters and old disk',packed(s)==saved.before and packed(saved.ledger)==saved.budget
    and s.job==saved.job and s.job.nodes==saved.staging and s.disk==saved.disk)
  check('cold final publication cannot refresh exhausted credits',not Scheduler.step(s,saved.ledger,1,saved.tick,true) and packed(s)==saved.before)
  local d=driver(s,saved.ledger,saved.tick); d.step()
  check('cold atomic move publishes once with no source loss',s.job==nil and s.disk.fs['/finished/sub/b'].text=='B' and not s.disk.fs['/source'])
  local installed=s.disk
  d.tick=d.tick+1; Scheduler.step(s,saved.ledger,1,d.tick,true)
  check('published filesystem operation is not replayed',s.disk==installed)
  check('cold stopped completed disk is unchanged',packed(saved.completed)==saved.stopped and saved.completed.disk==saved.completed_disk
    and saved.completed.disk.fs['/source/a'].text=='A' and saved.completed.status=='stopped')
end
return M
