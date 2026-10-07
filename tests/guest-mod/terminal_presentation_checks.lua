-- Real GUI module with table-backed elements: not native client/focus acceptance.
local GUI=require('__computer_core_2__.scripts.terminal_gui')
local VM=require('__computer_core_2__.scripts.guest.vm')
local Compiler=require('__computer_core_2__.scripts.guest.compiler')
local Terminal=require('__computer_core_2__.scripts.guest.terminal')
return function(check)
  local report,results=check,{}
  check=function(name,condition) assert(condition,name); results[#results+1]=name end
  local real_game,real_storage=game,storage
  local writes,focus,selection=0,0,0
  local function element(spec,parent)
    local values={valid=true,parent=parent,tags={},children={},style={}}
    local node=setmetatable({}, {
      __index=function(_,key) return values[key] end,
      __newindex=function(_,key,value)
        if key=='style' and type(value)=='string' then values.style={}; values.style_name=value
        else values[key]=value end
        if key=='caption' and values.tags.cc2_cell then writes=writes+1 end
      end})
    for key,value in pairs(spec) do node[key]=value end
    node.add=function(child)
      local result=element(child,node)
      values.children[#values.children+1]=result
      if child.name then values[child.name]=result end
      return result
    end
    node.clear=function() values.children={} end
    node.destroy=function() values.valid=false end
    node.focus=function() focus=focus+1 end
    node.select_all=function() selection=selection+1 end
    return node
  end
  local vm=VM.new(assert(Compiler.compile("return 'presentation-pass'")))
  local display=vm.display
  local screen=element({})
  local player={index=1,valid=true,character={valid=true},opened=nil,gui={screen=screen},
    force={technologies={['computer-gauntlet-technology']={researched=true}}},
    display_scale=1,display_resolution={width=1920,height=1080}}
  local computer={id=1,personal=true,player_index=1,guest=vm}
  local ok,err=pcall(function()
    game={tick=0,get_player=function(index) return index==1 and player or nil end}
    storage={sessions={},computers={[1]=computer}}
    assert(GUI.open(player,computer))
    local frame=screen.cc2_root
    local capture=frame.cc2_capture
    local marker=capture.text
    check('mock terminal opens with tiny native capture focused/selected',capture.style_name=='cc2_terminal_capture' and focus==1 and selection==1)
    GUI.render(player) -- Finish the initial bounded sweep.
    writes=0
    GUI.render(player)
    check('mock unchanged terminal performs no cell writes',writes==0)
    local grid=frame.cc2_scroll.cc2_cells
    Terminal.methods.setCursorPos(display,1,display.rows)
    Terminal.methods.write(display,'Z')
    writes=0
    GUI.render(player)
    check('mock bottom-row typing renders immediately without a full sweep',grid.children[(display.rows-1)*display.columns+1].caption=='Z' and writes<=2)
    Terminal.methods.setPaletteColor(display,1,0.1,0.2,0.3)
    writes=0; GUI.render(player)
    check('mock palette refresh remains bounded',writes<=512)
    Terminal.methods.setCursorPos(display,1,display.rows)
    Terminal.methods.write(display,'Q')
    writes=0; GUI.render(player)
    check('mock typing during unfinished repaint prioritizes the latest row',grid.children[(display.rows-1)*display.columns+1].caption=='Q' and writes<=512)
    for _=1,display.rows do GUI.render(player) end
    check('mock partial refresh eventually updates every row',grid.children[1].style.font_color.r==0.1)
    vm.display=Terminal.new(display.columns,display.rows)
    vm.display.revision=display.revision
    GUI.render(player); GUI.render(player)
    check('mock same-size display replacement invalidates cached rows',grid.children[(display.rows-1)*display.columns+1].caption==' ')
    local cell=grid.children[1]
    GUI.event({player_index=1,name=defines.events.on_gui_click,element=cell,button=defines.mouse_button_type.left})
    check('mock terminal cell click restores native typing focus',focus==2 and selection==2 and capture.text==marker)
    local before=#vm.events.queue
    capture.text='a'
    GUI.event({player_index=1,name=defines.events.on_gui_text_changed,element=capture})
    check('mock hidden capture forwards typed character and rearms',vm.events.queue[before+1].tuple[1]=='char' and vm.events.queue[before+1].tuple[2]=='a' and capture.text==marker)
    before=#vm.events.queue
    capture.text='alpha\nbeta'..marker
    GUI.event({player_index=1,name=defines.events.on_gui_text_changed,element=capture})
    check('mock paste preserves user-supplied zero-width bytes',vm.events.queue[before+1].tuple[2]=='alpha\nbeta'..marker)
    game.tick=1; before=#vm.events.queue; capture.text=''
    GUI.event({player_index=1,name=defines.events.on_gui_text_changed,element=capture})
    check('mock native marker deletion forwards Backspace when custom input is intercepted',#vm.events.queue==before+2 and vm.events.queue[before+1].tuple[2]==259)
    game.tick=2; before=#vm.events.queue
    GUI.key({player_index=1,in_gui=false},259)
    capture.text=''
    GUI.event({player_index=1,name=defines.events.on_gui_text_changed,element=capture})
    check('mock custom and native deletion in one tick do not duplicate Backspace',#vm.events.queue==before+2)
    GUI.key({player_index=1,in_gui=false},263)
    before=#vm.events.queue; capture.text='b'..marker
    GUI.event({player_index=1,name=defines.events.on_gui_text_changed,element=capture})
    check('mock insertion after navigation strips only the retained capture marker',vm.events.queue[before+1].tuple[2]=='b')
    local revision=vm.display.revision
    Terminal.methods.setCursorPos(vm.display,vm.display.x,vm.display.y)
    Terminal.methods.setCursorBlink(vm.display,vm.display.blink)
    local color=vm.display.palette[1]
    Terminal.methods.setPaletteColor(vm.display,1,color.r,color.g,color.b)
    check('unchanged native cursor/blink/palette setters do not invalidate display',vm.display.revision==revision)
    GUI.close(player)
  end)
  game,storage=real_game,real_storage
  assert(ok,err)
  for _,name in ipairs(results) do report(name,true) end
end
