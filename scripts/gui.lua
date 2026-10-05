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
  if not player or not player.valid or not c or not research(player) then return false end
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
    session.notice = "Unsaved changes. Save, or choose Discard & close."; session.notice_kind = "error"; session.notice_until = game.tick + 600
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
local Layout = require("scripts.gui_layout")
local function feedback(session, text, kind)
  if kind == "error" and not text:match("^Error:") then text = "Error: " .. text end
  Layout.feedback(session, text, kind, game.tick)
end
local function label(parent, text, width, style)
  local element = parent.add{type = "label", caption = text, style = style or "cc2_status"}
  element.style.maximal_width = width
  element.style.single_line = false
  return element
end
local function stretch(element)
  element.style.horizontally_stretchable = true
  return element
end
local function button(parent, name, caption, tooltip, enabled, style)
  return parent.add{type = "button", name = name, caption = caption, tooltip = tooltip, enabled = enabled ~= false, style = style or "button"}
end
local function current_title(c)
  return c.personal and "Personal computer" or ("Computer " .. c.id .. (c.label and " — " .. c.label or ""))
end
function M.refresh(player)
  local session = storage.sessions[player.index]
  local c = session and storage.computers[session.id]
  local frame = root(player)
  if not frame or not c then return end
  find(frame, "cc2_title").caption = current_title(c)
  find(frame, "cc2_process").caption = Layout.status(c, R.powered(c))
  local notice = Layout.notice(session, game.tick)
  local status = find(frame, "cc2_status")
  status.caption = notice or (session.view == "editor" and (session.draft ~= session.base and "Unsaved changes" or "All changes saved") or "Ready")
  status.style.font_color = session.notice_kind == "error" and {1, 0.45, 0.4} or (session.notice_kind == "success" and {0.65, 0.9, 0.55} or {0.85, 0.85, 0.85})
  find(frame, "cc2_stop").enabled = c.process ~= nil
  local run = find(frame, "cc2_save_run")
  if run then run.enabled = c.process == nil and R.powered(c) end
  local source_state = find(frame, "cc2_source_state")
  if source_state then source_state.caption = session.draft ~= session.base and "Modified • " .. #session.draft .. " bytes" or "Saved • " .. #session.draft .. " bytes" end
  local output = find(frame, "cc2_output")
  if output and output.text ~= c.output then output.text = c.output; output.scroll_to_bottom() end
  local prompt = find(frame, "cc2_prompt")
  if prompt then prompt.caption = c.cwd .. " >" end
  local files = find(frame, "cc2_file_list")
  if files then
    for _, child in pairs(files.children) do
      if child.name:match("^cc2_run_%d+$") then child.enabled = c.process == nil and R.powered(c) end
    end
  end
  local send = find(frame, "cc2_send_input")
  if send then send.enabled = c.process ~= nil and R.powered(c) end
  local draft_input = find(frame, "cc2_input")
  -- Do not replace a field while the player is composing program input.
  if draft_input and session.input_draft == nil and draft_input.text ~= c.input then draft_input.text = c.input end
