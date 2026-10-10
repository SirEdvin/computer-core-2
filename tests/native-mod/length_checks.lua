-- Durable dense-prefix metadata: bounded reads, mutation and old-save fallback.
local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Events=require('__computer_core_2__.scripts.native.events')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local M={}
local function create(source)
 local m=Execution.new(assert(Compiler.compile(source,'=native-length-test')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick)
 local m=s.machines[1]
 for i=0,200 do
  Scheduler.tick(s,tick+i)
  if (m.status=='yield' and not m.collector and #m.events.queue==0) or m.status=='return' or m.status=='error' then return m end
 end
 error('native length fixture deadline')
end
local function oracle(values)
 local n=0; while values[n+1]~=nil do n=n+1 end; return n
end
function M.run(check)
 local s,m=create('local a={} for i=1,400 do a[#a+1]=false end return #a,a')
 finish(s,10)
 check('native dense append loop executes with linear metered length work and false values',m.status=='return'
  and m.result[1]==400 and m.heap[m.result[2].native_ref].dense_length==400 and s.budget.used.table<400*64)
 s,m=create('local value=value; while true do coroutine.yield(#value,value) end')
 local value=Execution.table_value(m); Execution.set(m,m.env,'value',value)
 local values={}
 local operations={{1,false},{2,'b'},{4,'d'},{3,'c'},{2},{2,'B'},{4},{1},{1,7},{2},
  {'label','ignored'},{-1,8},{1.5,9},{2,false},{3},{3,'C'},{8,'tail'},{4,'D'}}
 finish(s,100)
 local matches=0
 for round=1,8 do
  for _,op in ipairs(operations) do
   Execution.set(m,value,op[1],op[2]); values[op[1]]=op[2]
   local expected=oracle(values)
   assert(Events.admit(m,table.pack('char','resume'))); finish(s,s.budget.tick+1)
   assert(m.status=='yield' and m.yielded[1]==expected and m.yielded[2].native_ref==value.native_ref)
   assert(m.heap[value.native_ref].dense_length==expected)
   matches=matches+1
  end
 end
 check('native dense-prefix mutation property covers append overwrite deletion hole bridging nonarray keys and false',matches==8*#operations)
 -- All routes which mutate numeric keys use the same setter.
 s,m=create([[
local a={false,'b','c','d'}; local initial=#a
rawset(a,2,nil); local shortened=#a
rawset(a,2,false); local restored=#a
local old=table.remove(a,1); local removed=#a
 table.insert(a,1,false); local inserted=#a
 table.sort(a,function(x,y) return tostring(x)<tostring(y) end)
return initial,shortened,restored,old,removed,inserted,#a,a
]])
 finish(s,200)
 check('native rawset insert remove and sort preserve dense-prefix metadata and false elements',m.status=='return'
  and m.result[1]==4 and m.result[2]==1 and m.result[3]==4 and m.result[4]==false
  and m.result[5]==3 and m.result[6]==4 and m.result[7]==4
  and m.heap[m.result[8].native_ref].dense_length==4)
end
local saved_source=[[
local a={false,'b',nil,'d'}; local alias=a; local first=#a
coroutine.yield('length-cache',a,alias,first)
a[2]=nil; local shortened=#alias
a[2]='B'; local before_bridge=#a
a[3]='C'; local repaired=#alias
return first,shortened,before_bridge,repaired,a,alias
]]
function M.suspend(check)
 local snapshots={}
 for _,mode in ipairs({'cached','legacy'}) do
  local s,m=create(saved_source); finish(s,game.tick)
  assert(m.status=='yield' and m.yielded[4]==2)
  local value=m.yielded[2]
  if mode=='legacy' then m.heap[value.native_ref].dense_length=nil end
  Collector.start(m)
  check('native '..mode..' length save retains alias before collected dirty hole repair',m.yielded[3].native_ref==value.native_ref
   and m.collector~=nil and (mode=='legacy' or m.heap[value.native_ref].dense_length==2))
  snapshots[mode]={scheduler=s,tick=s.budget.tick,value=value,blocks=m.blocks}
 end
 return snapshots
end
function M.reload(snapshots,check)
 for _,mode in ipairs({'cached','legacy'}) do
  local snapshot=snapshots[mode]; local s=snapshot.scheduler; local m=s.machines[1]
  check('native cold '..mode..' length metadata does not rebuild or replay on load',m.blocks==snapshot.blocks
   and m.yielded[2].native_ref==snapshot.value.native_ref
   and m.heap[snapshot.value.native_ref].dense_length==(mode=='cached' and 2 or nil))
  assert(Events.admit(m,table.pack('char','resume'))); finish(s,snapshot.tick+1)
  check('native collected '..mode..' length repairs hole and preserves alias after cold reload',m.status=='return'
   and m.result.n==6 and m.result[1]==2 and m.result[2]==1 and m.result[3]==2 and m.result[4]==4
   and m.result[5].native_ref==m.result[6].native_ref and m.heap[snapshot.value.native_ref].dense_length==4)
 end
end
return M
