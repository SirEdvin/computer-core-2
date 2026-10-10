local Compiler=require('__computer_core_2__.scripts.native.compiler')
local Execution=require('__computer_core_2__.scripts.native.execution')
local Helpers=require('__computer_core_2__.scripts.native.helpers')
local Scheduler=require('__computer_core_2__.scripts.native.scheduler')
local Collector=require('__computer_core_2__.scripts.native.collector')
local Events=require('__computer_core_2__.scripts.native.events')
local FS=require('__computer_core_2__.scripts.native.filesystem')
local Limits=require('__computer_core_2__.scripts.guest.limits')
local Model=require('__computer_core_2__.scripts.filesystem')
local function create(source,input)
 local m=Execution.new(assert(Compiler.compile(source,'=native-file-handle')))
 Execution.install_core(m); Helpers.install(m); Events.install_services(m)
 FS.install(m,input or {fs={['/']={type='dir'},['/original']={type='file',text='old'},
  ['/lines']={type='file',text='a\nb\n'},['/binary']={type='file',text='\0\255'}}})
 local s=Scheduler.new(); Scheduler.add(s,1,m); return s,m
end
local function finish(s,tick,terminal)
 local m=s.machines[1]
 for i=0,100 do
  Scheduler.tick(s,tick+i)
  if m.status=='return' or m.status=='error' or (m.status=='yield' and not terminal) then return m end
 end
 error('native handle fixture deadline exceeded')
end
local function capture(m)
 return serpent.line({fs=m.disk.fs,open=m.open_handles,bytes=m.handle_bytes},{sortkeys=true})
end
local function bind(m,receiver,method)
 local ref=Execution.get(m,receiver,method); return m.heap[ref.native_ref].data
end
local function invoke(m,receiver,method,args,admit)
 return FS.services(admit or function() return true end)['@file.'..method](m,args or {n=0},bind(m,receiver,method))
end
local function opened(m,io_mode)
 local _,result=FS.services(function() return true end)[io_mode and 'io.open' or 'fs.open'](m,{n=2,'/original','w+'})
 assert(result[1],result[2]); return result[1]
end
local function record(m,receiver) return m.heap[bind(m,receiver,'read').handle.native_ref] end
local function collect(m)
 Collector.start(m)
 while m.collector do Collector.step(m,64) end
