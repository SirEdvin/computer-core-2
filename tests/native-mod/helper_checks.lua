local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Helpers = require('__computer_core_2__.scripts.native.helpers')
local Scheduler = require('__computer_core_2__.scripts.native.scheduler')
local Collector = require('__computer_core_2__.scripts.native.collector')
local Events = require('__computer_core_2__.scripts.native.events')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local SortChecks = require('sort_checks')
local TableChecks = require('table_checks')
local ScalarChecks = require('scalar_checks')
local ConstructionChecks = require('construction_checks')
local IteratorChecks = require('iterator_checks')
local NextChecks = require('next_checks')
local PatternSource = require('__computer_core_2__.scripts.guest.patterns')
local PatternChecks = require('pattern_checks')
local function create(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-helper')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 local s=Scheduler.new(); Scheduler.add(s,1,m)
 return s,m
end
local function finish(s,tick)
 local m=s.machines[1]
 for i=0,200 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or m.status=='yield' then return m end
 end
 error('helper fixture failed to finish')
end
local source=[[
local p=table.pack(1,nil,3,nil)
local a,b,c,d=table.unpack(p,1,p.n)
local x,y=string.find('roots.leaves','.',1,true)
return p.n,a,b,c,d,select('#',a,b,c,d),select(-2,a,b,c,d),
 tonumber('ff',16),tonumber('9',2),tonumber(' 12.5 '),
 tostring(nil),tostring(false),string.len('forest'),string.sub('forest',-3),
 string.sub('forest',9000000000000),string.sub('forest',1,-9000000000000),
 string.byte('AZ',1,2),string.char(65,0,90),string.rep('a',3,'-'),
 string.rep('',9000000000000),string.lower('ROOT'),string.upper('leaf'),string.reverse('tree'),x,y,
 table.concat({'root',7,'leaf'},':'),table.concat({},','),table.concat({'a','b','c'},'-',2,3),
 string.format('%04x %+.2f %.3s %%',15,1.25,'forest'),string.format('%q','leaf\n'),nil
]]
local math_source=[[
local mantissa,exponent=math.frexp(8)
local whole,fraction=math.modf(3.25)
return math.floor('3.9'),math.ceil(-3.9),math.max('2',3,1),math.min(2,'-3',1),
 math.log('8','2'),math.abs(-7),math.sqrt(16),math.pow(2,3),math.fmod(7,3),
 math.atan2(0,1),math.cos(0),math.sin(0),math.tan(0),math.cosh(0),math.sinh(0),math.tanh(0),
 math.acos(1),math.asin(0),math.atan(0),math.deg(math.pi),math.rad(180),math.exp(0),math.log10(100),
 mantissa,exponent,math.ldexp(mantissa,exponent),whole,fraction,math.huge,nil
]]
return {
 run=function(check)
  SortChecks.run(check)
  TableChecks.run(check)
  ScalarChecks.run(check)
  ConstructionChecks.run(check)
  IteratorChecks.run(check)
  NextChecks.run(check)
  local pattern_metrics = {}
  local pattern_bundle, pattern_error = Compiler.compile(PatternSource, '=native-pattern-library', pattern_metrics)
  log('CC2 NATIVE PATTERN COMPILE '..serpent.line({ok=pattern_bundle~=nil,error=pattern_error,metrics=pattern_metrics}))
  check('native monolithic pattern library refuses at unchanged output cap',pattern_bundle==nil and pattern_error=='native generated output limit exceeded')
  PatternChecks.run(check)
  local s,m=create(source); finish(s,10)
  -- Fixed authored reference source only; never an alternate guest loader.
  local reference=table.pack(assert(load(source,'=helper-reference','t',{
   table=table,string=string,tonumber=tonumber,tostring=tostring,select=select}))())
  check('native scalar tuple and string helpers match fixed host reference',m.status=='return' and m.result.n==reference.n)
  for i=1,reference.n do check('native helper reference value '..i,m.result[i]==reference[i]) end
  local ms,mm=create(math_source); finish(ms,200)
  local expected=table.pack(assert(load(math_source,'=math-reference','t',{math=math}))())
  check('native scalar math helpers retain reference result arity',mm.status=='return' and mm.result.n==expected.n)
  for i=1,expected.n do check('native math reference value '..i,mm.result[i]==expected[i]) end
  s,m=create([[local old=string; string={}; return ('forest'):sub(2,4),('leaf'):upper(),('tree').missing==nil]])
  finish(s,250)
  check('native string methods use original library despite replaced global',m.status=='return' and m.result[1]=='ore'
   and m.result[2]=='LEAF' and m.result[3]==true)
  s,m=create([[
setmetatable(string,{__index=function(library,key)
 local resumed=coroutine.yield('lookup',nil,key)
 return function(value) return resumed,value end
end})
local child=coroutine.create(function() return ('leaf'):custom() end)
local ok,tag,gap,key=coroutine.resume(child)
local success,resumed,value=coroutine.resume(child,'ready')
return ok,tag,gap,key,success,resumed,value,nil
]])
  finish(s,275)
  check('native string-library metamethod lookup suspends through the guest resumer',m.status=='return' and m.result.n==8
   and m.result[1]==true and m.result[2]=='lookup' and m.result[3]==nil and m.result[4]=='custom'
   and m.result[5]==true and m.result[6]=='ready' and m.result[7]=='leaf' and m.result[8]==nil)
  check('native helper identities contain no host functions',Execution.type(m,Execution.get(m,m.env,'tostring'))=='function'
   and type(m.heap[Execution.get(m,m.env,'table').native_ref].values.spack)=='table')
  s,m=create('local t={}; return tostring(t),tostring(t)'); finish(s,300)
  check('native tostring uses stable guest identity not host wrapper address',m.status=='return' and m.result[1]==m.result[2]
   and m.result[1]:sub(1,7)=='table: ')
  -- Atomic refusal before a pack allocation, including aggregate/table counters.
  s,m=create('return 1'); Scheduler.begin_tick(s,400)
  assert(Scheduler.consume(s,1,'table',Limits.table_work_per_computer))
  local services=Helpers.services(function(domain,amount)
   assert(Scheduler.consume(s,1,domain,amount),'fixture quota refusal')
  end)
  local objects,next_id=m.objects,m.next_id
  check('native refused pack cannot allocate or mutate shared counters',not pcall(services['table.pack'],m,table.pack(1,nil,3))
   and m.objects==objects and m.next_id==next_id and s.budget.used.table==Limits.table_work_per_computer)
  local bytes=string.rep('x',Limits.string_bytes)
  Scheduler.begin_tick(s,401)
  local _,result=services['string.sub'](m,table.pack(bytes,1,1))
  check('native tiny slice charges output not entire backing string',result[1]=='x' and s.budget.used.string==1)
  local before=s.budget.used.string
  check('native oversized repeated output refuses before spending',not pcall(services['string.rep'],m,table.pack('x',Limits.string_bytes+1))
   and s.budget.used.string==before)
  check('native malformed helper index cannot poison counters',not pcall(services['string.sub'],m,table.pack('x',math.huge))
   and s.budget.used.string==before)
  for _,name in ipairs({'match','gmatch','gsub'}) do
   local status,operation=services['string.'..name](m,table.pack('x','x'))
   check('native pattern helper uses private continuation '..name,status=='continue' and operation.kind=='helper')
  end
  check('native unsupported bytecode dumping fails explicitly',not pcall(services['string.dump'],m,table.pack('x')))
  local pattern_status=services['string.find'](m,table.pack('x','.*'))
  check('native patterned find is not opaque host execution',pattern_status=='continue')
  local refused=Helpers.services(function() return false end)
  check('native helper false admission cannot perform output work',not pcall(refused['string.sub'],m,table.pack('forest',1,1)))
  local original=s.budget.used.string
  check('native worst-case plain-search estimate refuses before opaque search',not pcall(services['string.find'],m,
   table.pack(bytes,bytes,1,true)) and s.budget.used.string==original)
  local pack_services=Helpers.services(function() end)
  local maximum={n=Limits.tuple_values}
  maximum[1],maximum[Limits.tuple_values-1]='edge',7
  local _,packed=pack_services['table.pack'](m,maximum)
  local _,unpacked=pack_services['table.unpack'](m,table.pack(packed[1],1,Limits.tuple_values))
  check('native table helpers preserve maximum sparse tuple including trailing nil',unpacked.n==Limits.tuple_values
   and unpacked[1]=='edge' and unpacked[Limits.tuple_values-1]==7 and unpacked[Limits.tuple_values]==nil)
  check('native unpack refuses excessive tuple before readback',not pcall(pack_services['table.unpack'],m,
   table.pack(packed[1],1,Limits.tuple_values+1)))
  local _,number=services['math.floor'](m,table.pack(3.9))
  check('native numeric-only math does not consume byte work',number[1]==3 and s.budget.used.string==original)
  assert(Scheduler.consume(s,1,'string',Limits.string_work_per_computer-s.budget.used.string))
  local exhausted=s.budget.used.string
  check('native paired math conversions refuse without poisoning byte counter',not pcall(services['math.log'],m,table.pack('8','2'))
   and s.budget.used.string==exhausted)
  local one=Execution.table_value(m)
  Execution.set(m,one,1,bytes)
  Scheduler.begin_tick(s,402)
  local _,joined=services['table.concat'](m,table.pack(one))
  check('native maximum concat output fits unchanged string allowance',joined[1]==bytes and s.budget.used.string==2*#bytes)
  local before_table=Execution.get(m,one,1)
  assert(Scheduler.consume(s,1,'string',Limits.string_work_per_computer-s.budget.used.string))
  check('native refused concat preserves input and shared byte counter',not pcall(services['table.concat'],m,table.pack(one))
   and Execution.get(m,one,1)==before_table and s.budget.used.string==Limits.string_work_per_computer)
  Scheduler.begin_tick(s,403)
  local two=Execution.table_value(m); Execution.set(m,two,1,bytes); Execution.set(m,two,2,'x')
  check('native excessive concat output refuses without input mutation',not pcall(services['table.concat'],m,table.pack(two))
   and Execution.get(m,two,1)==bytes and Execution.get(m,two,2)=='x')
  Scheduler.begin_tick(s,404)
  local _,scalar=services['string.format'](m,table.pack('%s/%s',false,nil))
  check('native formatting preserves scalar false and nil stringification',scalar[1]=='false/nil')
  local _,largest=services['string.format'](m,table.pack('%s',bytes))
  check('native maximum format output fits existing credits',largest[1]==bytes)
  local saved=s.budget.used.string
  check('native excessive format width is rejected before opaque expansion',not pcall(services['string.format'],m,
   table.pack('%999999999d',1)) and s.budget.used.string>=saved and s.budget.used.string<=Limits.string_work_per_computer)
  local wrapped=Execution.table_value(m)
  local heap_before=m.objects
  check('native formatting rejects guest identity operands without host tostring',not pcall(services['string.format'],m,
   table.pack('%s',wrapped)) and m.objects==heap_before)
  assert(Scheduler.consume(s,1,'string',Limits.string_work_per_computer-s.budget.used.string))
  check('native refused formatting retains exhausted counter',not pcall(services['string.format'],m,
   table.pack('%s','leaf')) and s.budget.used.string==Limits.string_work_per_computer)
  s,m=create([[local protect,format=pcall,string.format; coroutine.yield(); local ok=protect(format,'%s','leaf'); return ok,'alive']])
  finish(s,449); assert(m.status=='yield')
  Scheduler.begin_tick(s,450); assert(Scheduler.consume(s,1,'string',Limits.string_work_per_computer))
  assert(Events.admit(m,table.pack('char','continue'))); Scheduler.tick(s,450)
  check('native format refusal routes through guest protected continuation',m.status=='return' and m.result[1]==false and m.result[2]=='alive')
  s,m=create([[local protect,rep=pcall,string.rep; coroutine.yield(); local ok=protect(rep,'x',10); return ok,'alive']])
  finish(s,499); assert(m.status=='yield')
  Scheduler.begin_tick(s,500); assert(Scheduler.consume(s,1,'string',Limits.string_work_per_computer))
  assert(Events.admit(m,table.pack('char','continue'))); Scheduler.tick(s,500)
  check('native helper quota refusal is caught by guest protected receiver',m.status=='return' and m.result[1]==false and m.result[2]=='alive'
   and s.budget.used.string==Limits.string_work_per_computer)
 end,
 suspend=function(check)
  local s,m=create([[
boot=(boot or 0)+1
local held=table.pack('before',nil,7,nil)
local upper=string.upper
string.upper=function(value)
 local chosen=coroutine.yield('method',nil,value)
 return upper(chosen),nil
end
local child=coroutine.create(function() return ('leaf'):upper() end)
local ok,tag,gap,original=coroutine.resume(child)
assert(ok and tag=='method' and gap==nil and original=='leaf')
string={}
local _,text=coroutine.yield()
local success,transformed,trailing=coroutine.resume(child,text)
return table.unpack(held,1,held.n),transformed,math.floor('3.9'),boot,success,trailing,text:lower(),('%s:%02x'):format(text,15)
]])
  finish(s,game.tick)
  assert(m.status=='yield')
  Scheduler.begin_tick(s,game.tick)
  assert(Scheduler.consume(s,1,'string',Limits.string_work_per_computer-(s.budget.used.string or 0)))
  Collector.start(m)
  check('native helper snapshot retains pending guest tuple and spent string budget',m.collector~=nil and s.budget.used.string==Limits.string_work_per_computer)
  return {scheduler=s,tick=game.tick,compiler=s.budget.used.compiler,string_library=m.string_library,
   sort=SortChecks.suspend(check),tables=TableChecks.suspend(check),scalars=ScalarChecks.suspend(check),construction=ConstructionChecks.suspend(check),iterator=IteratorChecks.suspend(check),next=NextChecks.suspend(check),patterns=PatternChecks.suspend(check)}
 end,
 reload=function(state,check)
  SortChecks.reload(state.sort,check)
  TableChecks.reload(state.tables,check)
  ScalarChecks.reload(state.scalars,check)
  ConstructionChecks.reload(state.construction,check)
  IteratorChecks.reload(state.iterator,check)
  NextChecks.reload(state.next,check)
  PatternChecks.reload(state.patterns,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native helper load retains identities and string credit exhaustion',s.budget.tick==state.tick
   and s.budget.used.string==Limits.string_work_per_computer and s.budget.used.compiler==state.compiler and m.collector~=nil)
  check('native original string-library identity survives load independently of global',m.string_library==state.string_library
   and m.string_library.native_ref~=Execution.get(m,m.env,'string').native_ref)
  assert(Events.admit(m,table.pack('char','leaf')))
  finish(s,state.tick+1)
  -- finish may stop at a still-yielded root during collection; run until return.
  for i=2,200 do
   if m.status=='return' or m.status=='error' then break end
   Scheduler.tick(s,state.tick+i)
  end
  check('native nested string-method callback math and format survive collected reload',m.status=='return' and m.result.n==8
   and m.result[1]=='before' and m.result[2]=='LEAF' and m.result[3]==3 and m.result[4]==1
   and m.result[5]==true and m.result[6]==nil and m.result[7]=='leaf' and m.result[8]=='leaf:0f')
 end,
}
