-- Native Factorio chrome; no external UI library or copied mod assets.
local styles = data.raw['gui-style'].default
styles.cc2_code = {type = 'textbox_style', parent = 'textbox', font = 'default', minimal_width = 0, minimal_height = 0}
styles.cc2_output = {type = 'textbox_style', parent = 'cc2_code'}
styles.cc2_status = {type = 'label_style', parent = 'label', single_line = false}
