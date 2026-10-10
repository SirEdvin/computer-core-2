-- Exercise live lifecycle disk consumers with real engine entities, no GUI mocks.
local L = require('__computer_core_2__.scripts.lifecycle')
local R = require('__computer_core_2__.scripts.os_runtime')
local VM = require('__computer_core_2__.scripts.guest.vm')
local Compiler = require('__computer_core_2__.scripts.guest.compiler')
local M = {}
function M.initial(check)
  L.init()
  local surface=game.surfaces[1]
  surface.request_to_generate_chunks({80,80},1)
  surface.force_generate_chunk_requests()
  for _,entity in ipairs(surface.find_entities_filtered{area={{75,75},{95,85}},type={'tree','simple-entity'}}) do entity.destroy() end
  local source=assert(surface.create_entity{name='computer-interface-entity',position={80,80},force='player'})
  source.energy=5000000
  local c=L.build(source)
  c.fs['/startup.lua']={type='file',text='error("legacy startup must not run")'}
  c.fs['/rc']={type='dir'}
  c.fs['/rc/user.lua']={type='file',text='legacy ROM collision'}
  c.process={source='error("legacy callback must not run")'}
  storage.drafts[1]={saved={id=c.id,path='/draft.lua',draft='unsaved legacy text'}}
  R.migrate(c)
  check('migration retains originals and retires callbacks without invoking them',c.process==nil and c.legacy_program.source~=nil and c.legacy_files['/startup.lua'].text=='error("legacy startup must not run")' and c.fs['/startup.lua']==nil and c.fs['/legacy-startup.lua']~=nil)
  check('migration recovers ROM collision and unsaved draft',c.migration_notice and c.fs['/legacy-recovery/rc/user.lua'].text=='legacy ROM collision' and c.fs['/legacy-recovery/draft-1.lua'].text=='unsaved legacy text')
  local old=c.fs
  c.guest=VM.new(assert(Compiler.compile([[
    fs.makeDir('/new')
    local f=assert(io.open('/new/value','w')); f:write('first'); f:close()
    fs.copy('/new','/copy'); fs.move('/copy','/moved')
    f=assert(io.open('/moved/value','w')); f:write('latest'); f:close()
    fs.delete('/new/value')
  ]])) ,nil,{fs=c.fs})
  local status=VM.run(c.guest,10000)
  assert(status=='dead','disk-consumer fixture did not finish')
  check('guest tree publication replaces the disk alias',c.fs==old and c.fs~=c.guest.disk.fs)
  local snapshot=L.snapshot(c).computer_core_2.fs
  check('snapshot uses current disk without reboot',snapshot['/moved/value'].text=='latest' and snapshot['/new/value']==nil and snapshot['/copy']==nil)
  local destination=assert(surface.create_entity{name='computer-interface-entity',position={90,80},force='player'})
  L.clone(source,destination)
  local clone=storage.computers[storage.units[destination.unit_number]]
  check('clone uses current disk without reboot',clone.fs['/moved/value'].text=='latest' and clone.fs['/new/value']==nil and clone.fs['/copy']==nil)
  clone.os_stopped=true
  R.tick()
  check('live dispatch refreshes the host disk alias',c.fs==c.guest.disk.fs)
  storage.live_disk_probe=c.id
end
function M.reload(check)
  local c=storage.computers[storage.live_disk_probe]
  local disk=L.snapshot(c).computer_core_2.fs
  check('current live disk snapshot survives process reload',disk['/moved/value'].text=='latest' and disk['/new/value']==nil)
  check('legacy recovery and retired callback archive survive reload',disk['/legacy-recovery/rc/user.lua'].text=='legacy ROM collision' and disk['/legacy-recovery/draft-1.lua'].text=='unsaved legacy text' and c.process==nil and c.legacy_files['/startup.lua']~=nil)
end
return M
