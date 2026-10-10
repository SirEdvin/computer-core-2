-- Fixed atomic local filesystem operations; no user code or arbitrary dispatch.
local FS=require('__computer_core_2__.scripts.filesystem')
local Import=require('__computer_core_2__.scripts.shell.import')
local Directory=require('__computer_core_2__.scripts.shell.directory')
local Resources=require('__computer_core_2__.scripts.shell.resources')
local M={VERSION=1,batch=8}
local operations={mkdir=true,cp=true,mv=true,rm=true}
local function plain(t) return type(t)=='table' and getmetatable(t)==nil end
local function integer(n,a,b) return type(n)=='number' and n==math.floor(n) and n>=a and n<=b end
local function inside(path,base) return path==base or path:sub(1,#base+1)==base..'/' end
local function parent(path) return path:match('^(.*)/[^/]+$') or '/' end
function M.new(state,op,args)
  assert(operations[op],'unknown filesystem operation')
  local src=FS.path(state.disk,args[1])
  local dst=(op=='cp' or op=='mv') and FS.path(state.disk,args[2]) or src
  assert(dst~='/' and not Directory.readonly(dst),'protected filesystem destination')
  local srcnode=Directory.get(state.disk,src)
  if op=='mkdir' then assert(not srcnode,'destination already exists')
  else
    assert(srcnode,'source does not exist')
    assert(op=='cp' or not Directory.readonly(src),'read-only source')
  end
  if op=='cp' or op=='mv' then
    assert(not Directory.get(state.disk,dst),'destination already exists; overwrite is not supported')
    assert(not inside(dst,src),'destination cannot be inside its source')
  end
  if op=='mkdir' or op=='cp' or op=='mv' then
    local p=parent(dst); if p=='' then p='/' end
    local node=Directory.get(state.disk,p)
    assert(node and node.type=='dir','destination parent does not exist')
    assert(not Directory.readonly(p),'read-only destination parent')
  end
  if op=='rm' or op=='mv' then assert(not inside(state.disk.cwd,src),'cannot remove current directory or its ancestor') end
  local input,err=Import.capture(state.disk); assert(input,err)
  local source=input.source
  if op=='cp' and Directory.readonly(src) then
    for path,node in pairs(Resources) do
      if inside(path,src) then source[#source+1]={path=path,node=node,resource=true} end
    end
  end
  return {version=1,kind='filesystem',op=op,phase='prepare',cursor=1,source=source,
    src=src,dst=dst,nodes={},paths={},parents={},count=0,bytes=0,metadata=0,cwd=state.disk.cwd}
end
function M.valid(job)
  if not plain(job) or job.version~=M.VERSION or job.kind~='filesystem' or not operations[job.op] then return false end
  local allowed={version=true,kind=true,op=true,phase=true,cursor=true,source=true,src=true,dst=true,nodes=true,
    paths=true,parents=true,count=true,bytes=true,metadata=true,cwd=true}
  local count=0
  for key in pairs(job) do count=count+1; if count>16 or not allowed[key] then return false end end
  if job.phase~='prepare' and job.phase~='publish' then return false end
  for _,key in ipairs({'src','dst','cwd'}) do if type(job[key])~='string' or #job[key]>1024 then return false end end
  return plain(job.source) and #job.source<=FS.max_nodes+2 and plain(job.nodes) and plain(job.paths) and plain(job.parents)
    and integer(job.cursor,1,#job.source+1) and integer(job.count,0,FS.max_nodes)
    and integer(job.bytes,0,FS.max_bytes) and integer(job.metadata,0,Import.max_metadata)
end
local function copy(node)
  assert(plain(node) and (node.type=='dir' or node.type=='file'),'invalid filesystem node')
  local out,fields={},0
  for key,value in pairs(node) do
    fields=fields+1; assert(fields<=5,'invalid filesystem node fields')
    if key=='type' then out.type=value
    elseif key=='text' then assert(node.type=='file' and type(value)=='string' and #value<=FS.max_bytes,'invalid file data'); out.text=value
    elseif key=='ctime' or key=='mtime' or key=='atime' then assert(integer(value,0,9007199254740991),'invalid node time'); out[key]=value
    else error('invalid filesystem node field',0) end
  end
  assert(out.type~='file' or type(out.text)=='string','missing file data')
  return out
end
local function add(job,path,node)
  assert(FS.path({cwd='/'},path)==path,'noncanonical destination')
  assert(not job.nodes[path],'duplicate destination')
  local value=copy(node)
  local bytes=value.type=='file' and #value.text or 0
  assert(job.count<FS.max_nodes and job.bytes+bytes<=FS.max_bytes and job.metadata+#path<=Import.max_metadata,'filesystem quota exceeded')
  job.count=job.count+1; job.bytes=job.bytes+bytes; job.metadata=job.metadata+#path
  job.nodes[path]=value; job.paths[job.count]=path
  local p=parent(path); if p=='' then p='/' end
  job.parents[path]=p -- Byte work belongs to the bounded preparation slice.
end
local function publication(job)
  -- Bounded shape/identity audit only: path-byte validation was paid per slice.
  local count,bytes,metadata=0,0,0
  for path,node in pairs(job.nodes) do
    count=count+1; assert(count<=FS.max_nodes and type(path)=='string' and #path<=1024,'invalid filesystem staging')
    local checked=copy(node)
    bytes=bytes+(checked.type=='file' and #checked.text or 0); metadata=metadata+#path
    if path~='/' then local p=job.parents[path]; assert(type(p)=='string' and #p<=1024 and job.nodes[p] and job.nodes[p].type=='dir','missing staged parent') end
  end
  assert(job.nodes['/'] and job.nodes['/'].type=='dir' and count==job.count and bytes==job.bytes and metadata==job.metadata,'inconsistent filesystem staging')
  local indexed,seen=0,{}
  for index,path in pairs(job.paths) do
    indexed=indexed+1
    assert(indexed<=FS.max_nodes and integer(index,1,job.count) and type(path)=='string' and #path<=1024 and job.nodes[path] and not seen[path],'invalid staged index')
    seen[path]=true
  end
  assert(indexed==job.count and #job.paths==job.count and job.cursor==#job.source+1,'incomplete filesystem staging')
  assert(job.nodes[job.cwd] and job.nodes[job.cwd].type=='dir' or Directory.readonly(job.cwd),'lost current directory')
  return {fs=job.nodes,paths=job.paths,cwd=job.cwd,nodes=count,bytes=bytes}
end
function M.audit(job)
  if not M.valid(job) then return false end
  local count,bytes,metadata,resources=0,0,0,0
  for index,record in pairs(job.source) do
    count=count+1
    if count>FS.max_nodes+2 or not integer(index,1,#job.source) or not plain(record)
      or type(record.path)~='string' or #record.path>1024 then return false end
    local fields=0
    for key,value in pairs(record) do
      fields=fields+1
      if fields>5 then return false end
      if key=='path' or key=='node' then
      elseif key=='canonical' or key=='parent_validated' then if type(value)~='boolean' then return false end
      elseif key=='resource' then
        if value~=true or job.op~='cp' or not Directory.readonly(job.src) or not Resources[record.path] then return false end
      else return false end
    end
    local ok,node=pcall(copy,record.node)
    if not ok then return false end
    if record.resource then
      resources=resources+1
      local bundled=Resources[record.path]
      if resources>2 or node.type~=bundled.type or node.text~=bundled.text then return false end
    else
      bytes=bytes+(node.type=='file' and #node.text or 0); metadata=metadata+#record.path
      if count-resources>FS.max_nodes or bytes>FS.max_bytes or metadata>Import.max_metadata then return false end
    end
  end
  if count~=#job.source then return false end
  if job.phase=='publish' then
    local ok=pcall(publication,job)
    return ok
  end
  return true
end
function M.work(job)
  -- Table work reserves the full closed source-envelope audit as well as the
  -- staged publication/index audit. Byte processing stays in eight-record slices.
  return {execution=1+32*M.batch,table=256*(FS.max_nodes+3),
    filesystem=32*M.batch*1024+128,string=16*M.batch*1024+128}
end
function M.advance(job)
  assert(M.valid(job),'malformed filesystem job')
  if job.phase=='prepare' then
    for i=job.cursor,math.min(#job.source,job.cursor+M.batch-1) do
      local record=job.source[i]
      assert(plain(record) and type(record.path)=='string' and #record.path<=1024,'invalid filesystem source')
      local matches=inside(record.path,job.src)
      if not record.resource and not (matches and (job.op=='mv' or job.op=='rm')) then add(job,record.path,record.node) end
      if matches and (job.op=='cp' or job.op=='mv') then add(job,job.dst..record.path:sub(#job.src+1),record.node) end
      job.cursor=i+1
    end
    if job.cursor>#job.source then
      if job.op=='mkdir' then add(job,job.dst,{type='dir'}) end
      job.phase='publish'
    end
    return false
  end
  -- All candidate data was validated per slice. This paid bounded envelope audit
  -- checks aliases/quotas/parents without byte copying or executable reconstruction.
  return publication(job)
end
return M
