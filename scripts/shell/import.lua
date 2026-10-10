-- Fixed boot/import operation; never an interpreter or persisted hash iterator.
local FS=require('__computer_core_2__.scripts.filesystem')
local M={VERSION=1,batch=8,max_metadata=FS.max_nodes*1024}
local function plain(t) return type(t)=='table' and getmetatable(t)==nil end
local function integer(n,a,b) return type(n)=='number' and n==math.floor(n) and n>=a and n<=b end
local function node_valid(node)
  if not plain(node) or (node.type~='dir' and node.type~='file') then return false end
  local count=0
  for key,value in pairs(node) do
    count=count+1
    if count>5 then return false end
    if key=='type' then
    elseif key=='text' then if node.type~='file' or type(value)~='string' then return false end
    elseif key=='ctime' or key=='mtime' or key=='atime' then
      if not integer(value,0,9007199254740991) then return false end
    else return false end
  end
  return node.type~='file' or type(node.text)=='string'
end
-- This price is reserved BEFORE even the bounded envelope traversal. Immutable
-- strings are retained by reference, not copied/scanned here. Byte work follows.
function M.envelope_cost() return 64*(FS.max_nodes+1) end
function M.capture(source)
  if source==nil then source={fs={['/']={type='dir'}}} end
  if not plain(source) or not plain(source.fs) then return nil,'invalid import envelope' end
  local fields=0
  for key,value in pairs(source) do
    fields=fields+1
    if fields>5 then return nil,'invalid import envelope fields' end
    if key=='fs' then
    elseif key=='cwd' then if type(value)~='string' or #value>1024 then return nil,'invalid import cwd' end
    elseif key=='nodes' then if not integer(value,0,FS.max_nodes) then return nil,'invalid import node count' end
    elseif key=='bytes' then if not integer(value,0,FS.max_bytes) then return nil,'invalid import byte count' end
    elseif key=='paths' then
      -- Optional committed metadata is checked, not trusted as traversal order.
      if not plain(value) then return nil,'invalid import path metadata' end
      local count=0
      for index,path in pairs(value) do
        count=count+1
        if count>FS.max_nodes or not integer(index,1,FS.max_nodes) or type(path)~='string' or #path>1024 then return nil,'invalid import path metadata' end
      end
    else return nil,'out-of-contract import payload' end
  end
  local job={version=M.VERSION,kind='import',phase='nodes',cursor=1,count=0,source={},nodes={},bytes=0,metadata=0}
  for path,node in pairs(source.fs) do
    job.count=job.count+1
    if job.count>FS.max_nodes or type(path)~='string' or #path>1024 or not node_valid(node) then return nil,'invalid import node envelope' end
    job.metadata=job.metadata+#path
    job.bytes=job.bytes+(node.type=='file' and #node.text or 0)
    if job.metadata>M.max_metadata or job.bytes>FS.max_bytes then return nil,'import quota exceeded' end
    local copy={}
    for key,value in pairs(node) do copy[key]=value end
    job.source[job.count]={path=path,node=copy,canonical=false,parent_validated=false}
  end
  if job.count==0 then return nil,'missing import root' end
  return job
end
function M.valid(job)
  if not plain(job) or job.kind~='import' or job.version~=M.VERSION then return false end
  local allowed={version=true,kind=true,phase=true,cursor=true,count=true,source=true,nodes=true,bytes=true,metadata=true}
  local fields=0
  for key in pairs(job) do fields=fields+1; if fields>9 or not allowed[key] then return false end end
  return (job.phase=='nodes' or job.phase=='parents') and integer(job.count,1,FS.max_nodes)
    and integer(job.cursor,1,job.count) and plain(job.source) and #job.source==job.count and plain(job.nodes)
    and integer(job.bytes,0,FS.max_bytes) and integer(job.metadata,0,M.max_metadata)
end
function M.work()
  -- Two slices can run when node validation ends and parent validation begins.
  -- The full cheap envelope/quota audit uses table units, not file byte units.
  return {execution=1+16*M.batch,table=2*M.envelope_cost()+64*M.batch,
    filesystem=32*M.batch*1024+128,string=16*M.batch*1024+128}
end
local function audit_source(job)
  local count,bytes,metadata=0,0,0
  for key,record in pairs(job.source) do
    count=count+1
    if count>FS.max_nodes or not integer(key,1,job.count) or not plain(record)
      or type(record.path)~='string' or #record.path>1024 or not node_valid(record.node) then return false end
    local fields=0
    for field in pairs(record) do
      fields=fields+1
      if fields>4 or (field~='path' and field~='node' and field~='canonical' and field~='parent_validated') then return false end
    end
    if type(record.canonical)~='boolean' or type(record.parent_validated)~='boolean' then return false end
    if job.phase=='nodes' then
      if record.canonical~=(key<job.cursor) or record.parent_validated then return false end
    elseif not record.canonical or record.parent_validated~=(key<job.cursor) then return false end
    bytes=bytes+(record.node.type=='file' and #record.node.text or 0); metadata=metadata+#record.path
    if bytes>FS.max_bytes or metadata>M.max_metadata then return false end
  end
  return count==job.count and bytes==job.bytes and metadata==job.metadata
end
local function audit_nodes(job)
  local count,bytes=0,0
  for path,node in pairs(job.nodes) do
    count=count+1
    if count>FS.max_nodes or type(path)~='string' or #path>1024 or not node_valid(node) then return false end
    bytes=bytes+(node.type=='file' and #node.text or 0)
    if bytes>FS.max_bytes then return false end
  end
  return count==job.count and bytes==job.bytes and plain(job.nodes['/']) and job.nodes['/'].type=='dir'
end
function M.advance(job)
  if not M.valid(job) or not audit_source(job) then return nil,'malformed import data' end
  if job.phase=='nodes' then
    local last=math.min(job.count,job.cursor+M.batch-1)
    for i=job.cursor,last do
      local record=job.source[i]
      local ok,path=pcall(FS.path,{cwd='/'},record.path)
      if not ok or path~=record.path then return nil,'noncanonical import path' end
      local node={}; for key,value in pairs(record.node) do node[key]=value end
      job.nodes[path]=node
      record.canonical=true
      job.cursor=i+1
    end
    if job.cursor<=job.count then return false end
    job.phase,job.cursor='parents',1
  end
  if not audit_nodes(job) then return nil,'invalid staged import disk' end
  local last=math.min(job.count,job.cursor+M.batch-1)
  for i=job.cursor,last do
    local path=job.source[i].path
    -- Parent phase repeats canonical validation so malformed retained staging
    -- cannot use this phase to install an unvalidated path.
    local ok,canonical=pcall(FS.path,{cwd='/'},path)
    if not ok or canonical~=path or not job.nodes[path] then return nil,'invalid import path' end
    if path~='/' then
      local parent=path:match('^(.*)/[^/]+$'); if parent=='' then parent='/' end
      local node=job.nodes[parent]
      if not plain(node) or node.type~='dir' then return nil,'missing import parent' end
    end
    job.source[i].parent_validated=true
    job.cursor=i+1
  end
  if job.cursor<=job.count then return false end
  local paths={}
  for i=1,job.count do paths[i]=job.source[i].path end
  return {fs=job.nodes,cwd='/',nodes=job.count,bytes=job.bytes,paths=paths}
end
return M
