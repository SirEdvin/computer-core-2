local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Events=require('__computer_core_2__.scripts.native.events')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local function create(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-scalar')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick)
 local m=s.machines[1]
 for i=0,200 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or m.status=='yield' then return m end
 end
 error('scalar fixture failed to finish')
end
local source=[[
local first,last,step='1','5','2'
local sum=0
for i=first,last,step do sum=sum+i end
return '2'+3,4-'2','3'*2,'9'/3,'7'%4,2^'3',-'5',
 'leaf'<'root','leaf'<='leaf','root'>'leaf','root'>='root',
 'root'=='root','root'~='leaf',1=='1','a' .. 7 .. 'b',#{false,7,8},#'branch',sum,nil
]]
return {
 run=function(check)
  local inline=assert(Compiler.compile('return left+right,left<right','=native-inline-operators'))
  check('native metered operators remain direct Lua rather than symbolic operation dispatch',inline.version==4
   and inline.generated:find('local l,r=a.b(',1,true)~=nil and inline.generated:find('l+r',1,true)~=nil
   and inline.generated:find('local l,r=a.q(',1,true)~=nil and inline.generated:find('l<r',1,true)~=nil)
  local s,m=create(source); finish(s,10)
  local expected=table.pack(assert(load(source,'=scalar-reference','t',{}))())
  check('native metered scalar operators retain fixed-reference arity',m.status=='return' and m.result.n==expected.n)
  for i=1,expected.n do check('native metered scalar reference value '..i,m.result[i]==expected[i]) end
  check('native scalar operands bill shared byte table and continuation domains',(s.budget.used.string or 0)>0
   and (s.budget.used.table or 0)==4+3*(16+8) and (s.budget.used.continuation or 0)>0)
  s,m=create('local l,r=left,right; coroutine.yield(); answer=l+r; return answer')
  local left,right=string.rep(' ',16384)..'2',string.rep(' ',16384)..'3'
  Execution.set(m,m.env,'left',left); Execution.set(m,m.env,'right',right); Execution.set(m,m.env,'answer','before')
  finish(s,99); assert(m.status=='yield')
  Scheduler.begin_tick(s,100)
  local before=Limits.string_work_per_computer-(#left+#right)+1
  assert(Scheduler.consume(s,1,'string',before))
  assert(Events.admit(m,table.pack('char','continue'))); Scheduler.tick(s,100)
  check('native paired arithmetic refuses before parsing or publishing either operand',m.status=='error'
   and Execution.get(m,m.env,'answer')=='before' and s.budget.used.string==before)
  for _,op in ipairs({'<','<=','>','>=','==','~='}) do
   s,m=create('local l,r,kept,protect=left,right,kept,pcall; coroutine.yield(); local ok=protect(function() return l '..op..' r end); return ok,kept')
   left,right=string.rep('x',32768),string.rep('y',32768)
   Execution.set(m,m.env,'left',left); Execution.set(m,m.env,'right',right); Execution.set(m,m.env,'kept','before')
   finish(s,199); assert(m.status=='yield')
   Scheduler.begin_tick(s,200)
   before=Limits.string_work_per_computer-(#left+#right)+1
   assert(Scheduler.consume(s,1,'string',before)); assert(Events.admit(m,table.pack('char','continue'))); Scheduler.tick(s,200)
   check('native string comparison '..op..' reserves both inputs before opaque comparison',m.status=='return'
    and m.result[1]==false and m.result[2]=='before' and s.budget.used.string==before)
  end
  s,m=create('return left .. right')
  left,right=string.rep('a',Limits.string_bytes/2),string.rep('b',Limits.string_bytes/2)
  Execution.set(m,m.env,'left',left); Execution.set(m,m.env,'right',right)
  finish(s,300)
  check('native maximum concatenation accepts unchanged output quota and bills input joining',m.status=='return'
   and m.result[1]==left..right and s.budget.used.string==2*(#left+#right)+11)
  s,m=create('local l,r,protect=left,right,pcall; coroutine.yield(); return protect(function() answer=l .. r end)')
  Execution.set(m,m.env,'left',left); Execution.set(m,m.env,'right',right); Execution.set(m,m.env,'answer','before')
  finish(s,399); assert(m.status=='yield')
  Scheduler.begin_tick(s,400)
  before=Limits.string_work_per_computer-2*(#left+#right)+1
  assert(Scheduler.consume(s,1,'string',before)); assert(Events.admit(m,table.pack('char','continue'))); Scheduler.tick(s,400)
  check('native refused concatenation preserves target and shared byte ledger',m.status=='return'
   and m.result[1]==false and Execution.get(m,m.env,'answer')=='before' and s.budget.used.string==before)
  s,m=create('return #input')
  local input=Execution.table_value(m)
  for i=1,Limits.table_keys do Execution.set(m,input,i,false) end
  Execution.set(m,m.env,'input',input); finish(s,500)
  check('native maximum table length scan is bounded and metered',m.status=='return' and m.result[1]==Limits.table_keys
   and s.budget.used.table==Limits.table_keys+8)
  s,m=create('local input,protect=input,pcall; coroutine.yield(); return protect(function() answer=#input end)')
  input=Execution.table_value(m)
  for i=1,32 do Execution.set(m,input,i,false) end
  Execution.set(m,m.env,'input',input); Execution.set(m,m.env,'answer','before')
  finish(s,599); assert(m.status=='yield')
  Scheduler.begin_tick(s,600); assert(Scheduler.consume(s,1,'table',Limits.table_work_per_computer-7))
  assert(Events.admit(m,table.pack('char','continue'))); Scheduler.tick(s,600)
  check('native partial length-scan refusal leaves table and assignment intact',m.status=='return'
   and m.result[1]==false and Execution.get(m,m.env,'answer')=='before' and m.heap[input.native_ref].keys==32
   and s.budget.used.table==Limits.table_work_per_computer)
  s,m=create('local first,last,step,protect=first,last,step,pcall; coroutine.yield(); return protect(function() for i=first,last,step do entered=true end end)')
  Execution.set(m,m.env,'first','1'); Execution.set(m,m.env,'last','3'); Execution.set(m,m.env,'step','1')
  finish(s,699); assert(m.status=='yield')
  Scheduler.begin_tick(s,700); assert(Scheduler.consume(s,1,'string',Limits.string_work_per_computer-2))
  assert(Events.admit(m,table.pack('char','continue'))); Scheduler.tick(s,700)
  check('native numeric-for reserves all conversions before loop entry',m.status=='return' and m.result[1]==false
   and Execution.get(m,m.env,'entered')==nil and s.budget.used.string==Limits.string_work_per_computer-2)
  s,m=create('return 2+3,2<3,2==3,not false')
  finish(s,800)
  check('native numeric-only operators do not bill string work',m.status=='return' and (s.budget.used.string or 0)==0)
  s,m=create("return native,rawget(_ENV,'native.work')")
  finish(s,900)
  check('native generated work callback has no guest global identity',m.status=='return' and m.result.n==2
   and m.result[1]==nil and m.result[2]==nil)
 end,
 suspend=function(check)
  local s,m=create([[
boot=(boot or 0)+1
local left,right='12','30'
local before=left+right
coroutine.yield()
return before,left+right,boot,nil
]])
  finish(s,game.tick); assert(m.status=='yield')
  assert(Scheduler.consume(s,1,'string',Limits.string_work_per_computer-(s.budget.used.string or 0)))
  assert(Scheduler.consume(s,1,'execution',Limits.instructions_per_computer-(s.budget.used.execution or 0)))
  Collector.start(m)
  check('native scalar snapshot retains exhausted shared byte and execution credits',m.collector~=nil)
  return {scheduler=s,tick=game.tick,blocks=m.blocks}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native scalar load preserves byte ledger and executes no operator',m.blocks==state.blocks
   and s.budget.used.string==Limits.string_work_per_computer and s.budget.used.execution==Limits.instructions_per_tick)
  assert(Events.admit(m,table.pack('char','continue')))
  Scheduler.tick(s,state.tick)
  check('native same-tick scalar reentry cannot renew credits or consume next event',m.blocks==state.blocks
   and m.delivered_events==nil and s.budget.used.string==Limits.string_work_per_computer)
  for i=1,200 do
   Scheduler.tick(s,state.tick+i)
   if m.status=='return' or m.status=='error' then break end
  end
  check('native scalar expression resumes after collected reload without replay',m.status=='return' and m.result.n==4
   and m.result[1]==42 and m.result[2]==42 and m.result[3]==1 and m.result[4]==nil and s.budget.used.string==9)
 end,
}
