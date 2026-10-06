-- Native byte-cell model. Presentation and guest application state are separate.
local Limits = require("__computer_core_2__.scripts.guest.limits")
local M = {}
local hex = "0123456789abcdef"
local defaults = {
  0xf0f0f0, 0xf2b233, 0xe57fd8, 0x99b2f2, 0xdede6c, 0x7fcc19, 0xf2b2cc, 0x4c4c4c,
  0x999999, 0x4c99b2, 0xb266e5, 0x3366cc, 0x7f664c, 0x57a64e, 0xcc4c4c, 0x111111
}
-- Model/resource bounds. Client-supported bounds remain a section-4 gate.
M.min_columns, M.max_columns = 1, 160
M.min_rows, M.max_rows = 1, 60
local function integer(value)
  assert(type(value) == "number" and value == value and math.abs(value) <= 2147483647, "expected finite coordinate")
  return math.floor(value)
end
local function geometry(columns, rows)
  assert(type(columns) == "number" and columns == math.floor(columns) and columns >= M.min_columns and columns <= M.max_columns, "invalid terminal columns")
  assert(type(rows) == "number" and rows == math.floor(rows) and rows >= M.min_rows and rows <= M.max_rows, "invalid terminal rows")
end
local function color(value)
  for i = 0, 15 do if value == 2^i then return hex:sub(i + 1, i + 1) end end
  error("expected one of the 16 color masks", 0)
end
local function color_mask(value) return 2^assert(tonumber(value, 16)) end
local function blank(display, width)
  return {text = string.rep(" ", width), foreground = string.rep(display.foreground, width), background = string.rep(display.background, width)}
end
local function dirty(display, row)
  display.revision = display.revision + 1
  if row then display.dirty[row] = true else for i = 1, display.rows do display.dirty[i] = true end end
end
function M.new(columns, rows)
  columns, rows = columns or 51, rows or 19
  geometry(columns, rows)
  local display = {version = 1, columns = columns, rows = rows, x = 1, y = 1, blink = false,
    foreground = "0", background = "f", lines = {}, palette = {}, dirty = {}, revision = 0}
  for i, rgb in ipairs(defaults) do
    display.palette[i] = {r = math.floor(rgb / 65536) / 255, g = math.floor(rgb / 256) % 256 / 255, b = rgb % 256 / 255}
  end
  for y = 1, rows do display.lines[y] = blank(display, columns) end
  dirty(display)
  return display
end
function M.dimensions()
  return settings.startup["computer-core-terminal-columns"].value, settings.startup["computer-core-terminal-rows"].value
end
function M.configured()
  return M.new(M.dimensions())
