-- Read-only backend selection/readback. No execution, migration or VM fallback.
local Shell=require('scripts.shell.runtime')
local M={}
local function plain(value) return type(value)=='table' and getmetatable(value)==nil end
function M.kind(c)
  if not plain(c) then return nil,'Invalid computer record' end
  if c.backend==nil or c.backend=='vm' then return 'vm' end
  if c.backend==Shell.BACKEND and not c.personal then return Shell.BACKEND end
  return nil,'Unsupported computer backend; retained data requires recovery'
end
local function session(c)
  local kind,err=M.kind(c)
  if kind~=Shell.BACKEND then return nil,err end
  if c.shell==nil then return nil,'Shell is not initialized' end
  if not Shell.compatible(c.shell) then return nil,'Incompatible event-shell state; retained data requires recovery' end
  return c.shell
end
function M.files(c)
  local kind,err=M.kind(c)
  if not kind then return nil,err end
  if kind=='vm' then return c.guest and c.guest.disk.fs or c.fs end
  local state; state,err=session(c)
  if not state then return nil,err end
  local disk; disk,err=Shell.committed_disk(state)
  if not disk then return nil,err end
  return disk.fs
end
function M.display(c)
  local kind,err=M.kind(c)
  if not kind then return nil,err end
  if kind=='vm' then return c.guest and c.guest.display end
  local state; state,err=session(c)
  return state and state.display or nil,err
end
function M.status(c)
  local kind,err=M.kind(c)
  if not kind then return 'recovery',err end
  if c.os_error then return 'recovery',c.os_error end
  if kind=='vm' then
    if c.os_stopped then return 'stopped' end
    return c.guest and 'ready' or 'boot'
  end
  local state; state,err=session(c)
  if not state then return c.shell==nil and 'initializing' or 'recovery',err end
  return state.status,state.recovery and state.recovery.message
end
function M.running(c)
  local kind=M.kind(c)
  if kind=='vm' then return c.guest~=nil and not c.os_stopped and not c.os_error end
  local status=M.status(c)
  return status=='ready' or status=='boot' or status=='initializing'
end
return M
