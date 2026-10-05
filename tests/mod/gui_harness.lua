-- Interaction contract tests using table-backed GUI elements, NOT native client
-- rendering. Native control checks below remain conditional on a real player.
local source = require('gui_source')
local Layout = require('__computer_core_2__.scripts.gui_layout')
local U = require('__computer_core_2__.scripts.util')
local M = {}
function M.run(check)
  local sequence = 0
  local function element(parent, spec)
    sequence = sequence + 1
    local e = {valid = true, parent = parent, name = spec.name or ('auto_' .. sequence), type = spec.type,
      children = {}, style = {}, tags = spec.tags or {}, caption = spec.caption, text = spec.text or '',
      enabled = spec.enabled ~= false, items = spec.items, selected_index = spec.selected_index,
      location = {x = 0, y = 0}}
    e.add = function(child)
      for _, other in ipairs(e.children) do assert(not child.name or child.name ~= other.name, 'duplicate GUI name') end
      local created = element(e, child)
      e.children[#e.children + 1] = created
      e[created.name] = created
      return created
    end
    e.destroy = function()
      for i = #e.children, 1, -1 do e.children[i].destroy() end
      e.valid = false
      if parent then
        parent[e.name] = nil
        for i, child in ipairs(parent.children) do if child == e then table.remove(parent.children, i); break end end
      end
    end
    e.focus = function() e.focused = true end
    e.scroll_to_bottom = function() e.scrolled = true end
    return e
  end
  local screen = element(nil, {type = 'screen', name = 'screen'})
  local player = {valid = true, index = 1, force = {index = 1, technologies = {['computer-gauntlet-technology'] = {researched = true}}},
    surface = {index = 1}, position = {x = 0, y = 0}, display_resolution = {width = 1920, height = 1080}, display_scale = 1,
    gui = {screen = screen}, print = function() end}
  local c = {id = 1, force_index = 1, surface_index = 1, position = {x = 0, y = 0}, sub = {}, output = '', input = '', cwd = '/', powered = true}
  local state = {sessions = {}, computers = {[1] = c}, drafts = {}, waypoints = {}}
  local files = {['/'] = {type = 'dir'}}
  local fs = {}
  fs.path = function(computer, path)
    local parts = {}
    local full = path:sub(1,1) == '/' and path or (computer.cwd .. '/' .. path)
    for part in full:gmatch('[^/]+') do
      if part == '..' then table.remove(parts) elseif part ~= '.' then parts[#parts+1] = part end
    end
    return '/' .. table.concat(parts, '/')
  end
  fs.read = function(_, path) assert(files[path] and files[path].type == 'file'); return files[path].text end
  fs.write = function(_, path, text) files[path] = {type = 'file', text = text} end
  fs.exists = function(_, path) return files[path] ~= nil end
  fs.get = function(_, path) return files[path] end
  fs.mkdir = function(computer, path) files[fs.path(computer,path)] = {type = 'dir'} end
  fs.list = function(_, path)
    local result = {}
    for full,node in pairs(files) do
      local parent,name = full:match('^(.*)/([^/]+)$')
      if (parent == '' and '/' or parent) == path then result[name] = node end
    end
    return result
  end
  local rt = {powered = function(computer) return computer.powered end}
  rt.start = function(computer, text, path) computer.process = {path = path}; computer.output = text; return true end
  rt.stop = function(computer) computer.process = nil end
  rt.output = function(computer,text) computer.output = computer.output .. text end
  local sent = 0
  rt.input = function(computer,text) sent = sent + 1; computer.input = text end
  local shell = {help = {help = 'help'}, api_help = {os = 'os.wait'}}
  shell.execute = function(_, text)
    if text == 'help' then return 'Available commands', nil, true end
    return 'unknown command', nil, false
  end
  local modules = {['scripts.util'] = U, ['scripts.filesystem'] = fs, ['scripts.runtime'] = rt,
    ['scripts.shell'] = shell, ['scripts.lifecycle'] = {}, ['scripts.gui_layout'] = Layout}
  local fake_game = {tick = 0, get_player = function(index) if index == 1 then return player end end}
  local env = setmetatable({storage = state, game = fake_game, require = function(name) return assert(modules[name], name) end}, {__index = _G})
  local gui = assert(load(source, 'gui-under-test', 't', env))()
  local function get(name) return assert(gui.find(screen.cc2_root, name), 'missing element ' .. name) end
  local function action(name, event, text)
    local e = get(name)
    if text ~= nil then e.text = text end
    gui.event{player_index = 1, element = e, name = event or defines.events.on_gui_click}
  end
  check('mock UI opens and renders all chrome',gui.open(player,c) and get('cc2_files') and get('cc2_process').caption:find('Idle'))
  local initial = screen.cc2_root
  action('cc2_command',defines.events.on_gui_text_changed,'help')
  action('cc2_command',defines.events.on_gui_confirmed)
  check('mock terminal updates without destroying its frame',screen.cc2_root == initial and c.output:find('Available commands') and get('cc2_command').text == '')
  action('cc2_command',defines.events.on_gui_text_changed,'bad')
  action('cc2_execute')
  check('mock shell failures show explicit error feedback',get('cc2_status').caption:find('Error:') ~= nil)
  c.process = {path = '/input.lua'}; gui.refresh(player)
  action('cc2_input',defines.events.on_gui_text_changed,'abc')
  gui.refresh(player)
  check('mock program input does not deliver keystrokes or lose draft',sent == 0 and get('cc2_input').text == 'abc')
  action('cc2_send_input')
  check('mock program input sends exactly once',sent == 1 and c.input == 'abc')
  c.powered = false; gui.refresh(player)
  check('mock power loss remains inspectable and blocks sends',get('cc2_process').caption:find('Paused') and not get('cc2_send_input').enabled)
  action('cc2_input',defines.events.on_gui_confirmed)
  check('mock Enter cannot bypass power guard',sent == 1 and get('cc2_status').caption:find('no power'))
  c.powered = true; c.process = nil
  action('cc2_files')
  check('mock file browser renders new-file controls',get('cc2_new_file') ~= nil)
  action('cc2_new_path',defines.events.on_gui_text_changed,'/test.lua')
  action('cc2_new_file')
  action('cc2_source',defines.events.on_gui_text_changed,'return {}')
  check('mock editor dirty state is live',get('cc2_source_state').caption:find('Modified') ~= nil)
  action('cc2_help')
  check('mock navigation cannot discard unsaved edits',state.sessions[1].view == 'editor' and state.sessions[1].draft == 'return {}')
  files['/test.lua'].text = 'other changes'
  action('cc2_save')
  check('mock editor exposes conflict without overwriting',get('cc2_current_source').text == 'other changes' and files['/test.lua'].text == 'other changes')
  action('cc2_rebase'); action('cc2_save')
  check('mock editor rebase and save retain user source',files['/test.lua'].text == 'return {}' and get('cc2_source_state').caption:find('Saved'))
  action('cc2_save_run')
  check('mock save/run returns to terminal with start feedback',state.sessions[1].view == 'console' and get('cc2_process').caption:find('/test.lua') and get('cc2_status').caption:find('started'))
  action('cc2_stop')
  check('mock stop updates process controls immediately',not get('cc2_stop').enabled and get('cc2_process').caption:find('Idle'))
  action('cc2_files')
  action('cc2_new_path',defines.events.on_gui_text_changed,'programs')
  action('cc2_new_folder')
  check('mock new-folder action gives success feedback',files['/programs'].type == 'dir' and get('cc2_status').caption:find('Folder created'))
  local index
  for i,path in ipairs(state.sessions[1].file_paths) do if path == '/test.lua' then index=i end end
  action('cc2_file_' .. index)
  action('cc2_source',defines.events.on_gui_text_changed,'unsaved resized draft')
  player.display_resolution = {width = 1280, height = 720}; player.display_scale = 1.5
  gui.resize{player_index = 1}
  check('mock display changes retain draft and fit window',get('cc2_source').text == 'unsaved resized draft' and screen.cc2_root.style.width <= 1280/1.5 and screen.cc2_root.style.height <= 720/1.5)
  check('mock close protects dirty editor',gui.close(player) == false and state.sessions[1] ~= nil)
  action('cc2_discard')
  check('mock discard closes deliberately',state.sessions[1] == nil)
  gui.open(player,c); action('cc2_help')
  check('mock help view renders',state.sessions[1].view == 'help')
  action('cc2_waypoint')
  action('cc2_wp_name',defines.events.on_gui_text_changed,'Home')
  action('cc2_wp_save')
  check('mock waypoints select saved entry and show feedback',get('cc2_waypoint_list').selected_index == 1 and get('cc2_status').caption:find('Waypoint saved'))
  action('cc2_wp_delete')
  check('mock waypoint deletion gives feedback',get('cc2_status').caption:find('Waypoint deleted'))
  -- The same element name outside our root must never reach the handler.
  c.process = {path='/trusted.lua'}
  gui.event{player_index=1,element=element(screen,{type='button',name='cc2_stop'}),name=defines.events.on_gui_click}
  check('mock foreign GUI element cannot trigger actions',c.process ~= nil)
  for _,resolution in ipairs({{width=1280,height=720},{width=1920,height=1080},{width=2560,height=1440}}) do
    for _,scale in ipairs({1,1.5,2}) do
      local d=Layout.dimensions(resolution,scale)
      check('layout fits '..resolution.width..'x'..resolution.height..' scale '..scale,d.width*scale<=resolution.width and d.height*scale<=resolution.height and d.content_width>0 and d.content_height>0)
    end
  end
  local notice={}
  Layout.feedback(notice,'Saved','success',10)
  check('feedback expires instead of hiding runtime status forever',Layout.notice(notice,609)=='Saved' and Layout.notice(notice,610)==nil)
end
return M
