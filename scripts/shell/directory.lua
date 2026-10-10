-- Bounded directory scan and merge-sort jobs shared by ls and Tab completion.
local FS=require('__computer_core_2__.scripts.filesystem')
local Parser=require('__computer_core_2__.scripts.shell.parser')
local Resources=require('__computer_core_2__.scripts.shell.resources')
local M={VERSION=1,batch=8,sort_batch=64,max_entries=FS.max_nodes+2}
function M.readonly(path) return path=='/rom' or path:sub(1,5)=='/rom/' end
function M.get(disk,path) return Resources[path] or disk.fs[path] end
local function keys(disk)
  local out={}
  for path in pairs(disk.fs) do
    assert(#out<FS.max_nodes,'directory inventory limit')
    if not M.readonly(path) then out[#out+1]=path end
  end
  out[#out+1]='/rom'; out[#out+1]='/rom/help.txt'
  return out -- Captured once during paid admission, not a saved hash cursor.
end
function M.new(state,kind,argument,names)
  local job={version=1,kind=kind,phase='scan',cursor=1,items={},paths={},base='/',prefix='',
    width=1,start=1,i=0,j=0,k=0,middle=0,last=0,buffer={}}
  if kind=='listing' then
    job.base=FS.path(state.disk,argument or state.disk.cwd)
    local node=M.get(state.disk,job.base)
    assert(node and node.type=='dir','not a directory')
    job.paths=keys(state.disk)
  else
    job.line,job.input_cursor=state.command,state.cursor
    local left=state.command:sub(1,state.cursor)
    local tokens,err=Parser.tokens(left,true); assert(tokens,err)
    local token=tokens[#tokens]
    job.token_start,job.quote=token.first,token.quote
    local prefix=token.text
    assert(#prefix<=1024,'completion token exceeds path byte limit')
    job.command_mode=#tokens==1
    if job.command_mode then job.paths=names; job.prefix=prefix
    else
      local slash=prefix:match('^.*()/')
      local directory=slash and prefix:sub(1,slash) or ''
      job.prefix=slash and prefix:sub(slash+1) or prefix
      job.base=FS.path(state.disk,directory~='' and directory or state.disk.cwd)
      local node=M.get(state.disk,job.base)
      assert(node and node.type=='dir','not a directory')
      job.directory_prefix=directory
      job.paths=keys(state.disk)
    end
  end
  return job
end
local function plain(t) return type(t)=='table' and getmetatable(t)==nil end
local function integer(n,a,b) return type(n)=='number' and n==math.floor(n) and n>=a and n<=b end
function M.valid(job)
  if not plain(job) or job.version~=M.VERSION or (job.kind~='listing' and job.kind~='completion') then return false end
  local allowed={version=true,kind=true,phase=true,cursor=true,items=true,paths=true,base=true,prefix=true,
    width=true,start=true,i=true,j=true,k=true,middle=true,last=true,buffer=true,line=true,input_cursor=true,
    token_start=true,quote=true,command_mode=true,directory_prefix=true,text=true,output_index=true}
  local count=0
  for key in pairs(job) do count=count+1; if count>25 or not allowed[key] then return false end end
  if not (job.phase=='scan' or job.phase=='sort' or job.phase=='finish' or job.phase=='output') then return false end
  if not plain(job.paths) or #job.paths>M.max_entries or not plain(job.items) or #job.items>M.max_entries or not plain(job.buffer) then return false end
  if type(job.base)~='string' or #job.base>1024 or type(job.prefix)~='string' or #job.prefix>1024 then return false end
  if job.command_mode~=nil and type(job.command_mode)~='boolean'
    or job.directory_prefix~=nil and (type(job.directory_prefix)~='string' or #job.directory_prefix>1024)
    or job.quote~=nil and job.quote~='"' and job.quote~="'"
    or job.text~=nil and (type(job.text)~='string' or #job.text>4098)
    or job.line~=nil and (type(job.line)~='string' or #job.line>Parser.max_bytes) then return false end
  for _,field in ipairs({'cursor','width','start','i','j','k','middle','last'}) do
    if not integer(job[field],0,2*M.max_entries+2) then return false end
  end
  if job.cursor<1 or job.width<1 or job.start<1 then return false end
  if job.phase=='output' and (job.kind~='listing' or type(job.text)~='string' or #job.text>4098
    or not integer(job.cursor,1,#job.text+1) or not integer(job.output_index,1,#job.items+1)) then return false end
  return job.kind=='listing' or type(job.line)=='string' and #job.line<=Parser.max_bytes
    and integer(job.input_cursor,0,#job.line) and integer(job.token_start,1,job.input_cursor+1)
    and (job.quote==nil or job.quote=='"' or job.quote=="'")
end
function M.work(job)
  local sorting=job and job.phase=='sort'
  return {execution=1+(sorting and 8*M.sort_batch or 16*M.batch),table=128*(M.max_entries+1),
    filesystem=sorting and 0 or 32*M.batch*1024+128,
    string=sorting and 2*M.sort_batch*1025+128 or 16*M.batch*1024+128}
end
local function audit_items(items)
  local count=0
  for index,item in pairs(items) do
    count=count+1
    if count>M.max_entries or not integer(index,1,M.max_entries) or not plain(item)
      or type(item.name)~='string' or #item.name>1025 or type(item.dir)~='boolean' then return false end
    local fields=0
    for key in pairs(item) do fields=fields+1; if fields>2 or (key~='name' and key~='dir') then return false end end
  end
  return true
end
function M.audit(job)
  if not audit_items(job.items) or not audit_items(job.buffer) then return false end
  local count=0
  for index,path in pairs(job.paths) do
    count=count+1
    if count>M.max_entries or not integer(index,1,M.max_entries) or type(path)~='string' or #path>1024 then return false end
  end
  return count==#job.paths
end
function M.advance(state,job)
  assert(M.valid(job),'malformed directory job')
  assert(M.audit(job),'malformed directory records')
  if job.phase=='scan' then
    local prefix=job.base=='/' and '/' or job.base..'/'
    for i=job.cursor,math.min(#job.paths,job.cursor+M.batch-1) do
      local path=job.paths[i]; assert(type(path)=='string' and #path<=1024,'invalid directory path')
      local name,node
      if job.command_mode then name,node=path,{type='file'}
      elseif path:sub(1,#prefix)==prefix then
        local tail=path:sub(#prefix+1)
        if tail~='' and not tail:find('/',1,true) then name,node=tail,M.get(state.disk,path) end
      end
      if name and node and name:sub(1,#job.prefix)==job.prefix then
        assert(#job.items<M.max_entries,'directory result limit')
        job.items[#job.items+1]={name=name..(node.type=='dir' and '/' or ''),dir=node.type=='dir'}
      end
      job.cursor=i+1
    end
    if job.cursor>#job.paths then job.phase='sort' end
    return false
  end
  if job.phase=='sort' then
    local n=#job.items
    for _=1,M.sort_batch do
      if job.width>=n then job.phase='finish'; break end
      if job.i==0 then
        job.middle=math.min(n,job.start+job.width-1)
        job.last=math.min(n,job.start+2*job.width-1)
        job.i,job.j,job.k=job.start,job.middle+1,job.start
      end
      local choose_left=job.j>job.last or job.i<=job.middle and job.items[job.i].name<=job.items[job.j].name
      local entry
      if choose_left then entry=job.items[job.i]; job.i=job.i+1 else entry=job.items[job.j]; job.j=job.j+1 end
      job.buffer[job.k]=entry; job.k=job.k+1
      if job.k>job.last then
        job.start=job.start+2*job.width; job.i=0
        if job.start>n then
          job.items,job.buffer=job.buffer,{}; job.start=1; job.width=job.width*2
        end
      end
    end
    return false
  end
  if job.phase=='finish' then return true end
  return false
end
function M.completion(job)
  if #job.items==0 then return nil end
  local first,last=job.items[1].name,job.items[#job.items].name
  local common=0
  while common<math.min(#first,#last) and first:byte(common+1)==last:byte(common+1) do common=common+1 end
  local name=first:sub(1,common)
  if #job.items==1 then name=first end
  if #name<=#job.prefix then return nil end
  local decoded=(job.directory_prefix or '')..name
  local before=job.line:sub(1,job.token_start-1)
  local after=job.line:sub(job.input_cursor+1)
  local tail={}; local i=1
  while i<=#after do
    local byte=after:sub(i,i)
    if job.quote and byte==job.quote or not job.quote and byte:find('%s') then break end
    if byte=='\\' and i<#after then i=i+1; byte=after:sub(i,i) end
    tail[#tail+1]=byte; i=i+1
  end
  tail=table.concat(tail)
  if #tail>0 then
    local rest=decoded:sub(#(job.directory_prefix or '')+#job.prefix+1)
    if #rest<#tail or rest:sub(-#tail)~=tail then return nil,'completion would change the existing suffix' end
    decoded=decoded:sub(1,#decoded-#tail)
  end
  local replacement=decoded
  if job.quote then
    replacement=job.quote..decoded:gsub('\\','\\\\'):gsub(job.quote,'\\'..job.quote):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')
    if not job.items[1].dir and #job.items==1 and after:sub(1,1)~=job.quote then replacement=replacement..job.quote end
  elseif decoded:find('[%s"\'\\]') then replacement=Parser.quote(decoded) end
  local line=before..replacement..after
  if #line>Parser.max_bytes then return nil,'completion exceeds command byte limit' end
  local cursor=#before+#replacement
  if not job.quote and replacement~=decoded and job.items[1].dir then cursor=cursor-1 end
  return line,cursor
end
return M
