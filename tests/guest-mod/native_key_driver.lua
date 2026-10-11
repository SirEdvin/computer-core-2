-- Table-backed GUI clicks feeding the real VM consumer; not client key delivery.
local GUI=require('__computer_core_2__.scripts.terminal_gui')
local Keys=require('__computer_core_2__.scripts.terminal_keys')
local M={}
local function element(spec,parent)
  local values={valid=true,parent=parent,tags={},children={},style={}}
  local node=setmetatable({}, {
    __index=function(_,key) return values[key] end,
    __newindex=function(_,key,value) values[key]=key=='style' and type(value)=='string' and {} or value end})
  for key,value in pairs(spec) do node[key]=value end
  node.add=function(child)
    local next=element(child,node); node.children[#node.children+1]=next
    if child.name then node[child.name]=next end
    return next
  end
  node.clear=function() node.children={} end
  node.destroy=function() node.valid=false end
  node.focus=function() end
  node.select_all=function() end
  return node
end
function M.send(vm,code)
  local real_game,real_storage=game,storage
  local ok,err=pcall(function()
    local player={index=1,valid=true,character={valid=true},gui={screen=element({})},force={technologies={['computer-gauntlet-technology']={researched=true}}},
      display_resolution={width=1920,height=1080},display_scale=1}
    local computer={id=1,personal=true,player_index=1,guest=vm}
    game={tick=vm.events.tick,get_player=function() return player end}
    storage={computers={[1]=computer},sessions={}}
    assert(GUI.open(player,computer))
    local frame=player.gui.screen.cc2_root
    local selected
    for i,key in ipairs(Keys.buttons) do if key.code==code then selected=i end end
    assert(selected,'missing native key alternative '..code)
    frame.cc2_key_actions.cc2_key_choice.selected_index=selected
    GUI.event{player_index=1,name=defines.events.on_gui_click,element=frame.cc2_key_actions.cc2_key_send}
    assert(not storage.sessions[1].notice,storage.sessions[1].notice)
    GUI.close(player)
  end)
  game,storage=real_game,real_storage
  assert(ok,err)
end
return M
