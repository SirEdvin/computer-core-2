local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Events=require('__computer_core_2__.scripts.native.events')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local function create(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-construction')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick)
 local m=s.machines[1]
 for i=0,200 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or m.status=='yield' then return m end
 end
 error('construction fixture failed to finish')
end
local source=[[
local function make(...) return {...},select('#',...) end
local marker={name='leaf'}
local t,n=make(marker,nil,false,7,nil)
local keyed={first=marker,[false]='false key',[marker]='reference key'}
return n,t[1]==marker,t[2],t[3],t[4],t[5],keyed.first==marker,keyed[false],keyed[marker],nil
]]
-- Synthetic trusted executable blocks isolate private API preflight on an
-- existing table; ordinary source and reload checks below use compiled code.
local function block(s,m,body,tick,domain,remaining)
 m.frames[1].pc=1
 Scheduler.begin_tick(s,tick)
 if domain then assert(Scheduler.consume(s,1,domain,Limits[domain..'_work_per_computer']-remaining)) end
 local services=Helpers.services(function(d,amount) return Scheduler.consume(s,1,d,amount) end)
 Execution.run(m,m.bundle,{{function(f,a,t) body(f,a,t); return 'return',{n=0} end}},1,services)
end
return {
 run=function(check)
  local s,m=create(source); finish(s,10)
  local expected=table.pack(assert(load(source,'=construction-reference','t',{select=select}))())
  check('native weighted constructors retain fixed-reference tuple arity',m.status=='return' and m.result.n==expected.n)
  for i=1,expected.n do check('native weighted construction reference value '..i,m.result[i]==expected[i]) end
  check('native constructors and list assembly bill both shared work domains',(s.budget.used.table or 0)>0
   and (s.budget.used.continuation or 0)>0)
  s,m=create('local function make(...) return {...} end; return make(donor())')
  Execution.service(m,'donor')
  local maximum={n=Limits.tuple_values, [1]=false,[Limits.tuple_values]='edge'}
  Scheduler.tick(s,100,{donor=function() return 'return',maximum end})
  local ref=m.result and m.result[1]
  check('native maximum sparse vararg constructor retains false nil holes and final slot',m.status=='return'
   and Execution.get(m,ref,1)==false and Execution.get(m,ref,2)==nil
   and Execution.get(m,ref,Limits.tuple_values)=='edge' and m.heap[ref.native_ref].keys==2
   and s.budget.used.table==24+8*Limits.tuple_values and s.budget.used.continuation>=1+4*Limits.tuple_values)
  s,m=create('return 1')
  local input=Execution.table_value(m); Execution.set(m,input,1,'old'); Execution.set(m,input,2,false)
  block(s,m,function(_,a) a.array(input,1,{n=3,'new',nil,'tail'}) end,200,'table',16+8*3-1)
  check('native array copy refuses before modifying any existing slots',Execution.get(m,input,1)=='old'
   and Execution.get(m,input,2)==false and Execution.get(m,input,3)==nil
   and m.heap[m.active].pending.kind=='unwind' and s.budget.used.table==Limits.table_work_per_computer-(16+8*3-1))
  s,m=create('return 1'); input=Execution.table_value(m)
  for i=2,Limits.table_keys+1 do Execution.set(m,input,i,false) end
  block(s,m,function(_,a) a.array(input,1,{n=2,'new','replacement'}) end,300)
  check('native array key-capacity refusal preflights before any partial replacement',Execution.get(m,input,1)==nil
   and Execution.get(m,input,2)==false and m.heap[input.native_ref].keys==Limits.table_keys
   and m.heap[m.active].pending.kind=='unwind')
  s,m=create('return 1'); input=Execution.table_value(m)
  for i=2,Limits.table_keys+1 do Execution.set(m,input,i,false) end
  block(s,m,function(_,a) a.array(input,1,{n=2,'new',nil}) end,400)
  check('native full-key array replacement removes holes before installing accepted keys',Execution.get(m,input,1)=='new'
   and Execution.get(m,input,2)==nil and m.heap[input.native_ref].keys==Limits.table_keys
   and m.heap[m.active].pending.kind=='return')
  s,m=create('return 1'); input=Execution.table_value(m); Execution.set(m,input,'key','old')
  block(s,m,function(_,a) a.set(input,'key','new') end,500,'table',7)
  check('native keyed constructor setter refuses before overwriting existing value',Execution.get(m,input,'key')=='old'
   and s.budget.used.table==Limits.table_work_per_computer-7)
  s,m=create('return 1')
  local tuple={n=2,'old',nil}
  block(s,m,function(_,a) a.append(tuple,{n=2,false,'new'},true) end,600,'continuation',8)
  check('native tuple append refusal preserves original arity and values',tuple.n==2 and tuple[1]=='old'
   and tuple[2]==nil and tuple[3]==nil and s.budget.used.continuation==Limits.continuation_work_per_computer-8)
  s,m=create('return 1')
  local result='before'
  block(s,m,function(_,a) result=a.copy({n=Limits.tuple_values,[1]=false,[Limits.tuple_values]='edge'}) end,
   700,'continuation',4*Limits.tuple_values)
  check('native maximum vararg copy refuses before publishing output',result=='before'
   and s.budget.used.continuation==Limits.continuation_work_per_computer-4*Limits.tuple_values)
  s,m=create('local protect=pcall; coroutine.yield(); return protect(function() answer={1,2,3} end)')
  Execution.set(m,m.env,'answer','old')
  finish(s,799); assert(m.status=='yield')
  Scheduler.begin_tick(s,800); assert(Scheduler.consume(s,1,'table',Limits.table_work_per_computer))
  assert(Events.admit(m,table.pack('char','continue'))); Scheduler.tick(s,800)
  check('native constructor quota failure is protected and cannot publish partial table',m.status=='return'
   and m.result[1]==false and Execution.get(m,m.env,'answer')=='old')
  s,m=create('local ok=pcall(function() sink(1,nil,false,nil) end); return ok')
  Execution.service(m,'sink'); local called=false
  Scheduler.begin_tick(s,900); assert(Scheduler.consume(s,1,'continuation',Limits.continuation_work_per_computer))
  Scheduler.tick(s,900,{sink=function() called=true; return 'return',{n=0} end})
  check('native list quota refusal reaches protected receiver without invoking callee',m.status=='return'
   and m.result[1]==false and not called)
 end,
 suspend=function(check)
  local s,m=create([[
boot=(boot or 0)+1
local marker={name='held'}
local function make(...) return {...},select('#',...) end
local first,n=make(marker,nil,false,nil)
coroutine.yield()
local second,count=make(first[1],nil,first[3],nil)
return n,count,first[1]==second[1],second[1].name,second[3],second[4],boot,nil
]])
  finish(s,game.tick); assert(m.status=='yield')
  assert(Scheduler.consume(s,1,'table',Limits.table_work_per_computer-(s.budget.used.table or 0)))
  assert(Scheduler.consume(s,1,'continuation',Limits.continuation_work_per_computer-(s.budget.used.continuation or 0)))
  Collector.start(m)
  check('native constructor snapshot retains exhausted tuple and table credits',m.collector~=nil)
  return {scheduler=s,tick=game.tick,blocks=m.blocks}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native constructor load preserves ledgers without replaying initializer',m.blocks==state.blocks and m.collector~=nil
   and s.budget.used.table==Limits.table_work_per_computer and s.budget.used.continuation==Limits.continuation_work_per_computer)
  assert(Events.admit(m,table.pack('char','continue')))
  for i=1,200 do
   Scheduler.tick(s,state.tick+i)
   if m.status=='return' or m.status=='error' then break end
  end
  check('native weighted varargs and constructors retain aliases nil arity and false through reload',m.status=='return'
   and m.result.n==8 and m.result[1]==4 and m.result[2]==4 and m.result[3]==true and m.result[4]=='held'
   and m.result[5]==false and m.result[6]==nil and m.result[7]==1 and m.result[8]==nil)
 end,
}