end
function M.render(player)
  local session = storage.sessions[player.index]
  local c = session and storage.computers[session.id]
  if not c or not M.authorized(player, c) then M.close(player, true); return end
  local old = root(player)
  local location = old and old.location
  if old then old.destroy() end
  local d = Layout.dimensions(player.display_resolution, player.display_scale)
  session.dimensions = d
  local width, height = d.content_width, d.content_height
  local frame = player.gui.screen.add{type = "frame", name = "cc2_root", direction = "vertical"}
  frame.style.width, frame.style.height = d.width, d.height
  local title = stretch(frame.add{type = "flow", direction = "horizontal"})
  title.add{type = "label", name = "cc2_title", caption = current_title(c), style = "frame_title", ignored_by_interaction = true}.style.maximal_width = math.max(1, width - 72)
  local drag = stretch(title.add{type = "empty-widget", style = "draggable_space", ignored_by_interaction = true})
  drag.style.height = 24
  title.drag_target, drag.drag_target = frame, frame
  title.add{type = "sprite-button", name = "cc2_close", sprite = "utility/close", style = "frame_action_button", tooltip = "Close (Esc). Unsaved edits are protected."}
  local shell = stretch(frame.add{type = "frame", direction = "vertical", style = "inside_shallow_frame"})
  shell.style.vertically_stretchable = true
  local nav = stretch(shell.add{type = "flow", name = "cc2_nav", direction = "horizontal"})
  for _, tab in ipairs({{"cc2_console", "Terminal", "console"}, {"cc2_files", "Files", "files"}, {"cc2_waypoint", "Waypoints", "waypoint"}, {"cc2_help", "Help", "help"}}) do
    local b = button(nav, tab[1], (session.view == tab[3] and "• " or "") .. tab[2], "Open " .. tab[2])
    b.style.minimal_width = 0
    if session.view == tab[3] then b.style.font_color = {1, 0.8, 0.4} end
  end
  local state = stretch(shell.add{type = "flow", direction = d.compact and "vertical" or "horizontal"})
  local process = state.add{type = "label", name = "cc2_process", caption = Layout.status(c, R.powered(c)), style = "cc2_status"}
  process.style.maximal_width = math.max(1, width - (d.compact and 0 or 140))
  button(state, "cc2_stop", "Stop", "Stop the program and clear circuit/speaker outputs.", c.process ~= nil, "red_button")
  local scroll = stretch(shell.add{type = "scroll-pane", name = "cc2_body", direction = "vertical", horizontal_scroll_policy = "never", vertical_scroll_policy = "auto"})
  scroll.style.vertically_stretchable = true
  scroll.style.minimal_height = 0
  scroll.style.maximal_height = math.max(1, d.height - 170)
  local body = stretch(scroll.add{type = "flow", direction = "vertical"})
  body.style.width = width
  if session.view == "editor" then
    label(body, "Editing " .. session.path, width, "subheader_caption_label")
    body.add{type = "label", name = "cc2_source_state", caption = "", style = "cc2_status"}
    local editor = body.add{type = "text-box", name = "cc2_source", style = "cc2_code", text = session.draft or "", tooltip = "Lua source. Startup belongs in init; durable values belong in state. Tab/Enter edit the source."}
    editor.word_wrap = false
    editor.style.width, editor.style.height = width, math.max(80, session.conflict and math.floor(height / 2) or height - 48)
    if session.conflict then
      label(body, "File changed elsewhere. Nothing was overwritten. Review the current file before rebasing:", width)
      local current = body.add{type = "text-box", name = "cc2_current_source", style = "cc2_code", text = session.conflict}
      current.read_only, current.word_wrap = true, false
      current.style.width, current.style.height = width, math.max(80, math.floor(height / 2))
      button(body, "cc2_rebase", "Keep draft & rebase", "Keep your edits; accept the displayed current file as the base. Save checks again before replacing it.")
    end
    local bar = body.add{type = "flow", direction = d.compact and "vertical" or "horizontal"}
    button(bar, "cc2_save", "Save", "Save without starting the program.", true, "confirm_button")
    button(bar, "cc2_save_run", "Save & run", "Save and start. Stop the current program first.", c.process == nil and R.powered(c))
    button(bar, "cc2_discard", "Discard & close", "Discard these editor changes and close.", true, "red_button")
  elseif session.view == "files" then
    label(body, c.cwd, width, "subheader_caption_label")
    label(body, "Open a file to edit it, or run a saved Lua program. Folders change the working directory.", width)
    local create = body.add{type = "flow", direction = d.compact and "vertical" or "horizontal"}
    local path = create.add{type = "textfield", name = "cc2_new_path", text = session.new_path or "", tooltip = "File or folder path, relative to the working directory (or absolute)."}
    path.style.width = math.max(80, width - (d.compact and 0 or 280))
    button(create, "cc2_new_file", "New file", "Create/open a file in the editor.")
    button(create, "cc2_new_folder", "New folder", "Create a directory.")
    local children = FS.list(c, c.cwd)
    local list = body.add{type = "table", name = "cc2_file_list", column_count = d.compact and 2 or 3}
    local up = button(list, "cc2_parent", ".. / Parent folder", "Go up one directory.")
    up.style.width = math.max(80, width - (d.compact and 124 or 248))
    list.add{type = "label", caption = ""}
    if not d.compact then list.add{type = "label", caption = ""} end
    session.file_paths = {}
    for index, name in ipairs(U.keys(children)) do
      local node = children[name]
      local full = FS.path(c, name)
      session.file_paths[index] = full
      local open = button(list, "cc2_file_" .. index, (node.type == "dir" and "Folder: " or "") .. name, full)
      open.tags = {path = full, directory = node.type == "dir"}
      open.style.width = math.max(80, width - (d.compact and 124 or 248))
      if node.type == "file" then
        local run = button(list, "cc2_run_" .. index, "Run", "Run " .. full, c.process == nil and R.powered(c))
        run.tags = {path = full}
      else list.add{type = "label", caption = node.virtual and "Shared" or "Folder"} end
      if not d.compact then list.add{type = "label", caption = node.type == "file" and (#node.text .. " bytes") or ""} end
    end
    if not next(children) then label(body, "This folder is empty. Enter a name above and choose New file or New folder.", width) end
    if c.personal and next(storage.drafts[player.index] or {}) then
      button(body, "cc2_recover", "Recover drafts", "Copy protected unsaved drafts into /recovered on this personal computer.")
    end
  elseif session.view == "waypoint" then
    local key = c.force_index .. ":" .. c.surface_index
    local points = storage.waypoints[key] or {}
    local names = U.keys(points)
    session.waypoint_names = names
    label(body, "Waypoints — shared with your force on this surface", width, "subheader_caption_label")
    if #names == 0 then label(body, "No waypoints yet. Give your current position a name and choose Save.", width) end
    local columns = body.add{type = "flow", direction = d.compact and "vertical" or "horizontal"}
    local form = columns.add{type = "flow", direction = "vertical"}
    local wp = session.waypoint or {name = "", x = player.position.x, y = player.position.y}
    session.waypoint = wp
    local selected = 0
    for i, name in ipairs(names) do if name == wp.original then selected = i end end
    form.add{type = "drop-down", name = "cc2_waypoint_list", items = names, selected_index = selected, tooltip = "Choose a saved waypoint"}
    field(form, "cc2_wp_name", "Name", wp.name)
    field(form, "cc2_wp_x", "X coordinate", tostring(wp.x))
    field(form, "cc2_wp_y", "Y coordinate", tostring(wp.y))
    local bar = form.add{type = "flow", direction = "horizontal"}
    button(bar, "cc2_wp_new", "New", "Use your current position.")
    button(bar, "cc2_wp_save", "Save", "Save this waypoint.", true, "confirm_button")
    button(bar, "cc2_wp_delete", "Delete", "Remove the selected waypoint.", wp.original ~= nil, "red_button")
    local camera = columns.add{type = "camera", name = "cc2_camera", position = {x = wp.x, y = wp.y}, surface_index = c.surface_index, zoom = 0.5}
    camera.style.width, camera.style.height = math.max(80, d.compact and width or width - 300), math.max(80, math.min(height, 350))
  elseif session.view == "help" then
    label(body, "Quick start", width, "subheader_caption_label")
    label(body, "Files → New file opens the Lua editor. Save & run starts your program. Stop clears outputs. The Terminal accepts shell commands; Program input is sent only when you choose Send or press Enter.", width)
    label(body, "Circuit ports", width, "subheader_caption_label")
    label(body, c.sub and "Red/green wires attach to the two feet, not the screen. Left and right are independent ports; programs can read and publish on either side. These are circuit networks, not roboport logistics." or "The personal computer has no physical circuit ports or speaker.", width)
    label(body, "Shell commands", width, "subheader_caption_label")
    for _, name in ipairs(U.keys(S.help)) do label(body, S.help[name], width) end
    label(body, "Programming APIs", width, "subheader_caption_label")
    for _, name in ipairs(U.keys(S.api_help)) do
      if c.sub or (name ~= "lan" and name ~= "speaker") then label(body, name .. ": " .. S.api_help[name], width) end
    end
    label(body, "Only run Lua you trust. Lasting values belong in state; callbacks use names. Source declarations are replayed, but init is not replayed after loading a save.", width)
  else
    local output = body.add{type = "text-box", name = "cc2_output", style = "cc2_output", text = c.output, tooltip = "Program output and shell results"}
    output.read_only, output.word_wrap = true, true
    output.style.width, output.style.height = width, math.max(80, height - 90)
    output.scroll_to_bottom()
    body.add{type = "label", name = "cc2_prompt", caption = c.cwd .. " >", style = "subheader_caption_label"}
    local bar = body.add{type = "flow", direction = "horizontal"}
    local command = bar.add{type = "textfield", name = "cc2_command", text = session.command or "", tooltip = "Shell command; Enter executes. Try help or edit /hello.lua."}
    command.style.width = math.max(80, width - 108)
    button(bar, "cc2_execute", "Execute", "Execute the shell command (Enter).")
    label(body, "Program input — delivered once when sent, not on every keystroke", width)
    local input_bar = body.add{type = "flow", direction = "horizontal"}
    local input = input_bar.add{type = "textfield", name = "cc2_input", text = session.input_draft or c.input, tooltip = "Text to send to the running program. Press Enter or Send."}
    input.style.width = math.max(80, width - 108)
    button(input_bar, "cc2_send_input", "Send", "Deliver program input once (Enter). A powered running program is required.", c.process ~= nil and R.powered(c))
    command.focus()
  end
  local footer = stretch(frame.add{type = "label", name = "cc2_status", caption = "", style = "cc2_status"})
  footer.style.maximal_width = width
  if location then
    frame.location = {x = math.max(0, math.min(location.x, player.display_resolution.width - d.width * player.display_scale)), y = math.max(0, math.min(location.y, player.display_resolution.height - d.height * player.display_scale))}
  else frame.auto_center = true end
  player.opened = frame
  M.refresh(player)
end
function M.resize(event)
  local player = game.get_player(event.player_index)
  if player and storage.sessions[player.index] then M.render(player) end
end
function M.open(player, c)
  if not M.authorized(player, c) then player.print("Computer unavailable: research the gauntlet, use the same force/surface, approach within 10 tiles."); return false end
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
  if session.view == "editor" and session.draft ~= session.base then feedback(session, "Save or discard your changes before leaving the editor.", "error"); return end
  if action.view == "editor" then
    local drafts = storage.drafts[player.index] or {}
    local count = 0; for _ in pairs(drafts) do count = count + 1 end
    local saved = drafts[session.id .. ":" .. action.path]
    assert(saved or count < 16, "Recover your saved drafts from the personal gauntlet before opening another editor.")
    session.base = saved and saved.base or FS.read(storage.computers[session.id], action.path)
    session.draft = saved and saved.draft or session.base
    M.check_save(session, FS.read(storage.computers[session.id], action.path))
  end
  session.view, session.path = action.view, action.path
  session.notice, session.notice_kind, session.notice_until = nil, nil, nil
end
function M.submit(player, session, c)
  local frame = root(player)
  local command = find(frame, "cc2_command")
  if not command then return end
  local line = command.text
  session.command = ""
  R.output(c, c.cwd .. " > " .. line .. "\n")
  local text, action, ok = S.execute(c, line)
  feedback(session, ok and (line == "" and "Ready" or "Command completed: " .. line) or text, ok and "success" or "error")
  if text and text ~= "" then R.output(c, text .. "\n") end
  if action then
    if action.view == "close" then M.close(player); return end
    navigate(player, session, action)
  end
  if session.view == "console" then
    command.text = ""; M.refresh(player); command.focus()
  else M.render(player) end
end
-- Plain-data conflict decisions are independently engine-testable without a player.
function M.check_save(session, current)
  if current ~= session.base then session.conflict = current; return false end
  session.conflict = nil
  return true
end
function M.rebase(session, current)
  assert(session.conflict ~= nil, "No conflict to review")
  if current ~= session.conflict then
    session.conflict = current
    return false
  end
  session.base, session.conflict = current, nil
  return true
end
function M.save(player, session, c, run)
  local source = find(root(player), "cc2_source").text
  assert(#source <= 262144, "program exceeds source limit")
  session.draft = source
  if not M.check_save(session, FS.read(c, session.path)) then
    feedback(session, "File changed elsewhere. Review the current version, then Keep draft & rebase; nothing has been overwritten.", "error")
    M.render(player)
    return
  end
  FS.write(c, session.path, source)
  session.base, session.draft = source, source
  local drafts = storage.drafts[player.index]
  if drafts then drafts[session.id .. ":" .. session.path] = nil end
  feedback(session, "Saved " .. session.path, "success")
  if run then
    assert(not c.process, "stop the current program first")
    local ok, err = R.start(c, source, session.path)
    assert(ok, err)
    session.view = "console"
    feedback(session, c.process and "Saved and started " .. session.path or "Saved and executed " .. session.path, "success")
  end
  M.render(player)
end
local function send_input(player, session, c)
  assert(c.process, "Start a program before sending input.")
  assert(R.powered(c), "Computer has no power; input was not sent.")
  local input = find(root(player), "cc2_input")
  R.input(c, input.text, player.index)
  session.input_draft = nil
  feedback(session, "Program input sent", "success")
  M.refresh(player)
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
        session.notice, session.notice_kind, session.notice_until = nil, nil, nil
        M.refresh(player)
      elseif name == "cc2_command" then session.command = event.element.text
      elseif name == "cc2_input" then session.input_draft = event.element.text
      elseif name == "cc2_new_path" then session.new_path = event.element.text
      elseif name == "cc2_wp_name" then session.waypoint.name = event.element.text
      elseif name == "cc2_wp_x" or name == "cc2_wp_y" then
        local value = tonumber(event.element.text)
        if value and value == value and math.abs(value) <= 1000000 then
          session.waypoint[name == "cc2_wp_x" and "x" or "y"] = value
          find(root(player), "cc2_camera").position = {x = session.waypoint.x, y = session.waypoint.y}
        end
      end
    elseif event.name == defines.events.on_gui_confirmed then
      if name == "cc2_command" then M.submit(player, session, c)
      elseif name == "cc2_input" then send_input(player, session, c) end
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
      elseif name == "cc2_rebase" then
        if M.rebase(session, FS.read(c, session.path)) then
          feedback(session, "Draft rebased. Review your edits, then Save.", "success")
        else feedback(session, "File changed again; review the refreshed current version before rebasing.", "error") end
        M.render(player)
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
        feedback(session, "Drafts recovered under /recovered. Use Files to open them.", "success")
        M.render(player)
      elseif name == "cc2_console" or name == "cc2_waypoint" or name == "cc2_files" or name == "cc2_help" then
        local views = {cc2_console = "console", cc2_waypoint = "waypoint", cc2_files = "files", cc2_help = "help"}
        navigate(player, session, {view = views[name]}); M.render(player)
      elseif name == "cc2_send_input" then send_input(player, session, c)
      elseif name == "cc2_parent" then
        c.cwd = FS.path(c, ".."); M.render(player)
      elseif name == "cc2_new_file" or name == "cc2_new_folder" then
        local path = find(root(player), "cc2_new_path").text
        assert(path ~= "", "Enter a file or folder name first.")
        if name == "cc2_new_folder" then
          FS.mkdir(c, path); feedback(session, "Folder created: " .. path, "success")
        else
          local absolute = FS.path(c, path)
          if not FS.exists(c, absolute) then FS.write(c, absolute, "") end
          navigate(player, session, {view = "editor", path = absolute})
        end
        session.new_path = ""; M.render(player)
      elseif name:match("^cc2_file_%d+$") then
        local path = event.element.tags.path
        local node = FS.get(c, path)
        assert(node, "File or folder no longer exists. Reopen Files to refresh.")
        if node.type == "dir" then c.cwd = path else navigate(player, session, {view = "editor", path = path}) end
        M.render(player)
      elseif name:match("^cc2_run_%d+$") then
        assert(not c.process, "Stop the current program first.")
        assert(R.powered(c), "Computer has no power.")
        local path = event.element.tags.path
        local ok, err = R.start(c, FS.read(c, path), path)
        assert(ok, err)
        session.view = "console"; feedback(session, c.process and "Started " .. path or "Executed " .. path, "success"); M.render(player)
      elseif name == "cc2_execute" then M.submit(player, session, c)
      elseif name == "cc2_save" or name == "cc2_save_run" then M.save(player, session, c, name == "cc2_save_run")
      elseif name == "cc2_stop" then R.stop(c); feedback(session, "Program stopped; circuit and speaker outputs cleared", "success"); M.refresh(player)
      elseif name == "cc2_wp_new" then session.waypoint = nil; feedback(session, "New waypoint at your current position"); M.render(player)
      elseif name == "cc2_wp_save" or name == "cc2_wp_delete" then
        local key = c.force_index .. ":" .. c.surface_index
        local points = storage.waypoints[key] or {}
        storage.waypoints[key] = points
        local wp = session.waypoint
        if name == "cc2_wp_delete" then if wp.original then points[wp.original] = nil end; session.waypoint = nil; feedback(session, "Waypoint deleted", "success")
        else
          assert(#wp.name > 0 and #wp.name <= 64, "waypoint name must be 1..64 characters")
          wp.x = U.finite(tonumber(find(root(player), "cc2_wp_x").text), "X")
          wp.y = U.finite(tonumber(find(root(player), "cc2_wp_y").text), "Y")
          assert(math.abs(wp.x) <= 1000000 and math.abs(wp.y) <= 1000000, "coordinates out of range")
          assert(not points[wp.name] or wp.name == wp.original, "waypoint name already exists")
          if wp.original then points[wp.original] = nil end
          points[wp.name] = {name = wp.name, x = wp.x, y = wp.y}
          wp.original = wp.name
          feedback(session, "Waypoint saved: " .. wp.name, "success")
        end
        M.render(player)
      end
    end
  end)
  if not ok then
    feedback(session, tostring(err), "error")
    M.refresh(player)
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
      else M.refresh(player) end
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