end
return {
 run=function(check)
  local _,abort_m=create('return true')
  local receiver=opened(abort_m,true)
  invoke(abort_m,receiver,'write',{n=2,receiver,'prefix'})
  local before=capture(abort_m)
  local ok=pcall(invoke,abort_m,receiver,'abort',{n=1,receiver},function() error('no abort credits',0) end)
  check('native abort credit refusal preserves staged draft accounting and committed file',not ok and capture(abort_m)==before
   and not record(abort_m,receiver).closed and record(abort_m,receiver).text=='prefix')
  invoke(abort_m,receiver,'abort',{n=1,receiver})
  check('native admitted abort discards staged prefix without flush and releases handles',abort_m.disk.fs['/original'].text=='old'
   and abort_m.open_handles==0 and abort_m.handle_bytes==0 and record(abort_m,receiver).closed)
  local s,m=create([[
local h=assert(fs.open('/original','w+'))
local alias=h
h:write('leaf')
local before=assert(fs.open('/original','r')); local old=before.readAll(); before.close()
h.seek('set',1); h.write('X'); h.seek('set',7); h.write('Z'); h.seek('set',0)
local draft=h:readAll(); local same=h.flush()==alias; h.close()
local reopened=assert(io.open('/original','r'))
local content=reopened:read('*a'); local eof=reopened:read(1); reopened:close()
return old,draft,content,eof,same,type(h),type(h.write),h.file_handle==nil,pcall(h.readAll)
]])
  finish(s,10)
  check('native fs and io handles preserve draft offset padding dot colon and identity',m.status=='return'
   and m.result[1]=='old' and m.result[2]=='lXaf\0\0\0Z' and m.result[3]==m.result[2]
   and m.result[4]==nil and m.result[5] and m.result[6]=='table' and m.result[7]=='function'
   and m.result[8] and m.result[9]==false and m.open_handles==0 and m.handle_bytes==0)
  s,m=create([[
local h=assert(fs.open('/binary','rb'))
local a,b,c=h.read(),h:read(),h.read(); h.close()
local w=assert(fs.open('/bytes','wb')); w.write(0,255); w.close()
local r=assert(fs.open('/bytes','rb')); local bytes=r.readAll(); r.close()
local append=assert(io.open('/original','a+')); append:seek('set',0); append:write('tail'); append:seek('set',0)
local appended=append:read('*a'); append:close()
local lines=assert(io.open('/lines','r')); local first,second=lines:read('*l','*l'); lines:close()
local values={}; for line in io.lines('/lines') do values[#values+1]=line end
local owned=assert(fs.open('/lines','r')); local iterator=owned.lines(); local one,two,none=iterator(),iterator(),iterator(); owned.close()
return a,b,c,bytes,appended,first,second,values[1],values[2],#values,one,two,none
]])
  finish(s,120)
  check('native binary append multi-format reads owned and auto-close iterators',m.status=='return'
   and m.result[1]==0 and m.result[2]==255 and m.result[3]==nil and m.result[4]=='\0\255' and m.result[5]=='oldtail'
   and m.result[6]=='a' and m.result[7]=='b' and m.result[8]=='a' and m.result[9]=='b'
   and m.result[10]==2 and m.result[11]=='a' and m.result[12]=='b' and m.result[13]==nil
   and m.open_handles==0 and m.handle_bytes==0)
  for _,mode in ipairs({'r','w','a','rb','wb','ab','r+','w+','a+','r+b','w+b','a+b','rb+','wb+','ab+'}) do
   s,m=create('return 1'); local _,result=FS.services(function() return true end)['fs.open'](m,{n=2,'/original',mode})
   check('native validated durable handle mode '..mode,result[1]~=nil and record(m,result[1]).version==1)
   invoke(m,result[1],'close'); check('native handle mode releases quotas '..mode,m.open_handles==0 and m.handle_bytes==0)
  end
  s,m=create([[
local missing,why=fs.open('/missing','r')
local rom=assert(fs.open('/rc/programs/shell.lua','r')); local source=rom.readAll(); rom.close()
local denied=fs.open('/rc/forbidden','w'); local bad=fs.open('/original','evil')
return missing,why,denied,bad,#source>0
]])
  finish(s,220)
  check('native open failures return nil diagnostic and ROM is source-only readonly',m.status=='return'
   and m.result[1]==nil and type(m.result[2])=='string' and m.result[3]==nil and m.result[4]==nil
   and m.result[5] and m.open_handles==0)
  for _,method in ipairs({'read','readAll','readLine','write','writeLine','seek','flush','close'}) do
   s,m=create('return 1'); local receiver=opened(m,true); invoke(m,receiver,'write',{n=1,'draft'})
   invoke(m,receiver,'seek',{n=2,'set',0})
   local before=capture(m); local h=record(m,receiver); local draft=h.text; local offset=h.offset
   local args=({read={n=1,'*a'},write={n=1,'changed'},writeLine={n=1,'line'},seek={n=2,'set',2}})[method] or {n=0}
   local ok=pcall(invoke,m,receiver,method,args,function() return false end)
   check('native credit-refused handle operation is atomic '..method,not ok and capture(m)==before
    and h.text==draft and h.offset==offset and not h.closed and not h.failed)
  end
  for _,case in ipairs({{'read',{n=2,2,2}},{'write',{n=2,'one','two'}}}) do
   s,m=create('return 1'); local receiver=opened(m,true); invoke(m,receiver,'write',{n=1,'abcdef'})
   invoke(m,receiver,'seek',{n=2,'set',0})
   local h=record(m,receiver); local before=capture(m); local saved=h.text; local offset=h.offset
   -- Admit the first member of the batch but refuse later work.
   local calls=0; local ok=pcall(invoke,m,receiver,case[1],case[2],function()
    calls=calls+1; return calls<4
   end)
   check('native multi-operand IO refusal never publishes a partial batch '..case[1],not ok
    and capture(m)==before and h.text==saved and h.offset==offset and not h.failed)
  end
  s,m=create('return 1'); local receiver=opened(m,true)
  invoke(m,receiver,'write',{n=1,'draft'})
  local h=record(m,receiver); local before=capture(m); local needed=0
  local measuring=FS.services(function(amount) needed=needed+amount; return true end)
  -- Measure a corresponding successful flush on a different graph.
  local _,reference=create('return 1'); local other=opened(reference,true); invoke(reference,other,'write',{n=1,'draft'})
  measuring['@file.close'](reference,{n=0},bind(reference,other,'close'))
  local used=0; local ok=pcall(invoke,m,receiver,'close',{n=0},function(amount) used=used+amount; return used<needed end)
  check('native final-charge close refusal retains retryable draft and committed bytes',not ok and capture(m)==before
   and not h.closed and h.text=='draft')
  invoke(m,receiver,'close')
  check('native successful close retry publishes once and releases quotas',h.closed and m.disk.fs['/original'].text=='draft'
   and m.open_handles==0 and m.handle_bytes==0)
  s,m=create('return 1'); receiver=opened(m,true)
  m.external_roots={Execution.get(m,receiver,'write')}; collect(m)
  check('native captured method alone roots private handle and complete receiver',m.heap[receiver.native_ref]~=nil
   and m.open_handles==1 and record(m,receiver).text=='')
  m.external_roots=nil; collect(m)
  check('native unreachable draft collection releases quotas without publishing',m.open_handles==0 and m.handle_bytes==0
   and m.disk.fs['/original'].text=='old')
  s,m=create('return 1'); local before=capture(m)
  while m.objects<Limits.heap_objects-10 do Execution.table_value(m) end
  local count=m.objects; local _,result=FS.services(function() return true end)['fs.open'](m,{n=2,'/original','w+'})
  check('native full heap open refuses before record counters or disk publication',result[1]==nil and type(result[2])=='string'
   and capture(m)==before and m.objects==count)
  s,m=create('return 1'); local receivers={}
  for i=1,Limits.open_handles do receivers[i]=opened(m,true) end
  local _,refused=FS.services(function() return true end)['fs.open'](m,{n=2,'/original','r'})
  check('native open handle ceiling is unchanged and refusal does not retain bytes',refused[1]==nil
   and m.open_handles==Limits.open_handles and m.handle_bytes==0)
  for _,value in ipairs(receivers) do invoke(m,value,'close') end
  s,m=create('return 1'); receiver=opened(m,true)
  local before=capture(m)
  local h=record(m,receiver)
  invoke(m,receiver,'seek',{n=2,'set',Model.max_bytes})
  local ok=pcall(invoke,m,receiver,'write',{n=1,'x'})
  check('native content-quota write refuses without changing offset draft or committed tree',not ok
   and h.failed and h.text=='' and h.offset==Model.max_bytes and capture(m)==before)
  ok=pcall(invoke,m,receiver,'close')
  check('native failed-content close releases without truncating previous saved file',not ok and h.closed
   and m.disk.fs['/original'].text=='old' and m.open_handles==0 and m.handle_bytes==0)
  local maximum=string.rep('x',Limits.string_bytes)
  s,m=create('return 1',{fs={['/']={type='dir'},['/original']={type='file',text=maximum..'\n'}}})
  local _,result=FS.services(function() return true end)['fs.open'](m,{n=2,'/original','r'})
  receiver=result[1]; h=record(m,receiver)
  ok=pcall(invoke,m,receiver,'readAll')
  check('native oversized read result refuses before offset mutation',not ok and h.offset==0 and h.text==maximum..'\n')
  local _,read=invoke(m,receiver,'read',{n=1,Limits.string_bytes})
  check('native maximum counted read uses bounded output and exact offset',read[1]==maximum and h.offset==Limits.string_bytes)
  invoke(m,receiver,'seek',{n=2,'set',0})
  ok=pcall(invoke,m,receiver,'readLine')
  check('native maximum-plus-newline read follows shared bounded scan contract',not ok and h.offset==0)
  s,m=create('return 1',{fs={['/']={type='dir'},['/original']={type='file',text='old'}}})
  receiver=opened(m,true)
  local chunk=string.rep('x',Limits.string_bytes)
  for i=1,Model.max_bytes/Limits.string_bytes do
   Scheduler.begin_tick(s,1000+i)
   invoke(m,receiver,'write',{n=1,chunk},function(amount) return Scheduler.consume(s,1,'filesystem',amount) end)
  end
  check('native maximum draft reconstruction fits fresh unchanged filesystem credits',record(m,receiver).text==string.rep('x',Model.max_bytes)
   and m.handle_bytes==Model.max_bytes and s.budget.used.filesystem<=Limits.filesystem_work_per_computer)
  Scheduler.begin_tick(s,2000)
  invoke(m,receiver,'close',{n=0},function(amount) return Scheduler.consume(s,1,'filesystem',amount) end)
  check('native maximum commit is bounded and releases retained draft quota',#m.disk.fs['/original'].text==Model.max_bytes
   and m.open_handles==0 and m.handle_bytes==0 and s.budget.used.filesystem<=Limits.filesystem_work_per_computer)
 end,
 suspend=function(check)
  local s,m=create([[
boot=(boot or 0)+1
local h=assert(io.open('/original','w+')); h:write('saved-draft'); h:seek('set',2)
local read,write,seek,close=h.read,h.write,h.seek,h.close
h=nil; fs=nil; io=nil
coroutine.yield('draft-ready')
local bytes=read(2)
seek('set',0); write('new'); close()
return boot,bytes,nil
]])
  finish(s,game.tick); assert(m.status=='yield')
  local handle; for _,id in ipairs(m.object_ids) do local o=m.heap[id]; if o.kind=='handle' then handle=o end end
  assert(handle and handle.text=='saved-draft' and handle.offset==2)
  assert(Scheduler.consume(s,1,'filesystem',Scheduler.remaining(s,1,'filesystem')))
  Collector.start(m)
  check('native private draft offset and quotas are retained at suspension',m.open_handles==1 and m.handle_bytes==11
   and m.disk.fs['/original'].text=='old')
  return {scheduler=s,tick=s.budget.tick,handle=handle,before=capture(m),blocks=m.blocks}
 end,
 reload=function(state,check)
  local s,m=state.scheduler,state.scheduler.machines[1]
  local h=state.handle
  check('native handle reload preserves draft identity offsets accounting and no replay',h.text=='saved-draft' and h.offset==2
   and capture(m)==state.before and m.blocks==state.blocks and Scheduler.remaining(s,1,'filesystem')==0)
  local receiver; for _,id in ipairs(m.object_ids) do local o=m.heap[id]
   if o.kind=='service' and o.name=='@file.close' then receiver=o.data.receiver end
  end
  local ok=pcall(invoke,m,receiver,'close',{n=0},function(amount) return Scheduler.consume(s,1,'filesystem',amount) end)
  check('native same-tick reloaded close remains retryable without altering saved draft',not ok and not h.closed
   and capture(m)==state.before and h.offset==2 and h.text=='saved-draft')
  assert(Events.admit(m,table.pack('char','resume')))
  finish(s,state.tick+1,true)
  check('native collected captured methods commit resumed draft exactly once after reload',m.status=='return'
   and m.result.n==3 and m.result[1]==1 and m.result[2]=='ve' and h.closed and m.disk.fs['/original'].text=='newed-draft'
   and m.open_handles==0 and m.handle_bytes==0)
 end,
}
