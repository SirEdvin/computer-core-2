-- Production runtime/readback consumers with isolated storage, not blue-model or
-- real GUI acceptance. All global overrides are restored before reporting.
local R=require('__computer_core_2__.scripts.os_runtime')
local L=require('__computer_core_2__.scripts.lifecycle')
local Shell=require('__computer_core_2__.scripts.shell.runtime')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local VMScheduler=require('__computer_core_2__.scripts.guest.scheduler')
local VM=require('__computer_core_2__.scripts.guest.vm')
local Compiler=require('__computer_core_2__.scripts.guest.compiler')
local Boot=require('__computer_core_2__.scripts.guest.boot')
local new=require('construct')
local M={}
local function packed(value) return serpent.line(value,{sortkeys=true}) end
function M.initial(check)
  local reports={}
  local function test(name,condition) assert(condition,name); reports[#reports+1]=name end
  local vm=VM.new(assert(Compiler.compile('return 1','=production-routing')))
  local s=new({fs={['/']={type='dir'},['/data']={type='file',text='retained'}}},51,19)
  local c={id=401,backend='event-shell',shell=s,guest=vm,fs={['/']={type='dir'}},entity={valid=true,electric_buffer_size=100,energy=0}}
  local unknown={id=402,backend='native',guest=vm,fs=c.fs,experiment={version=5,retained=17},entity=c.entity}
  local invalid={id=403,backend='event-shell',shell=new(nil,51,19),guest=vm,fs=c.fs,entity=c.entity}
  invalid.shell.version=99
  local personal={id=404,personal=true,backend='event-shell',shell=s,guest=vm,fs=c.fs}
  local real_storage,real_game=storage,game
  local original_boot,original_run=Boot.new,VM.run
  local ok,err=pcall(function()
    game={tick=10}; storage={computers={[401]=c,[402]=unknown,[403]=invalid,[404]=personal},sessions={}}
    local before={packed(c),packed(unknown),packed(invalid),packed(personal)}
    Boot.new=function() error('non-VM production record entered VM boot',0) end
    VM.run=function() error('non-VM production record entered VM execution',0) end
    storage.terminal_scheduler=VMScheduler.new()
    VMScheduler.add(storage.terminal_scheduler,c.id,vm) -- Stale scheduler registration must be removed, not executed.
    R.init(); R.tick()
    test('production migration and VM traversal preserve shell unknown invalid and personal-shell records',packed(c)==before[1]
      and packed(unknown)==before[2] and packed(invalid)==before[3] and packed(personal)==before[4]
      and #storage.terminal_scheduler.order==0 and vm.instructions==0)
    local tags,reason=L.snapshot(c)
    test('production snapshot explicitly refuses unfinished import instead of exporting stale VM files',tags==nil and reason:find('not ready',1,true)
      and R.files(c)==nil and R.display(c)==s.display and R.status(c)=='initializing')
    storage.units={[81]=c.id}
    local notice,destroyed
    local source={valid=true,unit_number=81,force={print=function(text) notice=text end}}
    local duplicate={valid=true,name='computer-interface-entity'}
    duplicate.destroy=function(options) destroyed=options.raise_destroy; duplicate.valid=false end
    local cloned,clone_error=L.clone(source,duplicate)
    test('production clone refuses unfinished source before allocating a VM fallback',cloned==nil and clone_error:find('not ready',1,true)
      and destroyed and not duplicate.valid and notice:find('clone unavailable',1,true) and packed(c)==before[1] and storage.next_computer==nil)
    local untouched=packed(unknown)
    test('unsupported production input reboot and shutdown refuse without fallback',not R.event(unknown,{n=2,'char','X'})
      and not R.reboot(unknown) and not R.shutdown(unknown) and packed(unknown)==untouched and R.status(unknown)=='recovery')
    c.entity.energy=100; local unpowered=packed(c); c.entity.energy=0; local paused=packed(c)
    test('production shell ingress refuses while unpowered without retaining input',not R.event(c,{n=2,'char','X'}) and packed(c)==paused)
    c.entity.energy=100; assert(packed(c)==unpowered)
    assert(Scheduler.step(s,storage.terminal_scheduler,c.id,11,true)); game.tick=12
    duplicate.valid=true; destroyed=nil; local initialized=packed(c)
    cloned,clone_error=L.clone(source,duplicate)
    test('production clone rejects copying a ready shell into the original VM model',cloned==nil and clone_error:find('cannot be cloned',1,true)
      and destroyed and not duplicate.valid and packed(c)==initialized and storage.next_computer==nil)
    test('production shell ingress reaches only the selected session',R.event(c,{n=2,'char','X'}) and #s.events.queue==1 and #vm.events.queue==0)
    assert(Scheduler.step(s,storage.terminal_scheduler,c.id,12,true))
    test('selected shell consumes production ingress without VM execution',s.command=='X' and vm.instructions==0)
    assert(R.shutdown(c)); assert(Scheduler.step(s,storage.terminal_scheduler,c.id,13,true)); game.tick=14
    test('production shell shutdown routes to owned lifecycle without destroying stale VM recovery graph',s.status=='stopped' and c.guest==vm
      and c.os_stopped==nil and not R.running(c))
    assert(R.reboot(c)); assert(Scheduler.step(s,storage.terminal_scheduler,c.id,14,true))
    assert(Scheduler.step(s,storage.terminal_scheduler,c.id,15,true)); game.tick=15
    test('production explicit shell reboot preserves committed disk without VM conversion',s.status=='ready' and s.command=='' and c.guest==vm)
    local tags=assert(L.snapshot(c))
    tags.computer_core_2.fs['/data'].text='outside'
    test('production snapshot copies current committed files defensively',R.files(c)==s.disk.fs and s.disk.fs['/data'].text=='retained')
    c.shell.disk={fs={['/']={type='dir'},['/replacement']={type='file',text='published'}},cwd='/',nodes=2,bytes=9,paths={'/','/replacement'}}
    tags=assert(L.snapshot(c))
    test('production snapshot resolves replacement disk rather than boot-time aliases',tags.computer_core_2.fs['/replacement'].text=='published'
      and not tags.computer_core_2.fs['/data'] and not c.fs['/replacement'])
  end)
  Boot.new,VM.run=original_boot,original_run
  storage,game=real_storage,real_game
  assert(ok,err)
  for _,name in ipairs(reports) do check(name,true) end
  local body=assert(game.surfaces[1].create_entity{name='computer-interface-entity',position={24,24},force=game.forces.player,raise_built=true})
  local public
  for _,id in ipairs(remote.call('computer_core_2','getComputerIDs')) do
    local metadata=remote.call('computer_core_2','getComputer',id)
    if metadata.position.x==body.position.x and metadata.position.y==body.position.y then public=metadata; break end
  end
  check('actual production remote metadata identifies unchanged VM model and preserves prior fields',public and public.backend=='vm'
    and public.model=='computer-interface-entity' and public.status=='boot' and not public.running and public.backend_version==nil
    and public.fs['/'].type=='dir' and public.force_index==body.force.index and public.surface_index==body.surface.index)
  public.fs['/'].type='file'
  check('actual production remote files remain defensive data copies',remote.call('computer_core_2','getComputer',public.id).fs['/'].type=='dir')
  return {computer=c,unknown=unknown,invalid=invalid,personal=personal,public_id=public.id,body=body,
    before=packed(c),unknown_before=packed(unknown),invalid_before=packed(invalid),personal_before=packed(personal)}
end
function M.observe(saved)
  assert(packed(saved.computer)==saved.before and packed(saved.unknown)==saved.unknown_before
    and packed(saved.invalid)==saved.invalid_before and packed(saved.personal)==saved.personal_before,'production routing records changed on load')
end
function M.reload(saved,check)
  M.observe(saved)
  local c=saved.computer
  check('cold production consumers retain authoritative shell files and unchanged unsupported records',R.files(c)==c.shell.disk.fs
    and R.display(c)==c.shell.display and R.status(c)=='ready' and R.status(saved.unknown)=='recovery' and R.status(saved.invalid)=='recovery')
  local tags,err=L.snapshot(saved.invalid)
  check('cold incompatible snapshot reports recovery without publishing a VM fallback',tags==nil and err:find('Incompatible',1,true))
  local metadata=remote.call('computer_core_2','getComputer',saved.public_id)
  check('actual cold production remote metadata preserves VM identity and authoritative files',saved.body.valid and metadata.id==saved.public_id
    and metadata.backend=='vm' and metadata.model=='computer-interface-entity' and metadata.fs['/'].type=='dir')
  saved.body.destroy{raise_destroy=true}
end
return M