end
local function insert(line, offset, value)
  return line:sub(1, offset - 1) .. value .. line:sub(offset + #value)
end
local function paint(display, text, foreground, background)
  local x, y = display.x, display.y
  local first, last = math.max(1, 2 - x), math.min(#text, display.columns - x + 1)
  if y >= 1 and y <= display.rows and first <= last then
    local line, offset = display.lines[y], x + first - 1
    line.text = insert(line.text, offset, text:sub(first, last))
    line.foreground = insert(line.foreground, offset, foreground:sub(first, last))
    line.background = insert(line.background, offset, background:sub(first, last))
    dirty(display, y)
  end
  display.x = display.x + #text
  display.revision = display.revision + 1
end
local function text_argument(text)
  assert(type(text) == "string", "expected text string")
  assert(#text <= Limits.string_bytes, "terminal write exceeds byte limit")
end
M.methods = {}
-- Conservative native-work estimate, evaluated before any guest mutation.
-- Geometry is bounded independently; invalid arguments retain handler errors
-- when credits are available. The caller owns the ephemeral admission scope.
function M.work(display, name, args)
  if name == "write" then
    local text = args[1]
    if type(text) == "number" then text = tostring(text) end
    local bytes = type(text) == "string" and math.min(#text, Limits.string_bytes) or 0
    return 1 + 2 * bytes + 9 * display.columns
  elseif name == "blit" then
    local bytes = 0
    for i = 2, 3 do
      if type(args[i]) == "string" then bytes = bytes + math.min(#args[i], Limits.string_bytes) end
    end
    return 1 + bytes + 9 * display.columns
  elseif name == "clear" or name == "scroll" then
    return 1 + 3 * display.columns * display.rows + 2 * display.rows
  elseif name == "clearLine" then return 1 + 3 * display.columns
  elseif name == "setPaletteColor" or name == "setPaletteColour" then return 17 + display.rows
  elseif name:find("Color", 1, true) or name:find("Colour", 1, true) then return 17 end
  return 1
end
local methods = M.methods
function methods.write(display, text)
  if type(text) == "number" then text = tostring(text) end
  text_argument(text)
  paint(display, text, string.rep(display.foreground, #text), string.rep(display.background, #text))
end
function methods.blit(display, text, foreground, background)
  text_argument(text)
  assert(type(foreground) == "string" and type(background) == "string", "expected color strings")
  assert(#text == #foreground and #text == #background, "blit lengths differ")
  assert(not foreground:find("[^0-9a-f]") and not background:find("[^0-9a-f]"), "invalid blit color")
  paint(display, text, foreground, background)
end
function methods.getSize(display) return display.columns, display.rows end
function methods.getCursorPos(display) return display.x, display.y end
function methods.setCursorPos(display, x, y)
  x, y = integer(x), integer(y)
  display.x, display.y = x, y
  display.revision = display.revision + 1
end
function methods.getCursorBlink(display) return display.blink end
function methods.setCursorBlink(display, blink)
  assert(type(blink) == "boolean", "expected blink boolean")
  display.blink = blink
  display.revision = display.revision + 1
end
function methods.isColor() return true end
function methods.getTextColor(display) return color_mask(display.foreground) end
function methods.getBackgroundColor(display) return color_mask(display.background) end
function methods.setTextColor(display, value) display.foreground = color(value) end
function methods.setBackgroundColor(display, value) display.background = color(value) end
function methods.clear(display)
  for y = 1, display.rows do display.lines[y] = blank(display, display.columns) end
  dirty(display)
end
function methods.clearLine(display)
  if display.y >= 1 and display.y <= display.rows then
    display.lines[display.y] = blank(display, display.columns)
    dirty(display, display.y)
  end
end
function methods.scroll(display, amount)
  amount = integer(amount)
  if amount == 0 then return end
  local lines = {}
  for y = 1, display.rows do lines[y] = display.lines[y + amount] or blank(display, display.columns) end
  display.lines = lines
  dirty(display)
end
function methods.setPaletteColor(display, mask, r, g, b)
  local index = tonumber(color(mask), 16) + 1
  if g == nil and b == nil then
    assert(type(r) == "number" and r == math.floor(r) and r >= 0 and r <= 0xffffff, "invalid packed palette color")
    r, g, b = math.floor(r / 65536) / 255, math.floor(r / 256) % 256 / 255, r % 256 / 255
  else
    for _, value in ipairs({r, g, b}) do assert(type(value) == "number" and value >= 0 and value <= 1, "invalid RGB channel") end
    assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "expected three RGB channels")
  end
  display.palette[index] = {r = r, g = g, b = b}
  dirty(display)
end
function methods.getPaletteColor(display, mask)
  local entry = display.palette[tonumber(color(mask), 16) + 1]
  return entry.r, entry.g, entry.b
end
for _, name in ipairs({"isColor", "getTextColor", "getBackgroundColor", "setTextColor", "setBackgroundColor", "getPaletteColor", "setPaletteColor"}) do
  methods[name:gsub("Color", "Colour")] = methods[name]
end
-- Called only at synchronized dispatch/configuration-change, never on_load.
-- Returning true tells the event bridge to admit exactly one term_resize first.
function M.reconcile(display, columns, rows)
  geometry(columns, rows)
  if display.columns == columns and display.rows == rows then return false end
  local lines = {}
  for y = 1, rows do
    local line = blank(display, columns)
    local old = display.lines[y]
    if old then
      local overlap = math.min(columns, display.columns)
      for _, member in ipairs({"text", "foreground", "background"}) do
        line[member] = old[member]:sub(1, overlap) .. line[member]:sub(overlap + 1)
      end
    end
    lines[y] = line
  end
  display.columns, display.rows, display.lines, display.dirty = columns, rows, lines, {}
  dirty(display)
  return true
end
return M
