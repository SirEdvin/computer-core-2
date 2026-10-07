-- Terminal presentation only: the BIOS, shell and editors live in guest Lua.
local U = require('scripts.util')
local L = require('scripts.lifecycle')
local R = require('scripts.os_runtime')

local Palette = require('scripts.terminal_palette')
local M = {}
local cache = {} -- Ephemeral rendering cache. Never an execution/persistence root.
local capture_marker='\226\128\139' -- Selected zero-width marker makes native Backspace observable.
local function focus_capture(frame,session)
  session.capture_marker_retained=false
  local input=frame.cc2_capture
  input.text=capture_marker
  input.focus()
  input.select_all()
end
local function rgb(value)
  return {r=math.floor(value/65536)/255,g=math.floor(value/256)%256/255,b=value%256/255}
end
local colors={}
for i,value in ipairs(Palette) do colors[i]=rgb(value) end
local function root(player) return player.gui.screen.cc2_root end
function M.authorized(player,c)
  local tech=player and player.valid and player.force.technologies['computer-gauntlet-technology']
  if not c or not tech or not tech.researched then return false end
  if c.personal then return player.index==c.player_index end
  if not c.entity or not c.entity.valid then return false end
  if player.force.index~=c.entity.force.index or player.surface.index~=c.entity.surface.index then return false end
  local dx,dy=player.position.x-c.entity.position.x,player.position.y-c.entity.position.y
  return dx*dx+dy*dy<=100
end
function M.close(player)
  if not player or not player.valid then return end
  local frame=root(player)
  storage.sessions[player.index]=nil
  cache[player.index]=nil
  if frame and frame.valid then frame.destroy() end
end
local function current(player)
  local session=storage.sessions[player.index]
  local c=session and storage.computers[session.id]
  if not session or not M.authorized(player,c) then M.close(player); return end
  return c,session,root(player)
end
local function owns(frame,element)
  while element and element.valid do
    if element==frame then return true end
    element=element.parent
  end
  return false
end
local function status(frame,c,session)
  local text=c.os_error or (not R.powered(c) and 'No power' or c.os_stopped and 'Stopped — Reboot to start' or c.guest and 'Running' or 'Booting…')
  if session.notice then text=session.notice end
  if frame and frame.cc2_status.caption~=text then frame.cc2_status.caption=text end
end
local function send(player,c,session,...)
  local ok,err=R.event(c,table.pack(...))
  session.notice=not ok and ('Input refused: '..tostring(err)) or nil
  return ok
end
local function tap(player,c,session,code)
  if send(player,c,session,'key',code,false) then send(player,c,session,'key_up',code) end
end
function M.render(player)
  local c,session,frame=current(player)
  if not c or not frame then return end
  local display=c.guest and c.guest.display
  status(frame,c,session)
  if not display then return end
  local blink=display.blink and math.floor(game.tick/30)%2==0
  local view=cache[player.index]
  if view and view.source==display and not view.pending and view.revision==display.revision and view.blink==blink then return end
  local pane=frame.cc2_scroll
  local grid=pane.cc2_cells
  if not grid or grid.column_count~=display.columns or #grid.children~=display.columns*display.rows then
    pane.clear()
    grid=pane.add{type='table',name='cc2_cells',column_count=display.columns,style='cc2_terminal_grid'}
    for y=1,display.rows do
      for x=1,display.columns do
        grid.add{type='button',caption=' ',style='cc2_terminal_bg_15',tags={cc2_cell=true,x=x,y=y}}
      end
    end
    cache[player.index]={cells={},rows={},next_row=1}
  end
  view=cache[player.index]
  if not view then view={cells={},rows={},next_row=1}; cache[player.index]=view end
  if view.source~=display then view.rows={} end
  view.source=display
  local children=grid.children
  local palette={}
  for i,color in ipairs(display.palette) do palette[i]=color.r..':'..color.g..':'..color.b end
  local palette_key=table.concat(palette,';')
  local remaining=512
  local function row(y)
    if y<1 or y>display.rows then return true end
    local line=display.lines[y]
    local cursor=blink and y==display.y and display.x or 0
    local old=view.rows[y]
    if old and old.text==line.text and old.fg==line.foreground and old.bg==line.background
      and old.palette==palette_key and old.cursor==cursor then return true end
    if remaining<display.columns then return false end
    remaining=remaining-display.columns
    for x=1,display.columns do
      local i=(y-1)*display.columns+x
      local byte=line.text:byte(x)
      local glyph=byte>=32 and byte<=126 and string.char(byte) or '?'
      local fg=tonumber(line.foreground:sub(x,x),16)+1
      local bg=tonumber(line.background:sub(x,x),16)+1
      if x==cursor then fg,bg=bg,fg; if glyph==' ' then glyph='_' end end
      local color=display.palette[fg]
      local signature=glyph..':'..bg..':'..palette[fg]
      if view.cells[i]~=signature then
        local cell=children[i]
        cell.style='cc2_terminal_bg_'..(bg-1)
        cell.caption=glyph
        cell.style.font_color=color
        cell.style.hovered_font_color=color
        cell.style.clicked_font_color=color
        view.cells[i]=signature
      end
    end
    view.rows[y]={text=line.text,fg=line.foreground,bg=line.background,palette=palette_key,cursor=cursor}
    return true
  end
  -- Cursor echo first; rotate remaining dirty rows without exceeding 512 cells.
  row(display.y)
  if view.cursor_y and view.cursor_y~=display.y then row(view.cursor_y) end
  view.pending=false
  local first=view.next_row
  for offset=0,display.rows-1 do
    local y=(first+offset-1)%display.rows+1
    if not row(y) then view.pending=true; view.next_row=y; break end
  end
  view.cursor_y=display.y
  view.revision,view.blink=display.revision,blink
