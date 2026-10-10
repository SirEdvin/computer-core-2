local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Events=require('__computer_core_2__.scripts.native.events')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local function create(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-next')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick,maximum,terminal)
 local m=s.machines[1]
 for i=0,maximum or 100 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or (m.status=='yield' and not terminal) then return m end
 end
 error('next fixture failed to finish')
end
local reference=[[
local key={}
local function_key=function() end
local input={}
input.z='z'; input[1024]='last array'; input[2]=false; input[-2]='negative'
input[true]='true'; input[false]='false'; input['r1']='string r1'
input[key]='table'; input[function_key]='function'; input[2048]='beyond array'
setmetatable(input,{__index=function() error('iteration must be raw') end})
local f,state,control=pairs(input)
local count,found,total,types=0,0,'',0
for k,v in pairs(input) do
 count=count+1
 if k==key then found=found+1 end
 if k==function_key then found=found+1 end
 if type(k)=='table' or type(k)=='function' then types=types+1 end
 if v==false then total=total..'false;' else total=total..v..';' end
end
local n=select('#',next({}))
local invalid=pcall(next,input,'absent')
local nan=pcall(next,input,0/0)
return f==next,state==input,control,count,found,total,types,n,invalid,nan,nil
]]
local deletion=[[
local input={first='one',second=false,third='three'}
local count,total=0,''
for key,value in pairs(input) do
 count=count+1
 input[key]=nil
 total=total..key..';'
end
return count,total,next(input),select('#',next(input))
]]
local function compare(source,check,label)
 local s,m=create(source); finish(s,10)
 local expected=table.pack(assert(load(source,'=next-reference','t',{
  pairs=pairs,next=next,type=type,select=select,setmetatable=setmetatable,error=error,pcall=pcall}))())
 check(label..' exact reference arity',m.status=='return' and m.result.n==expected.n)
 for i=1,expected.n do check(label..' reference value '..i,m.result[i]==expected[i]) end
end
local function direct(services,m,args)
 local status,p=services.next(m,args)
 for i=1,20 do
  if status=='return' then break end
  status,p=services['native.next.step'](m,p)
 end
 return status,p
end
return {
 run=function(check)
  compare(reference,check,'native mixed-key pairs')
  compare(deletion,check,'native delete-current-key traversal')
  compare([[
local t={first='one',second='two',third='three'}
local k,v=next(t)
t[k]=nil; t.second=nil; t.third='updated'
local j,w=next(t,k)
t.new='new'
local total=''
for key,value in pairs(t) do total=total..value..';' end
return j,w,total
]],check,'native deletion overwrite and fresh insertion order')
  local s,m=create([[
local saved=pairs
local original=next
next=function() error('replaced next must not affect pairs') end
pairs=nil
local input={false,{name='held'}}
local f,t,k=saved(input)
local count=0
for key,value in saved(input) do count=count+1 end
local ok=pcall(setmetatable,{}, {__pairs=function() end})
return f==original,t==input,k,count,type(f),select('#',saved(input)),ok
]])
  finish(s,50)
  check('native pairs owns original raw iterator independently of mutable globals',m.status=='return'
   and m.result.n==7 and m.result[1]==true and m.result[2]==true and m.result[3]==nil
   and m.result[4]==2 and m.result[5]=='function' and m.result[6]==3 and m.result[7]==false)
  s,m=create('return 1'); Scheduler.begin_tick(s,100)
  local services=Helpers.services(function(d,n) return Scheduler.consume(s,1,d,n) end)
  local input=Execution.table_value(m); Execution.set(m,input,false,false)
  assert(Scheduler.consume(s,1,'table',Limits.table_work_per_computer))
  local status,p=direct(services,m,table.pack(input))
  check('native next read deferral is plain control without mutation or fake result',status=='continue'
   and p.kind=='helper' and not p.read and p.object==input and Execution.get(m,input,false)==false
   and s.budget.used.table==Limits.table_work_per_computer)
  local again,q=services['native.next.step'](m,p)
  check('native next same-tick refusal retains exact private cursor and counters',again=='continue' and q==p
   and s.budget.used.table==Limits.table_work_per_computer)
  Scheduler.begin_tick(s,101)
  local result,value
  for i=1,3 do
   result,value=services['native.next.step'](m,p)
   if result=='return' then break end
  end
  check('native next retry decodes false key and false value without losing either',result=='return'
   and value.n==2 and value[1]==false and value[2]==false)
  Scheduler.begin_tick(s,102)
  local long=string.rep('k',Limits.string_bytes)
  input=Execution.table_value(m); Execution.set(m,input,long,7)
  direct(services,m,table.pack(input))
  assert(m.heap[input.native_ref].iteration)
  Scheduler.begin_tick(s,103)
  assert(Scheduler.consume(s,1,'string',Limits.string_work_per_computer))
  status,p=direct(services,m,table.pack(input))
  local spent=s.budget.used.table
  check('native next byte refusal retains an already admitted raw read',status=='continue' and p.read
   and p.encoded=='s'..long and p.value==7 and p.result_paid and spent>0)
  again,q=services['native.next.step'](m,p)
  check('native next output retry does not repeat table or tuple admission',again=='continue' and q==p
   and s.budget.used.table==spent and s.budget.used.continuation==9)
  Scheduler.begin_tick(s,104)
  result,value=services['native.next.step'](m,p)
  check('native maximum string key decodes after later-tick credit renewal',result=='return'
   and value.n==2 and value[1]==long and value[2]==7 and (s.budget.used.table or 0)==0
   and (s.budget.used.continuation or 0)==0 and s.budget.used.string==2*(#long+1))
  Scheduler.begin_tick(s,105); assert(Scheduler.consume(s,1,'string',Limits.string_work_per_computer))
  status,p=services.next(m,table.pack(input,long))
  check('native next input encoding waits before lookup when byte credits are exhausted',status=='continue'
   and not p.input_paid and not p.read and p.index==long)
  Scheduler.begin_tick(s,106); result,value=services['native.next.step'](m,p)
  check('native next long control advances with exact nil arity and one input charge',result=='return'
   and value.n==1 and value[1]==nil and s.budget.used.string==2*(#long+1))
  s,m=create('local count=0; for k,v in pairs(input) do count=count+1 end; return count')
  input=Execution.table_value(m)
  for i=1,Limits.table_keys do Execution.set(m,input,i,false) end
  Execution.set(m,m.env,'input',input)
  local _,neighbor=create('local n=0; while true do n=n+1 end')
  Scheduler.add(s,2,neighbor); finish(s,200,800)
  check('native maximum pairs inventory completes across invisible helper deferrals',m.status=='return'
   and m.result[1]==Limits.table_keys and m.blocks>Limits.instructions_per_tick and m.yielded==nil)
  check('native maximum pairs traversal services a busy neighbor under unchanged shared caps',neighbor.blocks>0
   and neighbor.status=='running' and s.budget.used.execution<=Limits.instructions_per_tick
   and (s.budget.used.table or 0)<=Limits.table_work_per_tick)
  s,m=create('return 1'); Scheduler.begin_tick(s,1100)
  services=Helpers.services(function(d,n) return Scheduler.consume(s,1,d,n) end)
  input=Execution.table_value(m)
  local orphan=Execution.table_value(m); Execution.set(m,input,orphan,7)
  Execution.set(m,input,'live',false); Execution.set(m,m.env,'input',input)
  direct(services,m,table.pack(input)); Execution.set(m,input,orphan,nil)
  Collector.start(m)
  while m.collector do Collector.step(m,32) end
  check('native cached deleted reference-key positions do not pin unreachable guest objects',m.heap[orphan.native_ref]==nil
   and m.heap[input.native_ref].iteration.n==2)
  result,value=direct(services,m,table.pack(input))
  check('native cached traversal skips collected deleted reference keys without decoding stale identities',result=='return'
   and value.n==2 and value[1]=='live' and value[2]==false)
 end,
 suspend=function(check)
  local s,m=create([[
boot=(boot or 0)+1
local saved=pairs
local original=next
pairs=nil; next=nil
local count,total=0,''
for key,value in saved(input) do
 count=count+1; total=total..value..';'
 input[key]=nil
 if count==1 then coroutine.yield() end
end
local f,t,k=saved({false})
return count,total,f==original,k,boot,nil
]])
  local input=Execution.table_value(m)
  for _,v in ipairs({'one','two','three'}) do Execution.set(m,input,v,v) end
  Execution.set(m,m.env,'input',input); finish(s,game.tick)
  assert(m.status=='yield'); Collector.start(m)
  check('native pairs save retains a deleted control key and collector cursor',m.collector~=nil)
  local pending,held=create('boot=(boot or 0)+1; local k,v=next(input); return k.name,v.name,boot,nil')
  local key=Execution.table_value(held); Execution.set(held,key,'name','key')
  local value=Execution.table_value(held); Execution.set(held,value,'name','value')
  local map=Execution.table_value(held); Execution.set(held,map,key,value); Execution.set(held,held.env,'input',map)
  Scheduler.tick(pending,game.tick,{next=function(machine,args)
   assert(Scheduler.consume(pending,1,'continuation',Scheduler.remaining(pending,1,'continuation')))
   return Helpers.services(function(d,n) return Scheduler.consume(pending,1,d,n) end).next(machine,args)
  end})
  local operation=held.heap[held.active].pending
  assert(operation.kind=='helper' and operation.read and not operation.result_paid)
  Execution.set(held,map,key,nil); Collector.start(held)
  check('native next output save roots reference key and value after public edge removal',operation.reference.native_ref==key.native_ref
   and operation.value.native_ref==value.native_ref and pending.budget.used.continuation==Limits.continuation_work_per_computer)
  local building,builder=create('boot=(boot or 0)+1; local k,v=next(input); return #k,v,boot,nil')
  local large=Execution.table_value(builder)
  Execution.set(builder,large,string.rep('k',Limits.string_bytes),false); Execution.set(builder,builder.env,'input',large)
  Scheduler.tick(building,game.tick,{next=function(machine,args)
   assert(Scheduler.consume(building,1,'string',Scheduler.remaining(building,1,'string')))
   return Helpers.services(function(d,n) return Scheduler.consume(building,1,d,n) end).next(machine,args)
  end})
  local build=builder.heap[builder.active].pending
  assert(build.kind=='helper' and build.build_ready and not build.read and build.order.n==0)
  Collector.start(builder)
  check('native next inventory save retains prepaid opaque lookup and maximum key before hashing',build.build_key~=nil
   and building.budget.used.string==Limits.string_work_per_computer)
  return {scheduler=s,tick=game.tick,pending=pending,key=key.native_ref,value=value.native_ref,
   blocks=held.blocks,iterator=m.next_iterator.native_ref,building=building,builder_blocks=builder.blocks,
   builder_table=building.budget.used.table}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  check('native pairs load retains its implicit iterator and removed globals',m.next_iterator.native_ref==state.iterator
   and Execution.get(m,m.env,'pairs')==nil and Execution.get(m,m.env,'next')==nil and m.collector~=nil)
  assert(Events.admit(m,table.pack('char','continue'))); finish(s,state.tick+1,nil,true)
  check('native collected pairs resumes after deleted-key cursor reload without replay',m.status=='return'
   and m.result.n==6 and m.result[1]==3 and m.result[2]=='one;two;three;' and m.result[3]==true
   and m.result[4]==nil and m.result[5]==1 and m.result[6]==nil)
  s,m=state.pending,state.pending.machines[1]
  check('native next pending load retains consumed credits and staged reference identities',m.blocks==state.blocks
   and m.heap[m.active].pending.reference.native_ref==state.key and m.heap[m.active].pending.value.native_ref==state.value
   and s.budget.used.continuation==Limits.continuation_work_per_computer)
  finish(s,state.tick+1)
  check('native next staged output survives collected reload after input deletion',m.status=='return' and m.result.n==4
   and m.result[1]=='key' and m.result[2]=='value' and m.result[3]==1 and m.result[4]==nil)
  s,m=state.building,state.building.machines[1]
  check('native next inventory load preserves private stage and exhausted byte credits',m.blocks==state.builder_blocks
   and m.heap[m.active].pending.build_ready and s.budget.used.table==state.builder_table
   and s.budget.used.string==Limits.string_work_per_computer)
  Scheduler.tick(s,state.tick); Scheduler.tick(s,state.tick)
  check('native next same-tick inventory reentry cannot renew bytes or replay opaque lookup',m.blocks==state.builder_blocks
   and m.heap[m.active].pending.build_ready and s.budget.used.table==state.builder_table
   and s.budget.used.string==Limits.string_work_per_computer)
  finish(s,state.tick+1)
  check('native maximum-key inventory and output finish after collected reload without replay',m.status=='return'
   and m.result.n==4 and m.result[1]==Limits.string_bytes and m.result[2]==false and m.result[3]==1 and m.result[4]==nil)
 end,
}
