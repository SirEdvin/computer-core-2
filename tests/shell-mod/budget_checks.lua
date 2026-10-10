local Shell=require('__computer_core_2__.scripts.shell.runtime')
local new=require('construct')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local VM=require('__computer_core_2__.scripts.guest.vm')
local Compiler=require('__computer_core_2__.scripts.guest.compiler')
local VMScheduler=require('__computer_core_2__.scripts.guest.scheduler')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local M={}
local function serialized(s) return serpent.line(s,{sortkeys=true}) end
function M.initial(check)
  local ledger=VMScheduler.new()
  Budget.begin(ledger,100)
  assert(Budget.admit(ledger,99,{execution=Limits.instructions_per_tick}))
  local before=serialized(ledger)
  check('compound refusal changes no work counters',not Budget.admit(ledger,2,{execution=1,event=5}) and serialized(ledger)==before)
  check('same tick preserves spent aggregate',not Budget.admit(ledger,2,{execution=1}))
  check('backwards tick rejected',not pcall(Budget.begin,ledger,99) and serialized(ledger)==before)
  local s=new(nil,51,19)
  before=serialized(s)
  check('zero execution preserves entire session',not Scheduler.step(s,ledger,2,100,true) and serialized(s)==before)
  Budget.begin(ledger,101)
  assert(Scheduler.step(s,ledger,2,101,true))
  local event={n=2,'char','a'}
  assert(Scheduler.push(s,ledger,2,101,event)); event[2]='z'
  assert(Scheduler.step(s,ledger,2,101,true))
  check('queued input is copied and delivered once',s.command=='a' and #s.events.queue==0 and s.events.bytes==0)
  assert(Scheduler.push(s,ledger,2,101,{n=2,'char','b'}))
  assert(Budget.admit(ledger,2,{terminal=Budget.remaining(ledger,2,'terminal')}))
  before=serialized(s)
  check('terminal refusal retains queued event and text',not Scheduler.step(s,ledger,2,101,true) and s.command=='a' and #s.events.queue==1)
  assert(Scheduler.step(s,ledger,2,102,true))
  check('later tick consumes retained event once',s.command=='ab' and #s.events.queue==0)
  before=serialized(s)
  check('power pause leaves shell and timers unchanged',not Scheduler.step(s,ledger,2,103,false) and serialized(s)==before)
  local timer=assert(Scheduler.start_timer(s,ledger,2,103,0))
  Scheduler.step(s,ledger,2,103,true)
  check('zero duration does not deliver inline',s.events.timers[timer]~=nil)
  assert(Scheduler.cancel_timer(s,ledger,2,103,timer))
  Scheduler.step(s,ledger,2,104,true)
  check('cancelled owned timer never publishes',s.events.timer_count==0 and #s.events.queue==0)
  timer=assert(Scheduler.start_timer(s,ledger,2,104,0))
  assert(Scheduler.step(s,ledger,2,105,true))
  check('timer belongs to single session and consumes once',s.events.timer_count==0 and #s.events.queue==0)
  local crowded=new(nil,51,19)
  assert(Scheduler.step(crowded,ledger,4,150,true))
  for i=1,Limits.events do assert(Scheduler.push(crowded,ledger,4,150,{n=2,'char','x'})) end
  check('queue count cap enforced',not Scheduler.push(crowded,ledger,4,150,{n=2,'char','y'}) and #crowded.events.queue==Limits.events)
  local first_timer
  for i=1,Limits.timers do
    local t=assert(Scheduler.start_timer(crowded,ledger,4,150,0)); first_timer=first_timer or t
  end
  check('timer count cap enforced',not pcall(Scheduler.start_timer,crowded,ledger,4,150,0))
  Scheduler.step(crowded,ledger,4,151,true)
  check('queue pressure retains due timers',crowded.events.timer_count==Limits.timers and crowded.events.timers[first_timer]~=nil)
  assert(Scheduler.cancel_timer(crowded,ledger,4,151,first_timer))
  Scheduler.step(crowded,ledger,4,152,true)
  check('cancelled due timer cannot reappear',crowded.events.timers[first_timer]==nil and crowded.events.timer_count<Limits.timers)
  -- Synthetic maximum output data, not generated execution or measured latency.
  local wide=new(nil,160,60)
  assert(Scheduler.step(wide,ledger,3,200,true))
  wide.job={version=1,kind='output',text=string.rep('\n',Limits.string_bytes),cursor=1}
  assert(Scheduler.push(wide,ledger,3,200,{n=2,'char','Q'}))
  local turns=0
  while wide.job and turns<10000 do
    turns=turns+1
    assert(Scheduler.step(wide,ledger,3,200+turns,true))
    assert(ledger.terminal_budget.machines[3].used<=Limits.terminal_work_per_computer)
    assert(ledger.execution_budget.instructions<=Limits.instructions_per_tick)
  end
  check('maximum newline output makes bounded progress',wide.job==nil and turns>1 and turns<10000)
  check('foreground job retains later input unchanged',wide.command=='' and #wide.events.queue==1)
  assert(Scheduler.step(wide,ledger,3,201+turns,true))
  check('queued post-job character delivered once',wide.command=='Q' and #wide.events.queue==0)
  local vm=VM.new(assert(Compiler.compile('local n=0; while true do n=n+1 end','=shell-budget-neighbor')))
  local shared=VMScheduler.new(); VMScheduler.add(shared,1,vm)
  local peer=new(nil,51,19)
  assert(Scheduler.step(peer,shared,2,1,true))
  assert(Scheduler.push(peer,shared,2,1,{n=2,'char','N'}))
  assert(Scheduler.step(peer,shared,2,1,true))
  local work=VMScheduler.tick(shared,1)
  check('real VM and shell share existing execution allowance',work>0 and shared.execution_budget.instructions<=Limits.instructions_per_tick
    and shared.execution_budget.machines[1].instructions>0 and shared.execution_budget.machines[2].instructions==peer.instructions-1 and peer.command=='N')
  local exhausted=serialized(shared.execution_budget)
  Scheduler.step(peer,shared,2,1,true)
  check('VM spending cannot be reset by shell dispatch',serialized(shared.execution_budget)==exhausted)
  -- Save with a real output job created by a built-in and a retained FIFO event.
  s=new(nil,51,19); ledger=VMScheduler.new()
  assert(Scheduler.step(s,ledger,2,1,true))
  assert(Scheduler.push(s,ledger,2,1,{n=2,'paste','help'})); assert(Scheduler.step(s,ledger,2,1,true))
  assert(Scheduler.push(s,ledger,2,1,{n=2,'key',257})); assert(Scheduler.step(s,ledger,2,1,true))
  assert(Scheduler.push(s,ledger,2,1,{n=2,'char','R'}))
  assert(Budget.admit(ledger,2,{execution=Budget.remaining(ledger,2,'execution')}))
  return {shell=s,ledger=ledger,job=s.job,queue=s.events.queue,before=serialized(s),budget=serialized(ledger)}
end
function M.reload(saved,check)
  check('cold saved job queue and shared ledger unchanged',serialized(saved.shell)==saved.before and serialized(saved.ledger)==saved.budget
    and saved.shell.job==saved.job and saved.shell.events.queue==saved.queue)
  local before=serialized(saved.shell)
  check('cold same-tick exhaustion remains spent',not Scheduler.step(saved.shell,saved.ledger,2,1,true) and serialized(saved.shell)==before)
  assert(Scheduler.step(saved.shell,saved.ledger,2,2,true))
  local tick=2
  while saved.shell.job and tick<32 do tick=tick+1; assert(Scheduler.step(saved.shell,saved.ledger,2,tick,true)) end
  check('cold builtin output completes once',saved.shell.job==nil and #saved.shell.events.queue==1)
  assert(Scheduler.step(saved.shell,saved.ledger,2,tick+1,true))
  check('cold queued input retains FIFO ownership',saved.shell.command=='R' and #saved.shell.events.queue==0)
end
return M
