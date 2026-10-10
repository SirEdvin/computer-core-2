local Shell=require('__computer_core_2__.scripts.shell.runtime')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local Import=require('__computer_core_2__.scripts.shell.import')
local FS=require('__computer_core_2__.scripts.filesystem')
local VM=require('__computer_core_2__.scripts.guest.vm')
local Compiler=require('__computer_core_2__.scripts.guest.compiler')
local VMScheduler=require('__computer_core_2__.scripts.guest.scheduler')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local new=require('construct')
local M={}
local function packed(value) return serpent.line(value,{sortkeys=true}) end
function M.initial(check)
  local invalid,reason=Import.capture(false)
  check('false import envelope is rejected rather than booting an empty replacement',invalid==nil and reason=='invalid import envelope')
  local ledger={version=1}
  Budget.begin(ledger,10)
  assert(Budget.admit(ledger,7,{execution=Limits.instructions_per_tick}))
  local source={fs={['/']={type='dir'}}}
  local before=packed(ledger)
  check('creation cannot retain data or repaint without credits',not Scheduler.new(source,51,19,ledger,2,10) and packed(ledger)==before)
  local original_path=FS.path
  local path_calls=0
  FS.path=function(...) path_calls=path_calls+1; return original_path(...) end
  local state=assert(Scheduler.new(source,51,19,ledger,2,11))
  FS.path=original_path
  check('paid envelope does no canonical whole-tree work',path_calls==0 and ledger.table_budget.machines[2].used>0
    and ledger.execution_budget.machines[2].instructions==1 and state.status=='initializing' and state.disk==nil)
  check('unfinished disk readback is explicitly not ready',Shell.committed_disk(state)==nil)
  before=packed(state)
  check('typing during initialization is refused without retention',not Scheduler.push(state,ledger,2,11,{n=2,'char','x'}) and packed(state)==before)
  assert(Scheduler.step(state,ledger,2,11,true))
  check('default admitted import completes and installs once',state.status=='ready' and state.job==nil and state.disk.nodes==1
    and Shell.committed_disk(state)==state.disk)
  -- Version-1 compatible sessions keep their identity/version, with no migration.
  state.version=1; local disk=state.disk
  assert(Scheduler.push(state,ledger,2,12,{n=2,'char','v'})); assert(Scheduler.step(state,ledger,2,12,true))
  check('compatible old session is not reconstructed or upgraded',state.version==1 and state.disk==disk and state.command=='v')
  local bad_source={fs={['/']={type='dir'},['/../escape']={type='file',text='data'}}}
  local bad=new(bad_source,51,19); local job=bad.job
  assert(Shell.handle(bad,{n=1,'boot'},function() return true end))
  check('invalid canonical import keeps safe source but installs no disk',bad.status=='recovery' and bad.disk==nil and bad.job==job)
  bad=new({fs={['/']={type='dir'},['/missing/file']={type='file',text='data'}}},51,19)
  assert(Shell.handle(bad,{n=1,'boot'},function() return true end))
  check('missing import parent never publishes a partial disk',bad.status=='recovery' and bad.disk==nil)
  bad=new(nil,51,19); job=bad.job; bad.job.version=99
  check('unsupported import version retains its graph',not Shell.handle(bad,{n=1,'boot'},function() return true end)
    and bad.status=='recovery' and bad.job==job and bad.job.version==99)
  bad=new(nil,51,19); bad.job.cursor=2
  check('completed-looking forged cursor cannot skip publication checks',not Shell.handle(bad,{n=1,'boot'},function() return true end) and bad.disk==nil)
  bad=new(nil,51,19); job=bad.job; bad.disk={fs={['/']={type='dir'}},cwd='/'}; bad.status='ready'
  check('import cannot masquerade as a normal output job',not Shell.handle(bad,{n=1,'advance'},function() return true end)
    and bad.status=='recovery' and bad.job==job)
  local source_tree={fs={['/']={type='dir'}}}
  for i=1,FS.max_nodes-1 do
    local suffix=tostring(i)
    source_tree.fs['/'..string.rep('x',1023-#suffix)..suffix]={type='file',text=''}
  end
  ledger=VMScheduler.new()
  local s=assert(Scheduler.new(source_tree,51,19,ledger,2,100))
  local source_bytes=s.job.metadata
  check('maximum path metadata retained separately from file bytes',s.job.count==FS.max_nodes and s.job.bytes==0
    and source_bytes>Limits.filesystem_work_per_computer and source_bytes<=Import.max_metadata)
  before=packed(s)
  assert(Budget.admit(ledger,2,{filesystem=Budget.remaining(ledger,2,'filesystem')}))
  check('zero filesystem credits preserve import and its aliases',not Scheduler.step(s,ledger,2,100,true) and packed(s)==before)
  assert(Scheduler.step(s,ledger,2,101,true))
  check('maximum import advances only its bounded canonical slice',s.job.cursor==Import.batch+1 and s.disk==nil and s.status=='initializing')
  assert(Scheduler.push(s,ledger,2,102,{n=3,'term_resize',43,8}))
  local cursor=s.job.cursor
  assert(Scheduler.step(s,ledger,2,102,true))
  check('initialization resize is serviced without another character or import slice',s.display.columns==43 and s.display.rows==8 and s.job.cursor==cursor)
  before=packed(s)
  check('unpowered import stays unchanged',not Scheduler.step(s,ledger,2,103,false) and packed(s)==before)
  local vm=VM.new(assert(Compiler.compile('local n=0; while true do n=n+1 end','=import-neighbor')))
  VMScheduler.add(ledger,1,vm)
  assert(Scheduler.step(s,ledger,2,104,true)); local work=VMScheduler.tick(ledger,104)
  check('maximum import leaves work for real VM neighbor',work>0 and ledger.execution_budget.machines[1].instructions>0
    and ledger.execution_budget.instructions<=Limits.instructions_per_tick and s.disk==nil)
  assert(Budget.admit(ledger,2,{execution=Budget.remaining(ledger,2,'execution')}))
  return {shell=s,ledger=ledger,before=packed(s),budget=packed(ledger),source=s.job.source,nodes=s.job.nodes,
    cursor=s.job.cursor,metadata=source_bytes,tick=104}
end
function M.reload(saved,check)
  local s,ledger=saved.shell,saved.ledger
  check('cold pending import preserves source staging and exact counters',packed(s)==saved.before and packed(ledger)==saved.budget
    and s.job.source==saved.source and s.job.nodes==saved.nodes and s.job.cursor==saved.cursor and s.disk==nil)
  local before=packed(s)
  check('cold import does not renew same-tick credits',not Scheduler.step(s,ledger,2,saved.tick,true) and packed(s)==before)
  local tick=saved.tick
  -- This is a synthetic-clock structural/resource oracle, not latency evidence.
  local turns=0
  while s.status=='initializing' and turns<2*FS.max_nodes do
    tick=tick+1; turns=turns+1
    assert(Scheduler.step(s,ledger,2,tick,true))
    local native=ledger.execution_budget.machines[2].instructions
    local work=VMScheduler.tick(ledger,tick)
    assert(work>0 and native>0 and ledger.execution_budget.instructions<=Limits.instructions_per_tick)
    assert(ledger.string_budget.machines[2].used<=Limits.string_work_per_computer)
    assert(ledger.filesystem_budget.machines[2].used<=Limits.filesystem_work_per_computer)
    assert(ledger.table_budget.machines[2].used<=Limits.table_work_per_computer)
    if s.status=='initializing' then assert(s.disk==nil and Shell.committed_disk(s)==nil) end
  end
  check('maximum metadata import publishes complete disk once',s.status=='ready' and s.job==nil and s.disk.nodes==FS.max_nodes
    and s.disk.bytes==0 and turns>1 and turns<2*FS.max_nodes)
  local source=saved.source
  for i=1,#source do assert(s.disk.fs[source[i].path] and s.disk.fs[source[i].path].type==source[i].node.type) end
  check('cold import loses no maximum-width paths',s.disk.fs['/'].type=='dir' and s.command=='' and s.display.blink)
  local disk=s.disk
  Scheduler.step(s,ledger,2,tick+1,true)
  check('installed disk is not republished or rebooted',s.disk==disk and s.job==nil)
end
return M
