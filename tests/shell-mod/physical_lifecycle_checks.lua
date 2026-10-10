-- Real engine bodies through production lifecycle/runtime modules with isolated
-- host storage; separate actual control/remote registration probes are included.
-- Not graphical or joining-peer acceptance.
local L=require('__computer_core_2__.scripts.lifecycle')
local R=require('__computer_core_2__.scripts.os_runtime')
local VM=require('__computer_core_2__.scripts.guest.vm')
local Compiler=require('__computer_core_2__.scripts.guest.compiler')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local ShellScheduler=require('__computer_core_2__.scripts.shell.scheduler')

local M={}
local function packed(value) return serpent.line(value,{sortkeys=true}) end
local function reporting(check)
  local fixture=storage
  return function(name,value)
    local old=storage; storage=fixture
    local ok,err=pcall(check,name,value); storage=old; assert(ok,err)
  end
end
local function host(m,fn)
  local old=storage; storage=m.host
  local ok,a,b=pcall(fn); storage=old; assert(ok,a); return a,b
end
local function body(name,x)
  return assert(game.surfaces[1].create_entity{name=name,position={x,64},force=game.forces.player,raise_built=false})
end
local function blue(x) return body('blue-computer-interface-entity',x) end
local function metadata(entity)
  for _,id in ipairs(remote.call('computer_core_2','getComputerIDs')) do
    local c=remote.call('computer_core_2','getComputer',id)
    if c.model==entity.name and c.position.x==entity.position.x and c.position.y==entity.position.y then return c end
  end
end
function M.initial(check)
  check=reporting(check)
  local m={host={},phase=1}
  host(m,L.init)
  local disk={fs={['/']={type='dir'},['/data']={type='file',text=string.rep('payload ',256)}}}
  for i=1,32 do disk.fs['/file'..i]={type='file',text='committed '..i} end
  host(m,function()
    m.source=assert(L.build(blue(60),{computer_core_2=disk})); m.source.entity.energy=5000000
    m.vm=assert(L.build(body('computer-interface-entity',48))); m.vm.entity.energy=5000000
    m.vm.terminal_schema=1
    m.vm.guest=VM.new(assert(Compiler.compile('local _,text=os.pullEvent("char"); term.write(text); while true do os.pullEvent("char") end','=physical-lifecycle-vm')),nil,nil,{columns=51,rows=19},true)
    m.vm.fs=m.vm.guest.disk.fs
    check('blue build selects shell and has no VM or world peripherals',m.source.backend=='event-shell' and not m.source.guest and not m.source.sub
      and m.source.shell.status=='initializing' and m.source.shell.job.kind=='import' and R.files(m.source)==nil)
    local fresh=blue(72); m.fresh=assert(L.build(fresh)); fresh.energy=5000000
    check('ordinary blue placement gets fresh identity and initializing readback',m.fresh.id~=m.source.id and m.fresh.backend=='event-shell' and R.status(m.fresh)=='initializing' and not R.files(m.fresh))
    local snapshot,export_error=L.snapshot(m.source)
    check('unfinished physical blueprint export refuses rather than copying staging',snapshot==nil and export_error:find('not ready',1,true))
    local duplicate,duplicate_error=L.clone(m.source.entity,m.fresh.entity)
    check('clone refuses already registered destination without destroying owned state',duplicate==nil and duplicate_error=='Clone destination is already registered'
      and m.fresh.entity.valid and m.host.computers[m.fresh.id]==m.fresh)
    duplicate,duplicate_error=L.clone(m.source.entity,m.vm.entity)
    check('cross-backend clone refuses registered VM destination without destroying source or VM',not duplicate and duplicate_error=='Clone destination is already registered'
      and m.source.entity.valid and m.vm.entity.valid and m.host.computers[m.vm.id]==m.vm)
    local denied=blue(84); local copied,err=L.clone(m.source.entity,denied)
    check('unfinished blue clone refuses before identity allocation or VM fallback',not copied and not denied.valid and err:find('not ready',1,true) and m.host.next_computer==3)
    for i,payload in ipairs({false,{fs={['/']={type='dir'}},job={kind='execute'}},{fs={['/']={type='dir'},['/bad']={type='file',text=function() end}}}}) do
      local rejected=assert(L.build(blue(96+12*i),{computer_core_2=payload}))
      check('malicious physical blueprint envelope rejected '..i,rejected.os_error and not rejected.shell and not R.files(rejected))
      L.remove(rejected.id); rejected.entity.destroy{raise_destroy=true}
    end
  end)
  local public=assert(game.surfaces[1].create_entity{name='blue-computer-interface-entity',position={72,24},force=game.forces.player,raise_built=true})
  public.energy=5000000; m.public=public; m.public_id=assert(metadata(public)).id
  check('actual built event and remote metadata register the blue shell model',metadata(public).backend=='event-shell' and metadata(public).status=='initializing')
  return m
