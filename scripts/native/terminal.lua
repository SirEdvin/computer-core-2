-- Reuse the byte-cell display contract; expose only scalar symbolic services.
local Display = require('__computer_core_2__.scripts.guest.terminal')
local Execution = require('__computer_core_2__.scripts.native.execution')
local Events = require('__computer_core_2__.scripts.native.events')
local M = {}
function M.install(machine, columns, rows)
  if machine.terminal_installed then return end
  local display = machine.display or Display.new(columns, rows)
  assert(display.version == 1, 'unsupported native terminal version')
  local library = Execution.table_value(machine)
  for name in pairs(Display.methods) do
    Execution.set(machine, library, name, Execution.service_value(machine, 'term.' .. name))
  end
  Execution.set(machine, machine.env, 'term', library)
  machine.display, machine.terminal_installed = display, true
end
function M.reconcile(machine, columns, rows, admit)
  Display.validate_geometry(columns, rows)
  local display = assert(machine.display, 'native terminal not installed')
  assert(display.version == 1, 'unsupported native terminal version')
  if display.columns == columns and display.rows == rows then return false end
  assert(type(admit) == 'function', 'native geometry admission required')
  assert(admit('terminal', 1 + 6 * columns * rows + 6 * display.columns * display.rows + 2 * rows) ~= false,
    'native terminal work quota exceeded')
  -- No guest dispatch occurs between notification admission and reconciliation.
  local ok, err = Events.admit(machine, {n=1,'term_resize'}, true, function(amount)
    assert(admit('event', amount) ~= false, 'native event work quota exceeded')
  end)
  assert(ok, err)
  Display.reconcile(display, columns, rows)
  return true
end
function M.reconcile_configured(machine, admit)
  if machine.configured_geometry == false then return false end
  local columns, rows = Display.dimensions()
  return M.reconcile(machine, columns, rows, admit)
end
function M.services(admit)
  assert(type(admit) == 'function', 'native terminal admission required')
  local services = {}
  for method, implementation in pairs(Display.methods) do
    local name, handler = method, implementation
    services['term.' .. name] = function(machine, args)
      local display = assert(machine.display, 'native terminal not installed')
      assert(display.version == 1, 'unsupported native terminal version')
      assert(admit(Display.work(display, name, args)) ~= false, 'native terminal work quota exceeded')
      return 'return', table.pack(handler(display, table.unpack(args, 1, args.n)))
    end
  end
  return services
end
return M
