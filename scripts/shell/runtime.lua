-- Trusted bundled shell. No executable value crosses a player/storage boundary.
local Terminal = require('__computer_core_2__.scripts.guest.terminal')
local Filesystem = require('__computer_core_2__.scripts.filesystem')
local Limits = require('__computer_core_2__.scripts.guest.limits')
local Events = require('__computer_core_2__.scripts.guest.events')
local Import = require('__computer_core_2__.scripts.shell.import')
local Parser = require('__computer_core_2__.scripts.shell.parser')
local Directory = require('__computer_core_2__.scripts.shell.directory')
local FileJob = require('__computer_core_2__.scripts.shell.file_job')
local M = {VERSION = 2, BACKEND = 'event-shell', command_bytes = 8192, history_count = 32, history_bytes = 32768, output_chunk = 128}
local command_names={'cat','cd','clear','cp','help','ls','mkdir','mv','pwd','reboot','rm','shutdown'}
local T = Terminal.methods
local handlers, commands = {}, {}
local function integer(n, low, high)
  return type(n)=='number' and n==math.floor(n) and n>=low and n<=high
end
local function plain(t) return type(t)=='table' and getmetatable(t)==nil end
function M.new(disk,columns,rows,admit)
  assert(type(admit)=='function','shell construction requires host work admission')
  if columns==nil then columns=51 end
  if rows==nil then rows=19 end
  assert(integer(columns,1,Terminal.max_columns) and integer(rows,1,Terminal.max_rows),'invalid shell geometry')
  local cost={execution=1,table=Import.envelope_cost()+256,event=64,string=64,
    terminal=512+6*columns*rows+8*rows}
  if not admit(cost) then return nil,'work deferred' end
  local job,err=Import.capture(disk)
  if not job then return nil,err end
  local state={backend=M.BACKEND,version=M.VERSION,status='initializing',disk=nil,
    display=Terminal.new(columns,rows),command='',cursor=0,history={},history_index=1,job=job,
    events=Events.new(),instructions=cost.execution}
  T.write(state.display,('Initializing...'):sub(1,columns))
  return state
end
function M.committed_disk(state)
  if state.disk then return state.disk end
  return nil,'initializing: disk not ready'
end
local function prompt(state)
  local d=state.display
  local full=state.disk.cwd..'> '..state.command
  local cursor=#state.disk.cwd+2+state.cursor
  local first=math.max(1,cursor-d.columns+2)
  T.setCursorPos(d,1,d.rows)
  T.clearLine(d)
  T.write(d,full:sub(first,first+d.columns-1))
  T.setCursorPos(d,math.min(d.columns,cursor-first+2),d.rows)
  T.setCursorBlink(d,state.status=='ready' and not state.job)
end
local function prompt_work(state)
  local d=state.display
  return 4+Terminal.work(d,'clearLine',{})+Terminal.work(d,'write',{string.rep(' ',d.columns)})
