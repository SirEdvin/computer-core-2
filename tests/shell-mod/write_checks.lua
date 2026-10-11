local Shell=require('__computer_core_2__.scripts.shell.runtime')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local FileJob=require('__computer_core_2__.scripts.shell.file_job')
local Import=require('__computer_core_2__.scripts.shell.import')
local FS=require('__computer_core_2__.scripts.filesystem')
local new=require('construct')
local M={}
local function packed(value) return serpent.line(value,{sortkeys=true}) end
local function driver(s,ledger,tick)
  local d={tick=tick or 0}
  function d.step()
    d.tick=d.tick+1
    assert(Scheduler.step(s,ledger,1,d.tick,true))
    assert(s.status~='recovery',s.recovery and s.recovery.message)
  end
  function d.write(path,text,base)
    d.tick=d.tick+1; Budget.begin(ledger,d.tick)
    assert(Budget.admit(ledger,1,{execution=1,table=Import.envelope_cost()+256,string=4*FileJob.write_bytes,filesystem=32768}))
    s.job=FileJob.write(s,path,text,base)
  end
  function d.publish()
    local turns=0
    while s.job do d.step(); turns=turns+1; assert(turns<20000) end
  end
  return d
end
local function setup(disk)
  local s,ledger=new(disk,51,19),{version=1}
  local tick=0
  while s.status=='initializing' do assert(Scheduler.step(s,ledger,1,tick,true)); tick=tick+1 end
  return s,ledger,driver(s,ledger,tick)
end
function M.initial(check)
  local source={fs={['/']={type='dir'},['/work']={type='dir'},['/work/a.lua']={type='file',text='old'},['/keep']={type='file',text='keep'}}}
  local s,ledger,d=setup(source)
  local old=s.disk
  d.write('/work/a.lua','new\nsource','old')
  check('write captures a plain owned candidate while committed data remains old',s.disk==old and s.disk.fs['/work/a.lua'].text=='old' and s.job.origin==old)
  d.publish()
  check('write atomically replaces only the target and keeps unrelated files',s.disk~=old and s.disk.fs['/work/a.lua'].text=='new\nsource' and s.disk.fs['/keep'].text=='keep' and old.fs['/work/a.lua'].text=='old')
  d.write('/work/new.lua','return {}',false); d.publish()
  check('write creates a new local source in an existing parent',s.disk.fs['/work/new.lua'].text=='return {}')
  for _,case in ipairs({{'/','x',false},{'/rom/help.txt','x',false},{'/work','x',false},{'/missing/a','x',false},
    {'/work/new.lua','x','stale'},{'/wide',''..string.rep('x',FileJob.write_bytes+1),false}}) do
    local before=packed(s.disk)
    local ok=pcall(d.write,table.unpack(case))
    check('write refuses invalid destination or baseline '..case[1],not ok and packed(s.disk)==before and s.job==nil)
  end
  d.write('/work/new.lua','candidate','return {}')
  local pending=packed(s)
  Budget.begin(ledger,d.tick); assert(Budget.admit(ledger,1,{execution=Budget.remaining(ledger,1,'execution')}))
  check('zero-credit save work preserves draft candidate and committed disk',not Scheduler.step(s,ledger,1,d.tick,true) and packed(s)==pending)
  d.publish()
  check('save retries after legitimate later-tick credits',s.disk.fs['/work/new.lua'].text=='candidate')
  d.write('/work/new.lua','lost','candidate')
  s.disk.fs['/work/new.lua'].text='external edit'
  d.publish()
  check('changed target rejects save without overwriting external bytes',s.disk.fs['/work/new.lua'].text=='external edit' and s.status=='ready')
  d.write('/work/new.lua','lost','external edit')
  local changed=s.disk
  local fresh={}; for key,value in pairs(changed) do fresh[key]=value end
  fresh.fs={}; for key,value in pairs(changed.fs) do fresh.fs[key]=value end
  fresh.fs['/another']={type='file',text='another writer'}; s.disk=fresh
  d.publish()
  check('changed disk refuses stale candidate without losing unrelated newer files',s.disk==fresh and s.disk.fs['/another'].text=='another writer' and s.disk.fs['/work/new.lua'].text=='external edit')
  local inventory={fs={['/']={type='dir'}}}
  for i=1,FS.max_nodes-1 do
    local suffix=tostring(i)
    inventory.fs['/'..string.rep('p',1023-#suffix)..suffix]={type='file',text=''}
  end
  local maximum,maxledger,maxdriver=setup(inventory)
  local path=next(maximum.disk.fs)
  if path=='/' then path=next(maximum.disk.fs,path) end
  maxdriver.write(path,string.rep('z',FileJob.write_bytes),''); maxdriver.publish()
  check('maximum accepted path metadata and editable bytes save without shrinking inventory',maximum.disk.nodes==FS.max_nodes and #maximum.disk.fs[path].text==FileJob.write_bytes)
  local full,_,fd=setup({fs={['/']={type='dir'},['/full']={type='file',text=string.rep('f',FS.max_bytes)}}})
  old=full.disk; fd.write('/extra','x',false); fd.publish()
  check('full filesystem rejects staged growth without truncation',full.disk==old and #full.disk.fs['/full'].text==FS.max_bytes and not full.disk.fs['/extra'])
  d.write('/work/new.lua','after cold save','external edit')
  while s.job.phase~='publish' do d.step() end
  local candidate,committed=s.job,s.disk
  Budget.begin(ledger,d.tick); assert(Budget.admit(ledger,1,{execution=Budget.remaining(ledger,1,'execution')}))
  return {shell=s,ledger=ledger,tick=d.tick,job=candidate,disk=committed,before=packed(s),budget=packed(ledger),
    completed=maximum,installed=maximum.disk,completed_before=packed(maximum)}
end
function M.observe(saved)
  assert(packed(saved.shell)==saved.before and packed(saved.ledger)==saved.budget,'write mutated on load')
  assert(packed(saved.completed)==saved.completed_before,'published write replayed on load')
end
function M.reload(saved,check)
  M.observe(saved)
  local s=saved.shell
  check('cold pending write retains original disk candidate and same-tick ledger aliases',s.job==saved.job and s.disk==saved.disk and s.job.origin==saved.disk)
  check('cold pending write cannot renew exhausted same-tick credits',not Scheduler.step(s,saved.ledger,1,saved.tick,true) and packed(s)==saved.before)
  local d=driver(s,saved.ledger,saved.tick); d.step()
  check('cold pending write publishes once after valid new credits',s.job==nil and s.disk.fs['/work/new.lua'].text=='after cold save' and s.disk.fs['/another'].text=='another writer')
  local installed=s.disk; d.tick=d.tick+1; Scheduler.step(s,saved.ledger,1,d.tick,true)
  check('published write is not replayed after cold resumption',s.disk==installed and saved.completed.disk==saved.installed and packed(saved.completed)==saved.completed_before)
end
return M
