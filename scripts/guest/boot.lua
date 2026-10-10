-- Pinned ROM boot factory shared by live computers and isolated tests.
local Compiler = require("__computer_core_2__.scripts.guest.compiler")
local VM = require("__computer_core_2__.scripts.guest.vm")
local Rom = require("__computer_core_2__.scripts.guest.rom")
local prototype = assert(Compiler.compile(Rom['/bios.lua'], '/bios.lua'))
local M = {}

function M.new(disk, dimensions)
  -- Explicit ROM selection bypasses the upstream external /.start_rc.lua shim.
  -- BIOS/scheduler root yields are admitted by the same durable event service.
  local vm = VM.new(prototype, table.pack(true), disk, dimensions, true)
  vm.configured_geometry = true
  return vm
end

return M
