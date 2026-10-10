-- Durable private file records bound to symbolic methods, never host closures.
local Files = require('__computer_core_2__.scripts.native.files')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local M = {}
local methods = {'read','readAll','readLine','write','writeLine','seek','flush','close','lines','abort'}
local function capacity(machine, count)
  assert(not machine.collector, 'native allocation paused during collection')
  assert(machine.objects + count <= Limits.heap_objects, 'native heap quota exceeded')
end
local function binding(machine, record, io_mode)
  local handle = Execution.handle_value(machine, record)
  local receiver = Execution.table_value(machine)
  machine.heap[receiver.native_ref].file_handle = handle
  for _,name in ipairs(methods) do
    Execution.set(machine, receiver, name, Execution.service_value(machine, '@file.'..name,
      {handle=handle,receiver=receiver,io_mode=io_mode}))
  end
  return receiver
end
local function state(machine, data)
  local record = assert(data and machine.heap[data.handle.native_ref], 'invalid native file binding')
  assert(record.kind=='handle' and record.version==1, 'unsupported native file handle version')
  return record
end
local function staged(machine, handle, spend)
  spend(32)
  local copy={}; for key,value in pairs(handle) do copy[key]=value end
  return copy, {disk=machine.disk,open_handles=machine.open_handles,handle_bytes=machine.handle_bytes}
end
local function publish(machine, handle, copy, shadow)
  handle.text,handle.offset,handle.failed,handle.closed=copy.text,copy.offset,copy.failed,copy.closed
  machine.open_handles,machine.handle_bytes=shadow.open_handles,shadow.handle_bytes
end
function M.services(spend)
  local services={}
  local function arguments(machine,args,data)
    local handle=state(machine,data)
    if args.n>0 and type(args[1])=='table' and args[1].native_ref==data.receiver.native_ref then
      spend(1+4*args.n)
      local shifted={n=args.n-1}; for i=1,shifted.n do shifted[i]=args[i+1] end
      args=shifted
    end
    return handle,args
  end
  local function open(machine,args,io_mode,extra)
    local ok,result=pcall(function()
      capacity(machine,2+#methods+(extra or 0)); spend(1+4*#methods)
      -- Directory-only older snapshots have no file accounting yet.
      machine.open_handles,machine.handle_bytes=machine.open_handles or 0,machine.handle_bytes or 0
      local record=Files.open(machine,args[1],args[2],spend)
      return binding(machine,record,io_mode)
    end)
    return ok and {n=1,result} or {n=2,nil,tostring(result)}
  end
  services['fs.open']=function(machine,args) return 'return',open(machine,args,false) end
  services['io.open']=function(machine,args) return 'return',open(machine,args,true) end
  services['@file.read']=function(machine,args,data)
    local handle; handle,args=arguments(machine,args,data)
    if not data.io_mode then
      local result=Files.read(handle,args[1]==nil and 1 or args[1],spend)
      if handle.binary and args[1]==nil and result then result=string.byte(result) end
      return 'return',{n=1,result}
    end
    spend(1+4*math.max(1,args.n))
    local copy,shadow=staged(machine,handle,spend)
    local result={n=math.max(1,args.n)}
    for i=1,result.n do result[i]=Files.read(copy,args[i],spend) end
    publish(machine,handle,copy,shadow)
    return 'return',result
  end
  services['@file.readAll']=function(machine,args,data)
    local handle=arguments(machine,args,data)
    return 'return',{n=1,Files.read(handle,'a',spend)}
  end
  services['@file.readLine']=function(machine,args,data)
    local handle; handle,args=arguments(machine,args,data)
    return 'return',{n=1,Files.read(handle,args[1] and 'L' or 'l',spend)}
  end
  services['@file.write']=function(machine,args,data)
    local handle; handle,args=arguments(machine,args,data)
    spend(1+4*args.n)
    local copy,shadow=staged(machine,handle,spend)
    local ok,err=pcall(function()
      for i=1,args.n do
        local text=args[i]
        if type(text)=='number' then
          spend(64)
          if copy.binary and not data.io_mode then
            assert(text==math.floor(text) and text>=0 and text<=255,'invalid byte'); text=string.char(text)
          else text=tostring(text) end
        end
        Files.write(shadow,copy,text,spend)
      end
    end)
    if not ok then
      if copy.failed then handle.failed=true end
      error(err,0)
    end
    publish(machine,handle,copy,shadow)
    return 'return',data.io_mode and {n=1,data.receiver} or {n=0}
  end
  services['@file.writeLine']=function(machine,args,data)
    local handle; handle,args=arguments(machine,args,data)
    spend(1)
    local text=args[1] or ''
    if type(text)=='number' then spend(64); text=tostring(text) end
    assert(type(text)=='string' and #text<Limits.string_bytes,'write line exceeds byte limit')
    spend(1+#text)
    Files.write(machine,handle,text..'\n',spend)
    return 'return',{n=0}
  end
  services['@file.seek']=function(machine,args,data)
    local handle; handle,args=arguments(machine,args,data)
    return 'return',{n=1,Files.seek(handle,args[1],args[2],spend)}
  end
  services['@file.flush']=function(machine,args,data)
    local handle=arguments(machine,args,data); Files.flush(machine,handle,spend)
    return 'return',{n=1,data.receiver}
  end
  services['@file.close']=function(machine,args,data)
    local handle=arguments(machine,args,data); Files.close(machine,handle,spend)
    return 'return',{n=1,true}
  end
  services['@file.abort']=function(machine,args,data)
    local handle=arguments(machine,args,data)
    assert(not handle.closed,'file handle is closed')
    spend(1) -- Never flush a partially staged save after a failed write.
    handle.closed,machine.open_handles=true,machine.open_handles-1
    machine.handle_bytes,handle.text=machine.handle_bytes-#handle.text,''
    return 'return',{n=1,true}
  end
  local function iterator(machine,data,formats,auto_close)
    capacity(machine,1); spend(1+4*formats.n)
    return Execution.service_value(machine,'@file.iterator',
      {handle=data.handle,receiver=data.receiver,formats=formats,auto_close=auto_close})
  end
  services['@file.lines']=function(machine,args,data)
    local _,formats=arguments(machine,args,data)
    return 'return',{n=1,iterator(machine,data,formats,false)}
  end
  services['@file.iterator']=function(machine,_,data)
    local handle=state(machine,data)
    spend(1+4*math.max(1,data.formats.n))
    local copy,shadow=staged(machine,handle,spend)
    local result={n=math.max(1,data.formats.n)}
    for i=1,result.n do result[i]=Files.read(copy,data.formats[i],spend) end
    if result[1]==nil and data.auto_close then Files.close(shadow,copy,spend) end
    publish(machine,handle,copy,shadow)
    return 'return',result
  end
  services['io.lines']=function(machine,args)
    spend(1+4*args.n)
    local opened=open(machine,{n=2,args[1],'r'},true,1)
    assert(opened[1],opened[2])
    local formats={n=math.max(0,args.n-1)}
    for i=1,formats.n do formats[i]=args[i+1] end
    local method=Execution.get(machine,opened[1],'lines')
    local data=machine.heap[method.native_ref].data
    -- Opening pre-admitted the fixed binding construction. No later credit
    -- refusal may strand a successfully opened private handle.
    return 'return',{n=1,Execution.service_value(machine,'@file.iterator',
      {handle=data.handle,receiver=data.receiver,formats=formats,auto_close=true})}
  end
  return services
end
return M
