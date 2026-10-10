-- Isolated native BIOS entry, not yet wired to playable computers.
-- Guest load owns bounded BIOS compilation and immutable source retention.
local Compiler = require('__computer_core_2__.scripts.native.compiler')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Helpers = require('__computer_core_2__.scripts.native.helpers')
local Events = require('__computer_core_2__.scripts.native.events')
local Terminal = require('__computer_core_2__.scripts.native.terminal')
local Filesystem = require('__computer_core_2__.scripts.native.filesystem')
local Display = require('__computer_core_2__.scripts.guest.terminal')
local Rom = require('__computer_core_2__.scripts.native.rom')
local entry = assert(Compiler.compile("local bios=...; return assert(load(bios,'/bios.lua','t',_G))(true)", '=native-os-entry'))
local M = {}
function M.new(disk, dimensions)
  local bios = assert(Rom['/bios.lua'], 'missing pinned BIOS')
  local machine = Execution.new(entry, {n = 1, bios})
  Execution.install_core(machine)
  Helpers.install(machine)
  Events.install_services(machine)
  Filesystem.install(machine, disk)
  local columns, rows
  if dimensions then columns, rows = dimensions.columns, dimensions.rows
  else columns, rows = Display.dimensions() end
  Terminal.install(machine, columns, rows)
  Execution.set(machine, machine.env, '_G', machine.env)
  Execution.set(machine, machine.env, '_VERSION', 'Lua 5.2')
  Execution.set(machine, machine.env, '_HOST', 'Computer Core 2 native guest')
  machine.configured_geometry = dimensions == nil
  return machine
end
return M
