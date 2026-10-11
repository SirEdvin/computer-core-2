local Compiler=require('__computer_core_2__.scripts.programs.compiler')
local Programs=require('__computer_core_2__.scripts.programs.runtime')
local Shell=require('__computer_core_2__.scripts.shell.runtime')
local Scheduler=require('__computer_core_2__.scripts.shell.scheduler')
local Budget=require('__computer_core_2__.scripts.shell.budget')
local Editor=require('__computer_core_2__.scripts.programs.editor')
local VM=require('__computer_core_2__.scripts.guest.vm')
local VMCompiler=require('__computer_core_2__.scripts.guest.compiler')
local Native=require('__computer_core_2__.scripts.native.dispatch')
local NativeCompiler=require('__computer_core_2__.scripts.native.compiler')
local Factory=require('factory_checks')
local Transactions=require('transaction_checks')
local Cleanup=require('cleanup_checks')
local Recovery=require('recovery_checks')
local loaded=false
local function forbidden() error('restricted program entered VM/continuation execution',0) end
local run_vm=VM.run
local allowed_vm
VM.run=function(vm,...)
  assert(vm==allowed_vm,'restricted program entered VM execution')
  return run_vm(vm,...)
end
VMCompiler.compile,Native.run,NativeCompiler.compile=forbidden,forbidden,forbidden
local function packed(value) return serpent.line(value,{sortkeys=true}) end
local function check(name,value)
  assert(value,'program probe: '..name); storage.checks=storage.checks+1; log('CC2 PROGRAMS PASS '..name)
end
local function source(body) return 'return {interval=1,on_tick=function(event,state) '..body..' end}' end
local function compiled(text)
  storage.compile_tick=storage.compile_tick+1
  local ledger={version=1}; Budget.begin(ledger,storage.compile_tick)
  assert(Budget.admit(ledger,1,Compiler.work()))
  return Compiler.compile(text,'/test.lua')
