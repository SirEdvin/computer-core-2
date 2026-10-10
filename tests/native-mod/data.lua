-- Data-stage results cannot substitute for control-stage execution.
assert(data and not game and not script)
local chunk = assert(load('return token, game, script, data, _G', '=native-data-probe', 't', {token = 42}))
local token, guest_game, guest_script, guest_data, guest_globals = chunk()
assert(token == 42 and guest_game == nil and guest_script == nil and guest_data == nil and guest_globals == nil)
log('CC2 NATIVE DATA LOAD PASS')
