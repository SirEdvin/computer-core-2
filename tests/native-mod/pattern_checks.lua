local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Events=require('__computer_core_2__.scripts.native.events')
local Dispatch=require('__computer_core_2__.scripts.native.dispatch')
local Patterns=require('__computer_core_2__.scripts.native.patterns')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local function create(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-pattern-test')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick,terminal)
 local m=s.machines[1]
 for i=0,500 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or (m.status=='yield' and not terminal) then return m end
 end
 local thread=m.heap[m.active]
 local frame=thread.frames[#thread.frames]
 log('CC2 NATIVE PATTERN DEADLINE '..serpent.line({status=m.status,blocks=m.blocks,objects=m.objects,
  bundle=frame and frame.bundle_id,proto=frame and frame.proto,pc=frame and frame.pc,budget=s.budget.used}))
 error('native pattern fixture failed to finish')
end
local source=[[
local f,l,a,b=string.find('leaf12 branch34','(%a+)(%d+)')
local word,number=('leaf12'):match('(%a+)(%d+)')
local balanced=('x(a(b)c)y'):match('%b()')
local frontier=('one two'):match('%f[%a]two')
local back=('leaf leaf'):match('(%a+)%s+%1')
local first,last=string.find('abc','()',2)
local parts=''
for x,y in string.gmatch('a1 b2','(%a)(%d)') do parts=parts..x..y..';' end
local replaced,count=string.gsub('a1 b2','(%a)(%d)','%2-%1')
local tabbed,n=string.gsub('a b','%a',{a=false,b='leaf'})
local callback,calls=string.gsub('a1 b2','(%a)(%d)',function(x,y) return y..x end)
local absent=select('#',string.match('leaf','%d+'))
local eof=select('#',string.gmatch('','%a')())
local empty,empties=string.gsub('ab','a*','X')
local runs=''
for item in string.gmatch('ab','a*') do runs=runs..'['..item..']' end
return f,l,a,b,word,number,balanced,frontier,back,first,last,parts,replaced,count,tabbed,n,callback,calls,absent,eof,empty,empties,runs,nil
]]
return {
 run=function(check)
  local core,api=Patterns.sources()
  for i,text in ipairs({core,api}) do
   local metrics={}; local bundle,err=Compiler.compile(text,'=native-pattern-part-'..i,metrics)
   log('CC2 NATIVE PATTERN PART '..i..' '..serpent.line({ok=bundle~=nil,error=err,generated=bundle and #bundle.generated,metrics=metrics}))
   check('native pattern part fits unchanged output and source limits '..i,bundle~=nil)
  end
  local s,m=create(source); finish(s,10)
  log('CC2 NATIVE PATTERN RESULT '..serpent.line({status=m.status,error=m.error,result=m.result}))
  local expected=table.pack(assert(load(source,'=pattern-reference','t',{string=string,select=select}))())
  log('CC2 ENGINE PATTERN REFERENCE '..serpent.line(expected))
  check('native pattern helpers retain fixed-source reference arity',m.status=='return' and m.result.n==expected.n)
  for i=1,expected.n do check('native pattern reference value '..i,m.result[i]==expected[i]) end
  check('native matcher and API have independent retained compiled sources',#m.bundles==3
   and m.bundles[2].name=='=native-pattern-core' and m.bundles[3].name=='=native-pattern-api'
   and Execution.type(m,m.pattern_functions)=='table')
  s,m=create([[
local ok=pcall(string.match,'leaf','[')
local long=pcall(string.match,'leaf',string.rep('a',4097))
local output=pcall(string.gsub,'aa','a',function() return string.rep('x',65536) end)
return ok,long,output,string.match('recovered12','(%a+)%d+')
]])
  finish(s,600)
  check('native malformed oversized patterns and oversized replacement recover through guest boundaries',m.status=='return'
   and m.result[1]==false and m.result[2]==false and m.result[3]==false and m.result[4]=='recovered')
  s,m=create([[
local replacement=string.rep('x',65536)
local target='saved'
local ok,message=pcall(function() target=string.gsub('aa','a',replacement) end)
return ok,target,message
]])
  finish(s,900)
  check('native maximum literal replacement refuses overflow without target publication within unchanged deadline',m.status=='return'
   and m.result[1]==false and m.result[2]=='saved'
   and string.find(m.result[3],'pattern result byte limit exceeded',1,true)~=nil)
  s,m=create([[
local replacement=string.rep('x',65536)
coroutine.yield('literal-ready')
local output,count=string.gsub('a','a',replacement)
return output,count
]])
  finish(s,950); assert(m.status=='yield')
  assert(Events.admit(m,table.pack('char','continue')))
  finish(s,s.budget.tick+1,true)
  check('native maximum literal replacement completes exactly under fresh bounded credits',m.status=='return'
   and m.result[1]==string.rep('x',65536) and m.result[2]==1)
  s,m=create("local replacement='%%'..string.rep('x',65534); coroutine.yield('escape-ready'); return string.gsub('a','a',replacement)")
  finish(s,960); assert(m.status=='yield')
  assert(Events.admit(m,table.pack('char','continue'))); finish(s,s.budget.tick+1,true)
  local escaped,escaped_count=string.gsub('a','a','%%'..string.rep('x',65534))
  log('CC2 NATIVE ESCAPED MAX '..serpent.line({status=m.status,error=m.error,blocks=m.blocks,budget=s.budget.used,
   result_bytes=m.result and type(m.result[1])=='string' and #m.result[1],count=m.result and m.result[2]}))
  check('native maximum escaped replacement completes exact output within unchanged deadline',m.status=='return'
   and m.result[1]==escaped and m.result[2]==escaped_count)
  local escaped_cases={
   {"string.rep('%%',32768)",string.rep('%%',32768),'a'},
   {"'%1'..string.rep('x',65534)",'%1'..string.rep('x',65534),'(a)'},
   {"string.rep('x',255)..'%0'..string.rep('z',65279)",string.rep('x',255)..'%0'..string.rep('z',65279),'a'},
  }
  for i,case in ipairs(escaped_cases) do
   s,m=create("local replacement="..case[1].."; coroutine.yield('escape-ready'); return string.gsub('a','"..case[3].."',replacement)")
   finish(s,970); assert(m.status=='yield')
   assert(Events.admit(m,table.pack('char','continue'))); finish(s,s.budget.tick+1,true)
   local expected,count=string.gsub('a',case[3],case[2])
   check('native maximum escaped replacement retains engine semantics '..i,m.status=='return'
    and m.result[1]==expected and m.result[2]==count)
  end
  local replacements={
   "return string.gsub('a b a','a','leaf')",
   "return string.gsub('aa','a','')",
   "return string.gsub('aa','a',17)",
   "return string.gsub('a1 b2','(%a)(%d)','literal%%:%0:%2-%1')",
   "return string.gsub('a','a','%1')",
   "local ok=pcall(string.gsub,'a','a','%'); return ok",
   "local ok=pcall(string.gsub,'a','a','%q'); return ok",
   "return string.gsub('b','a','%q')",
   "return string.gsub('aaa','a','leaf',0)",
  }
  for i,text in ipairs(replacements) do
   s,m=create(text); finish(s,980)
   local reference=table.pack(assert(load(text,'=replacement-reference','t',{string=string,pcall=pcall}))())
   local same=m.status=='return' and m.result.n==reference.n
   for j=1,reference.n do same=same and m.result[j]==reference[j] end
   check('native literal fast path preserves exact-engine replacement semantics '..i,same)
  end
  s,m=create("local target='saved'; local ok=pcall(function() target=string.gsub('a','a','leaf') end); return ok,target")
  local services=Helpers.services(function(domain,amount) return Scheduler.consume(s,1,domain,amount) end)
  for tick=1000,1020 do
   Scheduler.tick(s,tick,{['string.find']=function(machine,args)
    if args[4] and args[2]=='%' then
     assert(Scheduler.consume(s,1,'string',Scheduler.remaining(s,1,'string')))
    end
    return services['string.find'](machine,args)
   end})
   if m.status=='return' or m.status=='error' then break end
  end
  check('native literal probe admission refusal cannot publish replacement target',m.status=='return'
   and m.result[1]==false and m.result[2]=='saved' and Scheduler.remaining(s,1,'string')==0)
  s,m=create([[
local function nested(n)
 if n==0 then return 'leaf' end
 return string.gsub('a','a',function() return nested(n-1) end)
end
local ok,message=pcall(nested,32)
return ok,message:find('nesting',1,true),string.match('recovered','%a+')
]])
  finish(s,1050)
  check('native nested pattern callbacks enforce shared helper depth and recover',m.status=='return'
   and m.result[1]==false and m.result[2]~=nil and m.result[3]=='recovered')
  s,m=create("local ok,e=pcall(string.match,'a','%a'); return ok,type(e)")
  Scheduler.tick(s,1100,{['string.match']=function(machine,args)
   assert(Scheduler.consume(s,1,'compiler',Scheduler.remaining(s,1,'compiler')))
   return Patterns.start(machine,args,'match',function(d,n)
    assert(Scheduler.consume(s,1,d,n),'fixture pattern admission refused')
   end)
  end})
  check('native cold pattern compilation refuses without publishing partial sources',m.status=='return'
   and m.result[1]==false and m.result[2]=='string' and m.bundles==nil and m.pattern_functions==nil
   and s.budget.used.compiler==Limits.compiler_work_per_computer)
  s,m=create("return string.match(string.rep('a',128),'a*a*a*a*b')")
  local _,neighbor=create('local n=0; while true do n=n+1 end')
  Scheduler.add(s,2,neighbor)
  for i=1,20 do Scheduler.tick(s,1200+i) end
  check('native pathological backtracking stays bounded beside a busy neighbor',neighbor.blocks>0
   and s.budget.used.execution<=Limits.instructions_per_tick and m.status=='running'
   and m.heap[m.active].frames[#m.heap[m.active].frames].bundle_id==2)
 end,
 suspend=function(check)
  local s,m=create([[
boot=(boot or 0)+1
local calls=0
local kept={name='leaf'}
local lookup=setmetatable({},{__index=function(_,key)
 if key=='a' then coroutine.yield('replacement',nil,kept) end
 return key:upper()
end})
local iterator=string.gmatch('one two','%a+')
local first=iterator()
local output,count=string.gsub('a1 b2','(%a)(%d)',function(a,b)
 calls=calls+1
 return b..lookup[a]
end)
return output,count,calls,iterator(),first,kept.name,boot,nil
]])
  finish(s,game.tick); assert(m.status=='yield')
  Collector.start(m)
  check('native pattern callback snapshot crosses matcher API and guest bundles',#m.bundles==3 and m.collector~=nil
   and m.yielded.n==3 and m.yielded[1]=='replacement' and m.yielded[2]==nil)
  local literal,lm=create([[
boot=(boot or 0)+1
string.match('ready','%a+')
local replacement=string.rep('x',65536)
coroutine.yield('literal-save')
local output,count=string.gsub('a','a',replacement)
return output,count,boot,nil
]])
  finish(literal,game.tick); assert(lm.status=='yield')
  Collector.start(lm)
  check('native maximum literal replacement snapshot retains original API and input during collection',#lm.bundles==3
   and lm.collector~=nil and lm.yielded[1]=='literal-save')
  return {scheduler=s,tick=s.budget.tick,blocks=m.blocks,bundles=m.bundles,functions=m.pattern_functions,
   literal=literal,literal_tick=literal.budget.tick,literal_blocks=lm.blocks,literal_functions=lm.pattern_functions}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native pattern reload retains source snapshots and implicit functions without running initializers',m.blocks==state.blocks
   and m.bundles==state.bundles and m.pattern_functions==state.functions and m.collector~=nil)
  Dispatch.clear_cache()
  assert(Events.admit(m,table.pack('char','continue')))
  finish(s,state.tick+1,true)
  log('CC2 NATIVE PATTERN RELOAD '..serpent.line({status=m.status,error=m.error,result=m.result}))
  check('native collected cold-cache replacement and gmatch resume exactly once across bundles',m.status=='return'
   and m.result.n==8 and m.result[1]=='1A 2B' and m.result[2]==2 and m.result[3]==2
   and m.result[4]=='two' and m.result[5]=='one' and m.result[6]=='leaf' and m.result[7]==1 and m.result[8]==nil)
  local literal,lm=state.literal,state.literal.machines[1]
  check('native saved literal reload runs no initializer and retains collection and source aliases',lm.blocks==state.literal_blocks
   and lm.pattern_functions==state.literal_functions and lm.collector~=nil)
  Dispatch.clear_cache()
  assert(Events.admit(lm,table.pack('char','continue')))
  finish(literal,state.literal_tick+1,true)
  check('native cold collected maximum literal replacement returns exact bytes without replay',lm.status=='return'
   and lm.result.n==4 and lm.result[1]==string.rep('x',65536) and lm.result[2]==1 and lm.result[3]==1 and lm.result[4]==nil)
 end,
}
