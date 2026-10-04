local U = require("scripts.util")
local FS = require("scripts.filesystem")
local R = require("scripts.runtime")
local S = require("scripts.shell")
local L = require("scripts.lifecycle")
local M = {}
local function find(root, name)
  if not root or not root.valid then return end
  if root.name == name then return root end
  for _, child in pairs(root.children) do local result = find(child, name); if result then return result end end
end
M.find = find
local function root(player) return player.gui.screen.cc2_root end
local function research(player)
  local tech = player.force.technologies["computer-gauntlet-technology"]
  return tech and tech.researched
end
function M.authorized(player, c)
  if not player or not player.valid or not c or not research(player) or not R.powered(c) then return false end
  if c.personal then return player.index == c.player_index end
  if player.force.index ~= c.force_index or player.surface.index ~= c.surface_index then return false end
  local dx, dy = player.position.x - c.position.x, player.position.y - c.position.y
  return dx * dx + dy * dy <= 100
end
function M.close(player, force)
  local session = storage.sessions[player.index]
  if not force and session and session.view == "editor" and session.draft ~= session.base then
    local frame = root(player)
    if frame then find(frame, "cc2_status").caption = "Unsaved changes. Save, or choose Discard & close." end
    return false
  end
  if session and session.view == "editor" and session.draft ~= session.base then
    storage.drafts[player.index] = storage.drafts[player.index] or {}
    storage.drafts[player.index][session.id .. ":" .. session.path] = {id = session.id, path = session.path, draft = session.draft, base = session.base}
  end
  local frame = root(player)
  storage.sessions[player.index] = nil
  if frame and frame.valid then frame.destroy() end
  return true
end
local function field(parent, name, caption, text)
  parent.add{type = "label", caption = caption}
  return parent.add{type = "textfield", name = name, text = text or "", tooltip = caption}
end
function M.render(player)
  local session = storage.sessions[player.index]
  local c = session and storage.computers[session.id]
  if not c or not M.authorized(player, c) then M.close(player, true); return end
  local old = root(player)
  if old then old.destroy() end
  local frame = player.gui.screen.add{type = "frame", name = "cc2_root", caption = c.personal and "Computer Gauntlet" or ("Computer " .. c.id .. (c.label and " — " .. c.label or "")), direction = "vertical"}
  frame.auto_center = true
  local scale = player.display_scale
  local width = math.max(400, math.min(900, math.floor(player.display_resolution.width / scale) - 80))
  local height = math.max(280, math.min(500, math.floor(player.display_resolution.height / scale) - 240))
  frame.style.maximal_width = width + 32
  local nav = frame.add{type = "flow", name = "cc2_nav", direction = "horizontal"}
  nav.add{type = "button", name = "cc2_console", caption = "Terminal"}
  nav.add{type = "button", name = "cc2_waypoint", caption = "Waypoints"}
  if c.personal and next(storage.drafts[player.index] or {}) then nav.add{type = "button", name = "cc2_recover", caption = "Recover drafts", tooltip = "Copy unsaved drafts from closed/unavailable computers into /recovered on this personal computer."} end
  nav.add{type = "button", name = "cc2_stop", caption = "Stop program", enabled = c.process ~= nil}
  nav.add{type = "button", name = "cc2_close", caption = "Close"}
  if session.view == "editor" then
    frame.add{type = "label", caption = "Editing " .. session.path}
    local editor = frame.add{type = "text-box", name = "cc2_source", text = session.draft or "", tooltip = "Lua source. Persistent programs return named handlers; startup belongs in init."}
    editor.word_wrap = false
    editor.style.width, editor.style.height = width, height
    local bar = frame.add{type = "flow", direction = "horizontal"}
    bar.add{type = "button", name = "cc2_save", caption = "Save"}
    bar.add{type = "button", name = "cc2_save_run", caption = "Save & run", enabled = c.process == nil}
    bar.add{type = "button", name = "cc2_discard", caption = "Discard & close"}
  elseif session.view == "waypoint" then
    local key = c.force_index .. ":" .. c.surface_index
    local points = storage.waypoints[key] or {}
    local names = U.keys(points)
    session.waypoint_names = names
    local body = frame.add{type = "flow", direction = "horizontal"}
    local form = body.add{type = "flow", direction = "vertical"}
    form.add{type = "drop-down", name = "cc2_waypoint_list", items = names, selected_index = 0, tooltip = "Saved waypoints on this surface"}
    local wp = session.waypoint or {name = "", x = player.position.x, y = player.position.y}
    session.waypoint = wp
    field(form, "cc2_wp_name", "Name", wp.name)
    field(form, "cc2_wp_x", "X", tostring(wp.x))
    field(form, "cc2_wp_y", "Y", tostring(wp.y))
    local bar = form.add{type = "flow", direction = "horizontal"}
    bar.add{type = "button", name = "cc2_wp_new", caption = "New"}
    bar.add{type = "button", name = "cc2_wp_save", caption = "Save"}
    bar.add{type = "button", name = "cc2_wp_delete", caption = "Delete", enabled = wp.original ~= nil}
    local camera = body.add{type = "camera", name = "cc2_camera", position = {x = wp.x, y = wp.y}, surface_index = c.surface_index, zoom = 0.5}
    camera.style.width, camera.style.height = math.max(200, width - 300), math.min(height, 350)
  else
    local output = frame.add{type = "text-box", name = "cc2_output", text = c.output, tooltip = "Terminal output"}
    output.read_only, output.word_wrap = true, true
    output.style.width, output.style.height = width, height
    frame.add{type = "label", name = "cc2_prompt", caption = c.cwd .. " >"}
    local bar = frame.add{type = "flow", direction = "horizontal"}
    local command = bar.add{type = "textfield", name = "cc2_command", text = session.command or "", tooltip = "Shell command; press Enter or Execute. Use help to list commands."}
    command.style.width = width - 120
    bar.add{type = "button", name = "cc2_execute", caption = "Execute"}
    field(frame, "cc2_input", "Program input", c.input)
    command.focus()
  end
  frame.add{type = "label", name = "cc2_status", caption = session.notice or (c.process and "Program running" or "Ready")}
  player.opened = frame
