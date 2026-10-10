-- Local/ROM directory bridge. No peer resolution, native IO or VM objects.
local Files = require('__computer_core_2__.scripts.native.files')
local Model = require('__computer_core_2__.scripts.filesystem')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local Handles = require('__computer_core_2__.scripts.native.file_handles')
local Loader = require('__computer_core_2__.scripts.native.loader')
local Glob = require('__computer_core_2__.scripts.native.glob')
local M = {}
local methods = {exists=Files.exists,isDir=Files.is_dir,isReadOnly=Files.is_readonly,
  getSize=Files.size,makeDir=Files.mkdir,delete=Files.delete}
local names = {'exists','isDir','isReadOnly','getSize','makeDir','delete','list','copy','move',
  'combine','getName','getDir','getFreeSpace','open','find'}
function M.install(machine, source)
  if machine.filesystem_installed then return end
  local disk = {cwd='/',fs={['/']={type='dir'}}}
  if source then
    assert(type(source)=='table' and getmetatable(source)==nil and type(source.fs)=='table'
      and getmetatable(source.fs)==nil, 'invalid native disk snapshot')
    local root=source.fs['/']
    assert(type(root)=='table' and getmetatable(root)==nil and root.type=='dir','invalid native disk root')
    local count, bytes = 0, 0
    for path,node in pairs(source.fs) do
      assert(type(path)=='string' and type(node)=='table' and getmetatable(node)==nil
        and (node.type=='file' or node.type=='dir'), 'invalid native disk node')
      assert(Model.path(disk,path)==path, 'native disk paths must be canonical')
      if node.type=='file' then
        assert(type(node.text)=='string', 'invalid native file content')
        bytes=bytes+#node.text
      end
      count=count+1
      assert(count<=Model.max_nodes and bytes<=Model.max_bytes, 'native disk quota exceeded')
      disk.fs[path]={type=node.type,text=node.type=='file' and node.text or nil}
    end
    assert(disk.fs['/'].type=='dir', 'invalid native disk root')
    for path in pairs(disk.fs) do
      if path~='/' then
        local parent=path:match('^(.*)/[^/]+$'); if parent=='' then parent='/' end
        assert(disk.fs[parent] and disk.fs[parent].type=='dir', 'native disk parent missing')
      end
    end
  end
  local library=Execution.table_value(machine)
  for _,name in ipairs(names) do Execution.set(machine,library,name,Execution.service_value(machine,'fs.'..name)) end
  Execution.set(machine,machine.env,'fs',library)
  local io=Execution.table_value(machine)
  for _,name in ipairs({'open','lines'}) do Execution.set(machine,io,name,Execution.service_value(machine,'io.'..name)) end
  Execution.set(machine,machine.env,'io',io)
  machine.open_handles, machine.handle_bytes = 0, 0
  machine.disk, machine.filesystem_installed = disk, true
  Loader.install(machine)
end
-- Trusted snapshot consumers must resolve this tree after every replacement.
function M.files(machine) return assert(machine.disk,'native filesystem not installed').fs end
function M.services(admit)
  assert(type(admit)=='function','native filesystem admission required')
  local function spend(amount) assert(admit(amount)~=false,'native filesystem work quota exceeded') end
  local services={}
  for method,implementation in pairs(methods) do
    local name,handler=method,implementation
    services['fs.'..name]=function(machine,args) return 'return',table.pack(handler(machine,args[1],spend)) end
  end
  for _,entry in ipairs({{'list',Files.list},{'find',Glob.find}}) do
    local name,handler=entry[1],entry[2]
    services['fs.'..name]=function(machine,args)
      local result=handler(machine,args[1],spend)
      assert(#result<=Limits.table_keys,'native directory result quota exceeded')
      spend(1+4*#result)
      local value=Execution.table_value(machine)
      for i,path in ipairs(result) do Execution.set(machine,value,i,path) end
      return 'return',{n=1,value}
    end
  end
  for _,method in ipairs({'copy','move'}) do
    local name=method
    services['fs.'..name]=function(machine,args)
      Files.transfer(machine,args[1],args[2],name=='move',spend)
      return 'return',{n=0}
    end
  end
  services['fs.combine']=function(_,args)
    local segments={}; spend(1)
    for i=1,args.n do
      assert(type(args[i])=='string' and #args[i]<=1024,'invalid path segment')
      spend(1+16*(#args[i]+1)); segments[i]=args[i]
    end
    return 'return',{n=1,Model.path({cwd='/'},'/'..table.concat(segments,'/')):sub(2)}
  end
  local function metadata(machine,name)
    assert(type(name)=='string' and #name<=1024,'invalid path')
    spend(1+16*(#name+#machine.disk.cwd+1))
    return name=='' and '/' or Model.path(machine.disk,name)
  end
  services['fs.getName']=function(machine,args) return 'return',{n=1,metadata(machine,args[1]):match('[^/]+$') or ''} end
  services['fs.getDir']=function(machine,args)
    local directory=(metadata(machine,args[1]):match('^(.*)/[^/]+$') or ''):gsub('^/','')
    return 'return',{n=1,directory}
  end
  services['fs.getFreeSpace']=function(machine)
    spend(1); local bytes=0
    for _,node in pairs(machine.disk.fs) do spend(1); if node.type=='file' then bytes=bytes+#node.text end end
    return 'return',{n=1,Model.max_bytes-bytes}
  end
  for name,service in pairs(Handles.services(spend)) do
    services[name]=service
  end
  return services
end
return M
