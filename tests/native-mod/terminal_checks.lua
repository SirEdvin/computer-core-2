local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Events=require('__computer_core_2__.scripts.native.events')
local Terminal=require('__computer_core_2__.scripts.native.terminal')
local Display=require('__computer_core_2__.scripts.guest.terminal')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local function equal(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local function create(source,w,h)
 local m=Execution.new(assert(Compiler.compile(source,'=native-terminal')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m); Terminal.install(m,w,h)
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick,terminal)
 local m=s.machines[1]
 for i=0,100 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or (m.status=='yield' and not terminal) then return m end
 end
 error('native terminal fixture deadline exceeded')
end
local source=[[
term.setCursorPos(-1,2)
term.write('leaf')
term.setCursorPos(3,1)
term.blit('xyz','123','abc')
term.setCursorBlink(true)
term.setTextColour(2)
term.setBackgroundColor(4)
term.setCursorPos(1,3)
term.clearLine()
term.scroll(1)
term.scroll(-1)
term.setPaletteColour(8,0x123456)
term.setPaletteColor(16,0.1,0.2,0.3)
local w,h=term.getSize()
local x,y=term.getCursorPos()
local r,g,b=term.getPaletteColour(16)
return w,h,x,y,term.getCursorBlink(),term.getTextColor(),term.getBackgroundColour(),r,g,b,
 term.isColor(),term.isColour(),select('#',term.setCursorPos(x,y)),nil
]]
return {
 run=function(check)
  local rs,rm=create('return true',7,4)
  local before=serpent.line({display=rm.display,events=rm.events},{sortkeys=true})
  for _,domain in ipairs({'terminal','event'}) do
   local ok=pcall(Terminal.reconcile,rm,11,6,function(name) return name~=domain end)
   check('native resize '..domain..' credit refusal preserves complete display and notification queue',not ok
    and serpent.line({display=rm.display,events=rm.events},{sortkeys=true})==before)
  end
  local ok=pcall(Terminal.reconcile,rm,161,6,function() error('invalid geometry must not request credits') end)
  check('native resize invalid geometry refuses before credit or state mutation',not ok
   and serpent.line({display=rm.display,events=rm.events},{sortkeys=true})==before)
  Scheduler.begin_tick(rs,1)
  local alias=rm.display
  local changed=Terminal.reconcile(rm,11,6,function(domain,amount) return Scheduler.consume(rs,1,domain,amount) end)
  local events=#rm.events.queue; local revision=rm.display.revision
  check('native resize keeps display alias admits one priority notification and is idempotent',changed and rm.display==alias
   and rm.display.columns==11 and rm.display.rows==6 and events==1 and rm.events.queue[1].tuple[1]=='term_resize'
   and not Terminal.reconcile(rm,11,6,function() error('unchanged geometry is free') end)
   and #rm.events.queue==events and rm.display.revision==revision)
  local s,m=create(source,7,4); finish(s,10)
  local reference=Display.new(7,4); local term={}
  for name,handler in pairs(Display.methods) do
   local fn=handler
   term[name]=function(...) return fn(reference,...) end
  end
  local expected=table.pack(assert(load(source,'=terminal-contract','t',{term=term,select=select}))())
  check('native terminal compiled cursor blink palette colors aliases and return arity match existing contract',m.status=='return'
   and equal(m.result,expected) and equal(m.display,reference))
  local display=m.display; local library=Execution.get(m,m.env,'term'); local objects=m.objects
  Terminal.install(m,160,60)
  check('native terminal installation preserves live geometry display and service identities',m.display==display
   and Execution.get(m,m.env,'term')==library and m.objects==objects)
  s,m=create("term.setCursorPos(1,1); term.write('abc'); return select('#',term.clear())",3,2); finish(s,100)
  check('native terminal clear returns no values and publishes bounded blank rows',m.status=='return' and m.result[1]==0
   and m.display.lines[1].text=='   ' and m.display.lines[2].text=='   ')
  local rejected={
   {'write',table.pack('leaf')},{'blit',table.pack('leaf','0000','ffff')},
   {'clear',table.pack()},{'clearLine',table.pack()},{'scroll',table.pack(1)},
   {'setCursorPos',table.pack(2,2)},{'setCursorBlink',table.pack(true)},
   {'setTextColor',table.pack(2)},{'setTextColour',table.pack(2)},
   {'setBackgroundColor',table.pack(2)},{'setBackgroundColour',table.pack(2)},
   {'setPaletteColor',table.pack(2,0x123456)},{'setPaletteColour',table.pack(2,0x123456)},
  }
  local refused=Terminal.services(function() return false end)
  for _,case in ipairs(rejected) do
   local before=serpent.line(m.display,{sortkeys=true})
   local ok=pcall(refused['term.'..case[1]],m,case[2])
   check('native terminal refused mutation preserves full display '..case[1],not ok
    and before==serpent.line(m.display,{sortkeys=true}))
  end
  local invalid={
   {'blit',table.pack('x','z','f')},{'blit',table.pack('xx','0','ff')},
   {'write',table.pack({native_ref=m.env.native_ref})},
   {'setCursorPos',table.pack(0/0,1)},{'scroll',table.pack(math.huge)},
   {'setCursorBlink',table.pack(1)},{'setTextColor',table.pack(3)},
   {'setPaletteColour',table.pack(2,0.1,nil,0.3)},
  }
  local accepted=Terminal.services(function() return true end)
  for _,case in ipairs(invalid) do
   local before=serpent.line(m.display,{sortkeys=true})
   local ok=pcall(accepted['term.'..case[1]],m,case[2])
   check('native terminal invalid input is atomic '..case[1],not ok and before==serpent.line(m.display,{sortkeys=true}))
  end
  s,m=create("local ok=pcall(term.write,'leaf'); return ok",7,4)
  Scheduler.begin_tick(s,200); assert(Scheduler.consume(s,1,'terminal',Limits.terminal_work_per_computer))
  local before=serpent.line(m.display,{sortkeys=true}); finish(s,200)
  check('native terminal compiled protected quota refusal preserves display and spent ledger',m.status=='return' and m.result[1]==false
   and before==serpent.line(m.display,{sortkeys=true}) and s.budget.used.terminal==Limits.terminal_work_per_computer)
  s,m=create('return 1',160,60); Scheduler.begin_tick(s,300)
  local services=Terminal.services(function(amount) return Scheduler.consume(s,1,'terminal',amount) end)
  local cost=Display.work(m.display,'clear',table.pack())
  local count=0
  while Scheduler.remaining(s,1,'terminal')>=cost do services['term.clear'](m,table.pack()); count=count+1 end
  before=serpent.line(m.display,{sortkeys=true})
  local prior=s.budget.used.terminal
  local ok=pcall(services['term.clear'],m,table.pack())
  check('native maximum geometry repeated clear fits and refuses before publication',count>0 and not ok
   and prior==s.budget.used.terminal and before==serpent.line(m.display,{sortkeys=true})
   and m.display.columns==160 and #m.display.lines==60 and #m.display.lines[60].text==160)
  local _,other=create('return 1',160,60); Scheduler.add(s,2,other)
  local services2=Terminal.services(function(amount) return Scheduler.consume(s,2,'terminal',amount) end)
  services2['term.clear'](other,table.pack())
  check('native terminal per-machine exhaustion does not consume neighbor allowance',s.budget.machines[2].terminal==cost
   and s.budget.used.terminal==prior+cost)
  assert(Scheduler.consume(s,2,'terminal',Scheduler.remaining(s,2,'terminal')))
  local _,third=create('return 1',160,60); Scheduler.add(s,3,third)
  assert(Scheduler.consume(s,3,'terminal',Scheduler.remaining(s,3,'terminal')))
  check('native terminal aggregate ceiling stays unchanged',s.budget.used.terminal==Limits.terminal_work_per_tick
   and not Scheduler.consume(s,3,'terminal',1))
  local maximum={
   {'write',table.pack(string.rep('x',Limits.string_bytes))},
   {'blit',table.pack(string.rep('x',Limits.string_bytes),string.rep('0',Limits.string_bytes),string.rep('f',Limits.string_bytes))},
   {'scroll',table.pack(2147483647)}, {'scroll',table.pack(-2147483647)},
   {'clearLine',table.pack()}, {'setPaletteColour',table.pack(2,0xffffff)},
  }
  for i,case in ipairs(maximum) do
   local state,value=create('return 1',160,60)
   local original=Display.new(160,60)
   Scheduler.begin_tick(state,350+i)
   local service=Terminal.services(function(amount) return Scheduler.consume(state,1,'terminal',amount) end)
   local status,result=service['term.'..case[1]](value,case[2])
   local reference_result=table.pack(Display.methods[case[1]](original,table.unpack(case[2],1,case[2].n)))
   check('native maximum geometry service retains clipped cells palette dirty rows and exact admission '..i,status=='return'
    and equal(result,reference_result) and equal(value.display,original)
    and state.budget.used.terminal==Display.work(original,case[1],case[2])
    and state.budget.used.terminal<=Limits.terminal_work_per_computer)
  end
  local geometry_state,geometry_machine=create('return 1',7,4)
  local original=Display.new(7,4)
  Display.methods.setCursorPos(geometry_machine.display,2,2); Display.methods.write(geometry_machine.display,'leaf')
  Display.methods.setCursorPos(original,2,2); Display.methods.write(original,'leaf')
  local alias=geometry_machine.display
  check('native display geometry reconciliation preserves authoritative alias and overlap',Display.reconcile(alias,4,3)
   and Display.reconcile(original,4,3) and equal(alias,original) and geometry_machine.display==alias
   and alias.lines[2].text==' lea' and not Display.reconcile(alias,4,3))
  s,m=create('for i=1,100 do pcall(term.clear) end; return true',160,60)
  local _,neighbor=create('while true do term.setCursorBlink(true) end',7,4); Scheduler.add(s,2,neighbor)
  for i=1,12 do Scheduler.tick(s,400+i) end
  check('native maximum geometry workload shares scheduler with another terminal',neighbor.blocks>0
   and s.budget.used.execution<=Limits.instructions_per_tick
   and (s.budget.used.terminal or 0)<=Limits.terminal_work_per_tick)
 end,
 suspend=function(check)
  local s,m=create([[
boot=(boot or 0)+1
term.setCursorPos(2,2); term.blit('leaf','1234','abcd'); term.setCursorBlink(true)
term.setPaletteColour(2,0x123456)
local write=term.write
term=nil
coroutine.yield('display-ready')
write('!')
return boot,nil
]],9,4)
  finish(s,game.tick); assert(m.status=='yield')
  assert(Scheduler.consume(s,1,'terminal',Scheduler.remaining(s,1,'terminal')))
  Collector.start(m)
  local before=serpent.line(m.display,{sortkeys=true})
  check('native terminal snapshot retains display and exhausted ledger during collection',m.collector~=nil
   and m.display.lines[2].text==' leaf    ' and m.display.x==6 and m.display.blink)
  return {scheduler=s,tick=s.budget.tick,display=m.display,before=before,blocks=m.blocks}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native terminal load preserves display alias revision and tick exhaustion',m.display==state.display
   and serpent.line(m.display,{sortkeys=true})==state.before and m.blocks==state.blocks
   and Scheduler.remaining(s,1,'terminal')==0)
  local services=Terminal.services(function(amount) return Scheduler.consume(s,1,'terminal',amount) end)
  local ok=pcall(services['term.write'],m,table.pack('wrong'))
  check('native terminal same-tick reload refuses without display mutation',not ok
   and serpent.line(m.display,{sortkeys=true})==state.before)
  assert(Events.admit(m,table.pack('char','resume')))
  finish(s,state.tick+1,true)
  check('native collected saved write service resumes without replay or global library',m.status=='return'
   and m.result.n==2 and m.result[1]==1 and m.display.lines[2].text==' leaf!   ' and m.display.x==7
   and m.display.blink and m.display.palette[2].r==0x12/255 and m.display.dirty[2])
 end,
}