end
function M.open(player,c)
  if not M.authorized(player,c) then return false end
  M.close(player)
  storage.sessions[player.index]={id=c.id}
  local frame=player.gui.screen.add{type='frame',name='cc2_root',direction='vertical',caption=c.personal and 'Personal terminal' or 'Computer '..c.id}
  frame.auto_center=true
  local bar=frame.add{type='flow',name='cc2_bar',direction='horizontal'}
  bar.add{type='button',name='cc2_reboot',caption='Reboot',tooltip='Restart execution. Unsaved guest editor buffers will be lost; saved files remain.'}
  bar.add{type='button',name='cc2_shutdown',caption='Shutdown',tooltip='Pause this computer until Reboot. Closing the window does not stop it.'}
  bar.add{type='button',name='cc2_terminate',caption='Terminate',tooltip='Send termination to the guest program.'}
  bar.add{type='button',name='cc2_close',caption='Close'}
  frame.add{type='label',name='cc2_status',caption='Booting…',style='cc2_status',tooltip='Click the terminal to type or paste. Enter submits; Ctrl+M opens the editor menu.'}
  if c.migration_notice then
    frame.add{type='label',caption='Alpha upgrade: old callbacks retired. Files/drafts retained; see /legacy-recovery and /legacy-startup*. Back up your save.',style='cc2_status'}.style.maximal_width=600
  end
  local pane=frame.add{type='scroll-pane',name='cc2_scroll',horizontal_scroll_policy='auto',vertical_scroll_policy='auto'}
  local scale=player.display_scale or 1
  pane.style.maximal_width=math.max(160,math.floor(player.display_resolution.width/scale)-100)
  pane.style.maximal_height=math.max(120,math.floor(player.display_resolution.height/scale)-260)
  frame.add{type='textfield',name='cc2_capture',text=capture_marker,style='cc2_terminal_capture',lose_focus_on_confirm=false}

  player.opened=frame
  M.render(player)
  focus_capture(frame,storage.sessions[player.index])
  return true
end
function M.gauntlet(player)
  if player and player.valid then return M.open(player,L.personal(player)) end
end
function M.tick()
  for _,index in ipairs(U.keys(storage.sessions)) do
    local player=game.get_player(index)
    if player and player.valid then M.render(player) else storage.sessions[index]=nil; cache[index]=nil end
  end
end
function M.resize(event)
  local player=game.get_player(event.player_index)
  local c=player and current(player)
  if c then M.open(player,c) end -- Presentation only; never changes guest geometry.
end
function M.closed(event)
  local player=game.get_player(event.player_index)
  if player and event.element and event.element==root(player) then M.close(player) end
end
function M.key(event,code)
  local player=game.get_player(event.player_index)
  if not player then return end
  local c,session,frame=current(player)
  if not c or not frame or player.opened~=frame then return end
  -- CustomInputEvent.element/in_gui describe mouse hover, not keyboard focus.
  -- The opened terminal and current authorization determine keyboard routing.
  tap(player,c,session,code)
  if code>=262 and code<=269 then session.capture_marker_retained=true end
  if code==259 or code==261 then session.capture_key_tick=game.tick end
end
function M.event(event)
  local player=game.get_player(event.player_index)
  if not player then return end
  local c,session,frame=current(player)
  local element=event.element
  if not c or not frame or not owns(frame,element) then return end
  local tags=element.tags
  if event.name==defines.events.on_gui_text_changed and element.name=='cc2_capture' then
    local text=element.text
    if text=='' then
      if session.capture_key_tick~=game.tick then tap(player,c,session,259) end
      focus_capture(frame,session)
    elseif text~=capture_marker then
      if session.capture_marker_retained then text=text:gsub(capture_marker,'',1) end
      if #text>0 and send(player,c,session,#text==1 and 'char' or 'paste',text) then focus_capture(frame,session) end
    end
  elseif event.name==defines.events.on_gui_confirmed and element.name=='cc2_capture' then
    tap(player,c,session,257)
  elseif event.name==defines.events.on_gui_click then
    if element.name=='cc2_close' then M.close(player); return
    elseif element.name=='cc2_reboot' then R.reboot(c); session.notice=nil
    elseif element.name=='cc2_shutdown' then R.shutdown(c)
    elseif element.name=='cc2_terminate' then send(player,c,session,'terminate')

    elseif tags.cc2_cell then
      local button=event.button==defines.mouse_button_type.right and 2 or event.button==defines.mouse_button_type.middle and 3 or 1
      if send(player,c,session,'mouse_click',button,tags.x,tags.y) then send(player,c,session,'mouse_up',button,tags.x,tags.y) end
    end
    if frame.valid then focus_capture(frame,session) end
  end
  M.render(player)
end
return M