end
local function syntax()
  for _,body in ipairs({'local a,b=false,nil; state.flag=(a or b)==nil',
    'local x=1; x=x+1; state.n=x; return state.n',
    'do local x=math.abs(-2); state.n=math.floor(x/2) end',
    'if event.tick>0 then state.n=1 elseif false then state.n=2 else state.n=3 end',
    'state.n=math.min(1,2)+math.max(3,4); state.s="a".."b"; state.n=#state.s',
    'print("literal \\\" end); game.print(\\\"escape\\\") --")',
    'state.n=(state.n or 0)+1; state.empty=nil; state.flag=not false'}) do
    local result,err=compiled(source(body)); assert(result,err); check('supported finite scalar grammar '..body,result~=nil)
  end
  for _,body in ipairs({'while true do end','repeat until false','for i=1,3 do end','for k,v in pairs(state) do end',
    'goto label; ::label::','local f=function() end','local function f() f() end','game.print("unsafe")',
    'require("x")','load("return 1")','setmetatable(state,{})','local f=print; f("alias")',
    'state["computed"]=1','state[event.name]=1','state.n={}','state.n=event','state.n=state','event.tick=1',
    'state:clear()','state.n=_G','state.n=...','state.n=1e999'}) do
    local result,err=compiled(source(body)); check('default-deny grammar '..body,result==nil and type(err)=='string' and #err<=1024 and err:match(':%d+:%d+:'))
  end
  for _,text in ipairs({'return {}','return {interval=0,on_tick=function(event,state) end}',
    'return {interval=1+1,on_tick=function(event,state) end}',
    'return {on_tick=function() end}','return {on_tick=print}','return {unknown=true,on_tick=function(event,state) end}',
    'local x=1; '..source('state.n=x'),'return {["on_tick"]=function(event,state) end}',
    'return {on_tick=function(event,state) end,on_tick=function(event,state) end}',
    string.char(27)..'Lua','return {','return {on_tick=function(event,state,...) end}',
    source('print("'..string.rep('x',257)..'")'),source(string.rep('print("x");',9)),
    string.rep(' ',Compiler.source_bytes+1)}) do
    local result,err=compiled(text); check('malformed/oversized descriptor refuses with bounded position',not result and type(err)=='string' and #err<=1024 and err:match(':%d+:%d+:'))
  end
  local last
  for count=1,32 do
    local text=source(string.rep('state.n=(state.n or 0)+1;',count))
    local result=compiled(text)
    if not result then break end
    last={source=text,nodes=result.nodes,statements=result.statements,repetitions=count}
  end
  assert(last)
  -- Fill the remaining accepted AST envelope with explicit native do blocks.
  while true do
    local text=last.source:gsub(' end}$',' do end end}')
    local result=compiled(text)
    if not result then break end
    last.source=text; last.nodes=result.nodes; last.statements=result.statements
  end
  -- Saturate the source byte ceiling using inert comment bytes, not a preset
  -- runnable demo or altered quotas. This is still parsed/validated native Lua.
  last.source=last.source..'\n--'..string.rep('x',Compiler.source_bytes-#last.source-3)
  local result,err=compiled(last.source); assert(result,err)
  check('maximum native callback and 16 KiB source are actually accepted',#last.source==Compiler.source_bytes and result.nodes==last.nodes)
  storage.maximum=last
end
local function send(s,event,id)
  assert(Scheduler.push(s,storage.ledger,id or 1,game.tick,event))
end
local function step(s,id,power) return Scheduler.step(s,storage.ledger,id or 1,game.tick,power~=false) end
local function queue_command(s,text,id)
  send(s,{n=2,'paste',text},id); send(s,{n=2,'key',257},id)
end
local authentic='return {interval=1,on_start=function(event,state) state.starts=1; print("authentic native start") end,on_tick=function(event,state) state.runs=(state.runs or 0)+1 end}'
script.on_init(function()
  storage.checks=0; storage.compile_tick=0; syntax(); Transactions.initial(check); Cleanup.initial(check)
  storage.recovery=Recovery.initial(check)
  storage.factory=Factory.new()
  allowed_vm=storage.factory.vm.guest
  storage.ledger=storage.factory.host.terminal_scheduler; storage.boot_tick=game.tick
  storage.shell=assert(Scheduler.new(nil,51,19,storage.ledger,1,game.tick))
  storage.neighbor=assert(Scheduler.new(nil,51,19,storage.ledger,2,game.tick))
  storage.stage='boot'; log('CC2 PROGRAMS BOOTSTRAP PASS')
end)
script.on_load(function()
  loaded=true
  allowed_vm=storage.factory.vm.guest
  if storage.stage=='snapshot' then
    assert(packed(storage.shell)==storage.before and packed(storage.ledger)==storage.budget,'program data/work changed on load')
    Factory.observe(storage.factory)
    Recovery.observe(storage.recovery)
  end
end)
script.on_event(defines.events.on_tick,function()
  local s=storage.shell; local stage=storage.stage
  if stage=='snapshot' and not loaded or stage=='done' then return end
  if stage=='snapshot' and loaded then
    loaded=false
    Recovery.reload(storage.recovery,check)
    check('cold exact source state draft event deadline and work identities are unchanged',packed(s)==storage.before and packed(storage.ledger)==storage.budget
      and s.controller==storage.controller and s.editor==storage.editor)
    local before=packed(s)
    check('cold callback cannot renew exhausted same-tick credits',not Programs.step(s,storage.saved_tick,true,function(cost) return Budget.admit(storage.ledger,1,cost) end) and packed(s)==before)
    Factory.resume(storage.factory,check)
    storage.stage='resume-input'; return
  end
  loaded=false
  if stage=='resume-input' or stage=='resume-callback' or stage=='dirty-exit' or stage=='stop' or stage=='stopped' or stage=='factory-resume' then
    Factory.resume(storage.factory,check)
  else Factory.tick(storage.factory,check) end
  step(s,1); step(storage.neighbor,2)
  if stage=='boot' and s.status=='ready' and storage.neighbor.status=='ready' then
    local ticks=1+game.tick-storage.boot_tick -- Count the first synchronized dispatch as one, not zero.
    check('actual cold shell boot is within two simulation ticks',ticks<=2)
    log('CC2 PROGRAMS METRIC phase=boot ticks='..ticks)
    queue_command(s,'edit /auth.lua'); storage.stage='open'
  elseif stage=='open' and s.editor then
    send(s,{n=2,'paste',authentic}); send(s,{n=2,'key',Editor.save_key}); storage.stage='save'
  elseif stage=='save' and s.editor and not s.editor.dirty and not s.job then
    check('authentic source was edited and atomically saved through native handlers',s.disk.fs['/auth.lua'].text==authentic)
    send(s,{n=2,'key',Editor.quit_key}); storage.stage='exit'
  elseif stage=='exit' and not s.editor then
    queue_command(s,'/auth.lua'); storage.stage='run'
  elseif stage=='run' and s.controller and s.controller.state.runs then
    check('edited committed source actually executes as native handlers',s.controller.state.starts==1 and s.controller.state.runs>=1 and s.controller.source==authentic)
    storage.auth=s.controller
    queue_command(s,'edit /auth.lua'); storage.stage='edit-live'
  elseif stage=='edit-live' and s.editor then
    send(s,{n=2,'paste','-- saved edit\n'}); send(s,{n=2,'key',Editor.save_key}); storage.stage='save-live'
  elseif stage=='save-live' and s.editor and not s.editor.dirty and not s.job then
    check('editing committed source does not change active snapshot or replay start',s.controller==storage.auth and s.controller.source==authentic and s.disk.fs['/auth.lua'].text~=authentic and s.controller.state.starts==1)
    send(s,{n=2,'key',Editor.quit_key}); storage.stage='exit-live'
  elseif stage=='exit-live' and not s.editor then
    queue_command(s,'stop'); queue_command(s,'edit /maximum.lua'); storage.stage='maximum-open'
  elseif stage=='maximum-open' and s.editor then
    for first=1,#storage.maximum.source,8192 do send(s,{n=2,'paste',storage.maximum.source:sub(first,first+8191)}) end
    send(s,{n=2,'key',Editor.save_key}); storage.stage='maximum-save'
  elseif stage=='maximum-save' and s.editor and not s.editor.dirty and not s.job then
    check('maximum controller source also traverses actual editor/save path',s.disk.fs['/maximum.lua'].text==storage.maximum.source)
    send(s,{n=2,'key',Editor.quit_key}); storage.stage='maximum-exit'
  elseif stage=='maximum-exit' and not s.editor then
    queue_command(s,'run /maximum.lua'); storage.stage='maximum-run'
  elseif stage=='maximum-run' and s.controller and s.controller.path=='/maximum.lua' and s.controller.state.n then
    check('maximum allowed callback genuinely executes',s.controller.state.n>=storage.maximum.repetitions)
    queue_command(s,'edit /bench'); storage.stage='benchmark-open'
  elseif stage=='benchmark-open' and s.editor then
    storage.samples=0; storage.editor_latencies={}; storage.shell_latencies={}; storage.pending=nil; storage.benchmark_start=s.controller.state.n
    storage.stage='benchmark'
  elseif stage=='benchmark' then
    if storage.pending then
      local p=storage.pending
      if #s.editor.text==p.editor_bytes+1 and #storage.neighbor.command==p.shell_bytes+1 then
        local latency=game.tick-p.tick
        storage.editor_latencies[#storage.editor_latencies+1]=latency; storage.shell_latencies[#storage.shell_latencies+1]=latency
        storage.pending=nil; storage.samples=storage.samples+1
      end
    elseif storage.samples<100 and game.tick%2==0 then
      storage.pending={tick=game.tick,editor_bytes=#s.editor.text,shell_bytes=#storage.neighbor.command}
      send(s,{n=2,'char','e'}); send(storage.neighbor,{n=2,'char','s'},2)
    elseif storage.samples==100 and Factory.ready(storage.factory) then
      table.sort(storage.editor_latencies); table.sort(storage.shell_latencies)
      local ep95,sp95=storage.editor_latencies[95],storage.shell_latencies[95]
      check('editor and shell p95 echo beside real maximum callbacks is within two ticks',ep95<=2 and sp95<=2 and s.controller.state.n>storage.benchmark_start)
      log('CC2 PROGRAMS METRIC phase=echo samples=100 editor_p95='..ep95..' shell_p95='..sp95..' callback_nodes='..storage.maximum.nodes..' callback_statements='..storage.maximum.statements)
      storage.controller=s.controller; storage.editor=s.editor; storage.saved_n=s.controller.state.n
      send(s,{n=2,'char','C'}); storage.saved_tick=game.tick
      assert(Budget.admit(storage.ledger,1,{execution=Budget.remaining(storage.ledger,1,'execution')}))
      Factory.freeze(storage.factory)
      storage.stage='snapshot'; storage.before=packed(s); storage.budget=packed(storage.ledger)
      game.server_save('cc2-resume'); log('CC2 PROGRAMS SNAPSHOT'); log('CC2 PROGRAMS COMPLETE FIRST checks='..storage.checks)
    end
  elseif stage=='resume-input' then
    check('cold queued editor input applies once and blocks no native input',s.editor.text:sub(-1)=='C' and #s.editor.text==101)
    storage.stage='resume-callback'
  elseif stage=='resume-callback' and s.controller.state.n>storage.saved_n then
    check('cold callback revalidates exact source and resumes state without start replay',s.controller.started and s.controller.source==storage.maximum.source and s.editor.dirty)
    send(s,{n=1,'terminate'}); storage.stage='dirty-exit'
  elseif stage=='dirty-exit' and s.editor and s.editor.confirm then
    send(s,{n=2,'char','d'}); storage.stage='stop'
  elseif stage=='stop' and not s.editor then
    queue_command(s,'stop'); storage.stage='stopped'
  elseif stage=='stopped' and s.controller.status=='stopped' then
    check('explicit stop halts only native background owner',s.status=='ready' and s.controller==storage.controller and storage.neighbor.command==string.rep('s',100))
    storage.stage='factory-resume'
  elseif stage=='factory-resume' and storage.factory.phase=='done' then
    storage.stage='done'; log('CC2 PROGRAMS COMPLETE RELOAD checks='..storage.checks)
  end
end)
