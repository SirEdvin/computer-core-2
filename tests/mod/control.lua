local examples=require("examples")
local GUI=require("__computer_core_2__.scripts.gui")
local function call(method, ...) return remote.call("computer_core_2", method, ...) end
local function check(name, condition)
  assert(condition, "FAIL: " .. name)
  storage.checks = (storage.checks or 0) + 1
  log("CC2 PASS " .. name)
end
local function data(id) return call("getComputer", id) end
local function find(root, name)
  if root.name == name then return root end
  for _, child in pairs(root.children) do local result = find(child, name); if result then return result end end
end
local function gui(player, name, kind, text)
  local element = find(player.gui.screen.cc2_root, name)
  assert(element, "missing GUI control: " .. name)
  if text ~= nil then element.text = text end
  script.raise_event(kind or defines.events.on_gui_click, {player_index = player.index, element = element, button = defines.mouse_button_type.left})
end
local function exec(id, command)
  local text, action, ok = call("exec", id, command)
  assert(ok, text)
  return text, action
end
local function spawn(position, surface, tags)
  local entity = (surface or game.surfaces[1]).create_entity{name = "computer-interface-entity", position = position, force = "player", raise_built = false}
  assert(entity)
  script.raise_event(defines.events.script_raised_built, {entity = entity, tags = tags})
  entity.energy = 5000000
  for _, id in ipairs(call("getComputerIDs")) do if call("getEntity", id) == entity then return id, entity end end
  error("computer was not registered")
