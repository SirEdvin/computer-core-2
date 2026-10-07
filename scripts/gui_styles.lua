-- Native Factorio chrome; no external UI library or copied mod assets.
local styles = data.raw['gui-style'].default
styles.cc2_code = {type = 'textbox_style', parent = 'textbox', font = 'default', minimal_width = 0, minimal_height = 0}
styles.cc2_output = {type = 'textbox_style', parent = 'cc2_code'}
styles.cc2_status = {type = 'label_style', parent = 'label', single_line = false}
data:extend{{type='font',name='cc2_terminal_mono',from='default-mono',size=14}}
styles.cc2_terminal_grid = {type='table_style',parent='table',horizontal_spacing=0,vertical_spacing=0}
-- Keep native text entry focusable, without a separate visible input box.
styles.cc2_terminal_capture = {type='textbox_style',parent='textbox',width=1,height=1,
  minimal_width=0,minimal_height=0,padding=0,margin=0,font_color={r=0,g=0,b=0,a=0},
  selection_background_color={r=0,g=0,b=0,a=0},default_background={},active_background={},disabled_background={}}
for i,value in ipairs(require('scripts.terminal_palette')) do
  local color={r=math.floor(value/65536)/255,g=math.floor(value/256)%256/255,b=value%256/255}
  local background={base={type='composition',center={filename='__computer_core_2__/graphics/terminal-cell.png',width=1,height=1},tint=color}}
  styles['cc2_terminal_bg_'..(i-1)]={type='button_style',parent='button',font='cc2_terminal_mono',
    width=9,height=18,padding=0,margin=0,
    default_graphical_set=background,hovered_graphical_set=background,clicked_graphical_set=background,
    disabled_graphical_set=background}
end
for _,key in ipairs(require('scripts.terminal_keys').bindings) do
  data:extend{{type='custom-input',name=key.name,key_sequence=key.sequence,consuming='none'}}
end
