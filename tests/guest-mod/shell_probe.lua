-- Executed as a local command by the real upstream shell/scheduler.
return [=[
local shell = require('shell')
local completion = require('cc.shell.completion')
local settings = require('settings')
local fs = require('fs')
local function contains(values, wanted)
  for _, value in ipairs(values) do if value == wanted then return true end end
  return false
end
assert(contains(shell.complete('edit pro'), 'be.lua'), 'edit filename completion')
assert(contains(completion.file('pro'), 'be.lua'), 'local file completion')
assert(contains(shell.completeProgram('edi'), 't'), 'editor command completion')
assert(not pcall(require, 'peripheral') and not pcall(require, 'http'))
settings.define('probe.boolean', {type = 'boolean', default = true})
settings.unset('probe.boolean')
assert(settings.get('probe.boolean') == true)
settings.set('probe.boolean', false)
assert(settings.get('probe.boolean') == false)
assert(settings.save('/probe.settings'))
settings.clear()
assert(settings.load('/probe.settings') and settings.get('probe.boolean') == false)
local textutils = require('textutils')
local values = {false, true, 1.2345678901234567, '123', math.huge, -math.huge, 0/0}
local restored = textutils.unserialize(textutils.serialize(values))
assert(restored[1] == false and restored[2] == true and restored[3] == values[3] and restored[4] == '123')
assert(restored[5] == math.huge and restored[6] == -math.huge and restored[7] ~= restored[7])
local isolated = assert(loadfile('/environment.lua', 't', {token = 7}))
assert(isolated() == 7, 'upstream IO loadfile must preserve the supplied environment')
assert(loadfile('/environment.lua', 'b') == nil)
assert(not pcall(loadfile, '/environment.lua', 't', false))
local file = assert(fs.open('/shell-result.txt', 'w'))
file.write('shell-completion-settings-pass')
file.close()
return 'shell-probe-pass'
]=]
