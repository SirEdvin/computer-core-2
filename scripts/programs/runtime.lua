-- Restricted native controllers. Generated closures and ASTs are ephemeral.
local Compiler=require('__computer_core_2__.scripts.programs.compiler')
local FS=require('__computer_core_2__.scripts.filesystem')
local Directory=require('__computer_core_2__.scripts.shell.directory')
local Circuit=require('__computer_core_2__.scripts.programs.circuit')
local M={VERSION=1,output_records=64,output_bytes=16384}
-- Completed one-shot controllers may be replaced without explicit stop. Do not
-- keep their source/closures alive after the durable record loses its owner.
local cache=setmetatable({},{__mode='k'})
local function plain(t) return type(t)=='table' and getmetatable(t)==nil end
local function integer(n,a,b) return type(n)=='number' and n==math.floor(n) and n>=a and n<=b end
local function scalar(value)
  local kind=type(value)
  assert(kind=='nil' or kind=='boolean' or kind=='number' and value==value and math.abs(value)<math.huge
    or kind=='string' and #value<=256,'expected finite scalar / string <=256 bytes')
  return value
end
local function valid_state(values)
  if not plain(values) then return false end
  local count,bytes=0,0
  for key,value in pairs(values) do
    count=count+1
    if count>64 or type(key)~='string' or #key>64 or not key:match('^[%a_][%w_]*$') then return false end
    local kind=type(value)
    if kind=='string' then if #value>256 then return false end; bytes=bytes+#value
    elseif kind=='number' then if value~=value or math.abs(value)==math.huge then return false end
    elseif kind~='boolean' then return false end
  end
  return bytes<=16384
end
M.valid_state=valid_state
local controller_fields={version=true,compiler=true,api=true,path=true,source=true,state=true,generation=true,
  status=true,interval=true,next_tick=true,started=true,message=true,owner=true,outputs=true}
function M.valid(c)
  if not plain(c) then return false end
  local count=0
  for key in pairs(c) do count=count+1; if count>14 or not controller_fields[key] then return false end end
  if c.owner~=nil then
    if not plain(c.owner) then return false end
    local fields=0
    for key,value in pairs(c.owner) do
      fields=fields+1
      if fields>3 or key~='id' and key~='force' and key~='surface' or not integer(value,1,9007199254740991) then return false end
    end
    if fields~=3 then return false end
  end
  return c.version==M.VERSION and c.compiler==Compiler.VERSION and c.api==Compiler.API
    and type(c.path)=='string' and #c.path<=1024 and type(c.source)=='string' and #c.source<=Compiler.source_bytes
    and valid_state(c.state) and (c.outputs==nil or Circuit.valid_banks(c.outputs))
    and integer(c.generation,1,9007199254740991) and integer(c.interval,1,3600)
    and integer(c.next_tick,0,9007199254740991) and type(c.started)=='boolean'
    and (c.status=='running' or c.status=='paused' or c.status=='faulted' or c.status=='stopped')
    and (c.message==nil or type(c.message)=='string' and #c.message<=1024)
end
function M.valid_output(output)
  if not plain(output) or output.version~=1 or not plain(output.queue) or not integer(output.bytes,0,M.output_bytes) then return false end
  local fields=0; for key in pairs(output) do fields=fields+1; if fields>3 or key~='version' and key~='queue' and key~='bytes' then return false end end
  local count,bytes,last=0,0,0
  for index,text in pairs(output.queue) do
    count=count+1
    if not integer(index,1,M.output_records) or count>M.output_records or type(text)~='string' or #text>256 then return false end
    bytes=bytes+#text; last=math.max(last,index)
  end
  return count==last and bytes==output.bytes
end
function M.valid_job(job)
  if not plain(job) then return false end
  local count=0
  for key in pairs(job) do count=count+1; if count>4 or key~='version' and key~='kind' and key~='source' and key~='path' then return false end end
  return job.version==1 and job.kind=='program' and type(job.source)=='string' and #job.source<=Compiler.source_bytes
    and type(job.path)=='string' and #job.path<=1024
end
function M.job(state,path)
  assert(not state.controller or state.controller.status=='stopped','stop the current controller before run')
  path=FS.path(state.disk,path)
  assert(not Directory.readonly(path),'run requires committed local source; copy the example first')
  local node=state.disk.fs[path]
  assert(node and node.type=='file','run: not a local source file')
  assert(#node.text<=Compiler.source_bytes,'run: source exceeds 16 KiB')
  return {version=1,kind='program',source=node.text,path=path}
end
function M.activate(state,job,tick,services)
  local compiled,err=Compiler.compile(job.source,job.path)
  if not compiled then return nil,err end
  local generation=state.controller and state.controller.generation+1 or 1
  assert(generation<=9007199254740991,'program generation exhausted')
  local c={version=M.VERSION,compiler=Compiler.VERSION,api=Compiler.API,path=job.path,source=job.source,state={},
    generation=generation,status='running',interval=compiled.interval,next_tick=tick,started=false,
    owner=services and services.identity() or nil,outputs={left={},right={}}}
  cache[c]={source=c.source,path=c.path,generation=c.generation,compiled=compiled}; state.controller=c
  if not state.program_output then state.program_output={version=1,queue={},bytes=0} end
  return true
end
function M.stop(state,services)
  if services then services.clear() end
  if state.controller then state.controller.status='stopped'; state.controller.message=nil; cache[state.controller]=nil end
end
function M.describe(state)
  local c=state.controller
  if not c then return 'No controller\n' end
  return c.status..' '..c.path..' next='..c.next_tick..(c.message and ' '..c.message or '')..'\n'
end
function M.take_print(state)
  local output=state.program_output
  if not output or #output.queue==0 then return nil end
  local text=table.remove(output.queue,1); output.bytes=output.bytes-#text
  return text
end
function M.callback_work()
  -- The default-deny compiler also checks its syntax-derived cost envelope.
  -- Reserve the complete accepted-subset upper bound before even reconstructing
  -- a cold closure. This intentionally charges warm hits equally and trusts no
  -- player/save-supplied work estimates, generated text or cached bytecode.
  return {compiler=Compiler.work().compiler,execution=2048,string=262144,table=524288,event=8192,filesystem=65536}
end
local function context(prints,banks,controller,services,effects)
  local a={scalar=scalar}
  function a.concat(...)
    local parts,bytes={},0
    for i=1,select('#',...) do
      local value=scalar(select(i,...)); local kind=type(value)
      assert(kind=='number' or kind=='string','concat requires numbers or strings')
      local text=tostring(value); bytes=bytes+#text; assert(bytes<=256,'concatenation exceeds 256 bytes'); parts[i]=text
    end
    return table.concat(parts)
  end
  function a.call(name,...)
    local n=select('#',...)
    if name=='print' then
      assert(#prints<8,'print call limit exceeded')
      local parts,bytes={},math.max(0,n-1)
      for i=1,n do local text=tostring(scalar(select(i,...))); bytes=bytes+#text; assert(bytes<=256,'print exceeds 256 bytes'); parts[i]=text end
      prints[#prints+1]=table.concat(parts,' '); return nil
    elseif name:sub(1,5)=='math.' then
      assert(n>=1 and n<=64,'math argument limit exceeded')
      local args={}
      for i=1,n do args[i]=scalar(select(i,...)); assert(type(args[i])=='number','math requires finite numbers') end
      local member=name:sub(6)
      if member=='floor' or member=='abs' then assert(n==1,'math '..member..' requires one argument') end
      assert(member=='floor' or member=='abs' or member=='min' or member=='max','unlisted math call')
      return scalar(math[member](table.unpack(args,1,n)))
    end
    assert(services,'Circuit services require an owned physical blue computer')
    effects.calls=effects.calls+1; assert(effects.calls<=16,'circuit call limit exceeded')
    effects.circuits=true
    local side,kind,signal,count=...
    if name=='circuit.read' then
      assert(n==4,'circuit.read requires side, wire, type, name')
      return scalar(services.read(controller,...))
    end
    services.validate(controller,side)
    if name=='circuit.clear' then
      assert(n==1,'circuit.clear requires one side'); banks[side]={}; return nil
    end
    assert(name=='circuit.write' and n==4,'circuit.write requires side, type, name, count')
    services.signal(kind,signal)
    assert(integer(count,-2147483648,2147483647),'signal count must be int32')
    local identity=kind..':'..signal
    if count==0 then banks[side][identity]=nil else banks[side][identity]={type=kind,name=signal,count=count} end
    assert(Circuit.valid_banks(banks),'at most 32 output identities per side')
    return nil
  end
  return a
end
function M.step(state,tick,powered,admit,services)
  local c=state.controller
  if not c or c.status=='stopped' or c.status=='faulted' then return false end
  if not powered then
    if c.status=='paused' then return false end
    if not admit({execution=1,table=16}) then return false,'work deferred' end
    c.status='paused'; return true
  end
  if c.status~='paused' and tick<c.next_tick then return false end
  if not admit(M.callback_work()) then return false,'work deferred' end
  local entry=cache[c]
  local compiled=entry and entry.source==c.source and entry.path==c.path and entry.generation==c.generation and entry.compiled
  if not compiled then
    local err; compiled,err=Compiler.compile(c.source,c.path)
    if not compiled then if services then services.clear() end; c.status='faulted'; c.message=err; return true end
    cache[c]={source=c.source,path=c.path,generation=c.generation,compiled=compiled}
  end
  if compiled.interval~=c.interval then if services then services.clear() end; c.status='faulted'; c.message='incompatible retained interval'; return true end
  local values,prints,banks,effects={}, {},{left={},right={}},{calls=0,circuits=false}
  for key,value in pairs(c.state) do values[key]=value end
  for _,side in ipairs({'left','right'}) do
    for identity,value in pairs(c.outputs and c.outputs[side] or {}) do banks[side][identity]={type=value.type,name=value.name,count=value.count} end
  end
  local name=not c.started and 'on_start' or 'on_tick'
  local handler=compiled[name]
  local ok,err=pcall(function()
    if services then services.prepare(c) end
    if handler then handler(context(prints,banks,c,services,effects),{name=name,tick=tick},values) end
    assert(valid_state(values),'persistent state exceeds scalar/key/payload limits')
    assert(Circuit.valid_banks(banks),'output bank limit exceeded')
    local output=state.program_output
    assert(output and M.valid_output(output),'malformed controller output FIFO')
    local bytes=output.bytes
    for _,text in ipairs(prints) do bytes=bytes+#text end
    assert(#output.queue+#prints<=M.output_records and bytes<=M.output_bytes,'background output FIFO is full')
    if services and (effects.circuits or next(banks.left) or next(banks.right)) then services.publish(c,banks) end
  end)
  if not ok then
    if services then services.clear() end
    c.status='faulted'; c.message=(c.path..': '..tostring(err)):sub(1,1024); return true
  end
  -- No state or print publication precedes successful full validation.
  c.state=values; c.outputs=banks; c.started=true; c.status=compiled.on_tick and 'running' or 'stopped'
  if c.status=='stopped' and services then services.clear() end
  c.next_tick=math.min(9007199254740991,tick+c.interval)
  for _,text in ipairs(prints) do state.program_output.queue[#state.program_output.queue+1]=text; state.program_output.bytes=state.program_output.bytes+#text end
  return true
end
return M
