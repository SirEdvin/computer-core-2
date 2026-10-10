local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Collector = require('__computer_core_2__.scripts.native.collector')
local Dispatch = require('__computer_core_2__.scripts.native.dispatch')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local M = {}
local function create(source)
 local b=assert(Compiler.compile(source,'=native-cell-pool'))
 local m=Execution.new(b); Execution.install_core(m)
 return m,b,Execution.executable(b)
end
local function step(m,b,blocks,credits)
 local before=m.cleanup_work or 0
 local status,spent=Execution.run(m,b,blocks,credits or 1)
 assert(spent<=(credits or 1) and (m.cleanup_work or 0)-before<=Limits.cleanup_work_per_step*(credits or 1))
 assert(status~='error',m.error and m.error.message)
 return status
end
local function finish(m,b,blocks)
 local turns=0
 while m.status=='running' do step(m,b,blocks); turns=turns+1; assert(turns<100000) end
end
local function pool_intact(m)
 local pool=assert(m.cell_pool,'native cell pool missing')
 assert(pool.version==1 and #pool.ids<=Limits.register_pool)
 local seen={}
 for _,id in ipairs(pool.ids) do
  local c=assert(m.heap[id],'collected pooled identity')
  assert(not seen[id] and c.kind=='cell' and c.captured==false and c.value==nil)
  seen[id]=true
  assert(m.object_ids[c.object_slot]==id)
 end
 return #pool.ids
end
local function wide_source(count,tail)
 local vars,values={},{}
 for i=1,count do vars[i]='x'..i; values[i]=tostring(i) end
 return (tail and 'local function identity(...) return ... end; ' or '')
  ..'local function wide() local '..table.concat(vars,',')..'='..table.concat(values,',')..'; '
  ..(tail and 'return identity(x1,nil,x'..count..',false)' or 'return x1,nil,x'..count..',false')
  ..' end; local a,b,c,d=wide(); return a,b,c,d'
end
function M.run(check)
 local m,b,blocks=create('local function f(x) local y=x+1; return y end; local n=0; for i=1,200 do n=f(n) end; return n')
 finish(m,b,blocks)
 check('native completed calls reuse cleared private cells',m.result[1]==200 and (m.cell_reuses or 0)>300 and pool_intact(m)>0)
 Collector.start(m); while m.collector do Collector.step(m,7) end
 check('native pool survives incremental collection within heap quota',pool_intact(m)>0 and m.objects==#m.object_ids)
 for _,tail in ipairs({false,true}) do
  m,b,blocks=create(wide_source(Limits.register_pool+70,tail))
  local turns=0
  repeat
   local before=m.cleanup_work or 0
   local status,spent=Execution.run(m,b,blocks,1)
   assert(spent<=1 and (m.cleanup_work or 0)-before<=Limits.cleanup_work_per_step)
   assert(status~='error',m.error and m.error.message)
   turns=turns+1; assert(turns<20000)
  until m.status~='running'
  check('native wide return/full pool '..tostring(tail),m.result.n==4 and m.result[1]==1 and m.result[2]==nil
   and m.result[3]==Limits.register_pool+70 and m.result[4]==false and pool_intact(m)==Limits.register_pool)
 end
 local sources={
  {'scoped shared capture',[=[local saved={}; local function f(i) local x=i; saved[i]={function() x=x+1; return x end,function() return x end} end; for i=1,50 do f(i) end; local n=0; for i=1,50 do n=n+saved[i][1]()+saved[i][2]() end; return n]=],2650},
  {'error capture',[=[local saved; local e={}; local ok,v=pcall(function() local x=17; saved=function() return x end; error(e,0) end); for i=1,100 do local function f(x) return x+1 end; f(i) end; return saved(),not ok and v==e]=],17},
  {'coroutine capture',[=[local saved; local co=coroutine.create(function() local x=11; saved=function() return x end; coroutine.yield(); x=x+3; return x end); coroutine.resume(co); for i=1,100 do local function f(x) return x+1 end; f(i) end; local ok,v=coroutine.resume(co); return saved(),ok and v==14]=],14},
  {'closure tail capture',[=[local function f(x) local function g() return x end; return g() end; local n=0; for i=1,100 do n=n+f(i) end; return n]=],5050},
 }
 for _,case in ipairs(sources) do
  m,b,blocks=create(case[2]); finish(m,b,blocks)
  check('native cell reuse preserves '..case[1],m.result[1]==case[3] and (m.result.n==1 or m.result[2]==true))
  pool_intact(m)
 end
 -- Synthetic compatibility probe: old v4 graphs have no optional pool and may
 -- lack capture metadata. Never infer uncaptured status from a missing flag.
 m,b,blocks=create('local function f(x) return x+1 end; return f(6)')
 m.version=4
 local legacy
 while not legacy do
  step(m,b,blocks)
  for _,f in ipairs(m.frames) do
   if f.proto==2 then
    for _,id in pairs(f.cells) do legacy=id; m.heap[id].captured=nil; break end
   end
  end
 end
 local cell=m.heap[legacy]
 finish(m,b,blocks)
 local pooled=false; for _,id in ipairs(m.cell_pool.ids) do if id==legacy then pooled=true end end
 check('native legacy cells stay ineligible during synchronized format upgrade',m.version==Execution.VERSION and m.result[1]==7 and not pooled and cell.value==6)
 local before=m.cell_pool
 before.version=99; m.status='running'
 local status,spent=Dispatch.run(m,1,function() return true end)
 check('native unsupported pool version retains recoverable graph',status=='recovery' and spent==0 and m.cell_pool==before and cell.value==6)
 m.cell_pool=false; m.status='running'
 status,spent=Dispatch.run(m,1,function() return true end)
 assert(status=='recovery' and spent==0 and m.cell_pool==false and cell.value==6,'malformed pool must not be silently replaced')
end
local function suspend_release(tail,check)
 local m,b,blocks=create(wide_source(90,tail))
 local p
 repeat
  step(m,b,blocks)
  p=m.heap[m.active].pending
 until p and p.kind==(tail and 'call' or 'return') and p.release_cursor and p.release_cursor>1
  and (not tail or p.child)
 local count=pool_intact(m)
 local work,steps=m.cleanup_work,m.blocks
 step(m,b,blocks,0)
 check('native zero credits preserve partial frame release',m.cleanup_work==work and m.blocks==steps and pool_intact(m)==count)
 -- Save with the result staged, old frame partially detached, and pooled cells
 -- still being marked. All saved aliases must survive in the new process.
 Collector.start(m); Collector.step(m,19)
 return {machine=m,bundle=b,pending=p,values=p.values,child=p.child,pool=m.cell_pool,ids=m.cell_pool.ids,
  work=work,blocks=steps,collection=m.collection_work}
end
function M.suspend(check)
 local states={suspend_release(false,check),suspend_release(true,check)}
 local m,b,blocks=create('local function f(x) return x+1 end; local n=f(6); return n')
 m.version=4
 local id
 while not id do
  step(m,b,blocks)
  for _,f in ipairs(m.frames) do
   if f.proto==2 then for _,cell in pairs(f.cells) do id=cell; m.heap[id].captured=nil; break end end
  end
 end
 assert(m.version==4 and m.cell_pool==nil)
 Collector.start(m); Collector.step(m,5)
 states.legacy={machine=m,bundle=b,id=id,cell=m.heap[id],blocks=m.blocks,work=m.collection_work}
 return states
end
local function reload_release(state,check)
 local m=state.machine
 check('native partial release load preserves graph and counters',m.heap[m.active].pending==state.pending and state.pending.values==state.values
  and state.pending.child==state.child
  and m.cell_pool==state.pool and m.cell_pool.ids==state.ids and m.blocks==state.blocks and m.cleanup_work==state.work
  and m.collection_work==state.collection and m.collector~=nil)
 while m.collector do Collector.step(m,11) end
 pool_intact(m)
 finish(m,state.bundle,Execution.executable(state.bundle))
 check('native collected cold release publishes retained nil tuple once',m.result.n==4 and m.result[1]==1 and m.result[2]==nil and m.result[3]==90 and m.result[4]==false)
 pool_intact(m)
end
function M.reload(states,check)
 for _,state in ipairs(states) do reload_release(state,check) end
 local state=states.legacy
 local m=state.machine
 check('native v4 load leaves legacy graph and counters untouched',m.version==4 and m.cell_pool==nil and m.heap[state.id]==state.cell
  and state.cell.captured==nil and state.cell.value==6 and m.blocks==state.blocks and m.collection_work==state.work)
 while m.collector do Collector.step(m,11) end
 finish(m,state.bundle,Execution.executable(state.bundle))
 local pooled=false; for _,id in ipairs(m.cell_pool.ids) do if id==state.id then pooled=true end end
 check('native v4 cold continuation upgrades without recycling unknown captures',m.version==Execution.VERSION and m.result[1]==7 and not pooled and state.cell.value==6)
 pool_intact(m)
end
return M
