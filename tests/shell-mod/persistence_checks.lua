-- Cold persisted peers are a deterministic-registry structural oracle, not a
-- substitute for an actual joining graphical client (the separate final gate).
local Shell=require('__computer_core_2__.scripts.shell.runtime')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local M={}
local function packed(value) return serpent.line(value,{sortkeys=true}) end
local function clone(value,seen)
  if type(value)~='table' then return value end
  seen=seen or {}; if seen[value] then return seen[value] end
  local out={}; seen[value]=out
  for k,v in pairs(value) do out[clone(k,seen)]=clone(v,seen) end
  return out
end
function M.initial(check)
  local source={fs={['/']={type='dir'}}}
  for i=1,20 do source.fs['/f'..i]={type='file',text='data'..i} end
  local ledger={version=1}
  local pending=assert(Scheduler.new(source,51,19,ledger,1,10))
  assert(Scheduler.step(pending,ledger,1,10,true))
  check('persistence oracle stops within actual admitted import',pending.status=='initializing' and pending.job.cursor>1 and pending.disk==nil)
  assert(Budget.admit(ledger,1,{execution=Budget.remaining(ledger,1,'execution')}))
  local previous=assert(Scheduler.new(nil,51,19,{version=1},1,0))
  assert(Shell.handle(previous,{n=1,'boot'},function() return true end))
  local committed=previous.disk
  previous.job=clone(pending.job); previous.status='initializing'
  check('pending replacement readback retains only previous committed disk',Shell.committed_disk(previous)==committed)
  local peer=clone({shell=pending,ledger=ledger})
  local invalid=clone(pending); invalid.job.version=99
  local retained=invalid.job
  check('unsupported persisted import visibly halts without replacement',not Shell.handle(invalid,{n=1,'boot'},function() return true end)
    and invalid.status=='recovery' and invalid.job==retained and invalid.disk==nil)
  local installed=assert(Scheduler.new(source,51,19,{version=1},1,0))
  for _=1,100 do
    if installed.status~='initializing' then break end
    assert(Shell.handle(installed,{n=1,'boot'},function() return true end))
  end
  check('post-publication state is separately persisted',installed.status=='ready' and installed.job==nil and installed.disk.nodes==21)
  return {shell=pending,ledger=ledger,peer=peer,previous=previous,previous_disk=committed,
    invalid=invalid,invalid_job=retained,installed=installed,installed_disk=installed.disk,
    before=packed(pending),budget=packed(ledger),peer_before=packed(peer),
    previous_before=packed(previous),invalid_before=packed(invalid),installed_before=packed(installed)}
end
function M.observe(saved)
  assert(packed(saved.shell)==saved.before and packed(saved.ledger)==saved.budget,'load changed pending import or credits')
  assert(packed(saved.peer)==saved.peer_before and packed(saved.previous)==saved.previous_before,'load changed structural peer or previous disk')
  assert(packed(saved.invalid)==saved.invalid_before and packed(saved.installed)==saved.installed_before,'load changed recovery or installed disk')
end
function M.reload(saved,check)
  M.observe(saved)
  local s,l=saved.shell,saved.ledger
  check('cold registry reconstruction preserves paired import records',packed(s)==packed(saved.peer.shell)
    and packed(l)==packed(saved.peer.ledger) and saved.invalid.job==saved.invalid_job and saved.invalid.disk==nil)
  check('cold paired imports cannot renew same-tick credits',not Scheduler.step(s,l,1,10,true)
    and not Scheduler.step(saved.peer.shell,saved.peer.ledger,1,10,true) and packed(s)==saved.before)
  local tick=10
  while s.status=='initializing' and tick<100 do
    tick=tick+1
    local a=Scheduler.step(s,l,1,tick,true)
    local b=Scheduler.step(saved.peer.shell,saved.peer.ledger,1,tick,true)
    assert(a==b and packed(s)==packed(saved.peer.shell) and packed(l)==packed(saved.peer.ledger),'paired reconstruction diverged')
  end
  check('cold structural peers publish equal complete disks and progress',s.status=='ready' and s.disk.nodes==21 and s.job==nil)
  local old=saved.previous_disk
  assert(Shell.committed_disk(saved.previous)==old)
  for _=1,100 do
    if saved.previous.status~='initializing' then break end
    assert(Shell.handle(saved.previous,{n=1,'boot'},function() return true end))
  end
  check('cold replacement publishes once without changing old committed graph',saved.previous.status=='ready'
    and saved.previous.disk~=old and old.nodes==1 and saved.previous.disk.nodes==21 and saved.previous.job==nil)
  local installed=saved.installed; local before=packed(installed)
  assert(not Shell.handle(installed,{n=1,'boot'},function() return false end))
  check('cold post-publication refusal preserves identity and effects',installed.disk==saved.installed_disk and packed(installed)==before)
  local display=packed(installed.display); local instructions=installed.instructions
  assert(Shell.handle(installed,{n=1,'boot'},function() return true end))
  check('cold initialized boot cannot duplicate publication or prompt',installed.disk==saved.installed_disk
    and installed.disk.nodes==21 and installed.instructions==instructions+1 and packed(installed.display)==display and installed.job==nil)
end
return M
