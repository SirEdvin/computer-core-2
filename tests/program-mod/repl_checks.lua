-- Actual shell handler/admission contracts; synthetic clocks are not latency evidence.
local Shell=require('__computer_core_2__.scripts.shell.runtime')
local Programs=require('__computer_core_2__.scripts.programs.runtime')
local Compiler=require('__computer_core_2__.scripts.programs.compiler')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local M={}
local function packed(value) return serpent.line(value,{sortkeys=true}) end
local function event(session,s,tuple)
  session.tick=session.tick+1; Budget.begin(session.ledger,session.tick)
  return Shell.handle(s,tuple,function(cost) return Budget.admit(session.ledger,1,cost) end)
end
local function advance(session,s)
  local limit=0
  while s.job do limit=limit+1; assert(limit<1000,'REPL job stuck'); assert(event(session,s,{n=1,'advance'})) end
end
local function submit(session,s,text)
  assert(event(session,s,{n=2,'paste',text})); assert(event(session,s,{n=2,'key',257}))
  assert(event(session,s,{n=1,'advance'}))
  local result=s.job and s.job.text
  advance(session,s)
  return result
end
local function new(session)
  session.tick=session.tick+1; Budget.begin(session.ledger,session.tick)
  local s=assert(Shell.new(nil,51,19,function(cost) return Budget.admit(session.ledger,1,cost) end))
  while s.status~='ready' do assert(event(session,s,{n=1,'boot'})) end
  assert(event(session,s,{n=2,'paste','lua'})); assert(event(session,s,{n=2,'key',257})); advance(session,s)
  return s