end
local receiver = [[
return {
 init = function()
  state.init = (state.init or 0) + 1
  state.messages = 0
  disk.writeFile('/persist.txt', 'saved')
  os.set('tuple', 1, nil, 3)
  wlan.on('message', 'receive')
  term.addInputListener('input')
  os.wait('timer', 1)
 end,
 timer = function() state.timers = (state.timers or 0) + 1; term.write('timer fired') end,
 receive = function(value) state.messages = state.messages + 1; state.message = value end,
 input = function(event) state.input = event.userInput end
}
]]
script.on_init(function()
  storage.checks = 0
  local editor={base='old',draft='my changes'}
  check('editor detects conflict without losing draft',not GUI.check_save(editor,'other changes') and editor.draft=='my changes')
  check('editor rebase rejects intervening file changes',not GUI.rebase(editor,'newer changes') and editor.base=='old' and editor.draft=='my changes')
  check('editor explicit reviewed rebase retains draft',GUI.rebase(editor,'newer changes') and editor.base=='newer changes' and editor.draft=='my changes')
  check('rebased editor ordinary save comparison',GUI.check_save(editor,'newer changes') and not GUI.check_save(editor,'changed again'))
  local surface = game.surfaces[1]
  surface.request_to_generate_chunks({0, 0}, 2); surface.force_generate_chunk_requests()
  for _, entity in ipairs(surface.find_entities_filtered{area = {{-30, -30}, {30, 30}}, type = {"tree", "simple-entity"}}) do entity.destroy() end
  game.forces.player.technologies["computer-gauntlet-technology"].researched = true
  game.forces.player.technologies["computer-technology"].researched = true
  check("recipe unlock", game.forces.player.recipes["computer-recipe"].enabled)
  storage.a, storage.b = spawn({0, 0}), spawn({6, 0})
  local a, b = storage.a, storage.b
  check("deterministic distinct IDs", a ~= b and a > 0 and b > a)
  local ports = call("getPorts", a)
  check("all composite children", ports.left.valid and ports.right.valid and ports.speaker.valid and ports.music.valid and ports.lamp.valid)
  check("protected circuit ports", not ports.left.destructible and not ports.left.minable and not ports.left.operable)
  exec(a, 'mkdir programs'); exec(a, 'touch "programs/file with spaces.lua"')
  check("quoted shell arguments", data(a).fs['/programs/file with spaces.lua'] ~= nil)
  local source = [[disk.writeFile('/programs/a', 'hello'); disk.appendFile('/programs/a', ' world'); term.write(disk.readFile('/programs/a')); assert(disk.fileExist('/programs/a'))]]
  check("one-shot source", call("run", a, source, "one-shot"))
  check("disk read/write/append", exec(a, 'cat programs/a') == 'hello world')
  check("one-shot finishes", not data(a).running)
  exec(a, 'cp programs/a programs/b'); exec(a, 'mv programs/b programs/c')
  check("copy/move files", data(a).fs['/programs/c'].text == 'hello world' and not data(a).fs['/programs/b'])
  exec(a, 'cd programs'); check("cwd", exec(a, 'pwd') == '/programs'); exec(a, 'cd ..')
  check("tree", exec(a, 'tree'):find('programs', 1, true) ~= nil)
  check("help API", exec(a, 'help os'):find('os.wait', 1, true) ~= nil)
  exec(a, 'label set alpha'); exec(b, 'label set beta')
  check("label lookup", exec(a, 'label get') == 'alpha')
  check("shared mounts", exec(b, 'cat /mnt/alpha/programs/a') == 'hello world')
  exec(b, 'cp /mnt/alpha/programs/a copied')
  check("mount copy", exec(b, 'cat copied') == 'hello world')
  local _, _, ok = call('exec', b, 'label set alpha'); check("duplicate label rejected", not ok)
  call('run', a, [[lan.writeLeftSignals({{signal={type='item',name='iron-plate'},count=5},{signal={type='item',name='iron-plate'},count=3}}); state.signals=lan.readLeftSignals(); speaker.playNote(1,1,0.5,false); speaker.mute(); speaker.setAlert('test',{type='virtual',name='signal-A'},1); speaker.mute()]], 'adapters')
  check("sections circuit output", data(a).outputs.left[1].count == 8 and ports.left.get_or_create_control_behavior().get_section(1).filters[1].min == 8)
  check("read own outputs", data(a).state.signals[1].count == 8)
  local external = surface.create_entity{name='constant-combinator', position={-3,1}, force='player'}
  external.get_or_create_control_behavior().add_section().set_slot(1,{value={type='virtual',name='signal-B',quality='normal',comparator='='},min=42})
  external.get_wire_connector(defines.wire_connector_id.circuit_red,true).connect_to(ports.left.get_wire_connector(defines.wire_connector_id.circuit_red,true))
  storage.external = external
  local quality = prototypes.quality.uncommon and 'uncommon' or 'normal'
  call('run', a, "lan.writeRightSignals({{signal={type='item',name='iron-plate',quality='normal'},count=2},{signal={type='item',name='iron-plate',quality='" .. quality .. "'},count=4}})", 'quality')
  check("quality identity", #data(a).outputs.right == (quality == 'normal' and 1 or 2))
  check("unsafe state rejected", not call('run', a, [[state.bad=function() end]], 'bad-state'))
  check("no function persisted", data(a).state.bad == nil)
  check("anonymous callback rejected", not call('run', a, [[os.wait(function() end,1)]], 'bad-callback'))
  check("binary load rejected", not call('run', a, [[assert(load('\27Lua'))]], 'bytecode'))
  check("filesystem quota", not call('run', a, [[disk.writeFile('/huge',string.rep('x',1048577))]], 'quota'))
  check("NaN args rejected", not pcall(function() call('run',a, 'print(1)', 'nan', {0/0}) end))
  -- start() must not leave a half-created process on rejected argument payloads.
  call('stop', a)
  local library = "return {twice=function(v) return v*2 end}"
  call('run', a, "disk.writeFile('/library'," .. string.format('%q',library) .. ")", 'library-write')
  local persistent = [[local lib=os.require('/library'); return {init=function() state.value=lib.twice(5) end, timer=function() state.value=lib.twice(state.value) end}]]
  check("source library", call('run', a, persistent, 'library'))
  check("library result", data(a).state.value == 10)
  call('stop', a)
  check('variable readback isolation program',call('run',a,[[
    os.set('copy', {value=1}, nil, 3)
    local value, hole, last=os.get('copy')
    assert(hole==nil and last==3)
    value.value=2; value.bad=function() end; value.self=value
    value.large=string.rep('x',262145)
  ]],'readback'))
  check('variable readback cannot persist mutation/function/cycle/oversize',data(a).vars.copy[1].value==1 and data(a).vars.copy[1].bad==nil and data(a).vars.copy[1].self==nil and data(a).vars.copy[1].large==nil)
  local long_directory=string.rep('p',1000)
  exec(a,'mkdir '..long_directory); exec(a,'cd '..long_directory)
  check('normalized relative paths respect metadata budget',not select(3,call('exec',a,'mkdir '..string.rep('q',40))))
  exec(a,'cd /'); exec(a,'rm '..long_directory)
  local player = game.players[1]
  if player then
  player.create_character(); player.teleport({0,4})
  storage.player_index = player.index
  check("terminal opens", call('open', a, player.index))
  check("terminal GUI exists", player.gui.screen.cc2_root ~= nil)
  gui(player,'cc2_command',defines.events.on_gui_text_changed,'edit /gui.lua')
  gui(player,'cc2_command',defines.events.on_gui_confirmed)
  check("editor opens", find(player.gui.screen.cc2_root,'cc2_source') ~= nil)
  gui(player,'cc2_source',defines.events.on_gui_text_changed,"term.write('GUI works')")
  gui(player,'cc2_save_run')
  check("editor save/run", data(a).fs['/gui.lua'].text == "term.write('GUI works')" and data(a).output:find('GUI works',1,true))
  gui(player,'cc2_command',defines.events.on_gui_text_changed,'edit /gui.lua')
  gui(player,'cc2_command',defines.events.on_gui_confirmed)
  gui(player,'cc2_source',defines.events.on_gui_text_changed,"term.write('my retained draft')")
  call('run',a,[[disk.writeFile('/gui.lua', "term.write('someone else')")]],'concurrent-edit')
  gui(player,'cc2_save')
  check('GUI conflict leaves current file intact',data(a).fs['/gui.lua'].text=="term.write('someone else')" and find(player.gui.screen.cc2_root,'cc2_rebase')~=nil)
  gui(player,'cc2_rebase'); gui(player,'cc2_save')
  check('GUI explicit rebase then save',data(a).fs['/gui.lua'].text=="term.write('my retained draft')")
  gui(player,'cc2_waypoint')
  gui(player,'cc2_wp_name',defines.events.on_gui_text_changed,'Home')
  gui(player,'cc2_wp_save')
  check("waypoint saved", find(player.gui.screen.cc2_root,'cc2_waypoint_list').items[1] == 'Home')
  gui(player,'cc2_wp_delete')
  check("waypoint deletion persists", #find(player.gui.screen.cc2_root,'cc2_waypoint_list').items == 0)
  gui(player,'cc2_close')
  call('openGauntlet',player.index)
  check("personal gauntlet opens", player.gui.screen.cc2_root ~= nil)
  storage.personal = call('getComputerIDs')[#call('getComputerIDs')]
  check("personal computer", data(storage.personal).personal and data(storage.personal).player_index == player.index)
  gui(player,'cc2_close')
  local other_force = game.create_force('other')
  other_force.technologies['computer-gauntlet-technology'].researched = true
  player.force = other_force
  check("foreign editor denied", not call('open',a,player.index))
  player.force = game.forces.player
  else
    log('CC2 MANUAL GUI/gauntlet checks require a client-created player; headless map creation has none')
  end
  local other_surface = game.create_surface('test-surface',{width=64,height=64})
  other_surface.request_to_generate_chunks({0,0},1); other_surface.force_generate_chunk_requests()
  storage.other = spawn({0,0},other_surface)
  check("surface mount isolation", not select(3, call('exec',storage.other,'cat /mnt/alpha/programs/a')))
  if player then
    check("surface editor isolation", not call('open',storage.other,player.index))
    local personal_surface=game.create_surface('personal-surface-test',{width=32,height=32})
    personal_surface.request_to_generate_chunks({0,0},1); personal_surface.force_generate_chunk_requests()
    player.teleport({0,0},personal_surface)
    call('openGauntlet',player.index)
    call('run',storage.personal,[[state.surface_marker=true; disk.writeFile('/surface-marker','retained')]],'personal-surface')
    gui(player,'cc2_close')
    player.teleport({0,4},surface)
    game.delete_surface(personal_surface)
    check('surface deletion preserves player-owned computer data',data(storage.personal).state.surface_marker and data(storage.personal).fs['/surface-marker'].text=='retained')
  end
  local entity = call('getEntity',a)
  local clone = entity.clone{position={12,0},surface=surface,force='player'}
  assert(clone)
  local clone_id
  for _, id in ipairs(call('getComputerIDs')) do if call('getEntity',id)==clone then clone_id=id end end
  check("clone registration", clone_id ~= nil)
  check("clone files, no identity/process", data(clone_id).fs['/programs/a'].text=='hello world' and not data(clone_id).label and not data(clone_id).running)
  clone.destroy()
  storage.clone = clone_id
  local tags = call('snapshot',a)
  storage.blueprint = spawn({18,0},surface,tags)
  check("blueprint tagged files", data(storage.blueprint).fs['/programs/a'].text=='hello world')
  check("blueprint no identity/process", not data(storage.blueprint).label and not data(storage.blueprint).running)
  local bad = spawn({24,0},surface,{computer_core_2={fs={['/bad/child']={type='file',text='invalid'}}}})
  check("malformed blueprint rejected", data(bad).fs['/bad/child']==nil)
  call('getEntity',bad).destroy{raise_destroy=true}
  check("script destroy cleanup", not pcall(data,bad))
  check("persistent receiver start", call('run',b,receiver,'receiver'))
  check("persistent tuple", data(b).vars.tuple.n==3 and data(b).vars.tuple[3]==3)
  call('input',b,'hello input')
  check("named terminal input", data(b).state.input=='hello input')
  check("sender start", call('run',a,[[return {init=function() state.sent=0; wlan.onBuiltComputer('built'); os.wait('send',0.1) end, send=function() wlan.emit('beta','message',{value=7}); wlan.emit('device_receiver','device_msg',7); state.sent=state.sent+1 end, built=function(event) state.built=event.computerID end}]],'sender'))
  -- A source-only extension attached to an external entity: state and code
  -- snapshots must survive registry replacement and a real engine reload.
  local api = [[return {name='device',entities={'car'},
    prototype={
      __init={'init',function(self) self.__state.init=(self.__state.init or 0)+1; self.__state.ticks=self.__state.ticks or 0 end},
      value={'value()',function(self) return self.__state.ticks end}
    },
    events={on_tick=function(self) self.__state.ticks=self.__state.ticks+1 end,
      on_message=function(self,event,value) if event=='device_msg' then self.__state.message=value end end,
      on_built_computer=function(self,event) self.__state.built=event.computerID end,
      on_gui_text_changed=function(self,event) self.__state.input=event.userInput end,
      after_text_print=function(self,event) self.__state.printed=true end,
      on_script_kill=function(self) self.__state.stops=(self.__state.stops or 0)+1 end}
  }]]
  check('source extension registration',call('addComputerAPI',api)=='device')
  local car=surface.create_entity{name='car',position={30,0},force='player'}
  storage.device=call('addEntityStructure',{entity=car,type='test-device',sub={}})
  check('external entity attachment',call('getEntity',storage.device)==car and not call('getPorts',storage.device))
  check('extension program starts',call('run',storage.device,[[return {init=function() os.setComputerLabel('device_receiver'); term.write('start'); os.wait('sample',1) end,sample=function() state.sample=device.value() end}]],'device-program'))
  check('extension init once',data(storage.device).extension_state.device.init==1)
  check('extension API help',exec(storage.device,'help device'):find('value()',1,true)~=nil)
  call('input',storage.device,'device input')
  check('extension input event',data(storage.device).extension_state.device.input=='device input')
  local teardown=surface.create_entity{name='car',position={36,0},force='player'}
  local teardown_id=call('addEntityStructure',{entity=teardown,type='teardown',sub={}})
  check('invalid reconstruction stops program',not call('run',teardown_id,[[assert(not state.fail); return {init=function() state.fail=true end}]],'bad-declaration'))
  check('extension cleanup independent of program reconstruction',data(teardown_id).extension_state.device.stops==1 and not data(teardown_id).running)
  teardown.destroy{raise_destroy=true}
  call('addComputerAPI',[[return {name='device',entities={'car'},prototype={value={'value',function() return -100 end}}}]])
  for _,name in ipairs({'quota_one','quota_two'}) do
    call('addComputerAPI',"return {name='"..name.."',entities={'car'},prototype={__init={'init',function(self) self.__state.payload=string.rep('x',140000) end}}}")
  end
  local quota_entity=surface.create_entity{name='car',position={36,8},force='player'}
  local quota_id=call('registerEntity',quota_entity)
  check('aggregate extension state quota enforced',not call('run',quota_id,[[return {}]],'extension-quota'))
  check('rejected extension aggregate remains serializable',not data(quota_id).running)
  quota_entity.destroy{raise_destroy=true}
  call('removeComputerAPI','quota_one'); call('removeComputerAPI','quota_two')
  storage.timer_test=spawn({0,-8})
  check('timer ordering start',call('run',storage.timer_test,[[return {
    init=function()
      state.order=''
      os.wait('first',0.1)
      local cancelled=os.wait('cancelled',0.1)
      os.wait('second',0.1)
      assert(os.cancelTimer(cancelled))
      local id=term.addInputListener('input')
      local other=term.addInputListener('input')
      term.removeListener(id)
      state.listener=other
    end,
    first=function() state.order=state.order..'1' end,
    second=function() state.order=state.order..'2' end,
    cancelled=function() error('cancelled timer fired') end,
    input=function(event) state.last_listener=event.listenerID end
  }]],'timer-order'))
  call('input',storage.timer_test,'test')
  check('stable listener IDs',data(storage.timer_test).state.last_listener==data(storage.timer_test).state.listener)
  check('unknown handler rejected',not call('run',storage.built_id or storage.blueprint,[[return {init=function() os.wait('absent',1) end}]],'unknown'))
  exec(a,'mkdir nested')
  check('script-relative disk paths',call('run',storage.blueprint,[[disk.writeFile('nested/relative','ok')]],'/scripts/main.lua'))
  check('implicit parent directories',data(storage.blueprint).fs['/scripts/nested/relative'].text=='ok')
  storage.closure=spawn({-8,-8})
  check('ephemeral closures start',call('run',storage.closure,[[local volatile=0; return {
    init=function() state.total=0; os.wait('step',0.1) end,
    step=function() volatile=volatile+1; state.volatile=volatile; state.total=state.total+1; os.wait('step',0.1) end
  }]],'closure-policy'))
  -- Nested pure libraries and state aliases are reconstructed faithfully.
  local full_disk=spawn({-16,8})
  check('full filesystem content quota accepted',call('run',full_disk,[[disk.writeFile('/full',string.rep('x',1048576))]],'full-disk'))
  check('full filesystem snapshot includes metadata',#call('snapshot',full_disk).computer_core_2.fs['/full'].text==1048576)
  check('full filesystem remote read',#data(full_disk).fs['/full'].text==1048576)
  local full_clone=call('getEntity',full_disk).clone{position={-32,8},surface=surface,force='player'}
  local full_clone_id
  for _,id in ipairs(call('getComputerIDs')) do if call('getEntity',id)==full_clone then full_clone_id=id end end
  check('full filesystem clone metadata budget',#data(full_clone_id).fs['/full'].text==1048576)
  local full_blueprint=spawn({-32,0},surface,call('snapshot',full_disk))
  check('full filesystem blueprint import metadata budget',#data(full_blueprint).fs['/full'].text==1048576)
  full_clone.destroy{raise_destroy=true}
  call('getEntity',full_blueprint).destroy{raise_destroy=true}
  call('getEntity',full_disk).destroy{raise_destroy=true}
  storage.alias=spawn({-8,8})
  check('nested library setup',call('run',storage.alias,[[disk.writeFile('/child', 'return {value=4}'); disk.writeFile('/parent', "return os.require('/child')")]],'setup'))
  check('nested library and captured state alias',call('run',storage.alias,[[local lib=os.require('/parent'); local saved=state; return {
    init=function() saved.value=lib.value; os.wait('step',0.1) end,
    step=function() saved.value=saved.value+1; os.wait('step',0.1) end
  }]],'alias'))
  storage.examples={}
  for i,name in ipairs({'counter','receiver','sender','circuit'}) do
    local id=spawn({i*6,-16})
    storage.examples[name]=id
    check('shipped example '..name,call('run',id,examples[name],'/examples/'..name..'.lua'))
  end
  -- Fill the real shared queue with player-source messages to an unpowered
  -- listener. The next lifecycle tick must not throw while announcing new builds.
  storage.queue_sink=spawn({-24,-16})
  exec(storage.queue_sink,'label set queue_sink')
  check('queue-pressure receiver starts',call('run',storage.queue_sink,[[return {
    init=function() wlan.on('flood','message'); wlan.onBuiltComputer('built') end,
    message=function() end,built=function() end
  }]],'queue-sink'))
  call('getEntity',storage.queue_sink).energy=0
  storage.queue_sender=spawn({-24,-8})
  check('queue-pressure source finishes safely',call('run',storage.queue_sender,[[for i=1,4097 do
    if not pcall(wlan.emit,'queue_sink','flood') then state.full=true; break end
  end]],'queue-flood'))
  check('queue is actually saturated',data(storage.queue_sender).state.full)
  local inventory=game.create_inventory(1)
  inventory[1].set_stack{name='blueprint'}
  local mapping=inventory[1].create_blueprint{surface=surface,force='player',area={{-4,-2},{2,2}}}
  local port_count=0
  for _,entity in pairs(mapping) do if entity.name=='computer-combinator' then port_count=port_count+1 end end
  check('actual blueprint captures both ports',port_count==2)
  inventory.destroy()
  storage.stage=1
  log('CC2 BOOTSTRAP PASS checks=' .. storage.checks)
end)
local reloaded=false
script.on_load(function() reloaded=storage.stage==2 end)
script.on_event(defines.events.on_tick,function()
  local a,b=storage.a,storage.b
  if game.tick==1 then
    check('saturated queue cannot crash lifecycle build tick',data(a).process.dropped_built>0)
    call('stop',storage.queue_sink)
    call('getEntity',storage.queue_sink).destroy{raise_destroy=true}
    call('getEntity',storage.queue_sender).destroy{raise_destroy=true}
  elseif game.tick==3 then
    check('destroy without raised event cleanup',not pcall(data,storage.clone))
    local ports=call('getPorts',a)
    call('stop',a)
    check('real red network read',call('run',a,[[state.network=lan.readLeftSignals('red')]],'network'))
    local found=false
    for _,signal in ipairs(data(a).state.network) do if signal.signal.name=='signal-B' and signal.count==42 then found=true end end
    check('external signal count',found)
    check('numeric wire constant compatibility',call('run',a,[[state.numeric_network=lan.readLeftSignals(defines.wire_type.red); defines.direction.north=-999]],'legacy-constants'))
    check('numeric wire matches red network',data(a).state.numeric_network[1].count==42 and defines.direction.north~=-999)
    call('run',a,[[return {init=function() state.sent=0; wlan.onBuiltComputer('built'); os.wait('send',0.1) end, send=function() wlan.emit('beta','message',{value=7}); wlan.emit('device_receiver','device_msg',7); state.sent=state.sent+1 end, built=function(event) state.built=event.computerID end}]],'sender')
  elseif game.tick==15 then
    check('wireless delivery',data(b).state.messages==1 and data(b).state.message.value==7)
    check('shipped sender/receiver delivery',data(storage.examples.receiver).state.received==1)
    check('shipped circuit callback',data(storage.examples.circuit).state.samples>0)
    check('timer order and cancellation',data(storage.timer_test).state.order=='12')
    local id=spawn({0,8})
    storage.built_id=id
  elseif game.tick==18 then
    check('built computer notification',data(a).state.built==storage.built_id)
    call('getEntity',b).energy=0
  elseif game.tick==30 then
    check('timer not early',not data(b).state.timers)
    check('file before save',data(b).fs['/persist.txt'].text=='saved')
    storage.stage=2
    game.server_save('cc2-resume')
    log('CC2 SNAPSHOT checks=' .. storage.checks)
  elseif game.tick==65 then
    check('unpowered timer paused',not data(b).state.timers)
    call('getEntity',b).energy=5000000
  elseif game.tick==70 then
    check('overdue timer exactly once',data(b).state.timers==1)
    check('init not replayed',data(b).state.init==1)
    check('file survives load',data(b).fs['/persist.txt'].text=='saved')
    check('input state survives load',data(b).state.input=='hello input')
    check('tuple survives load',data(b).vars.tuple.n==3 and data(b).vars.tuple[2]==nil)
    check('extension state and source snapshot',data(storage.device).extension_state.device.init==1 and data(storage.device).state.sample>=59)
    call('stop',storage.device)
    check('extension stop lifecycle',data(storage.device).extension_state.device.stops==1)
    local device=data(storage.device).extension_state.device
    check('extension message/built/output events survive reload',device.message==7 and device.built==storage.built_id and device.printed)
    check('captured locals never carry between dispatches',data(storage.closure).state.volatile==1 and data(storage.closure).state.total>=11)
    check('nested library and alias survive reload',data(storage.alias).state.value>=15)
    check('shipped counter survives reload',data(storage.examples.counter).state.count>=11)
    check('no duplicate delivery',data(b).state.messages==1)
    if reloaded then check('fresh runtime reconstructed',storage.stage==2) end
    -- Removing a surface must remove every composite child and computer.
    game.delete_surface('test-surface')
    storage.surface_deleted=true
    local ports=call('getPorts',storage.blueprint)
    call('getEntity',storage.blueprint).die()
    check('death cleanup',not pcall(data,storage.blueprint) and not ports.left.valid and not ports.speaker.valid)
    call('stop',a); call('stop',b)
    check('stop clears process',not data(a).running and not data(b).running)
  elseif game.tick==75 then
    check('surface deletion cleanup',not pcall(data,storage.other))
    log('CC2 COMPLETE ' .. (reloaded and 'RELOAD' or 'FIRST') .. ' checks=' .. storage.checks)
  end
end)