end
function M.prepare(m,check)
  check=reporting(check)
  if m.prepared then return true end
  host(m,function() L.tick(); R.tick() end)
  if not m.source.shell or m.source.shell.status~='ready' or not m.fresh.shell or m.fresh.shell.status~='ready' then return false end
  if m.phase==1 then
    host(m,function()
      check('physical VM application suspends beside actual blue bodies',m.vm.guest.objects[m.vm.guest.main.ref].status=='waiting' and m.vm.guest.instructions>0)
      assert(R.event(m.source,{n=2,'paste','cat /data'})); assert(R.event(m.source,{n=2,'key',257}))
    end)
    m.phase=2; return false
  end
  if not m.source.shell.job then return false end
  host(m,function()
    local source=m.source
    assert(ShellScheduler.start_timer(source.shell,m.host.terminal_scheduler,source.id,game.tick,10))
    assert(R.event(source,{n=2,'char','Z'}))
    m.clone=assert(L.clone(source.entity,blue(84))); m.clone.entity.energy=5000000
    local tags=assert(L.snapshot(source))
    m.blueprint=assert(L.build(blue(96),tags)); m.blueprint.entity.energy=5000000
    tags.computer_core_2.fs['/data'].text='outside'
    check('blue clone and blueprint start owned fresh import without input output jobs or timers',m.clone.id~=source.id and m.blueprint.id~=source.id
      and m.clone.shell.job.kind=='import' and m.blueprint.shell.job.kind=='import' and m.clone.shell.command=='' and m.clone.shell.events.timer_count==0
      and m.clone.shell.job~=source.shell.job and source.shell.job.kind=='cat' and source.shell.events.timer_count==1
      and #source.shell.events.queue==1 and #m.clone.shell.events.queue==0)
    local ledger=m.host.terminal_scheduler
    -- Supported retained import with a previous committed disk; explicit admitted
    -- setup, not a user-facing reimport command or automatic conversion.
    m.previous_disk=m.fresh.shell.disk
    local candidate={fs={['/']={type='dir'}}}
    for i=1,32 do candidate.fs['/unpublished'..i]={type='file',text='replacement'} end
    m.fresh.shell=assert(R.construct_shell(m.fresh.id,candidate)); m.fresh.shell.disk=m.previous_disk
    assert(ShellScheduler.step(m.fresh.shell,ledger,m.fresh.id,game.tick,true))
    local committed=assert(L.snapshot(m.fresh))
    check('pending import readback keeps previous disk and excludes actual staged nodes',m.fresh.shell.status=='initializing' and m.fresh.shell.job
      and next(m.fresh.shell.job.nodes)~=nil and R.files(m.fresh)==m.previous_disk.fs and not committed.computer_core_2.fs['/unpublished1'])
    m.oldclone=assert(L.clone(m.fresh.entity,blue(120))); m.oldclone.entity.energy=5000000
    check('clone during replacement import copies previous disk not source staging',m.oldclone.shell.job~=m.fresh.shell.job
      and m.oldclone.shell.job.count==1 and m.oldclone.shell.job.source[1].path=='/')
    local next_id=m.host.next_computer+1
    assert(Budget.admit(ledger,next_id,{table=Budget.remaining(ledger,next_id,'table')}))
    local refused=blue(108)
    local copied,reason=L.clone(source.entity,refused)
    check('zero-credit clone destroys only uncommitted duplicate and preserves source identity/job',not copied and reason=='work deferred' and not refused.valid
      and m.host.next_computer+1==next_id and source.shell.job.kind=='cat')
    local before=packed(source.shell)
    assert(Budget.admit(ledger,source.id,{table=Budget.remaining(ledger,source.id,'table')}))
    local export,err=L.snapshot(source)
    check('exhausted readback refuses without disk or session mutation',not export and err=='work deferred' and packed(source.shell)==before)
    assert(R.event(m.vm,{n=2,'char','V'}))
    m.before_source=packed(source.shell); m.before_vm=packed(m.vm.guest); m.before_ledger=packed(ledger)
    m.before_fresh=packed(m.fresh.shell)
    m.source_job=source.shell.job; m.clone_job=m.clone.shell.job
    m.prepared=true
  end)
  local public=assert(metadata(m.public))
  check('actual powered blue placement reaches published shell disk through production ticks',public.status=='ready' and public.backend_version==2 and public.fs['/'].type=='dir')
  local tags=assert(remote.call('computer_core_2','snapshot',m.public_id))
  m.public_clone=assert(m.public.clone{position={84,24},surface=m.public.surface,force=m.public.force})
  local ghost=assert(m.public.surface.create_entity{name='entity-ghost',inner_name='blue-computer-interface-entity',position={96,24},force=m.public.force})
  ghost.tags=tags
  local _,rebuilt=ghost.revive{raise_revive=true}; m.public_blueprint=assert(rebuilt)
  m.public_clone.energy=5000000; rebuilt.energy=5000000
  local clone_meta=assert(metadata(m.public_clone)); local rebuilt_meta=assert(metadata(rebuilt))
  m.public_clone_id=clone_meta.id; m.public_blueprint_id=rebuilt_meta.id
  check('real entity clone and tagged ghost revival select fresh blue initializing records',clone_meta.id~=m.public_id and rebuilt_meta.id~=m.public_id
    and clone_meta.backend=='event-shell' and rebuilt_meta.backend=='event-shell' and clone_meta.status=='initializing' and rebuilt_meta.status=='initializing'
    and clone_meta.fs==nil and rebuilt_meta.fs==nil)
  local bad=assert(m.public.surface.create_entity{name='entity-ghost',inner_name='blue-computer-interface-entity',position={108,24},force=m.public.force})
  bad.tags={computer_core_2={fs={['/']={type='dir'},['/../escape']={type='file',text='not installed'}}}}
  local _,rejected=bad.revive{raise_revive=true}; m.rejected=assert(rejected); rejected.energy=5000000
  m.rejected_id=assert(metadata(rejected)).id
  return true
end
function M.observe(m)
  if not m.prepared then return end
  assert(packed(m.source.shell)==m.before_source and packed(m.vm.guest)==m.before_vm and packed(m.host.terminal_scheduler)==m.before_ledger,'physical state or work changed on load')
  assert(m.source.shell.job==m.source_job and m.clone.shell.job==m.clone_job,'physical job identity changed on load')
  assert(packed(m.fresh.shell)==m.before_fresh and m.fresh.shell.disk==m.previous_disk,'previous disk/import changed on load')
end
function M.resume(m,check)
  check=reporting(check)
  if m.done then return true end
  if not m.cleaned then
    host(m,function() L.tick(); R.tick() end)
    if m.clone.shell.status~='ready' or m.blueprint.shell.status~='ready' or m.oldclone.shell.status~='ready' or m.fresh.shell.status~='ready' or m.source.shell.job then return false end
    host(m,function()
      check('cold actual-body clones publish only committed data with independent nodes',R.files(m.clone)['/data'].text==string.rep('payload ',256)
        and R.files(m.blueprint)['/data'].text==R.files(m.source)['/data'].text and R.files(m.clone)['/data']~=R.files(m.source)['/data'])
      check('suspended physical VM resumes queued input without conversion',m.vm.guest.display.lines[1].text:sub(1,1)=='V' and R.backend(m.vm)=='vm')
      check('previous-disk import switches readback only after atomic replacement',m.fresh.shell.disk~=m.previous_disk and R.files(m.fresh)['/unpublished1'].text=='replacement')
      check('previous-disk clone never publishes unrelated replacement staging',R.files(m.oldclone)['/unpublished1']==nil and R.files(m.oldclone)['/'].type=='dir')
      local vm=m.vm.guest; local vm_body=m.vm.entity; local id=m.source.id; local unit=m.source.unit_number
      L.remove(id); m.source.entity.destroy{raise_destroy=true}
      check('blue removal cleans owned scheduler and unit only',not m.host.computers[id] and not m.host.units[unit]
        and not m.host.terminal_scheduler.machines[id] and m.vm.guest==vm and vm_body.valid and m.clone.entity.valid)
      for _,c in ipairs({m.vm,m.fresh,m.clone,m.blueprint,m.oldclone}) do L.remove(c.id); c.entity.destroy{raise_destroy=true} end
    end)
    m.cleaned=true
  end
  local clone_meta=remote.call('computer_core_2','getComputer',m.public_clone_id)
  local rebuilt_meta=remote.call('computer_core_2','getComputer',m.public_blueprint_id)
  if clone_meta.file_error=='work deferred' or rebuilt_meta.file_error=='work deferred' then return false end
  check('actual control clone and blueprint publish after cold resume',clone_meta.status=='ready' and rebuilt_meta.status=='ready'
    and clone_meta.fs and clone_meta.fs['/'].type=='dir' and rebuilt_meta.fs and rebuilt_meta.fs['/'].type=='dir')
  local rejected=remote.call('computer_core_2','getComputer',m.rejected_id)
  check('actual malicious ghost import recovers without partial or empty replacement disk',rejected.status=='recovery' and rejected.fs==nil and rejected.file_error)
  m.public.destroy{raise_destroy=true}; m.public_clone.destroy{raise_destroy=true}; m.public_blueprint.destroy{raise_destroy=true}; m.rejected.destroy{raise_destroy=true}; m.done=true
  return true
end
return M
