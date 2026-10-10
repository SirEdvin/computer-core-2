-- Real GUI module with table-backed elements: not native client/focus acceptance.
local GUI=require('__computer_core_2__.scripts.terminal_gui')
local VM=require('__computer_core_2__.scripts.guest.vm')
local Compiler=require('__computer_core_2__.scripts.guest.compiler')
local Terminal=require('__computer_core_2__.scripts.guest.terminal')
local ShellScheduler=require('__computer_core_2__.scripts.shell.scheduler')
local VMScheduler=require('__computer_core_2__.scripts.guest.scheduler')

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
  local players={[1]=player}
  local ok,err=pcall(function()
    game={tick=0,get_player=function(index) return players[index] end}
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
    player.force.index=1; player.surface={index=1}; player.position={x=0,y=0}
    computer.personal=nil; computer.player_index=nil; computer.backend='event-shell'
    computer.entity={valid=true,energy=100,position={x=0,y=0},force=player.force,surface=player.surface}
    storage.terminal_scheduler=VMScheduler.new()
    computer.shell=assert(ShellScheduler.new(nil,51,19,storage.terminal_scheduler,1,game.tick))
    assert(GUI.open(player,computer))
    frame=screen.cc2_root; capture=frame.cc2_capture
    check('mock shell presentation identifies initialization without reading stale VM display',frame.caption=='Shell computer 1'
      and frame.cc2_status.caption=='Initializing…' and not frame.cc2_status.tooltip:find('editor',1,true))
    assert(ShellScheduler.step(computer.shell,storage.terminal_scheduler,1,game.tick,true))
    GUI.render(player)
    local shell_grid=frame.cc2_scroll.cc2_cells
    check('mock shell rendering reads selected shell prompt rather than retained VM pixels',shell_grid.children[(computer.shell.display.rows-1)*51+1].caption=='/'
      and frame.cc2_status.caption=='Running')
    local queued=#vm.events.queue
    GUI.key({player_index=1,in_gui=false},263)
    check('mock shell key routing omits unsupported key-up while preserving VM queue',#computer.shell.events.queue==1
      and computer.shell.events.queue[1].tuple[1]=='key' and #vm.events.queue==queued and storage.sessions[1].notice==nil)
    GUI.close(player)
    check('mock shell close preserves session and queued input',#computer.shell.events.queue==1 and computer.shell.status=='ready')
    local shell=computer.shell
    local function step(powered)
      game.tick=game.tick+1
      return ShellScheduler.step(shell,storage.terminal_scheduler,1,game.tick,powered~=false)
    end
    local function click(control)
      GUI.event{player_index=1,name=defines.events.on_gui_click,element=control,button=defines.mouse_button_type.left}
    end
    assert(step())
    assert(GUI.open(player,computer)); frame=screen.cc2_root; capture=frame.cc2_capture
    local before_shell=serpent.line(shell,{sortkeys=true})
    local before_focus=focus
    click(frame.cc2_scroll.cc2_cells.children[1])
    check('mock shell cell click focuses without unsupported mouse input or state mutation',focus==before_focus+1
      and storage.sessions[1].notice==nil and serpent.line(shell,{sortkeys=true})==before_shell)
    player.opened=element({})
    capture.text='forged input'
    GUI.event{player_index=1,name=defines.events.on_gui_text_changed,element=capture}
    click(frame.cc2_bar.cc2_reboot); click(frame.cc2_bar.cc2_shutdown)
    GUI.key({player_index=1},257)
    local opened=player.opened
    GUI.resize{player_index=1}
    check('mock inactive owned frame cannot receive text key reboot or shutdown',serpent.line(shell,{sortkeys=true})==before_shell)
    check('mock inactive terminal resize cannot steal another GUI focus',player.opened==opened)
    player.opened=frame
    local outsider=element({name='cc2_capture',text='forged input'})
    GUI.event{player_index=1,name=defines.events.on_gui_text_changed,element=outsider}
    check('mock foreign element cannot inject shell input',serpent.line(shell,{sortkeys=true})==before_shell)
    local force,surface=player.force,player.surface
    local restrictions={
      {'force',function() player.force={index=2,technologies=force.technologies} end,function() player.force=force end},
      {'surface',function() player.surface={index=2} end,function() player.surface=surface end},
      {'range',function() player.position={x=11,y=0} end,function() player.position={x=0,y=0} end},
      {'research',function() force.technologies['computer-gauntlet-technology'].researched=false end,function() force.technologies['computer-gauntlet-technology'].researched=true end},
      {'personal ownership',function() computer.personal=true; computer.player_index=2 end,function() computer.personal=nil; computer.player_index=nil end}
    }
    for _,restriction in ipairs(restrictions) do
      restriction[2]()
      check('mock shell open rejects '..restriction[1],not GUI.open(player,computer))
      GUI.key({player_index=1},257)
      GUI.event{player_index=1,name=defines.events.on_gui_text_changed,element=capture}
      click(frame.cc2_bar.cc2_reboot)
      check('mock lost '..restriction[1]..' rejects existing view input without shell changes',serpent.line(shell,{sortkeys=true})==before_shell and storage.sessions[1]==nil)
      restriction[3](); assert(GUI.open(player,computer)); frame=screen.cc2_root; capture=frame.cc2_capture
    end
    capture.text='ab\r\ncd'
    GUI.event{player_index=1,name=defines.events.on_gui_text_changed,element=capture}
    assert(step())
    check('mock shell paste reaches real handler without executing newline',shell.command=='ab cd' and #shell.history==0)
    GUI.key({player_index=1,in_gui=false,element=outsider},263); assert(step())
    capture.text='Z'..marker
    GUI.event{player_index=1,name=defines.events.on_gui_text_changed,element=capture}; assert(step())
    check('mock shell keyboard and native capture preserve insertion cursor',shell.command=='ab cZd' and shell.cursor==#'ab cZ')
    local saved=serpent.line(shell,{sortkeys=true})
    player.display_scale=2; player.display_resolution={width=1280,height=720}
    GUI.resize{player_index=1}; frame=screen.cc2_root; capture=frame.cc2_capture
    check('mock shell resize redraws immediately without another character or session reset',computer.shell==shell and serpent.line(shell,{sortkeys=true})==saved
      and frame.cc2_scroll.style.maximal_width==540 and frame.cc2_scroll.cc2_cells.children[(shell.display.rows-1)*51+3].caption==' '
      and frame.cc2_scroll.cc2_cells.children[(shell.display.rows-1)*51+4].caption=='a')
    local second={index=2,valid=true,character={valid=true},gui={screen=element({})},force=force,surface=surface,position={x=0,y=0},
      display_scale=1,display_resolution={width=1920,height=1080}}
    players[2]=second
    local peer={id=2,personal=true,player_index=2,guest=VM.new(assert(Compiler.compile('return true')))}
    storage.computers[2]=peer
    assert(GUI.open(second,peer))
    local peer_queue=#peer.guest.events.queue
    GUI.key({player_index=1},268); assert(step())
    GUI.key({player_index=2},263)
    check('mock simultaneous shell and VM viewers use independent event protocols',shell.cursor==0 and #peer.guest.events.queue==peer_queue+2
      and peer.guest.events.queue[peer_queue+2].tuple[1]=='key_up' and #vm.events.queue==queued)
    computer.entity.electric_buffer_size=5000000; computer.entity.energy=0
    saved=serpent.line(shell,{sortkeys=true})
    click(frame.cc2_bar.cc2_reboot)
    check('mock powerless shell lifecycle refusal is visible without changing state',frame.cc2_status.caption=='Input refused: Computer is not powered'
      and serpent.line(shell,{sortkeys=true})==saved)
    check('mock paused shell dispatch preserves input session and progress',not step(false) and serpent.line(shell,{sortkeys=true})==saved)
    computer.entity.energy=100
    GUI.key({player_index=1},269); assert(step())
    check('mock restoring power continues same shell input without reboot',computer.shell==shell and shell.command=='ab cZd' and shell.cursor==#'ab cZd')
    local disk=shell.disk
    click(frame.cc2_bar.cc2_shutdown); assert(step())
    GUI.render(player)
    check('mock GUI shutdown reaches selected shell and preserves committed disk',shell.status=='stopped' and shell.disk==disk and frame.cc2_status.caption=='Stopped — Reboot to start')
    click(frame.cc2_bar.cc2_reboot); assert(step()); assert(step())
    GUI.render(player)
    check('mock GUI reboot restarts shell only and preserves disk',shell.status=='ready' and shell.command=='' and shell.disk==disk and #peer.guest.events.queue==peer_queue+2)
    capture.text='help'
    GUI.event{player_index=1,name=defines.events.on_gui_text_changed,element=capture}
    GUI.event{player_index=1,name=defines.events.on_gui_confirmed,element=capture}
    assert(step()); assert(step())
    local job=assert(shell.job)
    saved=serpent.line(shell,{sortkeys=true})
    GUI.close(player)
    check('mock closing terminal preserves foreground job input and complete display',serpent.line(shell,{sortkeys=true})==saved and shell.job==job)
    assert(step())
    check('mock closed powered shell advances its same foreground output job',shell.job==job and serpent.line(shell,{sortkeys=true})~=saved)
    assert(GUI.open(player,computer)); frame=screen.cc2_root
    computer.entity.energy=0; saved=serpent.line(shell,{sortkeys=true})
    check('mock power loss pauses pending GUI-originated job without resetting it',not step(false) and shell.job==job and serpent.line(shell,{sortkeys=true})==saved)
    computer.entity.energy=100; assert(step())
    check('mock job resumes after power restoration without replacement',shell.job==job and serpent.line(shell,{sortkeys=true})~=saved)
    click(frame.cc2_bar.cc2_terminate); assert(step())
    check('mock GUI terminate cancels foreground work and keeps committed disk',shell.job==nil and shell.disk==disk and shell.status=='ready')
    saved=serpent.line(shell,{sortkeys=true})
    GUI.close(player); assert(GUI.open(player,computer))
    check('mock shell reopen preserves complete session and leaves VM viewer open',serpent.line(shell,{sortkeys=true})==saved and storage.sessions[2].id==2)
    GUI.close(player); GUI.close(second)
  end)
  game,storage=real_game,real_storage
  assert(ok,err)
  for _,name in ipairs(results) do report(name,true) end
end