end
local function output(state,text,kind)
  kind=kind or 'output'
  assert(type(text)=='string' and #text<=(kind=='cat' and Filesystem.max_bytes or Limits.string_bytes),'shell output limit')
  state.job={version=1,kind=kind,text=text,cursor=1}
  T.setCursorBlink(state.display,false)
end
commands.pwd=function(state,args)
  output(state,args=='' and state.disk.cwd..'\n' or 'pwd: no arguments accepted\n')
end
commands.help=function(state,args)
  output(state,args=='' and 'Built-ins: help, pwd, cd PATH, ls [PATH], cat PATH, mkdir PATH, cp SRC DST, mv SRC DST, rm PATH, clear, reboot, shutdown. No overwrite. rm is recursive; root/current-dir ancestors and /rom are protected. Quote/escape paths. Tab completes. Files are data: no scripts, modules, editors, pipes or substitutions.\n'
    or 'help: no arguments accepted\n')
end
local function path_argument(args)
  local values,err=Parser.arguments(args,1); assert(values,err)
  assert(values[1]~='','path argument required')
  return values[1]
end
commands.cd=function(state,args)
  local path=Filesystem.path(state.disk,path_argument(args))
  local node=Directory.get(state.disk,path)
  assert(node and node.type=='dir','not a local directory')
  state.disk.cwd=path
end
commands.cat=function(state,args)
  local node=Directory.get(state.disk,Filesystem.path(state.disk,path_argument(args)))
  assert(node and node.type=='file','not a local file')
  output(state,node.text,'cat') -- An immutable data snapshot, never loaded as Lua.
end
commands.clear=function(state,args)
  assert(args=='','clear: no arguments accepted')
  T.clear(state.display)
end
commands.ls=function(state,args)
  state.job=Directory.new(state,'listing',args~='' and path_argument(args) or nil)
  T.setCursorBlink(state.display,false)
end
for _,operation in ipairs({'mkdir','cp','mv','rm'}) do
  local op=operation
  commands[op]=function(state,args)
    local values,err=Parser.arguments(args,(op=='cp' or op=='mv') and 2 or 1); assert(values,err)
    state.job=FileJob.new(state,op,values); T.setCursorBlink(state.display,false)
  end
end
local function reset_session(state,status)
  local tick=state.events.tick
  state.events=Events.new(); state.events.tick=tick
  state.job=nil; state.command,state.cursor='',0; state.history={}; state.history_index=1
  state.history_draft,state.history_draft_cursor=nil,nil; state.error=nil; state.status=status
  T.clear(state.display); T.setCursorPos(state.display,1,1); T.setCursorBlink(state.display,false)
end
commands.reboot=function(state,args)
  assert(args=='','reboot: no arguments accepted')
  reset_session(state,'boot'); T.write(state.display,('Rebooting...'):sub(1,state.display.columns))
end
commands.shutdown=function(state,args)
  assert(args=='','shutdown: no arguments accepted')
  reset_session(state,'stopped'); T.write(state.display,('Stopped'):sub(1,state.display.columns))
end
handlers.reboot=function(state) commands.reboot(state,'') end
handlers.shutdown=function(state) commands.shutdown(state,'') end
local function valid_job(job)
  if job==nil then return true end
  if plain(job) and job.kind=='import' then return Import.valid(job) end
  if plain(job) and (job.kind=='listing' or job.kind=='completion') then return Directory.valid(job) end
  if plain(job) and job.kind=='filesystem' then return FileJob.valid(job) end
  if not plain(job) then return false end
  local count=0
  for key in pairs(job) do
    count=count+1
    if count>4 or (key~='version' and key~='kind' and key~='text' and key~='cursor') then return false end
  end
  return job.version==1 and (job.kind=='output' or job.kind=='cat') and type(job.text)=='string'
    and #job.text<=(job.kind=='cat' and Filesystem.max_bytes or Limits.string_bytes)
    and integer(job.cursor,1,#job.text+1)
end
local function history_size(history)
  if not plain(history) then return nil end
  local count,bytes=0,0
  for index,line in pairs(history) do
    count=count+1
    if count>M.history_count or not integer(index,1,M.history_count) or type(line)~='string' or #line>M.command_bytes then return nil end
    bytes=bytes+#line
    if bytes>M.history_bytes then return nil end
  end
  if count~=#history then return nil end
  return bytes
end
local function valid_state(state)
  return plain(state) and state.backend==M.BACKEND and (state.version==M.VERSION or state.version==1 and state.status~='initializing')
    and (state.status=='initializing' or state.status=='boot' or state.status=='ready' or state.status=='stopped' or state.status=='recovery')
    and ((state.status=='initializing' or state.status=='recovery') and Import.valid(state.job)
      or plain(state.disk) and plain(state.disk.fs) and type(state.disk.cwd)=='string' and #state.disk.cwd<=1024)
    and plain(state.display) and state.display.version==1
    and integer(state.display.columns,1,Terminal.max_columns) and integer(state.display.rows,1,Terminal.max_rows)
    and type(state.command)=='string' and #state.command<=M.command_bytes and integer(state.cursor,0,#state.command)
    and history_size(state.history)~=nil and valid_job(state.job)
    and (not state.job or state.job.kind~='import' or state.status=='initializing' or state.status=='recovery')
    and integer(state.history_index,1,#state.history+1)
    and (state.history_draft==nil or type(state.history_draft)=='string' and #state.history_draft<=M.command_bytes
      and integer(state.history_draft_cursor,0,#state.history_draft))
    and integer(state.instructions,0,9007199254740991)
    and plain(state.events) and state.events.version==1 and plain(state.events.queue) and #state.events.queue<=Limits.events
    and integer(state.events.bytes,0,Limits.event_bytes) and plain(state.events.timers)
    and integer(state.events.timer_count,0,Limits.timers) and integer(state.events.tick,0,9007199254740991)
end
local function event_valid(event)
  if not plain(event) or not integer(event.n,1,3) then return false end
  local name=event[1]
  if not handlers[name] then return false end
  if name=='char' or name=='paste' then
    return event.n==2 and type(event[2])=='string' and #event[2]<=M.command_bytes and not event[2]:find('%z')
  elseif name=='key' then
    return (event.n==2 or event.n==3 and type(event[3])=='boolean') and integer(event[2],0,512)
  elseif name=='term_resize' then
    return event.n==3 and integer(event[2],1,Terminal.max_columns) and integer(event[3],1,Terminal.max_rows)
  elseif name=='timer' then return event.n==2 and integer(event[2],1,9007199254740991)
  end
  return event.n==1
end
local function halt(state,reason,admit)
  if not admit({execution=1}) then return false,'work deferred' end
  state.recovery={message=reason,previous_status=state.status}
  state.status='recovery'
  return false,reason
end
handlers.boot=function(state)
  if state.status=='initializing' then
    local disk,err=Import.advance(state.job)
    if disk==false then return end
    if not disk then
      state.recovery={message=err,previous_status=state.status}
      state.status='recovery'
      return
    end
    state.disk=disk; state.job=nil; state.status='boot'
  end
  if state.status~='boot' then return end
  T.clear(state.display)
  state.status='ready'
  prompt(state)
end
local function insert(state,text)
  if state.status~='ready' or state.job then return end
  if #text>M.command_bytes-#state.command then state.error='command byte limit exceeded'; return end
  state.command=state.command:sub(1,state.cursor)..text..state.command:sub(state.cursor+1)
  state.cursor=state.cursor+#text
  state.error=nil
  prompt(state)
end
handlers.char=function(state,event) insert(state,event[2]) end
handlers.paste=function(state,event) insert(state,event[2]:gsub('\r\n',' '):gsub('[\r\n]',' ')) end
local function command_parts(text)
  local first,last=1,#text
  local function space(i) local b=text:byte(i); return b==32 or b and b>=9 and b<=13 end
  while first<=last and space(first) do first=first+1 end
  while last>=first and space(last) do last=last-1 end
  if first>last then return nil,'',true end
  local finish=first
  while finish<=last and not space(finish) do finish=finish+1 end
  local name=text:sub(first,finish-1)
  if not name:match('^[%w_-]+$') then return nil,'',false end
  while finish<=last and space(finish) do finish=finish+1 end
  return name,text:sub(finish,last),false
end
handlers.key=function(state,event)
  if state.status~='ready' or state.job then return end
  local key=event[2]
  if key==257 then
    local command=state.command
    state.command,state.cursor='',0
    if command~='' then
      local bytes=history_size(state.history)
      while #state.history>=M.history_count or bytes+#command>M.history_bytes do
        bytes=bytes-#state.history[1]; table.remove(state.history,1)
      end
      state.history[#state.history+1]=command
      state.history_index=#state.history+1
    end
    state.history_draft,state.history_draft_cursor=nil,nil
    local name,args,empty=command_parts(command)
    if empty then prompt(state); return end
    T.scroll(state.display,1)
    T.setCursorPos(state.display,1,state.display.rows)
    local fn=name and commands[name]
    if fn then
      local ok,err=pcall(fn,state,args)
      if not ok then output(state,tostring(err):sub(1,M.command_bytes)..'\n') end
    else output(state,'unsupported command; built-ins only\n') end
  elseif key==258 then
    local ok,job=pcall(Directory.new,state,'completion',nil,command_names)
    if ok then state.job=job; T.setCursorBlink(state.display,false) else state.error=tostring(job):sub(1,1024) end
  elseif key==263 then state.cursor=math.max(0,state.cursor-1)
  elseif key==262 then state.cursor=math.min(#state.command,state.cursor+1)
  elseif key==268 then state.cursor=0
  elseif key==269 then state.cursor=#state.command
  elseif key==265 and state.history_index>1 then
    if state.history_index==#state.history+1 then
      state.history_draft,state.history_draft_cursor=state.command,state.cursor
    end
    state.history_index=state.history_index-1
    state.command=state.history[state.history_index]; state.cursor=#state.command
  elseif key==264 and state.history_index<=#state.history then
    state.history_index=state.history_index+1
    if state.history_index==#state.history+1 then
      state.command=state.history_draft or ''
      state.cursor=state.history_draft_cursor or #state.command
    else state.command=state.history[state.history_index]; state.cursor=#state.command end
  elseif key==259 and state.cursor>0 then
    state.command=state.command:sub(1,state.cursor-1)..state.command:sub(state.cursor+1)
    state.cursor=state.cursor-1
  elseif key==261 then state.command=state.command:sub(1,state.cursor)..state.command:sub(state.cursor+2)
  end
  if not state.job and state.status=='ready' then prompt(state) end
end
-- Preview only the fixed 128-byte window, counting actual writes and scrolls.
local function output_work(state)
  local job,d=state.job,state.display
  local count,cost,x=0,prompt_work(state)+Terminal.work(d,'scroll',{})+1,d.x
  for i=job.cursor,math.min(#job.text,job.cursor+M.output_chunk-1) do
    local byte=job.text:sub(i,i)
    local work=0
    if byte=='\n' then work=Terminal.work(d,'scroll',{})+1; x=1
    else
      work=Terminal.work(d,'write',{byte}); x=x+1
      if x>d.columns then work=work+Terminal.work(d,'scroll',{})+1; x=1 end
    end
    if cost+work>Limits.terminal_work_per_computer then break end
    count,cost=count+1,cost+work
  end
  return count,cost
end
handlers.advance=function(state)
  local job=state.job
  if not job or state.status~='ready' then return end
  if job.kind=='filesystem' then
    local ok,disk=pcall(FileJob.advance,job)
    if not ok then output(state,tostring(disk):sub(1,1024)..'\n'); return end
    if disk then state.disk=disk; state.job=nil; prompt(state) end
    return
  end
  if job.kind=='listing' or job.kind=='completion' then assert(Directory.audit(job),'malformed directory records') end
  if (job.kind=='listing' or job.kind=='completion') and job.phase~='output' then
    if not Directory.advance(state,job) then return end
    if job.kind=='completion' then
      local line,cursor=Directory.completion(job)
      if line then state.command,state.cursor=line,cursor; state.job=nil; prompt(state); return end
      if cursor then state.error=cursor end
      if #job.items==0 then state.job=nil; prompt(state); return end
      T.scroll(state.display,1); T.setCursorPos(state.display,1,state.display.rows)
      job.kind='listing' -- Ambiguous candidates are all rendered in sorted chunks.
    end
    job.phase,job.output_index,job.cursor='output',1,1
    job.text=job.items[1] and Parser.quote(job.items[1].name)..'\n' or ''
    return
  end
  local count=output_work(state)
  local last=job.cursor+count-1
  for i=job.cursor,last do
    local byte=job.text:sub(i,i)
    if byte=='\n' then T.scroll(state.display,1); T.setCursorPos(state.display,1,state.display.rows)
    else
      T.write(state.display,byte)
      if state.display.x>state.display.columns then T.scroll(state.display,1); T.setCursorPos(state.display,1,state.display.rows) end
    end
  end
  job.cursor=last+1
  if job.cursor>#job.text then
    if job.kind=='listing' and job.output_index<#job.items then
      job.output_index=job.output_index+1; job.cursor=1
      job.text=Parser.quote(job.items[job.output_index].name)..'\n'
      return
    end
    if #job.text>0 and job.text:sub(-1)~='\n' and state.display.x~=1 then T.scroll(state.display,1) end
    state.job=nil; prompt(state)
  end
end
handlers.terminate=function(state)
  if state.status=='initializing' then
    state.recovery={message='initialization interrupted',previous_status=state.status}
    state.status='recovery'; return
  end
  state.job=nil
  state.command,state.cursor='',0
  if state.status=='ready' then prompt(state) end
end
handlers.timer=function() end -- Timers belong to the single shell session.
handlers.term_resize=function(state,event)
  Terminal.reconcile(state.display,event[2],event[3])
  if state.job then
    T.setCursorPos(state.display,math.max(1,math.min(state.display.x,state.display.columns)),state.display.rows)
  else prompt(state) end
end
function M.handle(state,event,admit)
  assert(type(admit)=='function','shell requires host work admission')
  if not plain(state) then return false,'invalid shell state' end
  if not valid_state(state) then return halt(state,'incompatible or malformed event-shell state',admit) end
  if state.status=='recovery' then return false,'shell requires recovery' end
  if not event_valid(event) then return false,'unsupported or malformed shell event' end
  if state.status=='initializing' and (event[1]=='char' or event[1]=='paste' or event[1]=='key') then return false,'initializing' end
  if state.status=='stopped' and (event[1]=='char' or event[1]=='paste' or event[1]=='key') then return false,'stopped' end
  if state.job and (event[1]=='char' or event[1]=='paste' or event[1]=='key') then return false,'shell busy' end
  local name=event[1]
  local d=state.display
  local cwd=state.disk and state.disk.cwd or '/'
  local cost={execution=1,event=1+4*event.n,string=1+4*(#state.command+#cwd),terminal=prompt_work(state)}
  if name=='boot' and state.status=='initializing' then
    for domain,amount in pairs(Import.work()) do cost[domain]=(cost[domain] or 0)+amount end
  end
  if type(event[2])=='string' then cost.string=cost.string+4*#event[2]; cost.event=cost.event+#event[2] end
  if name=='boot' then cost.terminal=cost.terminal+Terminal.work(d,'clear',{}) end
  if name=='reboot' or name=='shutdown' then
    if not state.disk then return false,'initializing: disk not ready' end
    cost.table=256*(Filesystem.max_nodes+3)
    cost.terminal=cost.terminal+Terminal.work(d,'clear',{})+Terminal.work(d,'write',{string.rep(' ',16)})
  end
  if name=='key' then
    cost.string=cost.string+M.history_bytes
    cost.table=64+4*#state.command
    cost.terminal=cost.terminal+Terminal.work(d,'scroll',{})+1
    if event[2]==257 then
      cost.filesystem=1+16*(#state.command+#state.disk.cwd+1)
      cost.terminal=cost.terminal+Terminal.work(d,'clear',{})
    end
    if event[2]==257 or event[2]==258 then
      cost.table=cost.table+128*(Directory.max_entries+1)
      cost.filesystem=(cost.filesystem or 0)+16*(#state.command+#state.disk.cwd+1)
    end
  end
  if name=='advance' and state.job then
    if state.job.kind=='filesystem' then
      for domain,amount in pairs(FileJob.work(state.job)) do cost[domain]=(cost[domain] or 0)+amount end
    elseif (state.job.kind=='listing' or state.job.kind=='completion') and state.job.phase~='output' then
      for domain,amount in pairs(Directory.work(state.job)) do cost[domain]=(cost[domain] or 0)+amount end
      if state.job.phase=='finish' then cost.string=cost.string+8*#state.command end
    else
      local count,terminal=output_work(state)
      cost.execution=cost.execution+count
      cost.string=cost.string+2*count
      cost.terminal=terminal
      if state.job.kind=='listing' then cost.string=cost.string+32768; cost.table=128*(Directory.max_entries+1) end
    end
  elseif name=='term_resize' then
    cost.terminal=cost.terminal+1+6*event[2]*event[3]+6*d.columns*d.rows+2*event[3]
      +4+1+3*event[2]+1+11*event[2]
  end
  if not admit(cost) then return false,'work deferred' end
  if name=='advance' and state.job and state.job.kind=='filesystem' and not FileJob.audit(state.job) then
    state.recovery={message='Malformed retained filesystem data',previous_status=state.status}
    state.status='recovery'; state.instructions=state.instructions+cost.execution
    return false,state.recovery.message
  end
  local ok,err=pcall(handlers[name],state,event)
  if not ok then
    state.recovery={message=tostring(err):sub(1,1024),previous_status=state.status}
    state.status='recovery'
  end
  state.instructions=state.instructions+cost.execution
  return true
end
M.valid_event=event_valid -- Host-only ingress validation, not an executable input API.
M.compatible=valid_state
return M
