-- Test-only ephemeral observers. Forward real generated blocks and runtime calls.
-- Never install these wrappers or their counters in guest values or storage.
local Execution=require('__computer_core_2__.scripts.native.execution')
local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local M={}
local audits=setmetatable({}, {__mode='k'})
local helper_seen=setmetatable({}, {__mode='k'})
local current
local MAX_ROWS,MAX_NODES,MAX_SNAPSHOTS=8192,1048576,128
local function source(name)
 assert(#name<=Limits.string_bytes,'audit source bound')
 return (name:gsub('[^%w_./=%-]',function(c) return string.format('%%%02X',string.byte(c)) end))
end
local function row(a,name,proto)
 local key=a.phase..' '..source(name)..' '..proto
 local r=a.rows[key]
 if not r then
  assert(a.count<MAX_ROWS,'allocation audit row bound')
  r={phase=a.phase,source=source(name),proto=proto,cells=0,other=0,steps=0,
   capture_bindings=0,new_captures=0,blocks=0}
  a.rows[key]=r; a.count=a.count+1
 end
 return r
end
local function location(m,f)
 if not f then return '<runtime>',0 end
 local bundle=f.bundle_id and f.bundle_id~=1 and m.bundles[f.bundle_id] or m.bundle
 return bundle.name,f.proto
end
local function allocations(m,a,r)
 assert(m.next_id-a.next_id<=Limits.heap_objects,'allocation observer scan bound')
 for id=a.next_id,m.next_id-1 do
  local o=assert(m.heap[id],'allocation disappeared before observer')
  local field=o.kind=='cell' and 'cells' or 'other'
  r[field]=r[field]+1; a.allocated=a.allocated+1
 end
 a.next_id=m.next_id
end
local function observe_helper(a)
 if helper_seen[a] then return end
 helper_seen[a]=true
 local closure=a.closure
 a.closure=function(f,pid)
  local c=current
  if not c then return closure(f,pid) end
  local m,audit=c.machine,c.audit
  local name,proto=location(m,f)
  local r=row(audit,name,proto)
  local b=f.bundle_id and f.bundle_id~=1 and m.bundles[f.bundle_id] or m.bundle
  local bindings=b.prototypes[pid].upvalues
  assert(#bindings<=Limits.tuple_values,'capture observer bound')
  local seen,fresh={},0
  for _,binding in ipairs(bindings) do
   local id=binding.kind=='local' and f.cells[binding.slot] or f.upvalues[binding.slot]
   if not seen[id] and m.heap[id].captured==false then fresh=fresh+1 end
   seen[id]=true
  end
  local value=closure(f,pid)
  r.capture_bindings=r.capture_bindings+#bindings
  r.new_captures=r.new_captures+fresh
  return value
 end
end
local installed=false
function M.install()
 assert(not installed,'allocation audit installed twice'); installed=true
 local executable=Execution.executable
 Execution.executable=function(bundle)
  local blocks=executable(bundle)
  local name=bundle.name
  for pid,labels in ipairs(blocks) do
   local wrapped={}
   for label,block in pairs(labels) do
    if not wrapped[block] then
     local proto=pid
     wrapped[block]=function(f,a,t,checkpoint)
      local c=current
      if not c then return block(f,a,t,checkpoint) end
      local m,audit=c.machine,c.audit
      local r=row(audit,name,proto)
      allocations(m,audit,r)
      observe_helper(a)
      local before=m.blocks
      -- Preserve return arity and the runtime's own protected error handling.
      local values=table.pack(block(f,a,t,checkpoint))
      allocations(m,audit,r)
      local steps=1+m.blocks-before -- First block credit is paid before entry.
      r.steps=r.steps+steps; r.blocks=r.blocks+1
      audit.generated=audit.generated+steps
      return table.unpack(values,1,values.n)
     end
    end
    labels[label]=wrapped[block]
   end
  end
  return blocks
 end
 local run=Execution.run
 Execution.run=function(m,...)
  local a=audits[m]
  if not a then return run(m,...) end
  local previous=current
  current={machine=m,audit=a}
  local before,generated=m.blocks,a.generated
  local result=table.pack(pcall(run,m,...))
  local f=m.frames[#m.frames]
  local name,proto=location(m,f)
  allocations(m,a,row(a,name,proto))
  local control=m.blocks-before-(a.generated-generated)
  assert(control>=0,'generated observer double counted steps')
  row(a,'<runtime-control>',0).steps=row(a,'<runtime-control>',0).steps+control
  current=previous
  if not result[1] then error(result[2],0) end
  return table.unpack(result,2,result.n)
 end
end
function M.watch(m)
 local a={rows={},count=0,next_id=1,allocated=0,generated=0,phase='setup',snapshots=0}
 audits[m]=a
 allocations(m,a,row(a,'<setup>',0))
end
function M.phase(m,name) audits[m].phase=name end
function M.snapshot(m,phase,sample)
 local a=audits[m]
 a.snapshots=a.snapshots+1
 assert(a.snapshots<=MAX_SNAPSHOTS,'allocation audit snapshot bound')
 local counts={resident_cells=0,resident_captured=0,resident_other=0,frames=0,
  temp_slots=0,temp_values=0,temp_refs=0,unique_temp_refs=0,nodes=0,partial=0}
 local refs,frames,groups={},{},0
 local function visit()
  if counts.nodes>=MAX_NODES then counts.partial=1; return false end
  counts.nodes=counts.nodes+1; return true
 end
 for _,o in pairs(m.heap) do
  if not visit() then break end
  if o.kind=='cell' then
   counts.resident_cells=counts.resident_cells+1
   if o.captured==true then counts.resident_captured=counts.resident_captured+1 end
  else counts.resident_other=counts.resident_other+1 end
  if o.kind=='thread' then
   for _,f in ipairs(o.frames) do
    if not visit() then break end
    counts.frames=counts.frames+1
    local name,proto=location(m,f)
    local key=source(name)..' '..proto
    local group=frames[key]
    if not group then
     if groups>=64 then counts.partial=1; break end
     groups=groups+1
     group={source=source(name),proto=proto,frames=0,temp_slots=0,temp_values=0,temp_refs=0}
     frames[key]=group
    end
    group.frames=group.frames+1
    for _,values in pairs(f.t) do
     if not visit() then break end
     counts.temp_slots=counts.temp_slots+1
     group.temp_slots=group.temp_slots+1
     for i=1,values.n do
      if not visit() then break end
      if values[i]~=nil then
       counts.temp_values=counts.temp_values+1; group.temp_values=group.temp_values+1
      end
      if type(values[i])=='table' and values[i].native_ref then
       counts.temp_refs=counts.temp_refs+1
       group.temp_refs=group.temp_refs+1
       if not refs[values[i].native_ref] then
        refs[values[i].native_ref]=true; counts.unique_temp_refs=counts.unique_temp_refs+1
       end
      end
     end
    end
   end
  end
 end
 local fields={'phase='..phase,'sample='..sample}
 for key,value in pairs(counts) do fields[#fields+1]=key..'='..value end
 table.sort(fields)
 log('CC2 WORKFLOW RESIDENT '..table.concat(fields,' '))
 local keys={}
 for key in pairs(frames) do keys[#keys+1]=key end
 table.sort(keys)
 for _,key in ipairs(keys) do
  local values={'phase='..phase,'sample='..sample}
  for field,value in pairs(frames[key]) do values[#values+1]=field..'='..value end
  table.sort(values)
  log('CC2 WORKFLOW FRAMES '..table.concat(values,' '))
 end
end
function M.finish(m)
 local a=audits[m]
 assert(a.allocated==m.allocations,'allocation observer missed identities')
 local steps=0
 local keys={}
 for key in pairs(a.rows) do keys[#keys+1]=key end
 table.sort(keys)
 for _,key in ipairs(keys) do
  local fields={}
  for name,value in pairs(a.rows[key]) do fields[#fields+1]=name..'='..value end
  steps=steps+a.rows[key].steps
  table.sort(fields)
  log('CC2 WORKFLOW ALLOCATION '..table.concat(fields,' '))
 end
 assert(steps==m.blocks,'allocation observer missed execution steps')
 log('CC2 WORKFLOW AUDIT allocated='..a.allocated..' steps='..steps..' rows='..a.count)
end
function M.verify()
 local b=assert(Compiler.compile([[local x=1
 local function f() x=x+1; return x end
 f()
 local ok,err=pcall(function() error('audit-error',0) end)
 return f(),nil,ok,err]],'=audit-forwarding'))
 local function machine()
  local m=Execution.new(b); Execution.install_core(m); return m
 end
 local baseline=machine()
 Execution.run(baseline,b,Execution.executable(b),4096)
 local observed=machine(); M.watch(observed)
 Execution.run(observed,b,Execution.executable(b),4096)
 assert(observed.status=='return' and observed.result.n==4 and observed.result[1]==3
  and observed.result[2]==nil and observed.result[3]==false and observed.result[4]=='audit-error',
  'observer changed capture/protected-error/nil tuple semantics')
 assert(serpent.line(observed.result)==serpent.line(baseline.result)
  and observed.blocks==baseline.blocks and observed.allocations==baseline.allocations
  and observed.objects==baseline.objects and observed.next_id==baseline.next_id,
  'observer changed native execution accounting')
 assert(not pcall(Execution.run,observed,b,nil,-1),'observer swallowed host error')
 log('CC2 WORKFLOW OBSERVER SELFTEST PASS')
end
return M