end
function M.initial(check)
  local session={ledger={version=1},tick=1000}
  local s=new(session)
  check('lua command enters native foreground with scalar owner and prompt',s.repl and Shell.compatible(s) and s.display.lines[19].text:sub(1,5)=='lua> ')
  for _,case in ipairs({{'1+2','3\n'},{'false','false\n'},{'nil','nil\n'},
    {'math.floor(4.9)','4\n'}, {'return math.floor(4.9)','4\n'},{'return false','false\n'}, {'print(false,nil)','false nil\n'}}) do
    check('REPL native expression/return '..case[1],submit(session,s,case[1])==case[2])
  end
  check('REPL finite statements commit persistent scalar state',submit(session,s,'local x=3; state.n=x; print(state.n)')=='3\n' and s.controller.state.n==3)
  check('REPL next submission reads prior state',submit(session,s,'state.n=state.n+1; return state.n')=='4\n')
  for _,bad in ipairs({'while true do end','repeat until false','for i=1,3 do end','game.print(1)',
    'local f=function() end','load("return 1")','require("x")','state["n"]=5','state.n={}',
    'state.n=99; print("UNCOMMITTED"); state.bad=1/0','x',string.char(27)..'Lua'}) do
    local previous=s.controller.state
    local result=submit(session,s,bad)
    check('REPL refusal retains usable session without partial state/prints '..bad,s.repl and s.status=='ready'
      and s.controller.state==previous and previous.n==4 and result:find('lua:',1,true) and not result:find('UNCOMMITTED',1,true))
  end
  local text='" end); game.print("escape") --'
  check('REPL literal escaping cannot execute player text',submit(session,s,string.format('%q',text))==text..'\n')
  local compiled,err=Compiler.compile(string.rep('x',8193),'=lua',true)
  check('REPL source cap refuses before parsing',not compiled and err:find('8 KiB',1,true))
  local maximum='return 1 --'..string.rep('x',8192-#'return 1 --')
  check('REPL maximum accepted bytes traverse actual submission path',submit(session,s,maximum)=='1\n')
  for _,bad in ipairs({string.rep(';',257),string.rep('do ',17)..string.rep('end ',17),
    string.rep('print("x");',9),string.rep('circuit.clear("right");',17)}) do
    compiled,err=Compiler.compile(bad,'=lua',true)
    check('REPL shares statement nesting and effect ceilings',not compiled and err and #err<=1024)
  end
  local before=packed(s)
  check('REPL cannot invoke background compile or callbacks',not Programs.step(s,9999,true,function() error('unexpected background admission') end) and packed(s)==before)
  assert(event(session,s,{n=2,'paste','state.n=state.n+1; print(state.n)'})); assert(event(session,s,{n=2,'key',257}))
  session.tick=session.tick+1; Budget.begin(session.ledger,session.tick)
  for domain,amount in pairs(Programs.callback_work()) do
    local previous,budget=packed(s),packed(session.ledger)
    local handled,reason=Shell.handle(s,{n=1,'advance'},function(cost)
      cost[domain]=Budget.remaining(session.ledger,1,domain)+1
      return Budget.admit(session.ledger,1,cost)
    end)
    check('REPL whole-submission '..domain..' refusal is atomic',not handled and reason=='work deferred' and packed(s)==previous and packed(session.ledger)==budget)
  end
  session.pending=s; session.pending_owner=s.controller; session.pending_values=s.controller.state
  session.partial=new(session)
  assert(event(session,session.partial,{n=2,'paste','state.kept=false'})); assert(event(session,session.partial,{n=2,'key',263}))
  session.partial_cursor=session.partial.cursor
  local fill={}
  for _,domain in ipairs({'execution','compiler','string','terminal','filesystem','event','advance','table'}) do
    fill[domain]=Budget.remaining(session.ledger,1,domain)
  end
  assert(Budget.admit(session.ledger,1,fill))
  session.before=packed(s); session.input_before=packed(session.partial); session.work_before=packed(session.ledger)
  return session
end
function M.observe(session)
  assert(packed(session.pending)==session.before and packed(session.partial)==session.input_before and packed(session.ledger)==session.work_before,'REPL changed on load')
end
function M.reload(session,check)
  M.observe(session)
  local s=session.pending
  check('cold REPL retains exact pending source state aliases and input cursor',s.controller==session.pending_owner
    and s.controller.state==session.pending_values and s.job.kind=='repl' and session.partial.cursor==session.partial_cursor)
  local before=packed(s)
  local ledger_before=packed(session.ledger)
  check('cold REPL actual retained exhausted credits cannot renew or execute',not Shell.handle(s,{n=1,'advance'},function(cost) return Budget.admit(session.ledger,1,cost) end)
    and packed(s)==before and packed(session.ledger)==ledger_before)
  assert(event(session,s,{n=1,'advance'}))
  check('cold REPL commits pending submission exactly once',s.controller.state.n==5 and s.job.text=='5\n')
  advance(session,s); assert(event(session,s,{n=1,'advance'}))
  check('cold committed REPL submission cannot replay',s.controller.state.n==5)
  assert(event(session,session.partial,{n=2,'char','X'}))
  check('cold REPL next char uses retained cursor exactly once',session.partial.command=='state.kept=falsXe')
  assert(event(session,s,{n=2,'paste','exit'})); assert(event(session,s,{n=2,'key',257}))
  check('REPL explicit exit returns shell and stops owner',s.repl==nil and s.controller.status=='stopped' and s.display.lines[19].text:sub(1,3)=='/> ')
  assert(event(session,session.partial,{n=1,'terminate'}))
  check('REPL terminate cancels partial input and stops owner',not session.partial.repl and session.partial.command=='' and session.partial.controller.status=='stopped')
  local fresh=new(session)
  check('new Lua session starts fresh state',next(fresh.controller.state)==nil)
  assert(event(session,fresh,{n=1,'shutdown'}))
  check('REPL shutdown stops owner and session',fresh.status=='stopped' and not fresh.repl and fresh.controller.status=='stopped')
  fresh=new(session)
  assert(submit(session,fresh,'state.n=1')=='')
  local disk=fresh.disk
  assert(event(session,fresh,{n=1,'reboot'}))
  check('REPL reboot stops lease clears session and preserves committed disk',fresh.status=='boot' and not fresh.repl
    and fresh.controller.status=='stopped' and fresh.command=='' and fresh.disk==disk)
  local incompatible=new(session); incompatible.repl.version=999
  local old=incompatible.repl
  assert(not Shell.compatible(incompatible)); event(session,incompatible,{n=1,'advance'})
  check('unsupported REPL remains inert with recovery data',incompatible.status=='recovery' and incompatible.repl==old)
end
return M
