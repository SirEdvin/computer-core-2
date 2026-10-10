-- Safe malformed records are prepared through real admitted jobs, then saved.
-- Mutators/observers are trusted fixture code, never stored executable values.
local Shell=require('__computer_core_2__.scripts.shell.runtime')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local VM=require('__computer_core_2__.scripts.guest.vm')
local FS=require('__computer_core_2__.scripts.filesystem')
local M={}
local function packed(value) return serpent.line(value,{sortkeys=true}) end
local cases={
  {name='unknown import source field',import=true,mutate=function(job) job.source[#job.source].handler='scripts.guest.vm' end},
  {name='sparse import source',import=true,mutate=function(job) job.source[0]=job.source[1] end},
  {name='unsupported import version',import=true,mutate=function(job) job.version=99 end},
  {name='unknown filesystem source field',command='cp /source /copy',kind='filesystem',mutate=function(job) job.source[#job.source].handler='scripts.guest.vm' end},
  {name='duplicate publication index',command='mkdir /created',kind='filesystem',publish=true,mutate=function(job) job.paths[2]=job.paths[1] end},
  {name='unknown directory item field',command='ls /source',kind='listing',items=true,mutate=function(job) job.items[#job.items].handler='scripts.guest.vm' end},
  {name='unsupported output version',command='help',kind='output',mutate=function(job) job.version=99 end},
}
local function direct_step(s,ledger,id,tick)
  -- Only the probe is inside this guard; the real VM neighbor runs afterwards.
  local run=VM.run
  VM.run=function() error('adversarial shell entered VM execution',0) end
  local ok,result=pcall(Scheduler.step,s,ledger,id,tick,true)
  VM.run=run
  assert(ok,result)
  return result
end
local function plain(value,seen)
  local kind=type(value)
  assert(kind=='nil' or kind=='boolean' or kind=='number' or kind=='string' or kind=='table','non-data adversarial state')
  if kind=='number' then assert(value==value and math.abs(value)<math.huge) end
  if kind~='table' then return end
  assert(getmetatable(value)==nil,'executable adversarial metatable')
  if seen[value] then return end; seen[value]=true
  for k,v in pairs(value) do plain(k,seen); plain(v,seen) end
end
function M.new() return {index=1,records={}} end
function M.prepare(state,ledger,tick,check)
  local case=cases[state.index]
  if not case then
    if not state.metadata then
      local source={fs={['/']={type='dir'}}}
      for i=1,FS.max_nodes-1 do
        local suffix=tostring(i)
        source.fs['/'..string.rep('x',1023-#suffix)..suffix]={type='file',text=''}
      end
      local id=#cases+3
      local s=assert(Scheduler.new(source,51,19,ledger,id,tick))
      assert(direct_step(s,ledger,id,tick))
      state.metadata={shell=s,id=id,job=s.job,source=s.job.source,nodes=s.job.nodes,before=packed(s)}
      check('independent maximum empty-content path metadata import is admitted beside VM',s.status=='initializing'
        and s.disk==nil and s.job.count==FS.max_nodes and s.job.bytes==0 and s.job.metadata>FS.max_bytes and s.job.cursor>1)
      local before=packed(s)
      check('executable ingress never enters owned queue beside VM',not Scheduler.push(s,ledger,id,tick,{n=2,'char',function() end}) and packed(s)==before)
      local ok,rejected=pcall(Scheduler.new,{fs={['/']={type='dir'},['/bad.lua']={type='file',text=function() end}}},51,19,ledger,id+1,tick)
      check('admitted executable snapshot is rejected without a retained shell beside VM',not ok or not rejected)
      plain(s,{})
    end
    return true
  end
  local record=state.records[state.index]
  if not record then
    local disk={fs={['/']={type='dir'},['/source']={type='dir'}}}
    for i=1,20 do disk.fs['/source/f'..i..'.lua']={type='file',text='game.print("NEVER EXECUTE"); require("scripts.guest.vm")'} end
    local id=state.index+2
    local s=assert(Scheduler.new(disk,51,19,ledger,id,tick))
    record={shell=s,id=id}; state.records[state.index]=record
    if not case.import then return false end
  end
  local s=record.shell
  if not case.import then
    if s.status=='initializing' then direct_step(s,ledger,record.id,tick); return false end
    if not record.submitted then
      assert(Scheduler.push(s,ledger,record.id,tick,{n=2,'paste',case.command}))
      assert(Scheduler.push(s,ledger,record.id,tick,{n=2,'key',257}))
      record.submitted=true
    end
    if not s.job or case.publish and s.job.phase~='publish' or case.items and #s.job.items==0 then
      direct_step(s,ledger,record.id,tick); return false
    end
    assert(s.job.kind==case.kind,'incorrect actual adversarial command job')
  end
  record.job,record.disk=s.job,s.disk
  case.mutate(s.job)
  plain(s,{})
  record.before=packed(s)
  check('malformed data-only job prepared beside VM: '..case.name,s.job==record.job and s.status~='recovery')
  state.index=state.index+1
  return false
end
function M.observe(state)
  local metadata=state.metadata
  assert(packed(metadata.shell)==metadata.before and metadata.shell.job==metadata.job and metadata.shell.job.source==metadata.source
    and metadata.shell.job.nodes==metadata.nodes and metadata.shell.disk==nil,'load changed maximum empty-content import')
  for _,record in ipairs(state.records) do
    assert(packed(record.shell)==record.before and record.shell.job==record.job and record.shell.disk==record.disk,'load changed malformed job/aliases')
  end
end
function M.resume(state,ledger,tick,check)
  state.resume_index=state.resume_index or 1
  local record=state.records[state.resume_index]
  if not record then
    local metadata=state.metadata
    local s=metadata.shell
    if s.status=='initializing' then
      if not metadata.paused then
        local before=packed(s)
        check('cold maximum empty-content import pauses without changing source or staging',not Scheduler.step(s,ledger,metadata.id,tick,false) and packed(s)==before)
        metadata.paused=true
        return false
      end
      direct_step(s,ledger,metadata.id,tick)
      assert(s.status~='recovery' and (s.status~='initializing' or s.disk==nil),'invalid independent metadata progress')
      return false
    end
    check('real-tick independent metadata import publishes every maximum path with no file bytes',s.status=='ready' and not s.job
      and s.disk.nodes==FS.max_nodes and s.disk.bytes==0)
    for _,record in ipairs(metadata.source) do assert(s.disk.fs[record.path],'lost empty-content maximum path') end
    local disk=s.disk
    direct_step(s,ledger,metadata.id,tick)
    check('independent metadata publication does not replay when idle',s.disk==disk and not s.job)
    plain(s,{})
    return true
  end
  local case=cases[state.resume_index]
  local s=record.shell
  check('cold malformed record and original disk retained: '..case.name,packed(s)==record.before and s.job==record.job and s.disk==record.disk)
  Budget.begin(ledger,tick)
  assert(Budget.admit(ledger,record.id,{execution=Budget.remaining(ledger,record.id,'execution')}))
  local spent=packed(ledger)
  check('zero-credit cold malformed dispatch is inactive: '..case.name,not direct_step(s,ledger,record.id,tick)
    and packed(s)==record.before and packed(ledger)==spent)
  state.refused_tick=tick
  state.phase='retry'
  return false
end
function M.retry(state,ledger,tick,check)
  local record=state.records[state.resume_index]
  local case=cases[state.resume_index]
  assert(tick>state.refused_tick)
  direct_step(record.shell,ledger,record.id,tick)
  local s=record.shell
  check('admitted cold malformed job halts without publication: '..case.name,s.status=='recovery'
    and s.job==record.job and s.disk==record.disk and (not s.disk or not s.disk.fs['/copy'] and not s.disk.fs['/created']))
  plain(s,{})
  state.resume_index=state.resume_index+1; state.phase='resume'
end
return M
