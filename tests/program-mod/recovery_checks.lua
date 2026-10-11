-- Malformed durable applications through real shell validation and cold save.
-- Synthetic admission clocks are functional oracles, not latency measurements.
local Compiler=require('__computer_core_2__.scripts.programs.compiler')
local Programs=require('__computer_core_2__.scripts.programs.runtime')
local Editor=require('__computer_core_2__.scripts.programs.editor')
local Shell=require('__computer_core_2__.scripts.shell.runtime')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local M={}
local function packed(value) return serpent.line(value,{sortkeys=true}) end
function M.initial(check)
  for mask=0,127 do
    local queue,count,last={},0,0
    for index=1,7 do
      if bit32.band(mask,bit32.lshift(1,index-1))~=0 then queue[index]='x'; count=count+1; last=index end
    end
    assert(Programs.valid_output{version=1,queue=queue,bytes=count}==(count==last),'sparse FIFO mask '..mask)
  end
  check('every seven-slot FIFO subset agrees with independent dense-index oracle',true)
  local saved={}
  local cases={
    {'editor version',function(s) Editor.open(s,'/case.lua'); s.editor.version=99 end},
    {'editor cursor',function(s) Editor.open(s,'/case.lua'); s.editor.cursor=#s.editor.text+1 end},
    {'editor path bytes',function(s) Editor.open(s,'/case.lua'); s.editor.path=string.rep('p',1025) end},
    {'controller version',function(s) s.controller.version=99 end},
    {'controller compiler',function(s) s.controller.compiler=99 end},
    {'controller generated text',function(s) s.controller.generated='return game' end},
    {'controller scalar state',function(s) s.controller.state.bad={host='not a scalar'} end},
    {'controller source bytes',function(s) s.controller.source=string.rep('x',Compiler.source_bytes+1) end},
    {'controller deadline',function(s) s.controller.next_tick=-1 end},
    {'controller plain header',function(s) s.controller=true end},
    {'FIFO bytes',function(s) s.program_output.bytes=1 end},
    {'FIFO sparse slots',function(s) s.program_output={version=1,queue={[1]='a',[3]='c',[4]='d',[6]='f'},bytes=4} end},
    {'pending executable job',function(s) s.job={version=1,kind='program',path='/case.lua',source='return {}',generated='return game'} end},
  }
  local source='return {on_tick=function(event,state) state.n=(state.n or 0)+1 end}'
  for _,case in ipairs(cases) do
    local ledger={version=1}; local s=assert(Scheduler.new({fs={['/']={type='dir'},['/case.lua']={type='file',text=source}}},51,19,ledger,1,0))
    local tick=0
    while s.status~='ready' do tick=tick+1; assert(Scheduler.step(s,ledger,1,tick,true)); assert(tick<20) end
    tick=tick+1; Budget.begin(ledger,tick); assert(Budget.admit(ledger,1,Compiler.work()))
    assert(Programs.activate(s,Programs.job(s,'/case.lua'),tick))
    case[2](s)
    assert(Budget.admit(ledger,1,{execution=Budget.remaining(ledger,1,'execution')}))
    local record={name=case[1],shell=s,ledger=ledger,tick=tick,disk=s.disk,controller=s.controller,editor=s.editor,output=s.program_output,job=s.job,
      before=packed(s),credits=packed(ledger)}
    check('malformed '..case[1]..' is incompatible and inert at zero credits',not Shell.compatible(s) and not Scheduler.step(s,ledger,1,tick,true)
      and packed(s)==record.before and packed(ledger)==record.credits)
    saved[#saved+1]=record
  end
  return saved
end
function M.observe(saved)
  for _,record in ipairs(saved) do
    assert(packed(record.shell)==record.before and packed(record.ledger)==record.credits,'malformed application changed on load')
  end
end
function M.reload(saved,check)
  M.observe(saved)
  for _,record in ipairs(saved) do
    local s=record.shell
    check('cold malformed '..record.name..' cannot renew work or execute retained data',not Scheduler.step(s,record.ledger,1,record.tick,true)
      and packed(s)==record.before and packed(record.ledger)==record.credits)
    Scheduler.step(s,record.ledger,1,record.tick+1,true)
    check('admitted malformed '..record.name..' recovery retains original graphs without fallback',s.status=='recovery' and s.disk==record.disk
      and s.controller==record.controller and s.editor==record.editor and s.program_output==record.output and s.job==record.job
      and s.disk.fs['/case.lua'].text:find('state.n=',1,true) and s.recovery)
  end
end
return M
