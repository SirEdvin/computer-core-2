-- Trusted native editor. Only plain document/session data is durable.
local FS=require('__computer_core_2__.scripts.filesystem')
local Directory=require('__computer_core_2__.scripts.shell.directory')
local FileJob=require('__computer_core_2__.scripts.shell.file_job')
local Import=require('__computer_core_2__.scripts.shell.import')
local Terminal=require('__computer_core_2__.scripts.guest.terminal')
local T=Terminal.methods
local M={VERSION=1,bytes=32768,save_key=501,quit_key=502}
local function plain(t) return type(t)=='table' and getmetatable(t)==nil end
local function integer(n,a,b) return type(n)=='number' and n==math.floor(n) and n>=a and n<=b end
local fields={version=true,path=true,text=true,base=true,cursor=true,top=true,left=true,dirty=true,saving=true,
  confirm=true,disposition=true,message=true,wanted=true}
local dispositions={exit=true,terminate=true,reboot=true,shutdown=true}
function M.valid(e)
  if not plain(e) then return false end
  local count=0
  for key in pairs(e) do count=count+1; if count>13 or not fields[key] then return false end end
  return e.version==M.VERSION and type(e.path)=='string' and #e.path<=1024
    and type(e.text)=='string' and #e.text<=M.bytes
    and (e.base==false or type(e.base)=='string' and #e.base<=M.bytes)
    and integer(e.cursor,0,#e.text) and integer(e.top,1,M.bytes+1) and integer(e.left,0,M.bytes)
    and type(e.dirty)=='boolean' and type(e.saving)=='boolean' and type(e.confirm)=='boolean'
    and (e.disposition==nil or dispositions[e.disposition])
    and (e.message==nil or type(e.message)=='string' and #e.message<=256)
    and (e.wanted==nil or integer(e.wanted,0,M.bytes))
end
function M.work(d,render)
  return {execution=64,table=8*(M.bytes+1)+(render and 0 or Import.envelope_cost()+256),
    string=render and M.bytes+d.columns*d.rows+2560 or 6*M.bytes+2048,
    filesystem=render and 1 or 65536,terminal=15*d.columns*d.rows+512}
end
local function lines(e)
  local starts={0}; local at=1
  while true do
    local found=e.text:find('\n',at,true)
    if not found then return starts end
    starts[#starts+1]=found; at=found+1
  end
end
local function position(e,starts)
  local row=1
  for i=2,#starts do if starts[i]>e.cursor then break end; row=i end
  return row,e.cursor-starts[row]
end
local function finish(e,starts,row) return (starts[row+1] or #e.text+1)-1 end
function M.render(state)
  local e,d=state.editor,state.display
  local starts=lines(e); local row,col=position(e,starts)
  local height=math.max(1,d.rows-2)
  e.top=math.max(1,math.min(e.top,row))
  if row>=e.top+height then e.top=row-height+1 end
  e.left=math.min(e.left,col)
  if col>=e.left+d.columns then e.left=col-d.columns+1 end
  T.clear(d)
  T.setCursorPos(d,1,1)
  T.write(d,('edit '..e.path..(e.dirty and ' *' or '')..(e.saving and ' [saving]' or '')):sub(1,d.columns))
  for y=2,d.rows-1 do
    local index=e.top+y-2
    if starts[index] then
      local first=starts[index]+1+e.left
      T.setCursorPos(d,1,y)
      T.write(d,e.text:sub(first,math.min(finish(e,starts,index),first+d.columns-1)))
    end
  end
  if d.rows>1 then
    T.setCursorPos(d,1,d.rows)
    local message=e.confirm and ('Unsaved '..(e.disposition or 'exit')..': s save / d discard / c cancel')
      or e.message or 'Save / Exit editor: buttons above terminal'
    T.write(d,message:sub(1,d.columns))
  end
  T.setCursorPos(d,col-e.left+1,math.max(1,math.min(d.rows-1,row-e.top+2)))
  T.setCursorBlink(d,d.rows>=3 and not e.confirm and not e.saving)
end
function M.open(state,path)
  path=FS.path(state.disk,path)
  assert(path~='/' and not Directory.readonly(path),'edit: protected path')
  local node=state.disk.fs[path]
  assert(not node or node.type=='file','edit: not a local file')
  local parent=path:match('^(.*)/[^/]+$'); if parent=='' then parent='/' end
  assert(state.disk.fs[parent] and state.disk.fs[parent].type=='dir','edit: parent does not exist')
  local text=node and node.text or ''
  assert(type(text)=='string' and #text<=M.bytes,'edit: file exceeds 32 KiB')
  state.editor={version=M.VERSION,path=path,text=text,base=node and text or false,cursor=0,top=1,left=0,
    dirty=not node,saving=false,confirm=false}
  M.render(state)
end
local function replace(e,first,last,text)
  local size=#e.text-(last-first)+#text
  if size>M.bytes then e.message='32 KiB document limit exceeded'; return end
  e.text=e.text:sub(1,first)..text..e.text:sub(last+1)
  e.cursor=first+#text; e.dirty=e.base==false or e.text~=e.base; e.message=nil; e.wanted=nil
end
function M.save(state)
  local e=state.editor
  local ok,job=pcall(FileJob.write,state,e.path,e.text,e.base)
  if not ok then
    e.message=tostring(job):sub(1,256); e.disposition=nil; e.confirm=false; return
  end
  state.job=job; e.saving=true; e.confirm=false; e.message=nil
end
function M.request(state,disposition)
  local e=state.editor
  if e.saving then
    state.job=nil; e.saving=false; e.message='Unpublished save canceled; draft retained'
  end
  e.disposition=disposition
  if e.dirty then e.confirm=true; return nil end
  state.editor=nil; return disposition
end
function M.published(state)
  local e=state.editor
  e.base=e.text; e.dirty=false; e.saving=false; e.message='Saved'; e.confirm=false
  local action=e.disposition; e.disposition=nil
  if action then state.editor=nil; return action end
end
function M.failed(state,message)
  local e=state.editor
  e.saving=false; e.confirm=false; e.disposition=nil; e.message=tostring(message):sub(1,256)
end
function M.handle(state,event)
  local e,name,key=state.editor,event[1],event[2]
  if name=='term_resize' then Terminal.reconcile(state.display,event[2],event[3])
  elseif name=='terminate' or name=='reboot' or name=='shutdown' then
    local action=M.request(state,name); if action then return action end
  elseif e.confirm then
    local choice=(name=='char' or name=='paste') and #key==1 and key:lower() or nil
    if choice=='s' or name=='key' and key==M.save_key then M.save(state)
    elseif choice=='d' then local action=e.disposition; state.editor=nil; return action
    elseif choice=='c' or name=='key' and (key==256 or key==M.quit_key) then
      e.confirm=false; e.disposition=nil; e.message=nil
    end
  elseif name=='char' or name=='paste' then
    replace(e,e.cursor,e.cursor,key:gsub('\r\n','\n'):gsub('\r','\n'))
  elseif name=='key' then
    if key==M.save_key then M.save(state)
    elseif key==M.quit_key then local action=M.request(state,'exit'); if action then return action end
    elseif key==257 then replace(e,e.cursor,e.cursor,'\n')
    elseif key==258 then replace(e,e.cursor,e.cursor,'  ')
    elseif key==259 and e.cursor>0 then replace(e,e.cursor-1,e.cursor,'')
    elseif key==261 then replace(e,e.cursor,math.min(#e.text,e.cursor+1),'')
    elseif key==263 then e.cursor=math.max(0,e.cursor-1); e.wanted=nil
    elseif key==262 then e.cursor=math.min(#e.text,e.cursor+1); e.wanted=nil
    elseif key==268 or key==269 or key==265 or key==264 or key==266 or key==267 then
      local starts=lines(e); local row,col=position(e,starts)
      if key==268 then e.cursor=starts[row]; e.wanted=nil
      elseif key==269 then e.cursor=finish(e,starts,row); e.wanted=nil
      else
        local delta=(key==265 or key==266) and -1 or 1
        if key==266 or key==267 then delta=delta*math.max(1,state.display.rows-2) end
        row=math.max(1,math.min(#starts,row+delta)); e.wanted=e.wanted or col
        e.cursor=math.min(finish(e,starts,row),starts[row]+e.wanted)
      end
    end
  end
  M.render(state)
end
return M
