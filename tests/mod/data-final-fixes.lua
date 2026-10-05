local port = data.raw['constant-combinator']['computer-combinator']
assert(port.selection_priority > data.raw['electric-energy-interface']['computer-interface-entity'].selection_priority, 'Computer body masks circuit-port selection')
for _, point in ipairs(port.circuit_wire_connection_points) do
  for _, colour in ipairs({'red', 'green'}) do
    assert(point.wire[colour][1] == 0 and point.wire[colour][2] == 0, 'Wire anchor must be at the artwork leg')
    assert(point.shadow[colour][1] == 0 and point.shadow[colour][2] == 0, 'Wire shadow must use the same anchor')
  end
end
local styles = data.raw['gui-style'].default
for _, name in ipairs({'frame_title', 'frame_action_button', 'inside_shallow_frame', 'draggable_space', 'subheader_caption_label', 'confirm_button', 'red_button', 'cc2_code', 'cc2_output', 'cc2_status'}) do
  assert(styles[name], 'Missing native UI style: ' .. name)
end
-- Headless engines do not load client fonts. Validate the prototype reference
-- explicitly so a successful headless run cannot hide a client startup failure.
for name, style in pairs(styles) do
  if name:match('^cc2_') and style.font then
    assert(data.raw.font[style.font], 'Missing font prototype for ' .. name .. ': ' .. style.font)
  end
end
log('CC2 DATA PASS: centred wire anchors, port selection priority and native UI styles and font references')
