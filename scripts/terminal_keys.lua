-- Guest codes come from the pinned Recrafted lwjgl3 keymap.
local M = {bindings = {}, buttons = {
  {caption='Tab',code=258}, {caption='Backspace',code=259}, {caption='Enter',code=257},
  {caption='Left',code=263}, {caption='Right',code=262}, {caption='Up',code=265},
  {caption='Down',code=264}, {caption='Ctrl / menu',code=341}
}}
for _,key in ipairs({
  {'tab','TAB',258}, {'backspace','BACKSPACE',259}, {'delete','DELETE',261},
  {'left','LEFT',263}, {'right','RIGHT',262}, {'up','UP',265}, {'down','DOWN',264},
  {'home','HOME',268}, {'end','END',269}, {'page-up','PAGEUP',266}, {'page-down','PAGEDOWN',267},
  {'menu','CONTROL + M',341}
}) do
  M.bindings[#M.bindings+1]={name='cc2-terminal-'..key[1],sequence=key[2],code=key[3]}
end
return M
