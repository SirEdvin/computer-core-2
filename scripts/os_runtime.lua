-- Live terminal OS. Durable execution belongs to the guest VM, not host callbacks.
local U = require("scripts.util")
local FS = require("scripts.filesystem")
local Boot = require("scripts.guest.boot")
local VM = require("scripts.guest.vm")
local Scheduler = require("scripts.guest.scheduler")
local Limits = require("scripts.guest.limits")
local M = {}
function M.files(c) return c.guest and c.guest.disk.fs or c.fs end
local function scheduler()
  storage.terminal_scheduler = storage.terminal_scheduler or Scheduler.new()
  return storage.terminal_scheduler
end
function M.powered(c)
  if c.personal then
    local player = game.get_player(c.player_index)
    local tech = player and player.force.technologies["computer-gauntlet-technology"]
    return player and player.valid and player.character and player.character.valid and tech and tech.researched
  end
  return c.entity and c.entity.valid and (c.entity.electric_buffer_size == nil or c.entity.energy > 0)
end
function M.output(c, text)
  c.os_error = tostring(text):sub(1,4096)
end
local function recover_file(c, path, text)
  local ok = pcall(function()
    if not c.fs['/legacy-recovery'] then FS.mkdir(c,'/legacy-recovery') end
    local name='/legacy-recovery/'..path
    local suffix=0
    while c.fs[name] do suffix=suffix+1; name='/legacy-recovery/'..path..'-'..suffix end
    FS.write(c,name,text)
  end)
  return ok
end
function M.migrate(c)
  if c.terminal_schema == 1 then return end
  c.legacy_files = c.fs -- Original paths/content retained even when recovery cannot fit disk quota.
  local disk={}
  for path,node in pairs(c.fs) do disk[path]={type=node.type,text=node.text} end
  c.fs=disk
  c.cwd='/'
  c.legacy_program = c.process
  c.process=nil -- Never reconstruct or execute legacy callbacks during migration.
  c.legacy_drafts={}
  for player_index, entries in pairs(storage.drafts or {}) do
    for _,draft in pairs(entries) do
      if draft.id==c.id then
        c.legacy_drafts[#c.legacy_drafts+1]={player_index=player_index,path=draft.path,text=draft.draft}
      end
    end
  end
  for player_index,session in pairs(storage.sessions or {}) do
    if session.id==c.id and session.view=='editor' and session.draft~=session.base then
      c.legacy_drafts[#c.legacy_drafts+1]={player_index=player_index,path=session.path,text=session.draft}
    end
  end
  local collision={}
  for path in pairs(disk) do if path=='/rc' or path:sub(1,4)=='/rc/' then collision[#collision+1]=path end end
  table.sort(collision,function(a,b) return #a==#b and a<b or #a<#b end)
  for _,path in ipairs(collision) do disk[path]=nil end
  if #collision>0 then
    pcall(function()
      if not disk['/legacy-recovery'] then FS.mkdir(c,'/legacy-recovery') end
      local target='/legacy-recovery/rc'
      local suffix=0
      while disk[target] do suffix=suffix+1; target='/legacy-recovery/rc-'..suffix end
      for _,path in ipairs(collision) do
        local node=c.legacy_files[path]
        FS.put(c,target..path:sub(4),node.text,node.type)
      end
    end) -- The original archive remains available if quota/path limits refuse recovery.
  end
  -- Startup contents remain inert; the original name is also preserved in the archive.
  for _,path in ipairs({'/startup.lua','/startup','/.start_rc.lua'}) do
    if disk[path] then
      local target='/legacy-'..path:sub(2)
      local n=0
      while disk[target] do n=n+1; target='/legacy-'..n..'-'..path:sub(2) end
      for _,candidate in ipairs(U.keys(disk)) do
        if candidate==path or candidate:sub(1,#path+1)==path..'/' then
          local destination=target..candidate:sub(#path+1)
          if #destination<=1024 and not disk[destination] then disk[destination]=disk[candidate] end
          disk[candidate]=nil -- Original paths/content remain archived if recovery cannot fit.
        end
      end
    end
  end
  for i,draft in ipairs(c.legacy_drafts) do
    if type(draft.text)=='string' then draft.recovered=recover_file(c,'draft-'..i..'.lua',draft.text) end
  end
  c.migration_notice = c.legacy_program~=nil or #c.legacy_drafts>0 or #collision>0
    or c.legacy_files['/startup.lua']~=nil or c.legacy_files['/startup']~=nil or c.legacy_files['/.start_rc.lua']~=nil
  c.terminal_schema=1
end
function M.init()
  scheduler()
  for _,id in ipairs(U.keys(storage.computers)) do M.migrate(storage.computers[id]) end
  -- Legacy viewer records are retained until migration copied their drafts.
  storage.sessions={}
  storage.schema=2
end
function M.on_load()
  -- Intentionally empty: no guest execution, migration or storage writes on_load.
end
function M.built(c) M.migrate(c) end
function M.supports(_) return false end -- Legacy world API extensions are intentionally retired.
function M.stop(c)
  if storage.terminal_scheduler then Scheduler.remove(storage.terminal_scheduler,c.id) end
end
function M.reboot(c)
  M.stop(c)
  if c.guest then c.fs=c.guest.disk.fs end
  c.guest=nil; c.os_error=nil; c.os_stopped=nil
end
function M.shutdown(c)
  M.stop(c)
  c.os_stopped=true
end
function M.event(c,event)
  if not M.powered(c) or not c.guest or c.os_error or c.os_stopped then return false,'Computer is not ready or powered' end
  local ok,accepted,err=pcall(VM.queue,c.guest,event)
  if not ok then return false,tostring(accepted) end
  return accepted,err
end
function M.tick()
  local state=scheduler()
  local booted=false
  for _,id in ipairs(U.keys(storage.computers)) do
    local c=storage.computers[id]
    M.migrate(c)
    if M.powered(c) and not c.os_stopped and not c.os_error then
      if not c.guest and not booted and #state.order<Limits.active_computers then
        booted=true
        local ok,guest=pcall(Boot.new,{fs=c.fs})
        if ok then guest.computer_id=c.id; c.guest=guest; c.fs=guest.disk.fs else c.os_error=tostring(guest):sub(1,4096) end
      end
      if c.guest and not state.machines[id] and #state.order<Limits.active_computers then Scheduler.add(state,id,c.guest) end
    else Scheduler.remove(state,id) end
  end
  local ok,err=pcall(Scheduler.tick,state,game.tick)
  if not ok then
    local index=state.cursor-1
    if index<1 then index=#state.order end
    local c=storage.computers[state.order[index]]
    if c then c.os_error='OS halted: '..tostring(err):sub(1,4000); M.stop(c)
    else storage.terminal_scheduler_error=tostring(err):sub(1,4096) end
  end
  for _,id in ipairs(U.keys(state.machines)) do
    local c=storage.computers[id]
    local vm=state.machines[id]
    c.fs=vm.disk.fs -- Guest tree operations may publish a replacement disk table.
    local main=vm.objects[vm.main.ref]
    if vm.host_request=='shutdown' then c.os_stopped=true
    elseif vm.host_request=='reboot' then M.reboot(c)
    elseif main.status=='dead' then
      c.os_stopped=true
      if main.failed then c.os_error=tostring(main.error):sub(1,4096) end
    end
  end
  -- Do not retain completed machines in the active scheduler forever.
  for _,id in ipairs(U.keys(state.machines)) do
    if storage.computers[id].os_stopped then Scheduler.remove(state,id) end
  end
end
return M