end
function M.open(player, c)
  if not M.authorized(player, c) then player.print("Computer unavailable: research the gauntlet, use the same force/surface, approach within 10 tiles and provide power."); return false end
  if storage.sessions[player.index] and not M.close(player) then return false end
  c.operator = player.index
  storage.sessions[player.index] = {id = c.id, view = "console"}
  M.render(player)
  return true
end
function M.gauntlet(player)
  if storage.sessions[player.index] then return M.close(player) end
  if not research(player) or not player.character then player.print("Research Computer Gauntlet and use a character to open the personal computer."); return end
  return M.open(player, L.personal(player))
end
local function navigate(player, session, action)
  if session.view == "editor" and session.draft ~= session.base then session.notice = "Save or discard your changes before leaving the editor."; return end
  if action.view == "editor" then
    local drafts = storage.drafts[player.index] or {}
    local count = 0; for _ in pairs(drafts) do count = count + 1 end
    local saved = drafts[session.id .. ":" .. action.path]
    assert(saved or count < 16, "Recover your saved drafts from the personal gauntlet before opening another editor.")
    session.base = saved and saved.base or FS.read(storage.computers[session.id], action.path)
    session.draft = saved and saved.draft or session.base
  end
  session.view, session.path = action.view, action.path
  session.notice = nil
end
function M.submit(player, session, c)
  local frame = root(player)
  local command = find(frame, "cc2_command")
  if not command then return end
  local line = command.text
  session.command = ""
  R.output(c, c.cwd .. " > " .. line .. "\n")
  local text, action = S.execute(c, line)
  if text and text ~= "" then R.output(c, text .. "\n") end
  if action then
    if action.view == "close" then M.close(player); return end
    navigate(player, session, action)
  end
  M.render(player)
