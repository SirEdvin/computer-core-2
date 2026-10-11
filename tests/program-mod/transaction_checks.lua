-- Functional admission/transaction oracles; synthetic clocks are NOT latency evidence.
local Compiler=require('__computer_core_2__.scripts.programs.compiler')
local Programs=require('__computer_core_2__.scripts.programs.runtime')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local M={}
local function packed(value) return serpent.line(value,{sortkeys=true}) end
local function source(body) return 'return {interval=1,on_tick=function(event,state) '..body..' end}' end
local function dispatch(s,ledger,tick)
  Budget.begin(ledger,tick)
  return Programs.step(s,tick,true,function(cost) return Budget.admit(ledger,1,cost) end)
end
local function make(text)
  local s={disk={cwd='/',fs={['/']={type='dir'},['/case.lua']={type='file',text=text}}}}
  local ledger={version=1}; Budget.begin(ledger,0)
  assert(Budget.admit(ledger,1,Compiler.work()))
  assert(Programs.activate(s,Programs.job(s,'/case.lua'),0))
  assert(dispatch(s,ledger,1)) -- Commit on_start (or its empty initial event).
  return s,ledger
end
function M.initial(check)
  local function refused(body,reason)
    local ledger={version=1}; Budget.begin(ledger,0); assert(Budget.admit(ledger,1,Compiler.work()))
    local result,err=Compiler.compile(source(body),'/limits.lua')
    check('compiler independently enforces '..reason..' ('..tostring(err)..')',not result and err:find(reason,1,true) and err:match(':%d+:%d+:'))
  end
  refused(string.rep('do ',17)..string.rep('end ',17),'nesting limit')
  refused(string.rep(';',257),'statement limit')
  -- Wide shallow statements isolate AST work from the parser's nesting cap.
  refused(string.rep('state.s=event.tick; ',200),'AST node limit')
  local function expression(count)
    if count==1 then return '"'..string.rep('x',256)..'"' end
    local left=math.floor(count/2)
    return '('..expression(left)..'+'..expression(count-left)..')'
  end
  refused('state.s='..expression(60),'emission work limit')
  local cases={
    {'local a,b=false,nil; state.flag=(a or b)==nil','flag',true},
    {'local x=1; x=x+1; state.n=x; return state.n','n',2},
    {'do local x=math.abs(-2); state.n=math.floor(x/2) end','n',1},
    {'if event.tick>0 then state.n=1 elseif false then state.n=2 else state.n=3 end','n',1},
    {'state.n=math.min(1,2)+math.max(3,4); state.s="a".."b"; state.n=#state.s','n',2},
    {'state.n=(state.n or 0)+1; state.empty=nil; state.flag=not false','flag',true},
    {'state.flag=false and (1/0); state.empty=nil; state.n=2^3%3','flag',false},
    {'local x,y=1,2; x,y=y,x; state.n=x-y','n',1},
  }
  for _,case in ipairs(cases) do
    local s,ledger=make(source(case[1])); assert(dispatch(s,ledger,2))
    check('generated native scalar semantics '..case[1],s.controller.status=='running' and s.controller.state[case[2]]==case[3] and s.controller.state.empty==nil)
  end
  local literal='" end); game.print("escape") --\n\\literal'
  local s,ledger=make(source('print('..string.format('%q',literal)..')'))
  assert(dispatch(s,ledger,2))
  check('native literal quoting renders exact inert player bytes',s.program_output.queue[1]==literal and s.controller.status=='running')
  local cost=Programs.callback_work()
  for domain,amount in pairs(cost) do
    s,ledger=make(source('state.runs=(state.runs or 0)+1'))
    Budget.begin(ledger,2)
    assert(Budget.admit(ledger,1,{[domain]=Budget.remaining(ledger,1,domain)-amount+1}))
    local before,work=packed(s),packed(ledger)
    local ok,err=dispatch(s,ledger,2)
    check('one-short '..domain..' defers entire native callback without ledger mutation',not ok and err=='work deferred' and packed(s)==before and packed(ledger)==work)
    assert(dispatch(s,ledger,3))
    check('legitimate next tick retries one refused callback '..domain,s.controller.state.runs==1 and s.controller.next_tick==4)
  end
  s,ledger=make(source('state.n=1'))
  Budget.begin(ledger,2)
  local fill={}; for domain,amount in pairs(cost) do fill[domain]=Budget.remaining(ledger,1,domain)-amount end
  assert(Budget.admit(ledger,1,fill)); assert(dispatch(s,ledger,2))
  check('exact complete native callback credits commit once',s.controller.state.n==1 and s.controller.next_tick==3)
  local before=packed(s); check('same deadline cannot execute twice',not dispatch(s,ledger,2) and packed(s)==before)
  for _,bad in ipairs({'state.bad=1/0','state.bad=0/0','state.bad=1e308*1e308',
    'state.bad="'..string.rep('x',256)..'".."y"','state.bad=math.floor(false)'}) do
    s,ledger=make(source('state.n=999; print("UNCOMMITTED"); '..bad))
    local values=s.controller.state; values.n=17
    assert(dispatch(s,ledger,2))
    check('native fault discards staged state and prints '..bad,s.controller.status=='faulted' and s.controller.state==values and values.n==17
      and #s.program_output.queue==0 and s.controller.message:find('/case.lua:',1,true))
  end
  s,ledger=make(source('state.n=999; print("overflow")'))
  local output=s.program_output
  for i=1,Programs.output_records do output.queue[i]=string.rep('q',256) end
  output.bytes=Programs.output_bytes
  local values=s.controller.state; values.n=17
  local editor={text='untouched draft'}; s.editor=editor
  check('exact maximum background FIFO is valid',Programs.valid_output(output))
  assert(dispatch(s,ledger,2))
  check('full FIFO faults before state/print publication and cannot overwrite editor',s.controller.status=='faulted' and s.controller.state==values
    and values.n==17 and #output.queue==64 and output.bytes==16384 and s.editor==editor and editor.text=='untouched draft')
  s,ledger=make(source('state.added=1'))
  for i=1,64 do s.controller.state['k'..i]=string.rep('s',256) end
  check('exact maximum scalar state payload is valid',Programs.valid_state(s.controller.state))
  local values=s.controller.state; assert(dispatch(s,ledger,2))
  check('65th state key faults without publishing staged mutation',s.controller.status=='faulted' and s.controller.state==values and values.added==nil)
  s,ledger=make('return {on_start=function(event,state) state.starts=1; print(false,nil) end}')
  check('one-shot handler commits once then stops with false/nil print semantics',s.controller.status=='stopped' and s.controller.state.starts==1 and s.program_output.queue[1]=='false nil')
  before=packed(s); check('completed one-shot cannot replay on later tick',not dispatch(s,ledger,100) and packed(s)==before)
  s,ledger=make(source('state.n=(state.n or 0)+1'))
  local active=s.controller
  check('run before explicit stop is refused without replacing source',not pcall(Programs.job,s,'/case.lua') and s.controller==active)
  check('readonly ROM execution is refused',not pcall(Programs.job,{disk=s.disk},'/rom/examples/stock-controller.lua'))
  s.disk.fs['/case.lua'].text=source('state.n=99')
  assert(dispatch(s,ledger,100))
  check('overdue event runs once using active source snapshot',active.state.n==1 and active.next_tick==101 and active.source~=s.disk.fs['/case.lua'].text)
  before=packed(s); check('overdue dispatch has no same-tick catch-up storm',not dispatch(s,ledger,100) and packed(s)==before)
  Programs.stop(s)
  Budget.begin(ledger,101); assert(Budget.admit(ledger,1,Compiler.work()))
  assert(Programs.activate(s,Programs.job(s,'/case.lua'),101))
  check('stop/run selects new exact committed bytes and fresh generation',s.controller~=active and s.controller.generation==active.generation+1 and s.controller.source==s.disk.fs['/case.lua'].text)
  local retained=s.controller; retained.generated='return game'
  check('saved generated text is not an admitted controller field',not Programs.valid(retained))
  retained.generated=nil; retained.compiler=999
  check('unsupported compiler ABI refuses retained controller',not Programs.valid(retained))
end
return M