end
function M.save(player, session, c, run)
  local source = find(root(player), "cc2_source").text
  assert(#source <= 262144, "program exceeds source limit")
  assert(FS.read(c, session.path) == session.base, "File changed elsewhere. Your draft is retained; reopen after resolving the conflict.")
  FS.write(c, session.path, source)
  session.base, session.draft = source, source
  local drafts = storage.drafts[player.index]
  if drafts then drafts[session.id .. ":" .. session.path] = nil end
  session.notice = "Saved"
  if run then
    assert(not c.process, "stop the current program first")
    local ok, err = R.start(c, source, session.path)
    assert(ok, err)
    session.view = "console"
  end
  M.render(player)
end
function M.event(event)
  local player = game.get_player(event.player_index)
  local session = player and storage.sessions[player.index]
  local c = session and storage.computers[session.id]
  if not session then return end
  if not M.authorized(player, c) then M.close(player, true); return end
  if not event.element or not event.element.valid then return end
  -- Check element ownership, not just a forgeable element name.
  local ancestor = event.element
  while ancestor and ancestor.valid and ancestor ~= root(player) do ancestor = ancestor.parent end
  if ancestor ~= root(player) then return end
  local name = event.element.name
  local ok, err = pcall(function()
    if event.name == defines.events.on_gui_text_changed then
      if name == "cc2_source" then
        assert(#event.element.text <= 262144, "program exceeds source limit")
        session.draft = event.element.text
      elseif name == "cc2_command" then session.command = event.element.text
      elseif name == "cc2_input" then R.input(c, event.element.text, player.index)
      elseif name == "cc2_wp_name" then session.waypoint.name = event.element.text
      elseif name == "cc2_wp_x" or name == "cc2_wp_y" then
        local value = tonumber(event.element.text)
        if value and value == value and math.abs(value) <= 1000000 then
          session.waypoint[name == "cc2_wp_x" and "x" or "y"] = value
          find(root(player), "cc2_camera").position = {x = session.waypoint.x, y = session.waypoint.y}
        end
      end
    elseif event.name == defines.events.on_gui_confirmed then if name == "cc2_command" then M.submit(player, session, c) end
    elseif event.name == defines.events.on_gui_selection_state_changed and name == "cc2_waypoint_list" then
      local selected = session.waypoint_names[event.element.selected_index]
      local key = c.force_index .. ":" .. c.surface_index
      local wp = storage.waypoints[key] and storage.waypoints[key][selected]
      if wp then session.waypoint = U.data(wp); session.waypoint.original = selected; M.render(player) end
    elseif event.name == defines.events.on_gui_click then
      if name == "cc2_close" then M.close(player)
      elseif name == "cc2_discard" then
        session.draft = session.base
        if storage.drafts[player.index] then storage.drafts[player.index][session.id .. ":" .. session.path] = nil end
        M.close(player, true)
      elseif name == "cc2_recover" and c.personal then
        local drafts = storage.drafts[player.index] or {}
        for _, key in ipairs(U.keys(drafts)) do
          local draft = drafts[key]
          local path = "/recovered/device-" .. draft.id .. draft.path
          local original, number = path, 1
          while FS.exists(c, path) do number = number + 1; path = original .. "." .. number end
          local parent = path:match("^(.*)/[^/]+$")
          local built = ""
          for part in parent:gmatch("[^/]+") do built = built .. "/" .. part; if not FS.exists(c, built) then FS.mkdir(c, built) end end
          FS.write(c, path, draft.draft)
          drafts[key] = nil -- Only discard backup after the write succeeds.
        end
        session.notice = "Drafts recovered under /recovered. Use tree /recovered."
        M.render(player)
      elseif name == "cc2_console" or name == "cc2_waypoint" then navigate(player, session, {view = name == "cc2_console" and "console" or "waypoint"}); M.render(player)
      elseif name == "cc2_execute" then M.submit(player, session, c)
      elseif name == "cc2_save" or name == "cc2_save_run" then M.save(player, session, c, name == "cc2_save_run")
      elseif name == "cc2_stop" then R.stop(c); M.render(player)
      elseif name == "cc2_wp_new" then session.waypoint = nil; M.render(player)
      elseif name == "cc2_wp_save" or name == "cc2_wp_delete" then
        local key = c.force_index .. ":" .. c.surface_index
        local points = storage.waypoints[key] or {}
        storage.waypoints[key] = points
        local wp = session.waypoint
        if name == "cc2_wp_delete" then if wp.original then points[wp.original] = nil end; session.waypoint = nil
        else
          assert(#wp.name > 0 and #wp.name <= 64, "waypoint name must be 1..64 characters")
          wp.x = U.finite(tonumber(find(root(player), "cc2_wp_x").text), "X")
          wp.y = U.finite(tonumber(find(root(player), "cc2_wp_y").text), "Y")
          assert(math.abs(wp.x) <= 1000000 and math.abs(wp.y) <= 1000000, "coordinates out of range")
          assert(not points[wp.name] or wp.name == wp.original, "waypoint name already exists")
          if wp.original then points[wp.original] = nil end
          points[wp.name] = {name = wp.name, x = wp.x, y = wp.y}
          wp.original = wp.name
        end
        M.render(player)
      end
    end
  end)
  if not ok then
    session.notice = tostring(err)
    local frame = root(player); if frame then find(frame, "cc2_status").caption = session.notice end
  end
end
function M.tick()
  for _, index in ipairs(U.keys(storage.sessions)) do
    local player, session = game.get_player(index), storage.sessions[index]
    local c = storage.computers[session.id]
    if not player or not M.authorized(player, c) then if player then M.close(player, true) else storage.sessions[index] = nil end
    else
      local frame = root(player)
      if not frame then M.render(player)
      elseif session.view == "console" then
        local output = find(frame, "cc2_output")
        if output.text ~= c.output then output.text = c.output; output.scroll_to_bottom() end
        find(frame, "cc2_input").text = c.input
        find(frame, "cc2_prompt").caption = c.cwd .. " >"
        find(frame, "cc2_stop").enabled = c.process ~= nil
        find(frame, "cc2_status").caption = session.notice or (c.process and "Program running" or "Ready")
      end
    end
  end
end
function M.closed(event)
  local player = game.get_player(event.player_index)
  if event.element and event.element.valid and event.element.name == "cc2_root" and storage.sessions[player.index] then
    if not M.close(player) then player.opened = event.element end
  end
end
return M
